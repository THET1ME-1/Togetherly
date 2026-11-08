/// Тексты уведомлений хуков на языке получателя.
///
/// Пуши пишет сервер, и до 08.11.2026 он писал их только по-русски: языка,
/// выбранного в приложении, он не знал (отзыв в App Store 19.08.2026: «The
/// notification and widgets are in Russian though the app I have set to
/// English»). Приложение кладёт код языка в `users.lang`, `apns_push.js`
/// передаёт его сюда. Пусто или незнакомо — русский, как было.
///
/// Тексты hotpath (чат, «Скучаю», настроение, воспоминания) — в
/// `../hotpath/push_texts.py`. `_f` и `_m` — по роду того, кто действует;
/// без рода — нейтральная строка.

const LANGS = ["ru", "en", "de", "fr", "es", "it", "pt", "zh", "uk"];

const TEXTS = {
  partner: {
    ru: "Партнёр", en: "Partner", de: "Partner", fr: "Partenaire", es: "Tu pareja",
    it: "Partner", pt: "Seu par", zh: "伴侣", uk: "Партнер",
  },
  comment: {
    ru: "Комментарий к воспоминанию", en: "Comment on a memory",
    de: "Kommentar zu einer Erinnerung", fr: "Commentaire sur un souvenir",
    es: "Comentario en un recuerdo", it: "Commento a un ricordo",
    pt: "Comentário em uma lembrança", zh: "评论了一段回忆", uk: "Коментар до спогаду",
  },
  draw_title: {
    ru: "{name} зовёт порисовать", en: "{name} invites you to draw",
    de: "{name} lädt dich zum Malen ein", fr: "{name} t’invite à dessiner",
    es: "{name} te invita a dibujar", it: "{name} ti invita a disegnare",
    pt: "{name} te chama para desenhar", zh: "{name}邀你一起画画",
    uk: "{name} кличе малювати",
  },
  draw_body: {
    ru: "Открыл раскраску — заходите рисовать вместе",
    en: "The coloring page is open, come draw together",
    de: "Das Ausmalbild ist offen, malt zusammen",
    fr: "Le coloriage est ouvert, venez dessiner ensemble",
    es: "El dibujo está abierto, venid a pintar juntos",
    it: "Il disegno è aperto, venite a colorare insieme",
    pt: "O desenho está aberto, venham pintar juntos",
    zh: "涂色页已打开，一起来画吧",
    uk: "Розмальовку відкрито, заходьте малювати разом",
  },
  reels_title: {
    ru: "{name} зовёт смотреть {feed}", en: "{name} invites you to watch {feed}",
    de: "{name} lädt dich zu {feed} ein", fr: "{name} t’invite à regarder {feed}",
    es: "{name} te invita a ver {feed}", it: "{name} ti invita a guardare {feed}",
    pt: "{name} te chama para ver {feed}", zh: "{name}邀你一起看{feed}",
    uk: "{name} кличе дивитися {feed}",
  },
  reels_feed: {
    ru: "ленту", en: "the feed", de: "den Feed", fr: "le fil", es: "el feed",
    it: "il feed", pt: "o feed", zh: "视频流", uk: "стрічку",
  },
  reels_body: {
    ru: "Совместная лента: ролики из ваших лент по очереди, чат и звонок",
    en: "Shared feed: videos from both your feeds in turn, chat and a call",
    de: "Gemeinsamer Feed: Videos aus euren Feeds im Wechsel, Chat und Anruf",
    fr: "Fil commun : vos vidéos à tour de rôle, chat et appel",
    es: "Feed compartido: vídeos de vuestros feeds por turnos, chat y llamada",
    it: "Feed condiviso: video dai vostri feed a turno, chat e chiamata",
    pt: "Feed compartilhado: vídeos dos seus feeds alternados, chat e chamada",
    zh: "共享视频流：轮流播放你们的视频，还能聊天和通话",
    uk: "Спільна стрічка: ролики з ваших стрічок по черзі, чат і дзвінок",
  },
  gift_f: {
    ru: "Прислала тебе подарок 🎁", en: "Sent you a gift 🎁", de: "Hat dir ein Geschenk geschickt 🎁",
    fr: "T’a envoyé un cadeau 🎁", es: "Te envió un regalo 🎁", it: "Ti ha mandato un regalo 🎁",
    pt: "Te mandou um presente 🎁", zh: "送了你一份礼物 🎁", uk: "Надіслала тобі подарунок 🎁",
  },
  gift_m: {
    ru: "Прислал тебе подарок 🎁", en: "Sent you a gift 🎁", de: "Hat dir ein Geschenk geschickt 🎁",
    fr: "T’a envoyé un cadeau 🎁", es: "Te envió un regalo 🎁", it: "Ti ha mandato un regalo 🎁",
    pt: "Te mandou um presente 🎁", zh: "送了你一份礼物 🎁", uk: "Надіслав тобі подарунок 🎁",
  },
  gift_x: {
    ru: "Прислал(а) тебе подарок 🎁", en: "Sent you a gift 🎁", de: "Hat dir ein Geschenk geschickt 🎁",
    fr: "T’a envoyé un cadeau 🎁", es: "Te envió un regalo 🎁", it: "Ti ha mandato un regalo 🎁",
    pt: "Te mandou um presente 🎁", zh: "送了你一份礼物 🎁", uk: "Надіслав(ла) тобі подарунок 🎁",
  },
  frame_f: {
    ru: "Отдала тебе свою рамку для аватарки", en: "Gave you their avatar frame",
    de: "Hat dir ihren Avatar-Rahmen geschenkt", fr: "T’a donné son cadre d’avatar",
    es: "Te regaló su marco de avatar", it: "Ti ha regalato la sua cornice avatar",
    pt: "Te deu sua moldura de avatar", zh: "把自己的头像框送给了你",
    uk: "Віддала тобі свою рамку для аватарки",
  },
  frame_m: {
    ru: "Отдал тебе свою рамку для аватарки", en: "Gave you their avatar frame",
    de: "Hat dir seinen Avatar-Rahmen geschenkt", fr: "T’a donné son cadre d’avatar",
    es: "Te regaló su marco de avatar", it: "Ti ha regalato la sua cornice avatar",
    pt: "Te deu sua moldura de avatar", zh: "把自己的头像框送给了你",
    uk: "Віддав тобі свою рамку для аватарки",
  },
  frame_x: {
    ru: "Отдал(а) тебе свою рамку для аватарки", en: "Gave you their avatar frame",
    de: "Hat dir den eigenen Avatar-Rahmen geschenkt", fr: "T’a donné son cadre d’avatar",
    es: "Te regaló su marco de avatar", it: "Ti ha regalato la sua cornice avatar",
    pt: "Te deu sua moldura de avatar", zh: "把自己的头像框送给了你",
    uk: "Віддав(ла) тобі свою рамку для аватарки",
  },
  plusgift_title: {
    ru: "Togetherly+ — подарок 💜", en: "Togetherly+ is a gift 💜", de: "Togetherly+ geschenkt 💜",
    fr: "Togetherly+ offert 💜", es: "Togetherly+ de regalo 💜", it: "Togetherly+ in regalo 💜",
    pt: "Togetherly+ de presente 💜", zh: "Togetherly+ 礼物 💜", uk: "Togetherly+ у подарунок 💜",
  },
  plusgift_from: {
    ru: "{name} подарил(а) вам полный доступ", en: "{name} gave you full access",
    de: "{name} hat dir vollen Zugang geschenkt", fr: "{name} vous a offert l’accès complet",
    es: "{name} te regaló el acceso completo", it: "{name} ti ha regalato l’accesso completo",
    pt: "{name} te deu acesso completo", zh: "{name}送了你完整权限",
    uk: "{name} подарував(ла) вам повний доступ",
  },
  plusgift_anon: {
    ru: "Вам подарили полный доступ", en: "You’ve been given full access",
    de: "Dir wurde voller Zugang geschenkt", fr: "On vous a offert l’accès complet",
    es: "Te regalaron el acceso completo", it: "Ti hanno regalato l’accesso completo",
    pt: "Você ganhou acesso completo", zh: "你获得了完整权限", uk: "Вам подарували повний доступ",
  },
  reset_title: {
    ru: "{name} восстанавливает доступ", en: "{name} is restoring access",
    de: "{name} stellt den Zugang wieder her", fr: "{name} récupère son accès",
    es: "{name} está recuperando el acceso", it: "{name} sta recuperando l’accesso",
    pt: "{name} está recuperando o acesso", zh: "{name}正在找回账号",
    uk: "{name} відновлює доступ",
  },
  reset_body_f: {
    ru: "Откройте Togetherly, там код. Передайте его, только если {name} сама попросила",
    en: "Open Togetherly to see the code. Share it only if {name} asked you to",
    de: "Öffne Togetherly, dort ist der Code. Gib ihn nur weiter, wenn {name} selbst darum gebeten hat",
    fr: "Ouvrez Togetherly pour voir le code. Ne le donnez que si {name} l’a demandé",
    es: "Abre Togetherly para ver el código. Pásalo solo si {name} te lo pidió",
    it: "Apri Togetherly per vedere il codice. Passalo solo se {name} te l’ha chiesto",
    pt: "Abra o Togetherly para ver o código. Passe-o só se {name} pediu",
    zh: "打开 Togetherly 查看验证码。只有{name}本人要求时才告诉对方",
    uk: "Відкрийте Togetherly, там код. Передайте його, лише якщо {name} сама попросила",
  },
  reset_body_m: {
    ru: "Откройте Togetherly, там код. Передайте его, только если {name} сам попросил",
    en: "Open Togetherly to see the code. Share it only if {name} asked you to",
    de: "Öffne Togetherly, dort ist der Code. Gib ihn nur weiter, wenn {name} selbst darum gebeten hat",
    fr: "Ouvrez Togetherly pour voir le code. Ne le donnez que si {name} l’a demandé",
    es: "Abre Togetherly para ver el código. Pásalo solo si {name} te lo pidió",
    it: "Apri Togetherly per vedere il codice. Passalo solo se {name} te l’ha chiesto",
    pt: "Abra o Togetherly para ver o código. Passe-o só se {name} pediu",
    zh: "打开 Togetherly 查看验证码。只有{name}本人要求时才告诉对方",
    uk: "Відкрийте Togetherly, там код. Передайте його, лише якщо {name} сам попросив",
  },
  security_title: {
    ru: "Кто-то пытался войти в ваш аккаунт", en: "Someone tried to sign in to your account",
    de: "Jemand wollte sich in dein Konto einloggen", fr: "Quelqu’un a tenté de se connecter à votre compte",
    es: "Alguien intentó entrar en tu cuenta", it: "Qualcuno ha provato ad accedere al tuo account",
    pt: "Alguém tentou entrar na sua conta", zh: "有人尝试登录你的账号",
    uk: "Хтось намагався увійти у ваш акаунт",
  },
  security_body_f: {
    ru: "{name} не подтвердила запрос кода. Если это были вы, попросите код ещё раз",
    en: "{name} didn’t confirm the code request. If it was you, ask for the code again",
    de: "{name} hat die Code-Anfrage nicht bestätigt. Warst du es, fordere den Code erneut an",
    fr: "{name} n’a pas confirmé la demande de code. Si c’était vous, redemandez le code",
    es: "{name} no confirmó la solicitud del código. Si fuiste tú, pide el código otra vez",
    it: "{name} non ha confermato la richiesta del codice. Se eri tu, richiedi il codice",
    pt: "{name} não confirmou o pedido de código. Se foi você, peça o código de novo",
    zh: "{name}没有确认验证码请求。如果是你本人，请重新获取验证码",
    uk: "{name} не підтвердила запит коду. Якщо це були ви, попросіть код ще раз",
  },
  security_body_m: {
    ru: "{name} не подтвердил запрос кода. Если это были вы, попросите код ещё раз",
    en: "{name} didn’t confirm the code request. If it was you, ask for the code again",
    de: "{name} hat die Code-Anfrage nicht bestätigt. Warst du es, fordere den Code erneut an",
    fr: "{name} n’a pas confirmé la demande de code. Si c’était vous, redemandez le code",
    es: "{name} no confirmó la solicitud del código. Si fuiste tú, pide el código otra vez",
    it: "{name} non ha confermato la richiesta del codice. Se eri tu, richiedi il codice",
    pt: "{name} não confirmou o pedido de código. Se foi você, peça o código de novo",
    zh: "{name}没有确认验证码请求。如果是你本人，请重新获取验证码",
    uk: "{name} не підтвердив запит коду. Якщо це були ви, попросіть код ще раз",
  },
};

/// Код из профиля → язык текста. Пусто или незнакомо — русский.
function langOf(code) {
  const c = String(code || "").trim().toLowerCase().slice(0, 2);
  return LANGS.indexOf(c) >= 0 ? c : "ru";
}

/// Текст [key] на языке [code] с подстановками `{имя}` из [vars].
function t(key, code, vars) {
  const variants = TEXTS[key];
  let text = variants[langOf(code)] || variants.ru;
  if (vars) {
    for (const k in vars) text = text.split("{" + k + "}").join(String(vars[k]));
  }
  return text;
}

module.exports = { LANGS, TEXTS, langOf, t };
