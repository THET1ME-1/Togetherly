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

  // В это поле приносят не только код. Вставляют ссылку-приглашение целиком
  // («…/invite/HQ792S» — так бывает, когда её переслали текстом и она не
  // кликнулась), набирают в русской раскладке (кириллические А, В, Е, К, М, Н,
  // О, Р, С, Т, У, Х от латинских не отличить), приводят кавычку от автозамены
  // на iPhone. Всё это раньше упиралось в «Код не найден» на ровном месте.
  // Чистим на сервере, а не в приложении: выпущенные сборки получают правку
  // сразу, без обновления в сторах.
  const normalizeCode = (input) => {
    let s = String(input || "").toUpperCase().trim();
    const marker = s.lastIndexOf("/INVITE/");
    if (marker !== -1) s = s.slice(marker + 8);
    s = s.split("?")[0].split("#")[0];
    const cyr = {
      "А": "A", "В": "B", "Е": "E", "К": "K", "М": "M", "Н": "H",
      "О": "O", "Р": "P", "С": "C", "Т": "T", "У": "Y", "Х": "X",
    };
    let out = "";
    for (let i = 0; i < s.length; i++) {
      const ch = cyr[s[i]] || s[i];
      if ((ch >= "A" && ch <= "Z") || (ch >= "0" && ch <= "9")) out += ch;
    }
    return out;
  };

  const code = normalizeCode(raw);

  // Отказы этого роута НЕ попадают в _logs сами: PocketBase пишет туда только
  // ошибки уровня middleware, а `e.json(400, …)` из тела хука проходит мимо
  // журнала (проверено). Из-за этого жалоба «код не работает» разбиралась
  // вслепую — в логах за две недели ноль строк при живом потоке отказов.
  // Поэтому каждую причину пишем сами, через warn (info в _logs не доходит).
  // Смотреть так:
  //   sqlite3 pb_data/auxiliary.db "select created, data from _logs
  //     where message like '%invite accept%' order by created desc limit 30;"
  const deny = (status, message, why) => {
    try {
      // Пишем и исходную строку, если чистка что-то изменила: по ней видно,
      // чем на самом деле пользуются люди — ссылкой, кириллицей, кавычкой.
      const rawStr = String(raw || "");
      if (rawStr.toUpperCase().trim() !== code) {
        $app.logger().warn("invite accept: отказ", "why", why, "code", code,
          "raw", rawStr, "uid", myUid);
      } else {
        $app.logger().warn("invite accept: отказ", "why", why, "code", code, "uid", myUid);
      }
    } catch (_) { /* журнал не должен ронять приём кода */ }
    return e.json(status, { success: false, message: message });
  };

  if (!code) return deny(400, "Код не указан", "пустой код");

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
  // Кодов в приложении два вида, а поле ввода одно: обычный инвайт и постоянный
  // код второго места у пары «он в армии» (`groups.claim_token`, waiting.pb.js).
  // Человеку разница не видна и видна быть не должна, поэтому сперва ищем
  // инвайт, а не нашли — пробуем второе место и отдаём заявку на подтверждение.
  let codeRec;
  try {
    codeRec = $app.findFirstRecordByFilter("invite_codes", "code = {:c}", { c: code });
  } catch (_) {
    let waiting = null;
    try {
      const rows = $app.findRecordsByFilter("groups", "claim_token = {:t}", "", 1, 0, { t: code });
      waiting = rows && rows.length ? rows[0] : null;
    } catch (_) { waiting = null; }
    if (waiting) {
      return e.json(200, { success: true, waiting: true, pairId: waiting.id, code: code });
    }
    // Чаще всего код не поддельный, а фантомный: сборки до 24 июля рисовали
    // его на устройстве сами, когда сервер был недоступен, и такой код осел в
    // памяти телефона навсегда (перевыпуск идёт только на пустом поле). Просить
    // партнёра перевыпустить — единственное, что человек может сделать сам, не
    // дожидаясь обновления приложения.
    return deny(
      404,
      "Код не найден. Пусть партнёр нажмёт «Новый код» и продиктует заново",
      "кода нет ни в invite_codes, ни в claim_token"
    );
  }
  const ownerUid = String(codeRec.getString("owner_uid") || "");
  if (!ownerUid) return deny(400, "Код повреждён", "у кода пустой owner_uid");
  if (ownerUid === myUid) {
    return deny(400, "Это ваш собственный код!", "свой же код");
  }
  const codeGroupId = String(codeRec.getString("group_id") || "");

  const me = profileOf(myUid, "");
  const owner = profileOf(ownerUid, "Partner");
  const groupsCol = $app.findCollectionByNameOrId("groups");
  const nowIso = new Date().toISOString();
  // РАНЬШЕ код удалялся сразу после успешного приёма, и это давало главный поток
  // жалоб: человек жмёт «подключиться» второй раз (двойной тап, диплинк присылает
  // код дважды, партнёр просит «попробуй ещё») — и получает «Код не найден» поверх
  // уже СОСТОЯВШЕЙСЯ пары. За сутки таких отказов 517. Теперь код не удаляем, а
  // привязываем к получившейся группе: повтор попадает в ветку A → joinGroup →
  // «уже в группе» → успех с тем же pairId. Третьего код не пустит — группа
  // заполнена. Живёт привязанный код недолго: приглашающий, увидев пару, сам
  // перевыпускает его групповым (Connection.claimPair) и старый удаляет.
  const bindCode = (pairId) => {
    try {
      if (String(codeRec.getString("group_id") || "") === String(pairId)) return;
      codeRec.set("group_id", pairId);
      $app.save(codeRec);
    } catch (_) { /* гонка/повтор — не критично */ }
  };

  // ── операции над группой (все через $app — правила не применяются) ────────
  // INV-1: мутации обёрнуты в $app.runInTransaction. PB исполняет транзакции на
  // единственном неконкурентном write-коннекте → два параллельных accept
  // сериализуются: второй читает уже обновлённый members → не превысит max_members
  // и не создаст дубль-группу. Внутри tx — ТОЛЬКО txApp. bindCode() вызываем ПОСЛЕ
  // коммита (если save упал — код инвайта не трогаем, см. INV-4). Решение «группа не
  // найдена → создать» принимаем ВНЕ tx, чтобы не открыть вложенную транзакцию.
  const createGroup = () => {
    let result;
    try {
      $app.runInTransaction((txApp) => {
        // Race-guard взаимного коннекта: уже есть живая группа с этим партнёром?
        let mine = [];
        try {
          mine = txApp.findRecordsByFilter(
            "groups", "members ~ {:u} && disbanded = false", "", 0, 0, { u: myUid });
        } catch (_) {}
        for (let i = 0; i < mine.length; i++) {
          if (membersOf(mine[i]).indexOf(ownerUid) !== -1) {
            result = { success: true, message: "Connected!", pairId: mine[i].id, _delCode: true };
            return;
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
        txApp.save(g);
        result = { success: true, message: "Connected!", pairId: g.id, _delCode: true };
      });
    } catch (err) { return { success: false, message: "Ошибка сохранения группы" }; }
    if (result && result._delCode) { bindCode(result.pairId); delete result._delCode; }
    return result;
  };

  const joinGroup = (groupId) => {
    // Существование группы решаем ВНЕ tx (createGroup откроет свою транзакцию).
    try { $app.findRecordById("groups", groupId); } catch (_) { return createGroup(); }
    let result;
    try {
      $app.runInTransaction((txApp) => {
        const g = txApp.findRecordById("groups", groupId); // свежее чтение внутри tx
        const members = membersOf(g);
        const maxM = Number(g.get("max_members")) || 2;
        if (members.indexOf(myUid) !== -1) {
          // Повтор приёма своего же кода: пара уже собрана, отвечаем успехом с тем
          // же pairId — клиент просто заново покажет пару, а не ошибку.
          result = { success: true, message: "Connected!", pairId: g.id };
          return;
        }
        if (members.length >= maxM) {
          result = { success: false, message: "Группа заполнена" };
          return;
        }
        const names = mapOf(g, "member_names");
        const avatars = mapOf(g, "member_avatars");
        members.push(myUid);
        names[myUid] = me.name;
        avatars[myUid] = me.avatar;
        g.set("members", members);
        g.set("member_names", names);
        g.set("member_avatars", avatars);
        txApp.save(g);
        result = { success: true, message: "Joined the group!", pairId: g.id, _full: members.length >= maxM };
      });
    } catch (err) { return { success: false, message: "Ошибка сохранения группы" }; }
    if (result && result.success && result.pairId) bindCode(result.pairId);
    if (result) delete result._full;
    return result;
  };

  const restoreGroup = (groupId) => {
    try { $app.findRecordById("groups", groupId); } catch (_) { return createGroup(); }
    let result;
    try {
      $app.runInTransaction((txApp) => {
        const g = txApp.findRecordById("groups", groupId);
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
        txApp.save(g);
        result = { success: true, message: "Reconnected!", pairId: g.id, restored: true };
      });
    } catch (err) { return { success: false, message: "Ошибка сохранения группы" }; }
    if (result && result.success) bindCode(result.pairId);
    return result;
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
        // Мы уже в паре с владельцем кода — повторный ввод не ошибка. Отдаём
        // успех с pairId: экран подключения покажет пару вместо красной плашки.
        res = { success: true, message: "Connected!", pairId: ownerGroup.id };
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

  if (!res || res.success !== true) {
    return deny(400, (res && res.message) || "Не удалось принять код",
      (res && res.message) || "ветвление вернуло пустоту");
  }
  return e.json(200, res);
}, $apis.requireAuth());
