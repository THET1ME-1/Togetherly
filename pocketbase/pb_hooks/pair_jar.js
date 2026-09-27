/// Копилка пары (28.09.2026): любой засчитанный ролик любого из двоих кладёт
/// каплю. Десять капель — каждому из пары по открытию сундука без рекламы,
/// сверх трёх в день, и копилка начинается заново.
///
/// Модуль, а не хук: хендлеры JSVM не видят функций своего файла, поэтому
/// `coins.pb.js` (ролик) и `chest.pb.js` (состояние, открытие) подключают его
/// внутри хендлера через `require(`${__hooks}/pair_jar.js`)`.
///
/// Запись `pair_jars` — одна на пару (`group_id` уникален):
///   drops      json  uid по капле в порядке, как клали (не больше SIZE)
///   day        text  UTC-день счёта полных копилок
///   jars_today number сколько копилок наполнено за этот день
///   bonus      json  {uid: сколько открытий из копилки ждёт}
///   last       json  {uid: мс последней капли} — против накрутки вызовом роута
///
/// Правила коллекции закрыты целиком: пишут и читают только хуки.

const SIZE = 10;
// Больше двух полных копилок в сутки на пару капли не падают: награда —
// сундук, а у сундука свой дневной предел.
const JARS_PER_DAY = 2;
// Ролик идёт не меньше пятнадцати секунд; чаще капли от одного человека —
// это вызов роута в обход рекламы.
const MIN_GAP_MS = 15 * 1000;
const HOTPATH = "http://127.0.0.1:8120/internal/group-read?id=";

function parse(s, fb) {
  try { const v = JSON.parse(s || ""); return v == null ? fb : v; } catch (_) { return fb; }
}

// Состав пары — из Postgres: зеркало в SQLite отстаёт. null — пары нет,
// распущена или в ней не двое.
function pairMembers(groupId) {
  if (!groupId) return null;
  try {
    const r = $http.send({ url: HOTPATH + encodeURIComponent(groupId), method: "GET", timeout: 6 });
    const rec = (r && r.json && r.json.record) || null;
    if (!rec || rec.disbanded === true) return null;
    const m = Array.isArray(rec.members) ? rec.members.map(String) : [];
    return m.length === 2 ? m : null;
  } catch (_) { return null; }
}

// Пара, в которую падает капля: присланная приложением, если человек в ней
// состоит; иначе первая живая из его `group_ids` (старые сборки пару не шлют).
function pickPair(uid, groupId) {
  if (groupId) {
    const m = pairMembers(groupId);
    return m && m.indexOf(uid) !== -1 ? { groupId: groupId, members: m } : null;
  }
  let ids = [];
  try { ids = $app.findRecordById("users", uid).getStringSlice("group_ids") || []; } catch (_) { ids = []; }
  for (let i = 0; i < ids.length && i < 6; i++) {
    const m = pairMembers(String(ids[i]));
    if (m && m.indexOf(uid) !== -1) return { groupId: String(ids[i]), members: m };
  }
  return null;
}

function findJar(app, groupId) {
  try {
    return app.findFirstRecordByFilter("pair_jars", "group_id = {:g}", { g: groupId });
  } catch (_) { return null; }
}

function view(rec, uid, extra) {
  const drops = rec ? parse(rec.getString("drops"), []) : [];
  const bonus = rec ? parse(rec.getString("bonus"), {}) : {};
  const today = new Date().toISOString().slice(0, 10);
  const jarsToday = rec && rec.getString("day") === today ? (rec.getInt("jars_today") || 0) : 0;
  let mine = 0;
  for (let i = 0; i < drops.length; i++) if (drops[i] === uid) mine++;
  return Object.assign({
    size: SIZE,
    drops: drops.map((d) => (d === uid ? 1 : 2)), // 1 — моя капля, 2 — партнёра
    mine: mine,
    partner: drops.length - mine,
    bonus: Math.max(0, parseInt(bonus[uid] || 0, 10) || 0),
    capped: jarsToday >= JARS_PER_DAY,
  }, extra || {});
}

/// Капля от засчитанного ролика. Возвращает вид копилки для ответа роута
/// (`added` — упала ли капля, `filled` — наполнилась ли копилка) или null,
/// если пары нет.
function addDrop(uid, groupId) {
  const pair = pickPair(uid, groupId);
  if (!pair) return null;
  let out = null;
  $app.runInTransaction((tx) => {
    let rec = findJar(tx, pair.groupId);
    if (!rec) {
      rec = new Record(tx.findCollectionByNameOrId("pair_jars"));
      rec.set("group_id", pair.groupId);
      rec.set("drops", "[]");
      rec.set("bonus", "{}");
      rec.set("last", "{}");
      rec.set("day", "");
      rec.set("jars_today", 0);
    }
    const now = Date.now();
    const today = new Date(now).toISOString().slice(0, 10);
    if (rec.getString("day") !== today) {
      rec.set("day", today);
      rec.set("jars_today", 0);
    }
    const drops = parse(rec.getString("drops"), []).filter((d) => pair.members.indexOf(d) !== -1);
    const last = parse(rec.getString("last"), {});
    const bonus = parse(rec.getString("bonus"), {});
    let added = false, filled = false;
    if ((rec.getInt("jars_today") || 0) < JARS_PER_DAY && now - (parseInt(last[uid] || 0, 10) || 0) >= MIN_GAP_MS) {
      drops.push(uid);
      last[uid] = now;
      added = true;
      if (drops.length >= SIZE) {
        filled = true;
        drops.length = 0;
        for (let i = 0; i < pair.members.length; i++) {
          const m = pair.members[i];
          bonus[m] = (parseInt(bonus[m] || 0, 10) || 0) + 1;
        }
        rec.set("jars_today", (rec.getInt("jars_today") || 0) + 1);
      }
    }
    rec.set("drops", JSON.stringify(drops));
    rec.set("last", JSON.stringify(last));
    rec.set("bonus", JSON.stringify(bonus));
    tx.save(rec);
    out = view(rec, uid, { added: added, filled: filled });
  });
  return out;
}

/// Копилка для экрана: без записи, только чтение.
function state(uid, groupId) {
  const pair = pickPair(uid, groupId);
  if (!pair) return null;
  return view(findJar($app, pair.groupId), uid);
}

/// Списать одно открытие из копилки внутри транзакции открытия сундука.
/// true — списано.
function takeBonus(tx, groupId, uid) {
  const rec = findJar(tx, groupId);
  if (!rec) return false;
  const bonus = parse(rec.getString("bonus"), {});
  const n = parseInt(bonus[uid] || 0, 10) || 0;
  if (n <= 0) return false;
  bonus[uid] = n - 1;
  rec.set("bonus", JSON.stringify(bonus));
  tx.save(rec);
  return true;
}

/// Сколько открытий из копилки ждёт человека (для ответа после открытия).
function bonusLeft(app, groupId, uid) {
  const rec = findJar(app, groupId);
  if (!rec) return 0;
  return Math.max(0, parseInt(parse(rec.getString("bonus"), {})[uid] || 0, 10) || 0);
}

module.exports = { addDrop: addDrop, state: state, takeBonus: takeBonus, bonusLeft: bonusLeft, SIZE: SIZE };
