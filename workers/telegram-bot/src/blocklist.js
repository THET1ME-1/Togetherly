/**
 * Кому бот не отвечает.
 *
 * Бот открыт всем, и изредка попадается человек, который пишет по кругу одно и
 * то же и не унимается после ответов: его обращения засоряют доску задач.
 * Такого заносим сюда — его сообщения не разбираются, задачи по ним не
 * заводятся, и ответы из Todoist ему не уходят.
 *
 * Держим и числовой id, и имя. Имя человек меняет в пару кликов, id — нет,
 * поэтому id главный, а имя ловит того, чей id ещё не знаем.
 */

const BLOCKED_IDS = new Set([
  "5259635693", // @Dimon9313, заблокирован 02.09.2026
]);

const BLOCKED_USERNAMES = new Set([
  "dimon9313",
]);

/// Отправитель (`message.from` или `{ id: chatId }`) в списке?
export function isBlocked(from) {
  if (!from) return false;
  if (from.id !== undefined && from.id !== null && BLOCKED_IDS.has(String(from.id))) return true;
  const name = String(from.username ?? "").replace(/^@/, "").toLowerCase();
  return name !== "" && BLOCKED_USERNAMES.has(name);
}
