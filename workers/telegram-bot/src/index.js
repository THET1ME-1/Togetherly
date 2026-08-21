/**
 * Бот баг-репортов @TogetherlyBugsBot: Telegram → Gemini → Todoist.
 *
 * Жил в Firebase Function `telegramWebhook`; после ухода с Firebase её бэкенд
 * перестал подниматься и Telegram получал 503. Переехать на VPS с PocketBase
 * нельзя: российский хостинг и Telegram не видят друг друга (api.telegram.org
 * с VPS — таймаут, вебхук от Telegram до VPS — тоже). Cloudflare вне этой
 * блокировки, поэтому бот живёт здесь.
 *
 * Секреты (wrangler secret put): TELEGRAM_BOT_TOKEN, TODOIST_API_TOKEN,
 * GEMINI_API_KEY, TG_WEBHOOK_SECRET.
 */

import { albumDoneKey, albumPartKey, albumPrefix, isCollector, mergeAlbum } from "./album.js";
import {
  chatKey, closedMessage, closedSeenKey, isReplyComment, noteSeenKey,
  replyMessage, SYNC_TOKEN_KEY,
} from "./replies.js";

const TODOIST_PROJECT_ID = "6ghRcQGgMJv3hwGH";

/// Сколько ждать остальные фото альбома. Телеграм шлёт их подряд, но своими
/// апдейтами: две секунды с запасом покрывают разброс, а человек всё равно
/// ждёт ответа бота, а не мгновенной реакции.
const ALBUM_WAIT_MS = 2500;
const TODOIST_ASSIGNEE_ID = "34940569";
const SECTION_SROCHNO = "6gjcfphM67QjC8Qq"; // 🔴 Срочно
const SECTION_OT_POLZOVATELEY = "6gjw3rP83qwqmvvH"; // 🐛 От пользователей

const CATEGORY_META = {
  crash: { labels: ["Баг / Ошибка"], priority: 4, section: SECTION_SROCHNO, emoji: "🔴" },
  ui_bug: { labels: ["Баг / Ошибка", "UI/IX"], priority: 3, section: SECTION_OT_POLZOVATELEY, emoji: "🟠" },
  bug: { labels: ["Баг / Ошибка"], priority: 3, section: SECTION_OT_POLZOVATELEY, emoji: "🟠" },
  performance: { labels: ["Улучшение"], priority: 2, section: SECTION_OT_POLZOVATELEY, emoji: "🟡" },
  feature: { labels: ["Новая фича"], priority: 1, section: SECTION_OT_POLZOVATELEY, emoji: "🟢" },
  question: { labels: ["Вопрос"], priority: 1, section: SECTION_OT_POLZOVATELEY, emoji: "💬" },
};

function classifyFallback(text) {
  const t = text.toLowerCase();
  if (/crash|вылет|падает|force close|не открывается|зависает/.test(t)) return "crash";
  if (/ui|интерфейс|кнопка|экран|отображ|верст|layout|визуал/.test(t)) return "ui_bug";
  if (/не работает|сломал|ошибка|баг|bug|глюк/.test(t)) return "bug";
  if (/медленно|лагает|тормоз|freeze/.test(t)) return "performance";
  if (/хочу|добавьте|было бы|feature|предлагаю|можно ли/.test(t)) return "feature";
  if (/как|вопрос|подскажите|работает ли|есть ли/.test(t)) return "question";
  return "bug";
}

function makeTitle(text) {
  const sentence = text.split(/[.!?\n]/)[0].trim();
  const clean = sentence.replace(
    /^(баг в том,?\s*(что)?|проблема в том,?\s*(что)?|обнаружил,?\s*(что)?|заметил,?\s*(что)?)\s*/i, "");
  const result = clean.charAt(0).toUpperCase() + clean.slice(1);
  return result.length > 70 ? result.slice(0, 67) + "..." : (result || sentence);
}

async function geminiAnalyze(text, apiKey) {
  const prompt = `Ты помощник разработчика мобильного приложения Togetherly (приложение для пар).
Пользователь написал в поддержку: "${text}"

Определи:
1. category — ОДНО из: crash (падает/вылетает), bug (не работает), ui_bug (визуальная проблема), performance (медленно/лагает), feature (запрос новой функции), question (вопрос как что-то работает), spam (бессмыслица/оскорбление)
2. title — короткое название задачи на русском (до 60 символов), начни с глагола или существительного

Ответь ТОЛЬКО JSON без markdown: {"category":"...","title":"..."}`;

  try {
    const res = await fetch(
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent?key=" + apiKey,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: { maxOutputTokens: 100, temperature: 0.2 },
        }),
      },
    );
    const json = await res.json();
    const raw = json?.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
    if (!raw) return null;
    const parsed = JSON.parse(raw.replace(/```json|```/g, "").trim());
    return (parsed.category && parsed.title) ? parsed : null;
  } catch (err) {
    console.error("gemini failed:", err);
    return null;
  }
}

async function tgSend(env, chatId, text) {
  try {
    await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chat_id: chatId, text, parse_mode: "HTML" }),
    });
  } catch (err) { console.error("sendMessage failed:", err); }
}

/// Что прислали: id файла и его тип. У фото берём последний размер — он самый
/// крупный.
function mediaOf(message) {
  if (message.photo?.length) {
    return {
      fileId: message.photo[message.photo.length - 1].file_id,
      mime: "image/jpeg",
    };
  }
  if (message.video) {
    return {
      fileId: message.video.file_id,
      mime: message.video.mime_type || "video/mp4",
    };
  }
  if (message.document) {
    return {
      fileId: message.document.file_id,
      mime: message.document.mime_type || "application/octet-stream",
    };
  }
  return { fileId: null, mime: "image/jpeg" };
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/// Части альбома, накопленные в KV к этому моменту.
async function albumParts(env, groupId) {
  const listed = await env.ALBUMS.list({ prefix: albumPrefix(groupId) });
  const parts = [];
  for (const key of listed.keys) {
    const raw = await env.ALBUMS.get(key.name);
    if (raw) parts.push(JSON.parse(raw));
  }
  return parts;
}

/// Альбом целиком или null, если собирать его не нам.
///
/// Каждая часть кладёт себя в KV и ждёт остальные. Дальше сравнивают номера
/// сообщений: собирает та, что пришла первой, — так задача заводится ровно
/// одна, без сговора между запросами Worker'а.
async function collectAlbum(env, message, media) {
  const groupId = String(message.media_group_id);
  await env.ALBUMS.put(
    albumPartKey(groupId, message.message_id),
    JSON.stringify({
      messageId: message.message_id,
      fileId: media.fileId,
      mime: media.mime,
      caption: (message.caption || "").trim(),
    }),
    { expirationTtl: 300 },
  );
  await sleep(ALBUM_WAIT_MS);
  const parts = await albumParts(env, groupId);
  if (!isCollector(parts.map((p) => p.messageId), message.message_id)) {
    console.log(`альбом ${groupId}: часть ${message.message_id} ждёт сборщика`);
    return null;
  }
  // Вторая защита от двойной задачи: KV согласуется не мгновенно, и при
  // неудачном стечении две части могут счесть себя первыми.
  const doneKey = albumDoneKey(groupId);
  if (await env.ALBUMS.get(doneKey)) {
    console.log(`альбом ${groupId}: уже собран другой частью`);
    return null;
  }
  await env.ALBUMS.put(doneKey, "1", { expirationTtl: 300 });
  return mergeAlbum(parts);
}

async function handleUpdate(update, env) {
  const message = update.message || update.channel_post;
  if (!message) return;

  const single = mediaOf(message);
  let mediaFileId = single.fileId;
  let mediaMime = single.mime;
  let album = null;

  // Несколько фото одним сообщением приходят разными апдейтами: собираем их в
  // одну задачу, иначе жалоба разлетается на три штуки — текст отдельно,
  // скриншоты отдельно.
  if (message.media_group_id && mediaFileId) {
    album = await collectAlbum(env, message, single);
    if (!album) return;
    mediaFileId = album.media[0]?.fileId || null;
    mediaMime = album.media[0]?.mime || "image/jpeg";
  }

  const text = album
      ? album.caption
      : (message.caption || message.text || "").trim();
  if (!text && !mediaFileId) return;

  const chatId = message.chat.id;
  const from = message.from || {};
  const username = from.username ? `@${from.username}` : (from.first_name || "Аноним");
  const tgLink = from.username ? `https://t.me/${from.username}` : null;

  if (text.startsWith("/")) {
    if (text === "/start") {
      await tgSend(env, chatId,
        "👋 Привет! Опиши баг или проблему в Togetherly — я создам задачу для разработчика. " +
        "Можешь приложить скриншот или видео.");
    }
    return;
  }

  const taskText = text || (mediaMime.startsWith("image") ? "Скриншот от пользователя" : "Видео от пользователя");

  const gemini = await geminiAnalyze(taskText, env.GEMINI_API_KEY);
  const category = gemini?.category || classifyFallback(taskText);
  const title = gemini?.title || makeTitle(taskText);

  if (category === "spam") {
    await tgSend(env, chatId, "Спасибо за обращение!");
    console.log(`spam от ${username}, пропущено`);
    return;
  }

  const meta = CATEGORY_META[category];
  if (!meta) return;

  const replyLine = tgLink ? `\n\n↩️ Ответить: ${tgLink}` : "";
  const created = await fetch("https://api.todoist.com/api/v1/tasks", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${env.TODOIST_API_TOKEN}`,
    },
    body: JSON.stringify({
      content: title,
      description: `От ${username}:\n\n${taskText}${replyLine}`,
      project_id: TODOIST_PROJECT_ID,
      section_id: meta.section,
      priority: meta.priority,
      labels: meta.labels,
      assignee_id: TODOIST_ASSIGNEE_ID,
    }),
  });

  if (!created.ok) {
    console.error(`todoist error ${created.status}:`, await created.text());
    await tgSend(env, chatId, "😔 Не получилось создать задачу. Разработчик уже в курсе, попробуй позже.");
    return;
  }

  const task = await created.json();

  // Кому отвечать по этой задаче. Дальше комментарий со знаком «>» в Todoist
  // уедет этому человеку в Telegram, а закрытие задачи скажет ему, что
  // разобрались.
  if (task?.id) {
    try {
      await env.ALBUMS.put(
        chatKey(task.id),
        JSON.stringify({ chatId, username }),
        { expirationTtl: 60 * 60 * 24 * 180 },
      );
    } catch (err) { console.error("chat bind failed:", err); }
  }

  // Медиа прикрепляем комментариями: Todoist сам скачает файл по file_url
  // (ссылка Telegram живёт около часа — этого хватает). У альбома вложений
  // несколько, и все они висят на одной задаче.
  const attachments = album
      ? album.media
      : (mediaFileId ? [{ fileId: mediaFileId, mime: mediaMime }] : []);
  if (task?.id) {
    for (const item of attachments) {
      try {
        const fileRes = await fetch(
          `https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/getFile?file_id=${item.fileId}`);
        const fileJson = await fileRes.json();
        const filePath = fileJson?.ok ? fileJson.result?.file_path : null;
        if (!filePath) continue;
        await fetch("https://api.todoist.com/api/v1/comments", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${env.TODOIST_API_TOKEN}`,
          },
          body: JSON.stringify({
            task_id: String(task.id),
            content: "📎 Вложение от пользователя",
            attachment: {
              file_name: filePath.split("/").pop(),
              file_type: item.mime,
              file_url: `https://api.telegram.org/file/bot${env.TELEGRAM_BOT_TOKEN}/${filePath}`,
            },
          }),
        });
      } catch (err) { console.error("media attach failed:", err); }
    }
  }

  const mediaNote = attachments.length > 1
      ? ` + 📎 ${attachments.length}`
      : (attachments.length ? " + 📎" : "");
  const replyText = category === "question"
    ? `💬 Вопрос получен, ${username}! Разработчик ответит в ближайшее время.`
    : `${meta.emoji} Принято! Спасибо, ${username}.\nМетка: <b>${meta.labels.join(", ")}</b>${mediaNote}`;
  await tgSend(env, chatId, replyText);

  console.log(`[${category}] от ${username}: "${title}"` +
      (attachments.length ? ` [вложений: ${attachments.length}]` : ""));
}

/// Ответы и закрытия из Todoist — раз в пару минут.
///
/// Sync API отдаёт только то, что изменилось с прошлого раза, поэтому проход
/// стоит один запрос. Первый запуск НИЧЕГО не рассылает: он лишь запоминает
/// точку отсчёта, иначе людям прилетела бы вся история разом.
async function pollTodoist(env) {
  let token = await env.ALBUMS.get(SYNC_TOKEN_KEY);
  const first = !token;
  const res = await fetch("https://api.todoist.com/api/v1/sync", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${env.TODOIST_API_TOKEN}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      sync_token: token || "*",
      resource_types: JSON.stringify(["notes", "items"]),
    }),
  });
  if (!res.ok) {
    console.error(`todoist sync ${res.status}:`, await res.text());
    return;
  }
  const data = await res.json();
  if (data.sync_token) await env.ALBUMS.put(SYNC_TOKEN_KEY, data.sync_token);
  if (first) {
    console.log("sync: первая точка отсчёта взята, рассылки нет");
    return;
  }

  for (const note of data.notes || []) {
    if (note.is_deleted || !isReplyComment(note.content)) continue;
    const seen = noteSeenKey(note.id);
    if (await env.ALBUMS.get(seen)) continue;
    const bound = await env.ALBUMS.get(chatKey(note.item_id));
    if (!bound) continue;
    const text = replyMessage(note.content);
    if (!text) continue;
    await tgSend(env, JSON.parse(bound).chatId, text);
    await env.ALBUMS.put(seen, "1", { expirationTtl: 60 * 60 * 24 * 30 });
    console.log(`ответ ушёл по задаче ${note.item_id}`);
  }

  for (const item of data.items || []) {
    if (!item.checked || item.is_deleted) continue;
    const seen = closedSeenKey(item.id);
    if (await env.ALBUMS.get(seen)) continue;
    const bound = await env.ALBUMS.get(chatKey(item.id));
    if (!bound) continue;
    await tgSend(env, JSON.parse(bound).chatId, closedMessage(item.content));
    await env.ALBUMS.put(seen, "1", { expirationTtl: 60 * 60 * 24 * 180 });
    console.log(`закрытие ушло по задаче ${item.id}`);
  }
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(pollTodoist(env).catch((err) => console.error("sync:", err)));
  },

  async fetch(request, env, ctx) {
    if (request.method !== "POST") return new Response("ok");

    // Без secret_token роут открыт всему интернету: любой мог бы насыпать задач
    // в Todoist. Telegram шлёт его в заголовке при каждом апдейте.
    const secret = request.headers.get("X-Telegram-Bot-Api-Secret-Token");
    if (secret !== env.TG_WEBHOOK_SECRET) return new Response("unauthorized", { status: 401 });

    let update;
    try { update = await request.json(); } catch { return new Response("ok"); }

    // Отвечаем Telegram сразу, обработку доигрываем в фоне: иначе он посчитает
    // медленный ответ недоставкой и переотправит апдейт — получим дубли задач.
    ctx.waitUntil(handleUpdate(update, env).catch((err) => console.error("unhandled:", err)));
    return new Response("ok");
  },
};
