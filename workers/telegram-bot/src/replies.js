/**
 * Ответы людям из Todoist.
 *
 * Человек пишет боту и остаётся в тишине: задача заводится, чинится, закрывается
 * — а он об этом не узнаёт. Отвечать в личку руками неудобно, ссылка `↩️ Ответить`
 * в задаче есть, но открывать её лень, и половина обращений остаётся без слова.
 *
 * Поэтому ответ пишется там же, где ведётся разбор: комментарием к задаче,
 * первой строкой со знаком `>`. Бот пересылает его человеку. Служебные записи
 * (мои разборы, ссылки, заметки на будущее) остаются в Todoist — они без `>`.
 */

/// Маркер ответа: комментарий, который надо переслать человеку.
export const REPLY_MARK = ">";

/// Это ответ человеку или служебная запись?
export function isReplyComment(content) {
  return typeof content === "string" && content.trimStart().startsWith(REPLY_MARK);
}

/// Текст ответа без маркера.
export function replyBody(content) {
  const text = String(content ?? "").trimStart();
  if (!text.startsWith(REPLY_MARK)) return text.trim();
  return text.slice(REPLY_MARK.length).trim();
}

/// Что уходит человеку в Telegram.
export function replyMessage(content) {
  const body = replyBody(content);
  return body ? `💬 Ответ от разработчика:\n\n${body}` : "";
}

/// Сообщение о закрытой задаче.
export function closedMessage(title) {
  const name = String(title ?? "").trim();
  return name
      ? `✅ Разобрались: ${name}\n\nСпасибо, что написали.`
      : "✅ Разобрались с вашим обращением. Спасибо, что написали.";
}

/// Ключи KV.
export const chatKey = (taskId) => `chat:${taskId}`;
export const noteSeenKey = (noteId) => `note:${noteId}`;
export const closedSeenKey = (taskId) => `closed:${taskId}`;
export const SYNC_TOKEN_KEY = "sync:token";
