/// <reference path="../pb_data/types.d.ts" />

// Удалённый холст не воскресает (TOG-12, 22.10.2026).
//
// Галерея сборок до 1.38.x при первом открытии за запуск шлёт в каталог ВСЕ
// холсты, что лежат у неё на телефоне, в том числе удалённые партнёром. Холст
// заводился на сервере снова, и у обоих («почему холсты нельзя удалять»,
// повторено на эмуляторе: «Canvas 3» вернулся сразу после открытия галереи).
// Эти сборки уже у людей, поэтому сервер помнит удалённые холсты
// (`canvas_catalogue_deleted`) и не даёт завести их снова. Новые холсты
// получают новый номер (`canvas_<время>`), им запрет не мешает.
//
// Хелперов уровня файла нет намеренно: обработчик JSVM их не видит.

onRecordAfterDeleteSuccess((e) => {
  try {
    const g = e.record.getString("group_id");
    const c = e.record.getString("canvas_id");
    if (g && c) {
      const now = new Date().toISOString().replace("T", " ");
      $app.db().newQuery(
        "INSERT OR IGNORE INTO canvas_catalogue_deleted (id, group_id, canvas_id, created, updated) " +
        "VALUES ('r' || lower(hex(randomblob(7))), {:g}, {:c}, {:now}, {:now})"
      ).bind({ g: g, c: c, now: now }).execute();
    }
  } catch (err) {
    $app.logger().warn("canvas_catalogue_guard: удаление не записано", "error", String(err));
  }
  e.next();
}, "canvas_catalogue");

onRecordCreateRequest((e) => {
  let deleted = false;
  const g = e.record.getString("group_id");
  const c = e.record.getString("canvas_id");
  try {
    const row = new DynamicModel({ n: 0 });
    $app.db().newQuery(
      "SELECT COUNT(*) AS n FROM canvas_catalogue_deleted WHERE group_id = {:g} AND canvas_id = {:c}"
    ).bind({ g: g, c: c }).one(row);
    deleted = row.n > 0;
  } catch (err) {
    // Журнала нет или он не читается — пропускаем: лишний холст лучше, чем
    // запрет заводить новые.
    $app.logger().warn("canvas_catalogue_guard: журнал не прочитан", "error", String(err));
  }
  if (deleted) {
    $app.logger().warn("canvas_catalogue_guard: удалённый холст не заводим", "group", g, "canvas", c);
    throw new BadRequestError("canvas was deleted");
  }
  e.next();
}, "canvas_catalogue");
