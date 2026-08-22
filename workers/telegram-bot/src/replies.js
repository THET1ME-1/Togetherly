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
///
/// Маркер снимается с КАЖДОЙ строки, а не только с первой: Todoist оформляет
/// ответ цитатой и сам расставляет стрелки по всем строкам. Пока срезался один
/// символ, человеку уезжал текст со стрелками посреди сообщения (22.08.2026).
/// Строки без маркера не трогаем — стрелка в середине фразы («5 > 3») остаётся.
export function replyBody(content) {
  const text = String(content ?? "").trimStart();
  if (!text.startsWith(REPLY_MARK)) return text.trim();
  return text
      .split("\n")
      .map((line) => {
        const trimmed = line.trimStart();
        if (!trimmed.startsWith(REPLY_MARK)) return line;
        return trimmed.slice(REPLY_MARK.length).replace(/^[ \t]+/, "");
      })
      .join("\n")
      .trim();
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

/// Отметки бота в комментарии — по ним видно судьбу ответа, не выходя из
/// задачи.
export const SENT_MARK = "✅ Отправлено";
export const FAILED_MARK = "⚠️ Не отправлено";

/// Комментарий с отметкой о доставке.
///
/// Дописываем в конец, а не заменяем: текст ответа остаётся на месте, а строка
/// снизу говорит, дошло ли. Повторно не помечаем — иначе каждый проход крона
/// наращивал бы хвост.
export function markDelivery(content, { ok, reason } = {}) {
  const text = String(content ?? "").trimEnd();
  if (text.includes(SENT_MARK) || text.includes(FAILED_MARK)) return text;
  const note = ok
      ? SENT_MARK
      : `${FAILED_MARK}: ${String(reason || "неизвестно").trim()}`;
  return `${text}\n\n${note}`;
}

/// Уже помечен?
export const isMarked = (content) => {
  const text = String(content ?? "");
  return text.includes(SENT_MARK) || text.includes(FAILED_MARK);
};
