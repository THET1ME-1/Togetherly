/// Вход через Google без страницы в браузере (09.11.2026).
///
/// Страница Google рвалась у владельца: Google просит подтвердить личность
/// ключом доступа, человек уходит в другое приложение, Android закрывает
/// соединение, по которому PocketBase ждёт ответа, и страница отвечает «Auth
/// failed». Теперь на Android вход берёт системное окно выбора аккаунта, на
/// iPhone — окно Google, и оба отдают idToken прямо приложению.
///
/// Подпись, аудиторию и срок токена проверяет релей `apns_relay.py`
/// (`/google/verify`): в JSVM нет ни RS256, ни загрузки ключей. Устроено как
/// `apple_native.pb.js`.
///
/// POST /api/google/native { idToken }
///   → 200 { token, record }  — как у обычного входа, клиент сохраняет сессию
///   → 4xx { ok: false, reason }
///
/// Человека находим по `sub`: вход через страницу кладёт в `_externalAuths`
/// тот же `sub` (веб-клиент один проект), значит прежние аккаунты находятся.
/// Связки нет — по почте: Google отдаёт её только подтверждённой.
routerAdd("POST", "/api/google/native", (e) => {
  const body = e.requestInfo().body || {};
  const idToken = String(body.idToken || "").trim();

  const deny = (status, reason) => {
    try {
      $app.logger().warn("google native: отказ", "reason", reason);
    } catch (_) { /* журнал не должен ронять вход */ }
    return e.json(status, { ok: false, reason: reason });
  };

  if (!idToken) return deny(400, "нет idToken");

  // ── проверка токена ───────────────────────────────────────────────────────
  let claims;
  try {
    const res = $http.send({
      url: "http://127.0.0.1:8096/google/verify",
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token: idToken }),
      timeout: 20,
    });
    claims = res.json || {};
  } catch (err) {
    return deny(502, "проверка токена недоступна: " + String(err));
  }
  if (!claims.ok) return deny(401, String(claims.reason || "токен не принят"));

  const sub = String(claims.sub || "");
  const email = String(claims.email || "").toLowerCase();
  const name = String(claims.name || "").trim();
  if (!sub) return deny(401, "в токене нет sub");

  const usersCol = $app.findCollectionByNameOrId("users");
  const linksCol = $app.findCollectionByNameOrId("_externalAuths");

  // ── кто это ───────────────────────────────────────────────────────────────
  let user = null;
  try {
    const link = $app.findFirstRecordByFilter(
      "_externalAuths",
      "provider = 'google' && providerId = {:sub}",
      { sub: sub },
    );
    user = $app.findRecordById("users", link.getString("recordRef"));
  } catch (_) { user = null; }

  let byEmail = false;
  if (!user && email) {
    try {
      user = $app.findFirstRecordByFilter("users", "email = {:e}", { e: email });
      byEmail = true;
    } catch (_) { user = null; }
  }

  // Аккаунт нашёлся по почте, а почту в нём никто не подтверждал: завести его
  // по паролю мог кто угодно, в расчёте на то, что хозяин почты потом войдёт
  // через Google в эту заготовку, а пароль останется рабочим. Google почту
  // подтвердил, значит аккаунт теперь хозяина почты: прежний пароль и все
  // прежние входы гасим, как делает штатный вход PocketBase страницей
  // (10.11.2026, стенд — `pocketbase/native_signin_stand.test.py`).
  // `password_set = -1` — «пароль выдуман сервером»: экран «Способы входа»
  // покажет, что пароля нет, и даст задать свой.
  if (user && byEmail && !user.verified()) {
    try {
      user.setPassword($security.randomString(40));
      user.setVerified(true);
      $app.save(user);
      $app.db()
        .newQuery("UPDATE users SET password_set = -1 WHERE id = {:id}")
        .bind({ id: user.id })
        .execute();
      $app.logger().warn("google native: прежний пароль неподтверждённого аккаунта погашен", "uid", user.id);
    } catch (err) {
      return deny(500, "не удалось погасить прежний пароль: " + String(err));
    }
  }

  // Бан по почте, как у обычной регистрации (users_guard.pb.js).
  if (!user && email) {
    try {
      const bytes = $os.readFile("/opt/pocketbase/pb_data/.banned_emails");
      const banned = String.fromCharCode.apply(null, bytes).split("\n")
        .map((s) => s.trim().toLowerCase()).filter(Boolean);
      if (banned.indexOf(email) !== -1) return deny(403, "регистрация закрыта");
    } catch (_) { /* нет файла — регистрации не мешаем */ }
  }

  let created = false;
  if (!user) {
    if (!email) return deny(401, "в токене нет почты");
    try {
      user = new Record(usersCol);
      user.set("email", email);
      user.set("emailVisibility", true);
      user.set("verified", true);
      // Пароль человеку не нужен: он входит окном Google. Поле обязательное,
      // поэтому кладём случайный и никому не показываем.
      const secret = $security.randomString(40);
      user.set("password", secret);
      user.set("passwordConfirm", secret);
      const display = name || email.split("@")[0];
      user.set("name", display);
      user.set("display_name", display);
      $app.save(user);
      created = true;
    } catch (err) {
      return deny(500, "не удалось создать аккаунт: " + String(err));
    }
  }

  // ── связка на будущее ─────────────────────────────────────────────────────
  try {
    $app.findFirstRecordByFilter(
      "_externalAuths",
      "provider = 'google' && providerId = {:sub}",
      { sub: sub },
    );
  } catch (_) {
    try {
      const link = new Record(linksCol);
      link.set("collectionRef", usersCol.id);
      link.set("provider", "google");
      link.set("providerId", sub);
      link.set("recordRef", user.id);
      $app.save(link);
    } catch (err) {
      $app.logger().warn("google native: связка не создана", "err", String(err));
    }
  }

  // ── сессия ────────────────────────────────────────────────────────────────
  const meta = { created: created, name: name, avatarURL: String(claims.picture || "") };
  try {
    return $apis.recordAuthResponse(e, user, "google", meta);
  } catch (err) {
    try {
      return e.json(200, { token: String(user.newAuthToken()), record: user.publicExport(), meta: meta });
    } catch (err2) {
      return deny(500, "не удалось выдать сессию: " + String(err2));
    }
  }
});
