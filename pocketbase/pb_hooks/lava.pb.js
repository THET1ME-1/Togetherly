/// Приём оплат lava.top напрямую в PocketBase.
///
/// Главный путь — без кода и без бота: если почта покупки совпала с почтой
/// аккаунта, монеты падают на баланс сами, человек просто открывает приложение.
///
/// Запасной путь — код: платили с другой почты (рабочая, семейная, вход через
/// Google с иным адресом) или аккаунта ещё нет. Тогда создаётся запись в
/// `redeem_codes`, и код выдаёт бот @SnTAppsBot.
///
/// Защита: секрет в заголовке `X-Api-Key` (или `?key=`), он же вписан в
/// lava.top. Без него роут молчит — иначе монеты мог бы начислить кто угодно.
/// Секрет живёт в переменной окружения LAVA_WEBHOOK_KEY процесса PocketBase.
///
/// !!! ГРАБЛИ PB JSVM (см. coins.pb.js:5-19): обработчик исполняется в
/// ИЗОЛИРОВАННОМ пуле и НЕ видит функции уровня файла — всё инлайнится.

routerAdd("POST", "/api/lava/webhook", (e) => {
  // Товары lava.top → монеты. Зеркало bot/coins.py (PRODUCTS).
  const PRODUCTS = {
    "4d8ff539-fd74-47ab-85e4-35906be3a5b4": 600,
    "64e68f3f-7281-4593-aa00-0b438522750b": 1400,
    "cd2e08ec-e826-495d-bb55-842a3e3742dc": 4000,
  };
  // Togetherly+ — разовая покупка: платные темы, календарь цикла, каталог
  // виджетов, свой рисунок в раскрасках и свои категории в «Хочу с тобой».
  // Идентификатор товара публичный (он же в ссылке на
  // покупку), поэтому лежит прямо здесь; переменной окружения можно
  // переопределить, если товар пересоздадут.
  const PLUS_SKU = ($os.getenv("LAVA_PLUS_SKU") ||
    "ec861b44-a4b7-49e3-aa0e-e4608abdb0f0").trim().toLowerCase();
  // У товара в lava.top есть ещё и оффер со СВОИМ идентификатором, и в
  // уведомлении может приехать он, а не товар (`/api/v2/products` показывает
  // оба). Держим список: совпадение с любым из них считаем покупкой Плюса.
  const PLUS_OFFER = ($os.getenv("LAVA_PLUS_OFFER") ||
    "40364f0a-b0c5-44e8-8380-55d9cf492bb6").trim().toLowerCase();
  const ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

  // Форма вебхука в кабинете lava.top спрашивает логин и пароль, то есть шлёт
  // обычный Basic. Заголовка X-Api-Key она не умеет вовсе, и первая покупка
  // (31 июля, 797 ₽) потерялась молча: интеграции там не было, а когда её
  // завели, оказалось, что ключ вписать некуда. Держим оба способа: Basic для
  // lava.top, X-Api-Key и ?key= для тестов curl'ом и на случай смены формата.
  //
  // Base64 в этой сборке JSVM нет (`atob` не определён), поэтому сравниваем
  // заголовок целиком с заранее посчитанной строкой из окружения:
  // LAVA_BASIC = base64("логин:пароль").
  const secret = $os.getenv("LAVA_WEBHOOK_KEY") || "";
  const basic = ($os.getenv("LAVA_BASIC") || "").trim();
  const given = e.request.header.get("X-Api-Key") ||
    e.request.url.query().get("key") || "";
  const auth = (e.request.header.get("Authorization") || "").trim();
  const okKey = secret !== "" && given === secret;
  const okBasic = basic !== "" && auth === "Basic " + basic;
  if (!okKey && !okBasic) {
    return e.json(401, { ok: false, error: "bad_key" });
  }

  let payload = {};
  try {
    payload = e.requestInfo().body || {};
  } catch (_) {
    payload = {};
  }

  // lava.top присылает разные обёртки в зависимости от типа события, поэтому
  // ищем поля по всему дереву, а не по фиксированному пути (так же в bot/lava.py).
  const flat = {};
  const walk = (node, path) => {
    if (node === null || node === undefined) return;
    if (typeof node !== "object") {
      flat[path.toLowerCase()] = String(node);
      return;
    }
    for (const key in node) {
      walk(node[key], path ? path + "." + key : key);
    }
  };
  walk(payload, "");

  const pick = (names) => {
    for (const key in flat) {
      const tail = key.split(".").pop();
      for (let i = 0; i < names.length; i++) {
        if (tail === names[i] || key === names[i]) return flat[key];
      }
    }
    return "";
  };

  const status = (pick(["status", "eventtype", "event", "state", "type"]) || "")
    .toLowerCase();
  const paid = status.indexOf("success") !== -1 ||
    status.indexOf("paid") !== -1 ||
    status.indexOf("completed") !== -1 ||
    status.indexOf("subscription.recurring.payment.success") !== -1;
  if (!paid) {
    // Не оплата (отказ, тестовый пинг, возврат) — повторы делу не помогут.
    return e.json(200, { ok: true, skipped: status || "no_status" });
  }

  const email = (pick(["email", "buyeremail", "clientemail", "contactemail"]) || "")
    .trim().toLowerCase();
  const orderId = (pick(["contractid", "orderid", "invoiceid", "paymentid"]) || "").trim();

  // Товар ищем НЕ по имени поля, а по значению: собираем из уведомления все
  // uuid подряд и смотрим, нет ли среди них знакомого. Прежний `pick` брал
  // первое поле, чей хвост совпал с «id», а им запросто оказывался
  // идентификатор покупателя или платежа, и покупка уходила в «not_ours».
  // Чужие uuid ни с чем не совпадут, поэтому ложных начислений не будет.
  const isUuid = (s) =>
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(s);
  let productId = "", amount = 0, isPlus = false;
  for (const key in flat) {
    const v = String(flat[key]).trim().toLowerCase();
    if (!isUuid(v)) continue;
    if (v === PLUS_SKU || v === PLUS_OFFER) { productId = v; isPlus = true; break; }
    if (PRODUCTS[v]) { productId = v; amount = PRODUCTS[v]; break; }
  }
  if (!productId) {
    productId = (pick(["productid", "offerid", "parentid", "uuid", "id"]) || "")
      .trim().toLowerCase();
  }

  // Каждый входящий вебхук оставляет след. `logger().warn` кладёт запись в
  // `_logs` (info туда не попадает), и теперь любую пропажу видно без
  // кабинета lava.top: кто платил, за что, чем закончилось. Первую живую
  // покупку разбирали вслепую именно потому, что следов не было никаких.
  const trace = (verdict) => {
    try {
      $app.logger().warn("lava/webhook: " + verdict,
        "email", email || "-", "product", productId || "-",
        "order", orderId || "-", "status", status || "-");
    } catch (_) {}
  };

  if (!amount && !isPlus) {
    // Товар другого приложения — этим занимается бот, не мы.
    trace("not_ours");
    return e.json(200, { ok: true, skipped: "not_ours", product: productId });
  }
  if (!email) {
    trace("no_email");
    return e.json(400, { ok: false, error: "no_email" });
  }

  let out = { s: 500, b: { ok: false, error: "internal" } };
  try {
    $app.runInTransaction((txApp) => {
      // Идемпотентность: один заказ — одно начисление. Ключом служит номер
      // заказа, а при его отсутствии — почта с товаром (lava.top иногда шлёт
      // событие дважды).
      const key = ("LAVA" + (orderId || email + productId))
        .toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 30);

      // Ключ заказа живёт в отдельном поле: код у записи свой, и раньше
      // повторный вебхук по покупке без аккаунта заводил вторую запись.
      let existing = null;
      try {
        existing = txApp.findFirstRecordByFilter(
          "redeem_codes", "order_key = {:k}", { k: key });
      } catch (_) {
        existing = null;
      }
      if (existing) {
        out = { s: 200, b: { ok: true, repeated: true } };
        return;
      }

      // Ищем аккаунт с той же почтой: нашёлся — начисляем сразу.
      let user = null;
      try {
        user = txApp.findFirstRecordByFilter(
          "users", "email = {:e}", { e: email });
      } catch (_) {
        user = null;
      }

      const col = txApp.findCollectionByNameOrId("redeem_codes");
      const rec = new Record(col);
      // У Togetherly+ монет нет: код открывает возможности, а не пополняет
      // баланс. Флаг едет вместе с кодом, чтобы погашение знало, что делать.
      rec.set("coins", isPlus ? 0 : amount);
      rec.set("plus", isPlus);
      rec.set("sku", productId);
      rec.set("buyer_email", email);
      rec.set("order_key", key);

      if (user) {
        rec.set("code", key);
        rec.set("used_by", user.id);
        rec.set("used_at", Date.now());
        txApp.save(rec);

        if (isPlus) {
          user.set("plus", true);
          // Откуда покупка: на iOS витрины Togetherly+ нет вовсе, и по этому
          // полю потом видно, почему у человека всё открыто без неё.
          user.set("plus_platform", "lava");
          txApp.save(user);
          out = { s: 200, b: { ok: true, plus: true, direct: true } };
          return;
        }

        user.set("coins", (user.getInt("coins") || 0) + amount);
        txApp.save(user);
        out = { s: 200, b: { ok: true, credited: amount, direct: true } };
        return;
      }

      // Аккаунта с такой почтой нет — заводим код для бота.
      let code = "";
      for (let i = 0; i < 8; i++) {
        code += ALPHABET.charAt(Math.floor(Math.random() * ALPHABET.length));
      }
      rec.set("code", "TG" + code);
      txApp.save(rec);
      out = { s: 200, b: { ok: true, credited: 0, direct: false } };
    });
    trace(out.b && out.b.repeated ? "repeated"
      : out.b && out.b.direct ? (isPlus ? "plus_granted" : "coins_credited")
      : "code_issued");
  } catch (err) {
    try {
      $http.send({
        url: "http://127.0.0.1:8000/api/1/store/",
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Sentry-Auth":
            "Sentry sentry_version=7, sentry_key=05953bce75c54cdb9fe149861d159da5",
        },
        body: JSON.stringify({
          message: "lava/webhook: " + String(err),
          level: "error",
          logger: "pb_hooks.lava",
          tags: { feature: "redeem", route: "lava_webhook", error_code: "server" },
        }),
        timeout: 5,
      });
    } catch (_) {}
    try {
      $app.logger().error("lava/webhook: " + String(err));
    } catch (_) {}
    out = { s: 500, b: { ok: false, error: "internal" } };
  }
  return e.json(out.s, out.b);
});
