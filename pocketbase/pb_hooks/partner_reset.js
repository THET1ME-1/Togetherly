/// partner_reset.js — правила сброса пароля через партнёра (05.11.2026).
///
/// Живёт отдельным модулем, потому что обработчики JSVM не видят функций уровня
/// файла: хук подключает это через `require`, а тест — через node
/// (`partner_reset.test.js`).
///
/// Код из шести цифр открывает аккаунт целиком, поэтому у него короткий срок и
/// мало попыток, а запросы не идут лавиной: каждый будит партнёра пушем.

/// Сколько живёт код у партнёра.
const CODE_TTL_MS = 10 * 60 * 1000;

/// Промахов до блокировки кода. Миллион вариантов на пять попыток.
const MAX_TRIES = 5;

/// Не чаще раза в две минуты на аккаунт, как у письма сброса.
const GAP_MS = 2 * 60 * 1000;

/// Запросов на аккаунт за сутки: больше похоже на перебор, чем на забытый пароль.
const DAY_LIMIT = 5;
const DAY_MS = 24 * 60 * 60 * 1000;

/// Сколько живёт пропуск на смену пароля после верного кода.
const TICKET_TTL_MS = 15 * 60 * 1000;

/// Можно ли слать новый запрос. [history] — отметки прошлых запросов (мс).
/// Возвращает {ok, why, history}: why — `gap` или `day`, history — что
/// сохранить (без устаревших отметок, с новой при успехе).
function mayRequest(history, now) {
  const recent = [];
  const list = Array.isArray(history) ? history : [];
  for (let i = 0; i < list.length; i++) {
    const t = Number(list[i]);
    if (isFinite(t) && t > 0 && t <= now && now - t < DAY_MS) recent.push(t);
  }
  let last = 0;
  for (let i = 0; i < recent.length; i++) if (recent[i] > last) last = recent[i];
  if (last && now - last < GAP_MS) return { ok: false, why: 'gap', history: recent };
  if (recent.length >= DAY_LIMIT) return { ok: false, why: 'day', history: recent };
  recent.push(now);
  return { ok: true, why: '', history: recent };
}

/// Сверка введённого кода с запросом [state] = {code, at, tries}.
/// Возвращает {verdict, left}: verdict — ok, wrong, expired, locked, none.
/// Промах увеличивает state.tries на месте: хук сохраняет запрос обратно.
function checkCode(state, input, now) {
  if (!state || !state.code) return { verdict: 'none', left: 0 };
  if (now - Number(state.at || 0) > CODE_TTL_MS) return { verdict: 'expired', left: 0 };
  const tries = Number(state.tries || 0);
  if (tries >= MAX_TRIES) return { verdict: 'locked', left: 0 };
  const digits = String(input == null ? '' : input).replace(/\D/g, '');
  if (digits.length === 6 && digits === String(state.code)) return { verdict: 'ok', left: MAX_TRIES - tries };
  state.tries = tries + 1;
  const left = MAX_TRIES - state.tries;
  return { verdict: left <= 0 ? 'locked' : 'wrong', left: Math.max(0, left) };
}

/// Партнёр из живой пары на двоих. [groups] — строки {id, members, disbanded},
/// members — json-строка или массив. Порядок строк — порядок предпочтения.
function pickPartner(me, groups) {
  const list = Array.isArray(groups) ? groups : [];
  for (let i = 0; i < list.length; i++) {
    const g = list[i] || {};
    if (Number(g.disbanded) || g.disbanded === true) continue;
    let members = g.members;
    if (typeof members === 'string') {
      try { members = JSON.parse(members); } catch (_) { members = null; }
    }
    if (!Array.isArray(members) || members.length !== 2) continue;
    if (members.indexOf(me) === -1) continue;
    const partner = String(members[0] === me ? members[1] : members[0]);
    if (partner && partner !== me) return { groupId: String(g.id), partner: partner };
  }
  return null;
}

/// Что не так с паролем: null, `short` или `long` (bcrypt режет после 72 байт).
function passwordProblem(password) {
  if (typeof password !== 'string' || password.length < 8) return 'short';
  if (password.length > 71) return 'long';
  return null;
}

module.exports = {
  CODE_TTL_MS: CODE_TTL_MS,
  MAX_TRIES: MAX_TRIES,
  GAP_MS: GAP_MS,
  DAY_LIMIT: DAY_LIMIT,
  TICKET_TTL_MS: TICKET_TTL_MS,
  mayRequest: mayRequest,
  checkCode: checkCode,
  pickPartner: pickPartner,
  passwordProblem: passwordProblem,
};
