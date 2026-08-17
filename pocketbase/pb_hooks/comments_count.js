/// comments_count.js — пересчёт числа комментариев под воспоминанием.
///
/// Живёт отдельным модулем, потому что обработчики JSVM не видят функций уровня
/// файла: хуки подключают это через `require`.
///
/// Счётчик лежит в json-поле `data` воспоминания — отдельной колонки в схеме
/// `memories` нет, поэтому читаем карту, правим одно поле и сохраняем обратно.
/// Пишем только при расхождении: иначе каждый комментарий рождал бы лишнюю
/// запись и лишнее realtime-событие на всю пару.

function apply(memoryId) {
  if (!memoryId) return;

  let memory;
  try {
    memory = $app.findRecordById("memories", memoryId);
  } catch (_) {
    return; // воспоминание удалили — считать нечего
  }

  let count = 0;
  try {
    count = $app.countRecords(
      "memory_comments",
      $dbx.exp("memory_id = {:m} AND deleted = false", { m: memoryId }),
    );
  } catch (err) {
    $app.logger().warn("счётчик комментариев: не посчитал",
      "memory", memoryId, "err", String(err));
    return;
  }

  const raw = memory.get("data");
  const data = (raw && typeof raw === "object") ? raw : {};
  if (Number(data.commentsCount || 0) === Number(count)) return;

  data.commentsCount = Number(count);
  memory.set("data", data);
  try {
    $app.save(memory);
  } catch (err) {
    $app.logger().warn("счётчик комментариев: не сохранил",
      "memory", memoryId, "err", String(err));
  }
}

module.exports = { apply: apply };
