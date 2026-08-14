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

  // ── пара живёт в Postgres: всё ветвление делает hotpath ──────────────────
  // Раньше здесь было три функции (создать, войти, восстановить) поверх
  // транзакций PocketBase: они сериализовали параллельные приёмы на
  // единственном соединении записи, и приём кода стоял в общей очереди со
  // всей остальной записью. Теперь запись пары лежит в Postgres, а решение
  // «войти / поднять распущенную / завести новую» принимается там же одним
  // запросом с блокировкой строки самой пары. PocketBase в этом пути больше
  // не пишет ничего — за ним остались только коды приглашений.
  let res = null;
  try {
    const hp = $http.send({
      url: "http://127.0.0.1:8120/internal/pair-accept",
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        owner_uid: ownerUid,
        my_uid: myUid,
        code_group_id: codeGroupId,
        owner_name: owner.name,
        owner_avatar: owner.avatar,
        my_name: me.name,
        my_avatar: me.avatar,
      }),
      timeout: 15,
    });
    res = (hp && hp.json) || null;
  } catch (err) {
    return deny(500, "Не удалось принять код", "hotpath недоступен: " + String(err));
  }

  if (!res || res.success !== true) {
    return deny(400, (res && res.message) || "Не удалось принять код",
      (res && res.message) || "hotpath вернул отказ");
  }
  // Код привязываем к получившейся паре ПОСЛЕ успеха — повтор того же кода
  // тем же человеком попадёт во «вход в свою пару» и ответит успехом.
  bindCode(res.pairId);
  return e.json(200, res);
}, $apis.requireAuth());
