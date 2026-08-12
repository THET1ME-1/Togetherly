/// Нативный вход через Apple.
///
/// Веб-вход отказывает у части людей: системный браузер не может загрузить
/// `appleid.apple.com`, и за сутки таких обрывов 77 против 33 удачных входов на
/// 57 разных телефонах. Ссылка при этом правильная, версия iOS не при чём, а в
/// журнале сервера одна ошибка за те же сутки — до нас дело просто не доходит.
/// Значит лечить надо не браузер, а способ: на iPhone вход берёт системный
/// диалог (`ASAuthorizationController`), никакой страницы не открывая.
///
/// Приложение присылает сюда `identityToken` — подписанный Apple JWT. Проверку
/// подписи (RS256 по JWKS Apple) делает релей `apns_relay.py`: в JSVM нет ни
/// RS256, ни загрузки ключей.
///
/// POST /api/apple/native { identityToken, nonce?, name? }
///   → 200 { token, record }  — как у обычного входа, клиент сохраняет сессию
///   → 4xx { ok: false, reason }
///
/// Человека находим по `sub` из токена: PocketBase хранит связку в
/// `_externalAuths`, и `sub` у одного Apple ID внутри команды один и тот же —
/// значит те, кто раньше входил через веб, попадают в свои прежние аккаунты, а
/// не заводят вторые.
routerAdd("POST", "/api/apple/native", (e) => {
  const body = e.requestInfo().body || {};
  const idToken = String(body.identityToken || "").trim();
  const nonce = String(body.nonce || "");
  const nameHint = String(body.name || "").trim();

  const deny = (status, reason) => {
    try {
      $app.logger().warn("apple native: отказ", "reason", reason);
    } catch (_) { /* журнал не должен ронять вход */ }
    return e.json(status, { ok: false, reason: reason });
  };

  if (!idToken) return deny(400, "нет identityToken");

  // ── проверка токена ───────────────────────────────────────────────────────
  let claims;
  try {
    const res = $http.send({
      url: "http://127.0.0.1:8096/apple/verify",
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token: idToken, nonce: nonce }),
      timeout: 20,
    });
    claims = res.json || {};
  } catch (err) {
    return deny(502, "проверка токена недоступна: " + String(err));
  }
  if (!claims.ok) return deny(401, String(claims.reason || "токен не принят"));

  const sub = String(claims.sub || "");
  const email = String(claims.email || "").toLowerCase();
  if (!sub) return deny(401, "в токене нет sub");

  const usersCol = $app.findCollectionByNameOrId("users");
  const linksCol = $app.findCollectionByNameOrId("_externalAuths");

  // ── кто это ───────────────────────────────────────────────────────────────
  let user = null;

  try {
    const link = $app.findFirstRecordByFilter(
      "_externalAuths",
      "provider = 'apple' && providerId = {:sub}",
      { sub: sub },
    );
    user = $app.findRecordById("users", link.getString("recordRef"));
  } catch (_) { user = null; }

  // Почта Apple («…@privaterelay.appleid.com») у человека одна и та же, поэтому
  // ею закрываем случай, когда связки нет, а аккаунт уже есть — например, вход
  // раньше был по почте.
  if (!user && email) {
    try {
      user = $app.findFirstRecordByFilter(
        "users", "email = {:e}", { e: email });
    } catch (_) { user = null; }
  }

  let created = false;
  if (!user) {
    try {
      user = new Record(usersCol);
      user.set("email", email);
      user.set("emailVisibility", true);
      user.set("verified", true);
      // Пароль человеку не нужен: он входит системным диалогом. Но поле
      // обязательное, поэтому кладём случайный и никому не показываем.
      const secret = $security.randomString(40);
      user.set("password", secret);
      user.set("passwordConfirm", secret);
      const display = nameHint || (email ? email.split("@")[0] : "Пара");
      user.set("name", display);
      user.set("display_name", display);
      user.set("platform", "ios");
      $app.save(user);
      created = true;
    } catch (err) {
      return deny(500, "не удалось создать аккаунт: " + String(err));
    }
  } else if (nameHint) {
    // Имя Apple отдаёт только при первом входе — не теряем его, если профиль
    // ещё пустой.
    try {
      if (!String(user.getString("display_name") || "").trim()) {
        user.set("display_name", nameHint);
        user.set("name", nameHint);
        $app.save(user);
      }
    } catch (_) { /* имя не критично */ }
  }

  // ── связка на будущее ─────────────────────────────────────────────────────
  try {
    $app.findFirstRecordByFilter(
      "_externalAuths",
      "provider = 'apple' && providerId = {:sub}",
      { sub: sub },
    );
  } catch (_) {
    try {
      const link = new Record(linksCol);
      link.set("collectionRef", usersCol.id);
      link.set("provider", "apple");
      link.set("providerId", sub);
      link.set("recordRef", user.id);
      $app.save(link);
    } catch (err) {
      // Вход всё равно состоится, просто в следующий раз человека найдём по
      // почте. Знать об этом полезно.
      $app.logger().warn("apple native: связка не создана", "err", String(err));
    }
  }

  // ── сессия ────────────────────────────────────────────────────────────────
  // `recordAuthResponse` отдаёт ответ той же формы, что обычный вход, поэтому
  // клиенту достаточно сохранить его как есть. `$tokens` в этой сборке
  // PocketBase нет (проверено), а `newAuthToken` остаётся запасным путём.
  try {
    return $apis.recordAuthResponse(e, user, "apple", { created: created });
  } catch (err) {
    try {
      return e.json(200, {
        token: String(user.newAuthToken()),
        record: user.publicExport(),
        created: created,
      });
    } catch (err2) {
      return deny(500, "не удалось выдать сессию: " + String(err2));
    }
  }
});
