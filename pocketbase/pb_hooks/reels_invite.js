/// reels_invite.js — правила зова в совместную ленту.
///
/// Отдельным модулем, потому что обработчики JSVM не видят функций уровня
/// файла: хук подключает это через `require`, тест — через node
/// (`node pocketbase/pb_hooks/reels_invite.test.js`).

/// Площадки ленты — те же ключи, что `ReelsSource.key` в приложении и
/// `SOURCES` в reels.js.
const FEEDS = {
  shorts: "YouTube Shorts",
  tiktok: "TikTok",
  rutube: "Rutube",
  vk: "ВК Клипы",
  dzen: "Дзен",
};

/// Зов не чаще раза в 10 минут: человек может выйти из ленты и зайти снова,
/// и каждый вход не должен будить партнёра заново.
const GAP_MS = 10 * 60 * 1000;

/// Сколько зов считается живым: столько партнёр без Плюса может войти по
/// плитке, не дожидаясь нового пуша.
const ACTIVE_MS = 3 * 60 * 60 * 1000;

function feedOf(raw) {
  const k = String(raw || "").toLowerCase().trim();
  return FEEDS[k] ? k : "";
}

function mayInvite(lastMs, nowMs) {
  const now = Number(nowMs);
  const last = Number(lastMs);
  if (!isFinite(now) || now <= 0) return false;
  if (!isFinite(last) || last <= 0 || last > now) return true;
  return now - last >= GAP_MS;
}

/// Заголовок и текст пуша. Имя не склоняем: «Аня зовёт смотреть TikTok».
///
/// [lang] — язык приложения получателя (`users.lang`); пусто — русский.
function message(name, feed, lang) {
  const T = require((typeof __hooks === "string" ? __hooks : __dirname) + "/push_texts.js");
  const who = String(name || "").trim() || T.t("partner", lang);
  return {
    title: T.t("reels_title", lang, { name: who, feed: FEEDS[feed] || T.t("reels_feed", lang) }),
    body: T.t("reels_body", lang),
  };
}

/// Живой ли зов: [at] — когда звали, [stopped] — партнёр вышел из ленты.
function isActive(session, nowMs) {
  if (!session || !session.at || session.stopped) return false;
  const age = Number(nowMs) - Number(session.at);
  return age >= 0 && age < ACTIVE_MS;
}

/// Есть ли Плюс: купленный или пробный из сундука ([trialUntilMs] — до какого
/// момента он действует). С одним `plus` пробный зов отбивался, и партнёр не
/// получал ни пуша, ни входа (обращение 558, 02.11.2026).
function hasPlus(plus, trialUntilMs, nowMs) {
  if (plus) return true;
  const until = Number(trialUntilMs);
  return isFinite(until) && until > Number(nowMs);
}

module.exports = { FEEDS, GAP_MS, ACTIVE_MS, feedOf, mayInvite, message, isActive, hasPlus };
