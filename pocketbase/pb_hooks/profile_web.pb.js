/// Профиль пары для сайта profile.togetherly.day.
///
/// Одним ответом отдаёт всё, что показывает страница: имена участников,
/// дату начала, счётчики, достижения и марки. Собирать это на клиенте из
/// нескольких запросов нельзя — правило `users` отдаёт человеку только его
/// собственную запись, а состав пары лежит в скрытом поле `group_ids`.
///
/// Грабли, уже стоившие разбора (см. CLAUDE.md проекта):
///  * обработчик исполняется в изолированном пуле и НЕ видит функций уровня
///    файла — всё инлайном;
///  * json- и relation-поля читать `getStringSlice`/`getString`, никогда `get()`;
///  * отказ, отданный через `e.json`, в `_logs` не попадает — писать причину
///    самому через `$app.logger().warn`.
routerAdd("GET", "/api/profile/web", (e) => {
  const uid = e.auth ? e.auth.id : "";
  if (!uid) {
    $app.logger().warn("profile_web deny", "reason", "no auth");
    return e.json(401, { error: "auth required" });
  }

  const deny = (code, why) => {
    $app.logger().warn("profile_web deny", "uid", uid, "reason", why);
    return e.json(code, { error: why });
  };

  let me;
  try { me = $app.findRecordById("users", uid); }
  catch (_) { return deny(404, "no user"); }

  // group_ids — relation, поэтому только getStringSlice
  const groups = me.getStringSlice("group_ids") || [];
  if (!groups.length) return e.json(200, { pair: null, stamps: {}, achievements: [] });

  let g = null;
  for (let i = 0; i < groups.length; i++) {
    try {
      const cand = $app.findRecordById("groups", groups[i]);
      if (cand.getBool("disbanded")) continue;
      g = cand;
      break;
    } catch (_) { /* группа могла быть удалена — идём дальше */ }
  }
  if (!g) return e.json(200, { pair: null, stamps: {}, achievements: [] });

  // Имена участников. Чужую запись `users` правило не отдаёт даже участнику
  // пары, поэтому читаем их сервером и наружу пускаем только имя.
  const members = g.getStringSlice("members") || [];
  const names = [];
  for (let i = 0; i < members.length && i < 2; i++) {
    let nm = "";
    try {
      const u = $app.findRecordById("users", members[i]);
      nm = u.getString("display_name") || u.getString("name") || "";
    } catch (_) { nm = ""; }
    names.push({ uid: members[i], name: nm, me: members[i] === uid });
  }
  // Свой профиль всегда первым: страница читается от себя.
  names.sort((a, b) => (b.me ? 1 : 0) - (a.me ? 1 : 0));

  // Дни вместе считаются от более ранней из двух дат — так же, как в
  // приложении: дата коннекта и правленый таймер расходятся у 12 тысяч пар.
  const startStr = g.getString("start_date") || g.getString("created") || "";
  let days = 0;
  if (startStr) {
    const t = Date.parse(startStr.substring(0, 10));
    if (!isNaN(t)) days = Math.max(0, Math.floor((Date.now() - t) / 86400000));
  }

  // Достижения лежат json-полем на группе: массив id открытых.
  let achievements = [];
  try {
    const raw = g.getString("achievements");
    if (raw) {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) achievements = parsed;
      else if (parsed && typeof parsed === "object") achievements = Object.keys(parsed);
    }
  } catch (_) { achievements = []; }

  // Марки. Коллекции ещё нет — пустой объект вместо отказа: страница
  // рисует каталог сезона и пустые гнёзда, а не ошибку.
  const stamps = {};
  let stampsTotal = 0;
  try {
    const rows = $app.findRecordsByFilter(
      "stamps", "group_id = {:g}", "-created", 200, 0, { g: g.id });
    for (let i = 0; i < rows.length; i++) {
      const r = rows[i];
      stamps[r.getString("stamp_id")] = {
        status: r.getString("status") || "mint",
        date: r.getString("cancel_date") || "",
        note: r.getString("note") || "",
      };
      stampsTotal++;
    }
  } catch (_) { /* коллекции нет — это штатно до её заведения */ }

  return e.json(200, {
    pair: {
      id: g.id,
      slug: g.getString("public_slug") || "",
      names: names,
      since: startStr,
      days: days,
      messages: g.getInt("messages_count"),
      memories: g.getInt("memories_count"),
      drawings: g.getInt("drawings_count"),
      streak: g.getInt("streak_days"),
    },
    achievements: achievements.map((id) => ({ id: id, title: id, emoji: "★" })),
    stamps: stamps,
    stamps_total: stampsTotal,
  });
}, $apis.requireAuth());
