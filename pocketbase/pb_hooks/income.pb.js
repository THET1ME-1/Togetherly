/// Доход приложения из всех источников — вкладка «Доход» в админке.
///
///   GET /modapi/income — сводка из кеша, гейт ?s= как у остальных /modapi/*.
///
/// Источники и где лежат ключи:
///   РСЯ (реклама Яндекса)  — OAuth-токен в pb_data/.rsya_token, API partner.yandex.ru
///   lava (Togetherly+)     — env LAVA_API_KEY, API gate.lava.top
///   AdMob (реклама Google) — pb_data/.admob_oauth.json {client_id, client_secret,
///                            refresh_token, publisher_id}; служебные аккаунты AdMob
///                            не принимает, поэтому только refresh-token.
///   Google Play (продажи)  — pb_data/.play_sa.json (ключ служебного аккаунта) +
///                            pb_data/.play_bucket (имя бакета с отчётами).
/// Источник без ключа не ломает сводку: он отдаётся с пометкой «не настроен».
///
/// Данные собирает крон и кладёт в pb_data/.income.json — роут только читает файл.
/// Так вкладка открывается мгновенно и не дёргает четыре чужих API на каждый F5.
/// ВАЖНО (PB JSVM): хендлер и крон ИЗОЛИРОВАНЫ — общие функции уровня файла внутри
/// не видны, поэтому всё живёт внутри своего колбэка.

// ── GET /modapi/income ───────────────────────────────────────────────────────
routerAdd("GET", "/modapi/income", (e) => {
  const info = e.requestInfo(); const h = info.headers || {}, q = info.query || {};
  const got = String(h["x_mod_secret"] || h["x-mod-secret"] || q["secret"] || q["s"] || "");
  let want = ""; try { want = $os.getenv("MOD_SECRET") || ""; } catch (_) {}
  if (!want) { try { const b = $os.readFile("/opt/pocketbase/pb_data/.mod_secret"); want = (typeof b === "string" ? b : String.fromCharCode.apply(null, b)).trim(); } catch (_) {} }
  if (!want || got !== want) return e.json(401, { error: "unauthorized" });

  // ?probe=1 — замер доступа к базе из хука. Заведён 13 августа 2026, когда
  // вкладка «Продукт» перестала грузиться: те же запросы в sqlite3 отвечали за
  // сотые доли секунды, а роут висел три минуты, и надо было понять, где время.
  if (String(q["probe"] || "") === "1") {
    const t = [];
    const mark = (name, fn) => {
      const at = Date.now();
      let res = "";
      try { res = String(fn()); } catch (err) { res = "ошибка: " + String(err).slice(0, 80); }
      t.push({ шаг: name, мс: Date.now() - at, ответ: res });
    };
    mark("простой COUNT users", () => {
      const m = new DynamicModel({ n: 0 });
      $app.db().newQuery("SELECT COUNT(*) AS n FROM users").one(m);
      return m.n;
    });
    mark("COUNT groups", () => {
      const m = new DynamicModel({ n: 0 });
      $app.db().newQuery("SELECT COUNT(*) AS n FROM groups WHERE disbanded = false").one(m);
      return m.n;
    });
    mark("когорты (JOIN presence)", () => {
      const rows = arrayOf(new DynamicModel({ wk: "", n: 0 }));
      $app.db().newQuery(
        "SELECT strftime('%Y-%m-%d', u.created) AS wk, COUNT(*) AS n FROM users u" +
        " LEFT JOIN user_presence p ON p.user_uid = u.id GROUP BY wk").all(rows);
      return rows.length + " строк";
    });
    mark("json_each по группам", () => {
      const m = new DynamicModel({ n: 0 });
      $app.db().newQuery("SELECT COUNT(DISTINCT je.value) AS n FROM groups g, json_each(g.members) je" +
        " WHERE g.disbanded = false AND json_valid(g.members)").one(m);
      return m.n;
    });
    return e.json(200, { probe: t });
  }

  // ?force=1 собирает заново на месте: нужен сразу после заливки и после смены
  // ключей, когда ждать двадцать минут до крона незачем. Ходит в четыре чужих
  // API, поэтому по умолчанию отдаём готовый файл.
  if (String(q["force"] || "") === "1") {
    try { return e.json(200, require(`${__hooks}/income_collect.js`)()); }
    catch (err) { return e.json(500, { error: "collect failed", reason: String(err).slice(0, 300) }); }
  }

  try {
    const raw = $os.readFile("/opt/pocketbase/pb_data/.income.json");
    const j = JSON.parse(typeof raw === "string" ? raw : String.fromCharCode.apply(null, raw));
    return e.json(200, j);
  } catch (_) {
    // Крон ещё не отработал — честная пустая сводка вместо ошибки.
    return e.json(200, {
      updated: null,
      sources: {},
      note: "данные ещё не собраны, крон ходит каждые 20 минут",
    });
  }
});

// ── сбор сводки ──────────────────────────────────────────────────────────────
cronAdd("incomeCollect", "*/20 * * * *", () => {
  try { require(`${__hooks}/income_collect.js`)(); }
  catch (err) { $app.logger().warn("income: сбор упал", "err", String(err)); }
});
