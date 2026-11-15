/// Обращения из приложения Stowa (15.11.2026): проверка, письмо, доставка.
///
/// Stowa живёт без аккаунтов, поэтому маршрут открытый, а от потока его
/// держат пределы в `stowa_feedback.pb.js`. Письмо ложится во «Входящие»
/// support@ по JMAP, как обращения Togetherly (`feedback_mail.js`), дальше его
/// несёт в Gmail служба `support-forward`. Модуль отдельный, чтобы правка
/// Stowa не задела приём Togetherly.

const KINDS = { bug: 'Ошибка', idea: 'Идея', question: 'Вопрос' };
const MIN = 10;
const MAX = 4000;
// Обращений в сутки с одного адреса и всего.
const PER_IP = 5;
const PER_DAY = 200;
const BOX = 'support@togetherly.day';
const JMAP = 'http://127.0.0.1:8080/jmap/';
const USING = ['urn:ietf:params:jmap:core', 'urn:ietf:params:jmap:mail'];
const EMAIL = /^[^\s@<>"]+@[^\s@<>"]+\.[^\s@<>"]+$/;

/// Почему обращение не принять; пустая строка — принять.
function problemOf(f) {
  if (!Object.prototype.hasOwnProperty.call(KINDS, String(f.kind || ''))) return 'bad_kind';
  const text = String(f.text || '').trim();
  if (text.length < MIN) return 'too_short';
  if (text.length > MAX) return 'too_long';
  const email = String(f.email || '').trim();
  if (email && (email.length > 200 || !EMAIL.test(email))) return 'bad_email';
  return '';
}

function subjectOf(f) {
  const start = String(f.text || '').replace(/\s+/g, ' ').trim().slice(0, 70);
  return `[Stowa] ${KINDS[f.kind] || 'Обращение'}: ${start}`.slice(0, 110);
}

function bodyOf(f) {
  return [
    String(f.text || '').trim(),
    '',
    '—',
    `Вид: ${KINDS[f.kind] || f.kind}`,
    `Ответить: ${f.email || 'почту не оставили'}`,
    `Телефон: ${f.device || 'не приложен'}`,
    `Приложение: Stowa ${f.app || '?'}, ${f.platform || '?'}, язык ${f.lang || '?'}`,
    `Обращение: ${f.id}`,
  ].join('\n');
}

/// Письмо в виде, в котором его принимает JMAP `Email/set`.
function mailOf(f, inbox) {
  const mail = {
    mailboxIds: { [inbox]: true },
    keywords: {},
    from: f.email ? [{ name: f.email, email: f.email }] : [{ name: 'Stowa', email: BOX }],
    to: [{ email: BOX }],
    subject: subjectOf(f),
    bodyValues: { b: { value: bodyOf(f) } },
    textBody: [{ partId: 'b', type: 'text/plain' }],
  };
  if (f.email) mail.replyTo = [{ email: f.email }];
  return mail;
}

function dayKey(who, nowMs) {
  return `stowa_fb_${who}_${new Date(nowMs).toISOString().slice(0, 10)}`;
}

/// Положить письмо в ящик поддержки. true — легло. Доступ — `SUPPORT_JMAP_BASIC`.
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
  const session = $http.send({ url: JMAP + 'session', method: 'GET', headers: { Authorization: auth }, timeout: 10 });
  if (session.statusCode !== 200 || !session.json) throw new Error('jmap session ' + session.statusCode);
  const account = session.json.primaryAccounts['urn:ietf:params:jmap:mail'];
  const boxes = call([['Mailbox/get', { accountId: account, properties: ['role'] }, 'a']]).list || [];
  let inbox = '';
  for (let i = 0; i < boxes.length; i++) if (boxes[i].role === 'inbox') inbox = boxes[i].id;
  if (!inbox) throw new Error('jmap: нет ящика «Входящие»');
  const made = call([['Email/set', { accountId: account, create: { m: mailOf(f, inbox) } }, 'c']]);
  return !!(made.created && made.created.m);
}

/// Коллекция заводится сама при первом обращении: правила закрыты, пишут только хуки.
function ensureCollection() {
  try {
    return $app.findCollectionByNameOrId('stowa_feedback');
  } catch (_) {
    const collection = new Collection({
      type: 'base',
      name: 'stowa_feedback',
      listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
      fields: [
        { name: 'kind', type: 'text', max: 30 },
        { name: 'text', type: 'text', max: 5000 },
        { name: 'email', type: 'text', max: 200 },
        { name: 'device', type: 'text', max: 200 },
        { name: 'app', type: 'text', max: 40 },
        { name: 'platform', type: 'text', max: 20 },
        { name: 'lang', type: 'text', max: 10 },
        { name: 'delivered', type: 'bool' },
        { name: 'created', type: 'autodate', onCreate: true, onUpdate: false },
        { name: 'updated', type: 'autodate', onCreate: true, onUpdate: true },
      ],
      indexes: ['CREATE INDEX `idx_stowa_feedback_delivered` ON `stowa_feedback` (`delivered`)'],
    });
    $app.save(collection);
    return collection;
  }
}

function fieldsOf(rec) {
  return {
    id: rec.id, kind: rec.getString('kind'), text: rec.getString('text'), email: rec.getString('email'),
    device: rec.getString('device'), app: rec.getString('app'), platform: rec.getString('platform'), lang: rec.getString('lang'),
  };
}

module.exports = {
  KINDS, MIN, MAX, PER_IP, PER_DAY, problemOf, subjectOf, bodyOf, mailOf, dayKey, deliver, ensureCollection, fieldsOf,
};
