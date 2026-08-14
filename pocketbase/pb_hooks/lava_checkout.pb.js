/// Покупка Togetherly+ через СЧЁТ lava.top, а не через витрину.
///
/// Зачем: уведомления lava.top приходят ТОЛЬКО по счетам, созданным их API.
/// Покупка по прямой ссылке на товар (`app.lava.top/products/…`) не порождает
/// ни вебхука, ни записи в их отчётах — проверено 31 июля на двух оплатах:
/// вебхук был настроен и молчал, а `/api/v1/invoices` этих покупок не видел
/// вовсе. Пока приложение ведёт людей на витрину, каждую оплату приходится
/// выдавать руками.
///
/// Как работает:
///   1. Приложение зовёт `POST /api/lava/checkout` своей сессией.
///   2. Хук создаёт счёт в lava на почту аккаунта и возвращает ссылку оплаты.
///   3. Человек платит; lava шлёт вебхук в `lava.pb.js` — доступ открывается.
///   4. Крон ниже добивает случай потерянного вебхука: раз в две минуты
///      спрашивает статус своих счетов и выдаёт Плюс по `COMPLETED`.
///
/// Ключ продавца — `LAVA_API_KEY` в окружении PocketBase.
///
/// !!! ГРАБЛИ PB JSVM (см. coins.pb.js): обработчик исполняется в
/// ИЗОЛИРОВАННОМ пуле и НЕ видит функции уровня файла — всё инлайнится.

routerAdd("POST", "/api/lava/checkout", (e) => {
  const PLUS_OFFER = ($os.getenv("LAVA_PLUS_OFFER") ||
    "40364f0a-b0c5-44e8-8380-55d9cf492bb6").trim();
  // Платные элементы каталога, которые продаются за деньги: ключ владения →
  // оффер lava.top. Зеркало `FEATURE_SKUS` в `lava.pb.js`, где тот же ключ
  // выдаётся по уведомлению об оплате. Новый элемент добавляется строкой сюда
  // и двумя строками туда (товар и оффер).
  const FEATURE_OFFERS = {
    "mood_pack:moti": "1d908a4e-9751-41f7-98e9-8499c0c835aa",
  };
  const apiKey = $os.getenv("LAVA_API_KEY") || "";
  if (!apiKey) return e.json(500, { ok: false, error: "no_api_key" });

  const user = e.auth;
  if (!user) return e.json(401, { ok: false, error: "unauthorized" });
  const email = String(user.getString("email") || "").trim().toLowerCase();
  if (!email) return e.json(400, { ok: false, error: "no_email" });

  // Валюту берём из запроса: RUB для карт и СБП, EUR и USD для остальных.
  // Язык тоже: без него lava рисует страницу оплаты по-английски («Payment»,
  // «To pay»), хотя витрина у неё была русской.
  let currency = "RUB";
  let lang = "RU";
  let method = "";
  let feature = "";
  try {
    const body = e.requestInfo().body || {};
    const c = String(body.currency || "").toUpperCase();
    if (c === "EUR" || c === "USD") currency = c;
    const l = String(body.lang || "").toUpperCase();
    if (l === "EN" || l === "ES") lang = l;
    method = String(body.method || "").toLowerCase();
    feature = String(body.feature || "").trim();
  } catch (_) {}

  // Без `feature` это покупка Togetherly+ — прежнее поведение хука.
  let OFFER = PLUS_OFFER;
  if (feature) {
    OFFER = FEATURE_OFFERS[feature] || "";
    if (!OFFER) return e.json(400, { ok: false, error: "unknown_feature" });
    // Уже куплено — счёт не заводим. Смотрим и свои ключи, и общие ключи пар:
    // элемент каталога общий на двоих, второй раз за него не платят.
    let owned = [];
    try { owned = JSON.parse(user.getString("owned_features") || "[]") || []; } catch (_) { owned = []; }
    let mine = owned.indexOf(feature) !== -1;
    if (!mine) {
      let groupIds = [];
      try { groupIds = user.getStringSlice("group_ids") || []; } catch (_) { groupIds = []; }
      // Владения пары читаем из Postgres: в SQLite лежит зеркало, оно
      // отстаёт на минуты, и человек успел бы оплатить уже купленное.
      for (let i = 0; i < groupIds.length && !mine; i++) {
        try {
          const r = $http.send({
            url: "http://127.0.0.1:8120/internal/group-read?id="
              + encodeURIComponent(String(groupIds[i])),
            method: "GET",
            timeout: 8,
          });
          const rec = (r && r.json && r.json.record) || null;
          const g = (rec && Array.isArray(rec.owned_features)) ? rec.owned_features : [];
          if (g.indexOf(feature) !== -1) mine = true;
        } catch (_) {}
      }
    }
    if (mine) return e.json(200, { ok: true, already: true });
  } else if (user.getBool("plus")) {
    return e.json(200, { ok: true, already: true });
  }

  // Провайдер решает, ЧЕМ человек заплатит, и для рублей это вопрос жизни:
  //   PAY2ME       — СБП, выбор банковского приложения (проверено живьём);
  //   SMART_GLOCAL — только форма карты, и российские карты в ней не ходят;
  //   BANK131      — на деле открывает ту же карточную форму.
  // По умолчанию lava берёт SMART_GLOCAL, то есть карты. Единственная живая
  // оплата через lava (31 июля, 797 ₽) прошла как раз по СБП, поэтому для
  // рублей ставим PAY2ME, а карту отдаём по явной просьбе клиента.
  let paymentMethod = "";
  if (currency === "RUB") {
    paymentMethod = method === "card" ? "SMART_GLOCAL" : "PAY2ME";
  } else if (method === "paypal") {
    paymentMethod = "PAYPAL";
  }

  let res;
  try {
    res = $http.send({
      url: "https://gate.lava.top/api/v2/invoice",
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Api-Key": apiKey },
      body: JSON.stringify(paymentMethod ? {
        email: email, offerId: OFFER, currency: currency,
        periodicity: "ONE_TIME", buyerLanguage: lang, paymentMethod: paymentMethod,
      } : {
        email: email, offerId: OFFER, currency: currency,
        periodicity: "ONE_TIME", buyerLanguage: lang,
      }),
      timeout: 15,
    });
  } catch (err) {
    return e.json(502, { ok: false, error: "lava_unreachable" });
  }
  if (res.statusCode < 200 || res.statusCode > 299) {
    $app.logger().warn("lava/checkout: отказ lava " + res.statusCode,
      "email", email, "body", String(res.raw || "").slice(0, 300));
    return e.json(502, { ok: false, error: "lava_error", status: res.statusCode });
  }

  let data = {};
  try { data = res.json || JSON.parse(String(res.raw || "{}")); } catch (_) {}
  const contractId = String(data.id || "");
  const payUrl = String(data.paymentUrl || "");
  if (!contractId || !payUrl) {
    return e.json(502, { ok: false, error: "lava_bad_response" });
  }

  try {
    const col = $app.findCollectionByNameOrId("lava_invoices");
    const rec = new Record(col);
    rec.set("contract_id", contractId);
    rec.set("user_uid", user.id);
    rec.set("email", email);
    rec.set("status", String(data.status || "NEW").toUpperCase());
    rec.set("granted", false);
    // Пусто — счёт за Togetherly+; иначе ключ владения, который выдаст крон,
    // если вебхук по этой оплате потеряется.
    rec.set("feature", feature);
    $app.save(rec);
  } catch (err) {
    // Счёт уже создан на стороне lava, ронять покупку из-за своей записи
    // нельзя: вебхук всё равно откроет доступ по совпадению почты.
    $app.logger().warn("lava/checkout: запись счёта не сохранилась",
      "contract", contractId, "err", String(err));
  }

  return e.json(200, { ok: true, url: payUrl, contractId: contractId });
}, $apis.requireAuth());

/// Подстраховка: спрашиваем lava про свои незакрытые счета.
///
/// Вебхук остаётся главным путём, этот крон закрывает дыру, если уведомление
/// потерялось или наш сервер лежал в момент оплаты. Берём только свои счета,
/// не старше трёх суток: дальше человек обратится сам.
///
/// Каждые шесть минут, а не две (14.08.2026). Проход синхронный: до двадцати
/// счетов подряд, на каждый поход в lava. Раньше их было пятьдесят с таймаутом
/// пятнадцать секунд, то есть один проход мог тянуться двенадцать минут и
/// накладываться сам на себя, занимая машину JSVM у PocketBase. В профиле
/// вечернего пика кроны съедали треть всего времени JS. Замок в `$app.store()`
/// не пускает второй проход, пока идёт первый.
cronAdd("lavaInvoicePoll", "*/6 * * * *", () => {
  const apiKey = $os.getenv("LAVA_API_KEY") || "";
  if (!apiKey) return;

  const started = Date.now();
  const busyUntil = Number($app.store().get("lavaPollBusyUntil") || 0);
  if (busyUntil > started) return; // прошлый проход ещё идёт
  $app.store().set("lavaPollBusyUntil", started + 5 * 60 * 1000);

  let pending = [];
  try {
    pending = $app.findRecordsByFilter(
      "lava_invoices",
      "granted = false && status != 'FAILED' && created > {:edge}",
      "-created", 20, 0,
      { edge: new Date(Date.now() - 3 * 24 * 3600 * 1000).toISOString().replace("T", " ") }
    );
  } catch (err) {
    $app.store().set("lavaPollBusyUntil", 0);
    return;
  }

  for (let i = 0; i < pending.length; i++) {
    const rec = pending[i];
    const contractId = rec.getString("contract_id");
    if (!contractId) continue;

    let res;
    try {
      res = $http.send({
        url: "https://gate.lava.top/api/v1/invoices/" + contractId,
        method: "GET",
        headers: { "X-Api-Key": apiKey },
        timeout: 6,
      });
    } catch (_) { continue; }
    if (res.statusCode !== 200) continue;

    let data = {};
    try { data = res.json || JSON.parse(String(res.raw || "{}")); } catch (_) { continue; }
    const status = String(data.status || "").toUpperCase();
    if (status && status !== rec.getString("status")) {
      rec.set("status", status);
      try { $app.save(rec); } catch (_) {}
    }
    if (status !== "COMPLETED") continue;

    // Оплачено, а доступа нет — значит вебхук не доехал. Выдаём сами.
    try {
      const user = $app.findRecordById("users", rec.getString("user_uid"));
      const feature = rec.getString("feature") || "";

      if (feature) {
        // Элемент каталога: ключ ложится покупателю и его парам — ровно то же,
        // что делает вебхук и покупка за монеты (shareToGroups в coins.pb.js).
        const parse = (s, fb) => {
          try { return JSON.parse(s || JSON.stringify(fb)) || fb; } catch (_) { return fb; }
        };
        const owned = parse(user.getString("owned_features"), []);
        if (owned.indexOf(feature) === -1) {
          user.set("owned_features", JSON.stringify(owned.concat([feature])));
          $app.save(user);
          $app.logger().warn("lava/poll: элемент выдан по опросу счёта",
            "email", rec.getString("email"), "feature", feature, "contract", contractId);
        }
        let groupIds = [];
        try { groupIds = user.getStringSlice("group_ids") || []; } catch (_) { groupIds = []; }
        // Купленное открыто обоим, а запись пары живёт в Postgres: ключ владения
        // добавляет hotpath одним запросом и идемпотентно — повтор чека, второй
        // канал оплаты и восстановление покупки ничего не задваивают.
        for (let i = 0; i < groupIds.length; i++) {
          try {
            $http.send({
              url: "http://127.0.0.1:8120/internal/group-write",
              method: "POST",
              headers: { "content-type": "application/json" },
              body: JSON.stringify({
                group_id: String(groupIds[i]),
                arr_add: { owned_features: [feature] },
              }),
              timeout: 10,
            });
          } catch (err) {
            $app.logger().warn("владение не доехало до пары",
              "group", String(groupIds[i]), "feature", String(feature), "err", String(err));
          }
        }
      } else if (!user.getBool("plus")) {
        user.set("plus", true);
        user.set("plus_platform", "lava");
        $app.save(user);
        $app.logger().warn("lava/poll: Плюс выдан по опросу счёта",
          "email", rec.getString("email"), "contract", contractId);
      }
      rec.set("granted", true);
      $app.save(rec);
    } catch (err) {
      $app.logger().warn("lava/poll: не удалось выдать покупку",
        "contract", contractId, "err", String(err));
    }
  }
  $app.store().set("lavaPollBusyUntil", 0);
});
