/// Серверный приём инвайт-кода (PocketBase JSVM-хук). Закрывает ДВА блокера:
///
///  1) ENUMERATION кодов: invite_codes больше НЕ читаются клиентом кросс-юзерно
///     (listRule/viewRule = owner-only, см. apply_acl.py). Приём идёт только
///     через этот роут — он ищет код под суперюзер-привилегиями ($app, в обход
///     API-правил), поэтому клиенту не нужен доступ к чужим кодам.
///
///  2) JOIN/RESTORE под ACL по членству: обычный клиент НЕ может дописать себя в
///     чужую группу (groups updateRule = `members ?~ auth.id` — он ещё не член),
///     ни прочитать чужой профиль (users viewRule = self). `$app.save` правила не
///     проверяет → присоединение работает только здесь.
///
/// POST /api/invite/accept  body { code }
///   → 200 { success:true, message, pairId, restored? }
///   → 4xx { success:false, message }
/// Клиент по success дочитывает группу по pairId (теперь он её член → правила
/// пускают) и строит pair-карту сам (PbDataService.acceptInviteCode).
///
/// Порт PbDataService.acceptInviteCode (ветки A/B/C/D + race-guard). ВАЖНО (PB
/// JSVM): хендлер исполняется изолированно — функции уровня файла не видны,
/// поэтому все хелперы объявлены ВНУТРИ. Поля groups/users — snake_case; json
/// (members/member_*) читаем через getString→JSON.parse (как coins.pb.js).
routerAdd("POST", "/api/invite/accept", (e) => {
  const myUid = e.auth.id;
  const raw = (e.requestInfo().body || {}).code;
  const code = String(raw || "").toUpperCase().trim();
  if (!code) return e.json(400, { success: false, message: "Код не указан" });

  // ── хелперы ────────────────────────────────────────────────────────────────
  const membersOf = (g) => {
    try { return JSON.parse(g.getString("members") || "[]") || []; }
    catch (_) { return []; }
  };
  const mapOf = (g, field) => {
    try { return JSON.parse(g.getString(field) || "{}") || {}; }
    catch (_) { return {}; }
  };
  const profileOf = (uid, fallbackName) => {
    try {
      const u = $app.findRecordById("users", uid);
      return {
        name: u.getString("display_name") || fallbackName,
        avatar: u.getString("avatar_url") || "",
      };
    } catch (_) { return { name: fallbackName, avatar: "" }; }
  };
  const liveGroupOf = (uid) => {
    try {
      const r = $app.findRecordsByFilter(
        "groups", "members ~ {:u} && disbanded = false", "-created_at", 1, 0, { u: uid });
      return r && r.length ? r[0] : null;
    } catch (_) { return null; }
  };
  const disbandedBetween = (mu, ou) => {
    let rows = [];
    try {
      rows = $app.findRecordsByFilter(
        "groups", "members ~ {:u} && disbanded = true", "", 0, 0, { u: mu });
    } catch (_) { return null; }
    let bestId = null, bestTs = -1;
    for (let i = 0; i < rows.length; i++) {
      if (membersOf(rows[i]).indexOf(ou) === -1) continue;
      let ts = 0;
      const da = rows[i].getString("disbanded_at");
      if (da) { const t = Date.parse(da); if (!isNaN(t)) ts = t; }
      if (bestId === null || ts > bestTs) { bestId = rows[i].id; bestTs = ts; }
    }
    return bestId;
  };

  // ── найти код ────────────────────────────────────────────────────────────
  let codeRec;
  try {
    codeRec = $app.findFirstRecordByFilter("invite_codes", "code = {:c}", { c: code });
  } catch (_) {
    return e.json(404, { success: false, message: "Код не найден" });
  }
  const ownerUid = String(codeRec.getString("owner_uid") || "");
  if (!ownerUid) return e.json(400, { success: false, message: "Код повреждён" });
  if (ownerUid === myUid) {
    return e.json(400, { success: false, message: "Это ваш собственный код!" });
  }
  const codeGroupId = String(codeRec.getString("group_id") || "");

  const me = profileOf(myUid, "");
  const owner = profileOf(ownerUid, "Partner");
  const groupsCol = $app.findCollectionByNameOrId("groups");
  const nowIso = new Date().toISOString();
  const delCode = () => { try { $app.delete(codeRec); } catch (_) { /* гонка — ок */ } };

  // ── операции над группой (все через $app — правила не применяются) ────────
  const createGroup = () => {
    // Race-guard взаимного коннекта: уже есть живая группа с этим партнёром?
    let mine = [];
    try {
      mine = $app.findRecordsByFilter(
        "groups", "members ~ {:u} && disbanded = false", "", 0, 0, { u: myUid });
    } catch (_) {}
    for (let i = 0; i < mine.length; i++) {
      if (membersOf(mine[i]).indexOf(ownerUid) !== -1) {
        delCode();
        return { success: true, message: "Connected!", pairId: mine[i].id };
      }
    }
    const g = new Record(groupsCol);
    const names = {}; names[ownerUid] = owner.name; names[myUid] = me.name;
    const avatars = {}; avatars[ownerUid] = owner.avatar; avatars[myUid] = me.avatar;
    g.set("members", [ownerUid, myUid]);
    g.set("member_names", names);
    g.set("member_avatars", avatars);
    g.set("max_members", 2);
    g.set("relationship_type", "couple");
    g.set("custom_relationship_types", []);
    g.set("memories_count", 0);
    g.set("drawings_count", 0);
    g.set("start_date", nowIso);
    g.set("created_at", nowIso);
    g.set("disbanded", false);
    try { $app.save(g); }
    catch (err) { return { success: false, message: "Ошибка сохранения группы" }; }
    delCode();
    return { success: true, message: "Connected!", pairId: g.id };
  };

  const joinGroup = (groupId) => {
    let g;
    try { g = $app.findRecordById("groups", groupId); } catch (_) { return createGroup(); }
    const members = membersOf(g);
    const maxM = Number(g.get("max_members")) || 2;
    if (members.indexOf(myUid) !== -1) {
      return { success: false, message: "Вы уже в этой группе" };
    }
    if (members.length >= maxM) {
      return { success: false, message: "Группа заполнена" };
    }
    const names = mapOf(g, "member_names");
    const avatars = mapOf(g, "member_avatars");
    members.push(myUid);
    names[myUid] = me.name;
    avatars[myUid] = me.avatar;
    g.set("members", members);
    g.set("member_names", names);
    g.set("member_avatars", avatars);
    try { $app.save(g); }
    catch (err) { return { success: false, message: "Ошибка сохранения группы" }; }
    if (members.length >= maxM) delCode();
    return { success: true, message: "Joined the group!", pairId: g.id };
  };

  const restoreGroup = (groupId) => {
    let g;
    try { g = $app.findRecordById("groups", groupId); } catch (_) { return createGroup(); }
    const members = membersOf(g);
    if (members.indexOf(ownerUid) === -1) members.push(ownerUid);
    if (members.indexOf(myUid) === -1) members.push(myUid);
    const names = mapOf(g, "member_names");
    const avatars = mapOf(g, "member_avatars");
    names[ownerUid] = owner.name; names[myUid] = me.name;
    avatars[ownerUid] = owner.avatar; avatars[myUid] = me.avatar;
    g.set("members", members);
    g.set("member_names", names);
    g.set("member_avatars", avatars);
    g.set("disbanded", false);
    g.set("disbanded_at", null);
    try { $app.save(g); }
    catch (err) { return { success: false, message: "Ошибка сохранения группы" }; }
    delCode();
    return { success: true, message: "Reconnected!", pairId: g.id, restored: true };
  };

  // ── ветвление A/B/C/D (зеркало Dart acceptInviteCode) ────────────────────
  let res;
  if (codeGroupId) {
    // A) код привязан к группе → войти в неё.
    res = joinGroup(codeGroupId);
  } else {
    // B) у владельца уже есть активная группа с местом → войти.
    const ownerGroup = liveGroupOf(ownerUid);
    let handled = false;
    if (ownerGroup) {
      const members = membersOf(ownerGroup);
      if (members.indexOf(myUid) !== -1 && members.indexOf(ownerUid) !== -1) {
        res = { success: false, message: "Вы уже подключены к этому пользователю" };
        handled = true;
      } else {
        const maxM = Number(ownerGroup.get("max_members")) || 2;
        if (members.indexOf(ownerUid) !== -1 &&
            members.indexOf(myUid) === -1 &&
            members.length < maxM) {
          res = joinGroup(ownerGroup.id);
          handled = true;
        }
      }
    }
    if (!handled) {
      // C) распущенная группа этих двоих → восстановить (старые данные целы).
      const disbandedId = disbandedBetween(myUid, ownerUid);
      // D) иначе создать новую пару.
      res = disbandedId ? restoreGroup(disbandedId) : createGroup();
    }
  }

  return e.json(res.success ? 200 : 400, res);
}, $apis.requireAuth());
