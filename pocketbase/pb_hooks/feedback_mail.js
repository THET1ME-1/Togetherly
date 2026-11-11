/// Обращение из приложения: проверка, тема и тело письма, доставка в ящик
/// поддержки (11.11.2026).
///
/// Google Play отклонил 1.42 по правилам о безопасности детей: приложение
/// обязано давать человеку сообщить о проблеме, не выходя из него, а у нас
/// поддержка открывала почту и Telegram. Форма теперь в приложении
/// (`lib/screens/feedback_screen.dart`), маршрут — `feedback.pb.js`.
///
/// Письмо кладётся прямо во «Входящие» ящика support@ по JMAP, минуя SMTP: у
/// домена DMARC `p=reject`, а отправителем стоит почта человека, чтобы на
/// обращение отвечали обычным «Ответить». Сторож почты приёмной видит такое
/// письмо как любое другое.
///
/// Модуль, а не хук: обработчики JSVM не видят функций своего файла и
/// подключают его через `require(`${__hooks}/feedback_mail.js`)`.

// Виды обращений; ключи — те же, что шлёт приложение.
const KINDS = {
  bug: 'Ошибка',
  idea: 'Предложение',
  payment: 'Оплата',
  abuse: 'Жалоба на человека или содержимое',
  child_safety: 'Безопасность детей',
  other: 'Другое',
};
const MIN = 10;
const MAX = 4000;
// Обращений в сутки от одного человека.
const PER_DAY = 5;
const BOX = 'support@togetherly.day';
const JMAP = 'http://127.0.0.1:8080/jmap/';
const USING = ['urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:mail'];

/// Почему обращение не принять; пустая строка — принять.
function problemOf(kind, text) {
  if (!Object.prototype.hasOwnProperty.call(KINDS, String(kind || ''))) return 'bad_kind';
  const body = String(text || '').trim();
  if (body.length < MIN) return 'too_short';
  if (body.length > MAX) return 'too_long';
  return '';
}

/// Такое обращение должно бросаться в глаза в ящике.
function urgent(kind) {
  return kind === 'child_safety' || kind === 'abuse';
}

function subjectOf(kind, text) {
  const start = String(text || '').replace(/\s+/g, ' ').trim().slice(0, 70);
  const head = kind === 'child_safety' ? '[БЕЗОПАСНОСТЬ ДЕТЕЙ] ' : '';
  return `${head}[Приложение] ${KINDS[kind] || KINDS.other}: ${start}`.slice(0, 110);
}

function bodyOf(f) {
  return [
    String(f.text || '').trim(),
    '',
    '—',
    `Вид: ${KINDS[f.kind] || f.kind}`,
    `Человек: ${f.name || 'без имени'}, ${f.email || 'почты нет'}`,
    `Аккаунт: ${f.uid}`,
    `Приложение: ${f.app || '?'}, ${f.platform || '?'}, язык ${f.lang || '?'}`,
    `Обращение: ${f.id}`,
  ].join('\n');
}

/// Письмо в виде, в котором его принимает JMAP `Email/set`.
function mailOf(f, inbox) {
  const mail = {
    mailboxIds: { [inbox]: true },
    keywords: urgent(f.kind) ? { $flagged: true } : {},
    from: f.email
      ? [{ name: f.name || f.email, email: f.email }]
      : [{ name: 'Togetherly', email: BOX }],
    to: [{ email: BOX }],
    subject: subjectOf(f.kind, f.text),
    bodyValues: { b: { value: bodyOf(f) } },
    textBody: [{ partId: 'b', type: 'text/plain' }],
  };
  if (f.email) mail.replyTo = [{ email: f.email }];
  return mail;
}

function dayKey(uid, nowMs) {
  return `fb_${uid}_${new Date(nowMs).toISOString().slice(0, 10)}`;
}

/// Положить письмо в ящик поддержки. true — легло.
/// Доступ — `SUPPORT_JMAP_BASIC` в окружении PocketBase: готовая строка
/// «Basic …» (base64 в этой сборке JSVM посчитать нечем).
function deliver(f) {
  const auth = String($os.getenv('SUPPORT_JMAP_BASIC') || '');
  if (!auth) return false;
  const call = (methodCalls) => {
    const res = $http.send({
      url: JMAP,
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: auth },
      body: JSON.stringify({ using: USING, methodCalls: methodCalls }),
      timeout: 10,
    });
    if (res.statusCode !== 200 || !res.json) throw new Error('jmap ' + res.statusCode);
    return res.json.methodResponses[0][1];
  };
  const session = $http.send({
    url: JMAP + 'session', method: 'GET', headers: { Authorization: auth }, timeout: 10,
  });
  if (session.statusCode !== 200 || !session.json) throw new Error('jmap session ' + session.statusCode);
  const account = session.json.primaryAccounts['urn:ietf:params:jmap:mail'];
  const boxes = call([['Mailbox/get', { accountId: account, properties: ['role'] }, 'a']]).list || [];
  let inbox = '';
  for (let i = 0; i < boxes.length; i++) if (boxes[i].role === 'inbox') inbox = boxes[i].id;
  if (!inbox) throw new Error('jmap: нет ящика «Входящие»');
  const made = call([['Email/set', { accountId: account, create: { m: mailOf(f, inbox) } }, 'c']]);
  return !!(made.created && made.created.m);
}

module.exports = {
  KINDS, MIN, MAX, PER_DAY, problemOf, urgent, subjectOf, bodyOf, mailOf, dayKey, deliver,
};
