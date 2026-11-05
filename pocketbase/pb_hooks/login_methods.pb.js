/// <reference path="../pb_data/types.d.ts" />
/// Несколько способов входа на одном аккаунте (05.11.2026, макет «Вход без
/// писем», экран «Способы входа»).
///
/// Привязку Google, Apple и Яндекса делает сам PocketBase: вход через
/// провайдера, когда человек уже вошёл, привязывает провайдера к текущему
/// аккаунту (`fallbackAuthRecord` в `record_auth_with_oauth2.go`). Здесь три
/// доработки вокруг этого:
///
///   * `GET /api/auth/methods` — что привязано и знает ли человек пароль;
///   * `POST /api/auth/set-password` — пароль аккаунту, заведённому через
///     провайдера (старого пароля у него нет, его выдумал сервер);
///   * `POST /api/auth/unlink` — отвязать провайдера, но не последний способ.
///
/// «Знает пароль» хранится в `users.password_set` (мс, когда пароль задан
/// человеком). У старых аккаунтов там 0, и тогда решает признак рождения:
/// аккаунт, у которого привязка провайдера появилась в первые две минуты
/// жизни, заведён через провайдера, и пароль у него случайный.
///
/// Всё инлайн: JSVM не показывает обработчику функции уровня файла.

routerAdd("GET", "/api/auth/methods", (e) => {
  const me = e.auth.id;
  const rows = arrayOf(new DynamicModel({ provider: "" }));
  $app.db()
    .newQuery("SELECT provider FROM _externalAuths WHERE recordRef = {:id} AND collectionRef = {:c} ORDER BY created")
    .bind({ id: me, c: e.auth.collection().id })
    .all(rows);
  const born = new DynamicModel({ born: 0, set: 0 });
  $app.db()
    .newQuery(
      "SELECT (SELECT count(*) FROM _externalAuths x WHERE x.recordRef = u.id " +
      "AND abs(julianday(x.created) - julianday(u.created)) * 86400 < 120) AS born, " +
      "coalesce(u.password_set, 0) AS \"set\" FROM users u WHERE u.id = {:id}",
    )
    .bind({ id: me })
    .one(born);
  const providers = [];
  for (let i = 0; i < rows.length; i++) {
    if (providers.indexOf(rows[i].provider) === -1) providers.push(rows[i].provider);
  }
  return e.json(200, {
    password: Number(born.set) > 0 || Number(born.born) === 0,
    providers: providers,
    email: e.auth.email(),
  });
}, $apis.requireAuth("users"));

/// Пароль для аккаунта, заведённого через провайдера. Кто пароль знает,
/// меняет его штатно, со старым паролем.
routerAdd("POST", "/api/auth/set-password", (e) => {
  const rule = require(`${__hooks}/partner_reset.js`);
  const me = e.auth.id;
  let body = {};
  try { body = e.requestInfo().body || {}; } catch (_) { body = {}; }
  const password = body.password;

  const born = new DynamicModel({ born: 0, set: 0 });
  $app.db()
    .newQuery(
      "SELECT (SELECT count(*) FROM _externalAuths x WHERE x.recordRef = u.id " +
      "AND abs(julianday(x.created) - julianday(u.created)) * 86400 < 120) AS born, " +
      "coalesce(u.password_set, 0) AS \"set\" FROM users u WHERE u.id = {:id}",
    )
    .bind({ id: me })
    .one(born);
  if (Number(born.set) > 0 || Number(born.born) === 0) {
    return e.json(409, { code: "has_password", message: "Пароль уже есть. Смените его со старым паролем." });
  }
  const problem = rule.passwordProblem(password);
  if (problem) return e.json(400, { code: problem, message: problem === "short" ? "Нужно не меньше 8 символов." : "Слишком длинный пароль." });

  const user = $app.findRecordById("users", me);
  user.setPassword(password);
  $app.save(user);
  $app.db()
    .newQuery("UPDATE users SET password_set = {:t} WHERE id = {:id}")
    .bind({ t: Date.now(), id: me })
    .execute();
  $app.logger().warn("login-methods: пароль задан", "uid", me);
  // Смена пароля меняет ключ токенов: прежний токен этого телефона больше не
  // годится, поэтому отдаём новый, как при входе.
  return $apis.recordAuthResponse(e, user, "password", null);
}, $apis.requireAuth("users"));

/// Отвязать провайдера. Последний способ входа не отдаём: без него аккаунт
/// закрылся бы насовсем.
routerAdd("POST", "/api/auth/unlink", (e) => {
  const me = e.auth.id;
  let body = {};
  try { body = e.requestInfo().body || {}; } catch (_) { body = {}; }
  const provider = String(body.provider || "");

  const rows = arrayOf(new DynamicModel({ provider: "" }));
  $app.db()
    .newQuery("SELECT DISTINCT provider FROM _externalAuths WHERE recordRef = {:id}")
    .bind({ id: me })
    .all(rows);
  const providers = rows.map((r) => r.provider);
  if (providers.indexOf(provider) === -1) return e.json(200, { ok: true });

  const born = new DynamicModel({ born: 0, set: 0 });
  $app.db()
    .newQuery(
      "SELECT (SELECT count(*) FROM _externalAuths x WHERE x.recordRef = u.id " +
      "AND abs(julianday(x.created) - julianday(u.created)) * 86400 < 120) AS born, " +
      "coalesce(u.password_set, 0) AS \"set\" FROM users u WHERE u.id = {:id}",
    )
    .bind({ id: me })
    .one(born);
  const hasPassword = Number(born.set) > 0 || Number(born.born) === 0;
  if (providers.length + (hasPassword ? 1 : 0) <= 1) {
    return e.json(409, { code: "last", message: "Это последний способ входа. Сначала привяжите другой." });
  }
  $app.db()
    .newQuery("DELETE FROM _externalAuths WHERE recordRef = {:id} AND provider = {:p}")
    .bind({ id: me, p: provider })
    .execute();
  $app.logger().warn("login-methods: отвязан провайдер", "uid", me, "provider", provider);
  return e.json(200, { ok: true });
}, $apis.requireAuth("users"));

/// Привязка провайдера, пока человек уже вошёл.
///
/// PocketBase сам держит две защиты от угона, и обе здесь мешают:
///   * провайдер, привязанный к ДРУГОМУ аккаунту, молча входит в тот аккаунт,
///     и телефон оказывается в чужом профиле — отвечаем отказом;
///   * у неподтверждённого аккаунта каждая новая привязка стирает прежние
///     («не больше одной привязки у неподтверждённого»). Почту подтверждали
///     единицы, и Яндекс снимал бы Google. Человек уже вошёл в этот аккаунт,
///     значит, он его хозяин: для этой привязки считаем аккаунт подтверждённым
///     (только в памяти запроса, в базу флаг не пишется).
onRecordAuthWithOAuth2Request((e) => {
  if (e.auth && e.record && e.auth.collection().id === e.record.collection().id) {
    if (e.record.id !== e.auth.id) {
      $app.logger().warn("login-methods: провайдер у другого аккаунта", "uid", e.auth.id, "provider", e.providerName);
      throw new BadRequestError("linked_elsewhere");
    }
    if (!e.record.verified()) e.record.setVerified(true);
  }
  e.next();
}, "users");

/// Вошёл по паролю — значит, знает его. Пишем один раз, без лишней записи на
/// каждом входе.
onRecordAuthWithPasswordRequest((e) => {
  e.next();
  try {
    if (e.record && !Number(e.record.get("password_set") || 0)) {
      $app.db()
        .newQuery("UPDATE users SET password_set = {:t} WHERE id = {:id} AND coalesce(password_set, 0) = 0")
        .bind({ t: Date.now(), id: e.record.id })
        .execute();
    }
  } catch (_) {
    // отметка — подсказка экрану, а не условие входа
  }
}, "users");

/// Пароль, заданный по ссылке из письма, человек тоже знает.
onRecordConfirmPasswordResetRequest((e) => {
  e.next();
  try {
    $app.db()
      .newQuery("UPDATE users SET password_set = {:t} WHERE id = {:id}")
      .bind({ t: Date.now(), id: e.record.id })
      .execute();
  } catch (_) {
    // см. выше
  }
}, "users");
