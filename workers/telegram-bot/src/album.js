/**
 * Альбом из Telegram: несколько фото одним сообщением.
 *
 * Телеграм шлёт такой альбом РАЗНЫМИ апдейтами — по одному на каждое фото, — и
 * связывает их только полем `media_group_id`. Бот обрабатывал каждый апдейт
 * сам по себе и заводил задачу на каждое фото: жалоба 21.08.2026 разлетелась
 * на три задачи, текст в одной, два скриншота в соседних, и разбирать её
 * приходилось по кусочкам.
 *
 * Части складываются в KV, а собирает их одна — та, чьё сообщение пришло
 * первым. Признак детерминированный, поэтому договариваться между запросами
 * Worker'а не нужно: все видят один список и один и тот же минимум.
 */

export const albumPrefix = (groupId) => `mg:${groupId}:`;

/// Отметка «этот альбом уже собран». Живёт ВНЕ префикса частей: попади она в
/// общий список, её приняли бы за часть и минимум номеров посчитался бы по
/// мусору.
export const albumDoneKey = (groupId) => `done:${groupId}`;

export const albumPartKey = (groupId, messageId) =>
    `${albumPrefix(groupId)}${messageId}`;

/// Моя ли очередь собирать альбом.
export function isCollector(messageIds, myId) {
  if (!messageIds.length) return false;
  return Math.min(...messageIds) === myId;
}

/// Склеивает части в одну жалобу: подпись и список вложений по порядку.
export function mergeAlbum(parts) {
  const ordered = [...parts].sort((a, b) => a.messageId - b.messageId);
  const withCaption = ordered.find((p) => (p.caption || '').trim());
  return {
    caption: (withCaption?.caption || '').trim(),
    media: ordered.map((p) => ({ fileId: p.fileId, mime: p.mime })),
  };
}
