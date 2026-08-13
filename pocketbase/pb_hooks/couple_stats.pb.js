/// Развёрнутая статистика пары — один запрос вместо двух десятков выборок.
///
/// GET /api/couple/stats?groupId=<id>
///
/// Экран «Статистика пары» показывает динамику за год, разбивку по участникам,
/// распределения и прогнозы. Тянуть ради этого сами записи на клиент нельзя: у
/// активной пары десятки тысяч сообщений, и один график стоил бы мегабайтов
/// трафика. Поэтому всё считается здесь агрегатами SQLite и уезжает готовыми
/// числами.
///
/// ВАЖНО (PB JSVM): обработчик исполняется в изолированном пуле и НЕ видит
/// функций уровня файла — все хелперы объявлены внутри обработчика.
routerAdd("GET", "/api/couple/stats", (e) => {
  const auth = e.auth;
  if (!auth) return e.json(401, { ok: false, error: "unauthorized" });

  const q = e.requestInfo().query || {};
  const groupId = String(q["groupId"] || "");
  if (!groupId) return e.json(400, { ok: false, error: "no_group" });

  // Суперюзер смотрит любую пару — им пользуется только админка и отладка.
  let isSuper = false;
  try { isSuper = auth.collection().name === "_superusers"; } catch (_) {}

  // Участие — по users.group_ids, как в правилах коллекций и watch.pb.js.
  const mine = isSuper ? [groupId] : (auth.get("group_ids") || []);
  let member = false;
  for (let i = 0; i < mine.length; i++) {
    if (String(mine[i]) === groupId) { member = true; break; }
  }
  if (!member) return e.json(403, { ok: false, error: "not_member" });

  const g = JSON.stringify(groupId);

  const one = (sql) => {
    try {
      const m = new DynamicModel({ n: 0 });
      $app.db().newQuery(sql).one(m);
      return m.n || 0;
    } catch (_) { return 0; }
  };
  const rows = (sql, shape) => {
    try {
      const r = arrayOf(new DynamicModel(shape));
      $app.db().newQuery(sql).all(r);
      return r;
    } catch (_) { return []; }
  };

  // Локальное время автора отметки. С 13 августа 2026 `timestamp` хранится в
  // UTC, а пояс автора лежит рядом в колонке `tz`; у записей старше пояс пуст —
  // там в `timestamp` уже лежат часы автора, и сдвиг нулевой.
  const moodLocal =
    "datetime(timestamp," +
    " (CASE WHEN tz IS NULL OR tz = '' THEN '+0'" +
    " ELSE substr(tz,1,1) || CAST(substr(tz,2,2) AS INTEGER) END) || ' hours'," +
    " (CASE WHEN tz IS NULL OR tz = '' THEN '+0'" +
    " ELSE substr(tz,1,1) || CAST(substr(tz,5,2) AS INTEGER) END) || ' minutes')";

  const out = { ok: true };

  // ── Пара ──────────────────────────────────────────────────────────────────
  const gr = rows(
    "SELECT created_at AS created, start_date AS start, anniversary_date AS anni," +
    " streak_days AS streak, xp AS xp, memories_count AS mem, drawings_count AS draw," +
    " messages_count AS msg, members AS members FROM groups WHERE id = " + g,
    { created: "", start: "", anni: "", streak: 0, xp: 0, mem: 0, draw: 0, msg: 0, members: "" },
  );
  const row = gr.length ? gr[0] : null;
  out.couple = row ? {
    created: row.created, start: row.start, anniversary: row.anni,
    streak: row.streak, xp: row.xp,
  } : {};

  // Участники: имена берём из users, чтобы клиент не гадал по member_names.
  out.members = rows(
    "SELECT je.value AS uid, COALESCE(u.display_name, '') AS name" +
    " FROM groups gr, json_each(gr.members) je LEFT JOIN users u ON u.id = je.value" +
    " WHERE gr.id = " + g + " AND json_valid(gr.members)",
    { uid: "", name: "" },
  ).map((r) => ({ uid: r.uid, name: r.name }));

  // ── Итоги ─────────────────────────────────────────────────────────────────
  const VIDEO = "(file LIKE '%.mp4' OR file LIKE '%.mov' OR file LIKE '%.webm' OR file LIKE '%.m4v' OR file LIKE '%.3gp' OR file LIKE '%.avi' OR file LIKE '%.mkv')";
  out.totals = {
    memories: one("SELECT COUNT(*) AS n FROM memories WHERE group_id = " + g + " AND deleted = false"),
    comments: one("SELECT COUNT(*) AS n FROM memory_comments WHERE group_id = " + g),
    messages: one("SELECT COUNT(*) AS n FROM chat_messages WHERE group_id = " + g + " AND deleted = false"),
    moods: one("SELECT COUNT(*) AS n FROM mood_entries WHERE group_id = " + g),
    missYou: one("SELECT COALESCE(SUM(count),0) AS n FROM miss_you WHERE group_id = " + g),
    strokes: one("SELECT COUNT(*) AS n FROM canvas_strokes WHERE group_id = " + g + " AND deleted = false"),
    canvases: one("SELECT COUNT(DISTINCT canvas_id) AS n FROM canvas_meta WHERE group_id = " + g),
    gifts: one("SELECT COUNT(*) AS n FROM gifts WHERE group_id = " + g),
    watch: one("SELECT COUNT(*) AS n FROM watch_history WHERE group_id = " + g),
    media: one("SELECT COUNT(*) AS n FROM media WHERE group_id = " + g),
    videos: one("SELECT COUNT(*) AS n FROM media WHERE group_id = " + g + " AND " + VIDEO),
    mascots: one("SELECT COUNT(*) AS n FROM mascots WHERE group_id = " + g),
  };
  out.totals.photos = out.totals.media - out.totals.videos;

  // ── Кто сколько сделал ────────────────────────────────────────────────────
  // Раздельный счёт по участникам: сравнение «я и партнёр» — половина смысла
  // этого экрана, а по общей сумме его не восстановить.
  out.byMember = {
    memories: rows(
      "SELECT author_uid AS uid, COUNT(*) AS c FROM memories WHERE group_id = " + g +
      " AND deleted = false GROUP BY uid", { uid: "", c: 0 },
    ).map((r) => ({ uid: r.uid, c: r.c })),
    messages: rows(
      "SELECT user_uid AS uid, COUNT(*) AS c FROM chat_messages WHERE group_id = " + g +
      " AND deleted = false GROUP BY uid", { uid: "", c: 0 },
    ).map((r) => ({ uid: r.uid, c: r.c })),
    moods: rows(
      "SELECT user_uid AS uid, COUNT(*) AS c FROM mood_entries WHERE group_id = " + g +
      " GROUP BY uid", { uid: "", c: 0 },
    ).map((r) => ({ uid: r.uid, c: r.c })),
    missYou: rows(
      "SELECT user_uid AS uid, COALESCE(SUM(count),0) AS c FROM miss_you WHERE group_id = " + g +
      " GROUP BY uid", { uid: "", c: 0 },
    ).map((r) => ({ uid: r.uid, c: r.c })),
    gifts: rows(
      "SELECT sender_uid AS uid, COUNT(*) AS c FROM gifts WHERE group_id = " + g +
      " GROUP BY uid", { uid: "", c: 0 },
    ).map((r) => ({ uid: r.uid, c: r.c })),
  };

  // ── Год по месяцам ────────────────────────────────────────────────────────
  // Три ряда на одной шкале времени: чем пара занималась и как это менялось.
  const monthsBack = "datetime('now','-12 months')";
  out.timeline = {
    memories: rows(
      "SELECT substr(created_at,1,7) AS m, COUNT(*) AS c FROM memories WHERE group_id = " + g +
      " AND deleted = false AND created_at >= " + monthsBack + " GROUP BY m ORDER BY m",
      { m: "", c: 0 },
    ).map((r) => ({ m: r.m, c: r.c })),
    messages: rows(
      "SELECT strftime('%Y-%m', ts/1000, 'unixepoch') AS m, COUNT(*) AS c FROM chat_messages" +
      " WHERE group_id = " + g + " AND deleted = false AND ts >= (strftime('%s','now')-31536000)*1000" +
      " GROUP BY m ORDER BY m", { m: "", c: 0 },
    ).map((r) => ({ m: r.m, c: r.c })),
    moods: rows(
      "SELECT substr(" + moodLocal + ",1,7) AS m, COUNT(*) AS c FROM mood_entries" +
      " WHERE group_id = " + g + " AND timestamp >= " + monthsBack +
      " GROUP BY m ORDER BY m", { m: "", c: 0 },
    ).map((r) => ({ m: r.m, c: r.c })),
  };

  // ── Ритм недели и суток ───────────────────────────────────────────────────
  // strftime('%w') отдаёт 0 = воскресенье; клиент разворачивает под свою неделю.
  out.rhythm = {
    weekdayMessages: rows(
      "SELECT CAST(strftime('%w', ts/1000, 'unixepoch') AS INTEGER) AS d, COUNT(*) AS c" +
      " FROM chat_messages WHERE group_id = " + g + " AND deleted = false GROUP BY d",
      { d: 0, c: 0 },
    ).map((r) => ({ d: r.d, c: r.c })),
    hourMessages: rows(
      "SELECT CAST(strftime('%H', ts/1000, 'unixepoch') AS INTEGER) AS h, COUNT(*) AS c" +
      " FROM chat_messages WHERE group_id = " + g + " AND deleted = false GROUP BY h",
      { h: 0, c: 0 },
    ).map((r) => ({ h: r.h, c: r.c })),
    weekdayMemories: rows(
      "SELECT CAST(strftime('%w', created_at) AS INTEGER) AS d, COUNT(*) AS c" +
      " FROM memories WHERE group_id = " + g + " AND deleted = false GROUP BY d",
      { d: 0, c: 0 },
    ).map((r) => ({ d: r.d, c: r.c })),
  };

  // ── Настроение ────────────────────────────────────────────────────────────
  // Оценку 1…5 держит клиент (каталог настроений), поэтому сюда уходит сам
  // mood_id — переводить его в баллы на сервере значило бы держать вторую
  // копию каталога и расходиться с достижениями.
  out.mood = {
    daily: rows(
      "SELECT substr(" + moodLocal + ",1,10) AS d, user_uid AS uid, mood_id AS id," +
      " COUNT(*) AS c FROM mood_entries WHERE group_id = " + g +
      " AND timestamp >= datetime('now','-90 days') GROUP BY d, uid, id ORDER BY d",
      { d: "", uid: "", id: "", c: 0 },
    ).map((r) => ({ d: r.d, uid: r.uid, id: r.id, c: r.c })),
    top: rows(
      "SELECT mood_id AS id, user_uid AS uid, COUNT(*) AS c FROM mood_entries" +
      " WHERE group_id = " + g + " GROUP BY id, uid ORDER BY c DESC LIMIT 24",
      { id: "", uid: "", c: 0 },
    ).map((r) => ({ id: r.id, uid: r.uid, c: r.c })),
  };

  // ── Что ещё делали ────────────────────────────────────────────────────────
  out.breakdown = {
    memoryTypes: rows(
      "SELECT COALESCE(type,'') AS k, COUNT(*) AS c FROM memories WHERE group_id = " + g +
      " AND deleted = false GROUP BY k ORDER BY c DESC", { k: "", c: 0 },
    ).map((r) => ({ k: r.k, c: r.c })),
    gifts: rows(
      "SELECT gift_key AS k, COUNT(*) AS c FROM gifts WHERE group_id = " + g +
      " GROUP BY k ORDER BY c DESC LIMIT 10", { k: "", c: 0 },
    ).map((r) => ({ k: r.k, c: r.c })),
    watchKinds: rows(
      "SELECT kind AS k, COUNT(*) AS c FROM watch_history WHERE group_id = " + g +
      " GROUP BY k ORDER BY c DESC", { k: "", c: 0 },
    ).map((r) => ({ k: r.k, c: r.c })),
    missYouWeekday: rows(
      "SELECT user_uid AS uid, by_weekday AS w FROM miss_you WHERE group_id = " + g,
      { uid: "", w: "" },
    ).map((r) => ({ uid: r.uid, w: r.w })),
  };

  // ── Темп последних недель ─────────────────────────────────────────────────
  // Основа прогноза: сколько пара делает СЕЙЧАС. Годовое среднее для пары,
  // которая только начала, врало бы вдвое.
  const since = (days) => "(strftime('%s','now')-" + (days * 86400) + ")";
  out.pace = {
    memories30: one("SELECT COUNT(*) AS n FROM memories WHERE group_id = " + g +
      " AND deleted = false AND created_at >= datetime('now','-30 days')"),
    memories90: one("SELECT COUNT(*) AS n FROM memories WHERE group_id = " + g +
      " AND deleted = false AND created_at >= datetime('now','-90 days')"),
    messages30: one("SELECT COUNT(*) AS n FROM chat_messages WHERE group_id = " + g +
      " AND deleted = false AND ts >= " + since(30) + "*1000"),
    messages90: one("SELECT COUNT(*) AS n FROM chat_messages WHERE group_id = " + g +
      " AND deleted = false AND ts >= " + since(90) + "*1000"),
    moods30: one("SELECT COUNT(*) AS n FROM mood_entries WHERE group_id = " + g +
      " AND timestamp >= datetime('now','-30 days')"),
    activeDays30: one("SELECT COUNT(DISTINCT d) AS n FROM (" +
      " SELECT date(ts/1000,'unixepoch') AS d FROM chat_messages WHERE group_id = " + g +
      " AND deleted = false AND ts >= " + since(30) + "*1000" +
      " UNION SELECT substr(" + moodLocal + ",1,10) FROM mood_entries WHERE group_id = " + g +
      " AND timestamp >= datetime('now','-30 days')" +
      " UNION SELECT substr(created_at,1,10) FROM memories WHERE group_id = " + g +
      " AND deleted = false AND created_at >= datetime('now','-30 days'))"),
    firstMemory: rows(
      "SELECT MIN(created_at) AS d FROM memories WHERE group_id = " + g + " AND deleted = false",
      { d: "" },
    ).map((r) => r.d)[0] || "",
  };

  return e.json(200, out);
});
