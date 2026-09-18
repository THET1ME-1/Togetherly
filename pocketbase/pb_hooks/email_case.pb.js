/// Почта без учёта регистра: вход и сброс пароля.
///
/// PocketBase ищет почту без учёта регистра, только если у уникального
/// индекса по `email` стоит `COLLATE NOCASE`. У нас индекс старый, без него, и
/// поиск идёт с точностью до буквы. Клавиатура телефона ставит первой букве
/// заглавную сама, и «Anna@gmail.com» не находил аккаунт «anna@gmail.com»:
///
///   • вход отвечал «неверная почта или пароль» при верном пароле;
///   • «Забыли пароль» отвечал 204, приложение говорило «письмо отправлено»,
///     а письмо не уходило вовсе (разбор 18.09.2026: «Jer0ccyXD@mail.ru» —
///     отказ, тот же адрес строчными — письмо доставлено).
///
/// На 18.09.2026 в базе 269 пар аккаунтов, различающихся только регистром
/// почты: человек не мог войти и заводил второй. Из-за них индекс нельзя
/// просто пересоздать с NOCASE — уникальность сломается, — поэтому поиск
/// чинится здесь: штатный путь PocketBase идёт первым, а без учёта регистра
/// ищем, только когда он промахнулся, и берём аккаунт, только если такой адрес
/// в базе ОДИН. Пара двойников остаётся на точном совпадении.
///
/// Хелперы повторены в каждом обработчике: JSVM не показывает обработчику
/// функции уровня файла (см. CLAUDE.md, «Грабли JSVM»).

/// Вход по паролю. PocketBase сам оставляет место для этого: не найденный
/// аккаунт передаётся хуку пустым («to allow custom record find
/// implementations»), и пароль после проверяет он же.
onRecordAuthWithPasswordRequest((e) => {
  if (!e.record) {
    const identity = String(e.identity || "").trim();
    const byEmail = !e.identityField || e.identityField === "email";
    if (byEmail && identity.indexOf("@") > 0) {
      try {
        const rows = arrayOf(new DynamicModel({ id: "" }));
        $app.db()
          .newQuery("SELECT id FROM users WHERE lower(email) = lower({:e}) LIMIT 2")
          .bind({ e: identity })
          .all(rows);
        if (rows.length === 1) e.record = $app.findRecordById("users", rows[0].id);
      } catch (err) {
        $app.logger().warn("email-case: вход", "err", String(err));
      }
    }
  }
  e.next();
}, "users");

/// «Забыли пароль» без учёта регистра.
///
/// Штатный `request-password-reset` ищет аккаунт ДО любого хука, поэтому
/// перехватить промах там нечем — нужен свой маршрут. Приложение с 1.32.1 зовёт
/// его, старые сборки остаются на штатном.
///
/// Ответ всегда 204, как у PocketBase: по нему нельзя узнать, есть ли такой
/// адрес. Повтор одному аккаунту — не чаще раза в две минуты (так же, как в
/// штатном), с одного адреса — не больше 30 запросов в час: письма стоят
/// квоты почтового сервиса.
routerAdd("POST", "/api/auth/password-reset", (e) => {
  const store = $app.store();
  const now = Date.now();

  const ipKey = "pwreset_ip_" + e.realIP();
  const hit = store.get(ipKey);
  const win = hit && now - hit.at < 3600 * 1000 ? hit : { at: now, n: 0 };
  if (win.n >= 30) return e.json(429, { message: "Слишком много запросов. Попробуйте через час." });
  store.set(ipKey, { at: win.at, n: win.n + 1 });

  let email = "";
  try {
    email = String((e.requestInfo().body || {}).email || "").trim();
  } catch (_) {
    email = "";
  }
  if (!email || email.indexOf("@") < 1 || email.length > 255) {
    return e.json(400, { message: "Нужна почта." });
  }

  let record = null;
  try {
    record = $app.findAuthRecordByEmail("users", email);
  } catch (_) {
    record = null;
  }
  if (!record) {
    try {
      const rows = arrayOf(new DynamicModel({ id: "" }));
      $app.db()
        .newQuery("SELECT id FROM users WHERE lower(email) = lower({:e}) LIMIT 2")
        .bind({ e: email })
        .all(rows);
      if (rows.length === 1) record = $app.findRecordById("users", rows[0].id);
    } catch (err) {
      $app.logger().warn("email-case: сброс", "err", String(err));
    }
  }
  if (!record) {
    $app.logger().info("pwreset: адреса нет", "email", email);
    return e.noContent(204);
  }

  const key = "pwreset_user_" + record.id;
  const last = store.get(key);
  if (last && now - last < 120 * 1000) return e.noContent(204);
  store.set(key, now);

  try {
    $mails.sendRecordPasswordReset($app, record);
  } catch (err) {
    // Письмо не ушло — снимаем отметку, чтобы человек мог нажать ещё раз.
    store.remove(key);
    $app.logger().error("pwreset: письмо не ушло", "email", email, "err", String(err));
  }
  return e.noContent(204);
});
