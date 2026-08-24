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
/// ПОДАРОК ПАРТНЁРУ (`{"gift": true}`) идёт тем же путём, и товар тот же.
/// Отличается ровно одним полем счёта: в `email` уходит почта ПАРТНЁРА, а не
/// покупателя. Дальше всё работает само — вебхук ищет аккаунт по почте оплаты
/// и ставит `plus` тому, кого нашёл. Почту подставляет сервер из записи пары:
/// клиент её не знает и не должен (в приложении почта партнёра нигде не
/// показывается), а подделать чужой адрес значит подарить Плюс кому угодно.
///
/// Скидка на подарок включается БЕЗ РЕЛИЗА, двумя переменными окружения:
///   • `LAVA_PLUS_GIFT_OFFER` — id второго тарифа того же товара («создать
///     несколько тарифов» в кабинете). Пусто — берётся обычный оффер.
///   • `LAVA_PLUS_GIFT_PROMO` — промокод, он уходит полем `promoCode`.
/// Оба пути можно совмещать. Промокод безопаснее: тариф видно на витрине
/// товара любому, а код живёт только здесь, в окружении сервера.
/// `LAVA_PLUS_GIFT_ENABLED=0` гасит подарок целиком, тоже без релиза.
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
  // Почта СЧЁТА, а не обязательно покупателя: у подарка сюда встаёт адрес
  // партнёра, и по нему вебхук откроет Плюс именно ему.
  let email = String(user.getString("email") || "").trim().toLowerCase();

  // Валюту берём из запроса: RUB для карт и СБП, EUR и USD для остальных.
  // Язык тоже: без него lava рисует страницу оплаты по-английски («Payment»,
  // «To pay»), хотя витрина у неё была русской.
  let currency = "RUB";
  let lang = "RU";
  let method = "";
  let feature = "";
  let gift = false;
  let groupId = "";
  try {
    const body = e.requestInfo().body || {};
    const c = String(body.currency || "").toUpperCase();
    if (c === "EUR" || c === "USD") currency = c;
    const l = String(body.lang || "").toUpperCase();
    if (l === "EN" || l === "ES") lang = l;
    method = String(body.method || "").toLowerCase();
    feature = String(body.feature || "").trim();
    gift = body.gift === true || String(body.gift || "") === "true";
    groupId = String(body.groupId || body.pairId || "").trim();
  } catch (_) {}

  // Без `feature` это покупка Togetherly+ — прежнее поведение хука.
  let OFFER = PLUS_OFFER;
  // Кому откроется доступ. У подарка это партнёр, и его же надо записать в
  // счёт: крон-подстраховка ниже выдаёт Плюс по `user_uid`, и с покупателем в
  // этом поле потерянный вебхук открыл бы доступ не тому.
  let recipientUid = user.id;
  let giftedBy = "";
  let promoCode = "";

  if (gift) {
    if (String($os.getenv("LAVA_PLUS_GIFT_ENABLED") || "1") === "0") {
      return e.json(400, { ok: false, error: "gift_disabled" });
    }
    // Дарить можно только Togetherly+: у элементов каталога владение и так
    // общее на пару, второй раз за них никто не платит.
    if (feature) return e.json(400, { ok: false, error: "gift_plus_only" });

    // Пары берём ПО СОСТАВУ из Postgres, а не по `users.group_ids`: список
    // ведёт отдельный хук и он отстаёт на секунды, а запись человека вдобавок
    // лежит в кэше авторизации нашей сборки до двадцати секунд. Живой регресс
    // на этом и краснел: в только что собранной паре даритель получал
    // `not_member`, хотя состоит в ней. Зеркало в SQLite тоже не годится — оно
    // отстаёт на минуты.
    let groups = [];
    try {
      const r = $http.send({
        url: "http://127.0.0.1:8120/internal/groups-of?live=1&uid="
          + encodeURIComponent(user.id),
        method: "GET",
        timeout: 8,
      });
      groups = (r && r.json && r.json.items) || [];
    } catch (_) { groups = []; }

    const partnerOf = (rec) => {
      const members = (rec && Array.isArray(rec.members)) ? rec.members : [];
      for (let i = 0; i < members.length; i++) {
        const m = String(members[i] || "");
        if (m && m !== user.id) return m;
      }
      return "";
    };

    let partnerUid = "";
    if (groupId) {
      let mine = null;
      for (let i = 0; i < groups.length; i++) {
        if (String(groups[i].id || "") === groupId) { mine = groups[i]; break; }
      }
      if (!mine) return e.json(403, { ok: false, error: "not_member" });
      partnerUid = partnerOf(mine);
    } else {
      // Пару без явного `groupId` выбираем только когда она одна: при
      // нескольких молча выбрать чужую значит подарить доступ не тому.
      let found = 0;
      for (let i = 0; i < groups.length; i++) {
        const p = partnerOf(groups[i]);
        if (!p) continue;
        found++;
        if (found > 1) return e.json(400, { ok: false, error: "many_groups" });
        partnerUid = p;
        groupId = String(groups[i].id || "");
      }
    }
    if (!partnerUid) return e.json(400, { ok: false, error: "no_partner" });

    let partner = null;
    try { partner = $app.findRecordById("users", partnerUid); } catch (_) { partner = null; }
    if (!partner) return e.json(400, { ok: false, error: "no_partner" });
    // Плюс у партнёра уже есть — платить не за что. Второй раз он бы не
    // «продлился»: покупка разовая, флаг на аккаунте один.
    if (partner.getBool("plus")) return e.json(200, { ok: true, already: true });

    email = String(partner.getString("email") || "").trim().toLowerCase();
    if (!email) return e.json(400, { ok: false, error: "partner_no_email" });

    recipientUid = partnerUid;
    giftedBy = user.id;
    // Скидка на подарок: тариф и промокод включаются переменными окружения,
    // приложение о них не знает вовсе и обновления не требует.
    const giftOffer = ($os.getenv("LAVA_PLUS_GIFT_OFFER") || "").trim();
    if (giftOffer) OFFER = giftOffer;
    promoCode = ($os.getenv("LAVA_PLUS_GIFT_PROMO") || "").trim();
  } else if (feature) {
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
  if (!email) return e.json(400, { ok: false, error: "no_email" });

  // Скидка на обычную покупку — теми же двумя ручками, что и подарочная, и
  // тоже без релиза: `LAVA_PLUS_SALE_OFFER` (другой тариф того же товара) и
  // `LAVA_PLUS_PROMO` (промокод). Пусто — продаём по обычной цене.
  if (!gift && !feature) {
    const saleOffer = ($os.getenv("LAVA_PLUS_SALE_OFFER") || "").trim();
    if (saleOffer) OFFER = saleOffer;
    promoCode = ($os.getenv("LAVA_PLUS_PROMO") || "").trim();
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

  // Тело собирается по частям, а не двумя литералами: полей, которые ставятся
  // по условию, стало три (способ оплаты, промокод), и «ещё один вариант
  // объекта» на каждое из них не масштабируется.
  const payload = {
    email: email,
    offerId: OFFER,
    currency: currency,
    periodicity: "ONE_TIME",
    buyerLanguage: lang,
  };
  if (paymentMethod) payload.paymentMethod = paymentMethod;
  if (promoCode) payload.promoCode = promoCode;

  let res;
  try {
    res = $http.send({
      url: "https://gate.lava.top/api/v2/invoice",
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Api-Key": apiKey },
      body: JSON.stringify(payload),
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

  // Скидку ждали, а сумма пришла обычная — молча это пропускать нельзя.
  // Несуществующий промокод lava НЕ отвергает: отвечает 201 и полной ценой
  // (проверено 24.08.2026 кодом `NOSUCHCODE1` — счёт создался на 827,82 ₽).
  // Опечатка в переменной окружения иначе стоила бы скидки у всех подарков
  // сразу, и заметить это было бы негде.
  if (!feature && (promoCode || OFFER !== PLUS_OFFER)) {
    try {
      const paid = Number((data.amountTotal && data.amountTotal.amount) || 0);
      let base = 0;
      const cached = $app.store().get("lavaPlusBase_" + currency);
      if (cached) base = Number(cached);
      if (!base) {
        const pr = $http.send({
          url: "https://gate.lava.top/api/v2/products?showInactive=true",
          method: "GET",
          headers: { "X-Api-Key": apiKey },
          timeout: 8,
        });
        let parsed = pr && pr.json;
        if (!parsed || !parsed.items) {
          try { parsed = JSON.parse(String((pr && pr.raw) || "{}")); } catch (_) { parsed = null; }
        }
        const items = (parsed && parsed.items) || [];
        for (let i = 0; i < items.length; i++) {
          // Обёртки `data` у ответа нет — товар лежит прямо в элементе.
          const d = items[i] || {};
          const offers = d.offers || [];
          for (let j = 0; j < offers.length; j++) {
            if (String(offers[j].id || "").toLowerCase() !== PLUS_OFFER.toLowerCase()) continue;
            const prices = offers[j].prices || [];
            for (let k = 0; k < prices.length; k++) {
              const cur = String(prices[k].currency || "");
              const amt = Number(prices[k].amount || 0);
              if (cur && amt) $app.store().set("lavaPlusBase_" + cur, String(amt));
              if (cur === currency) base = amt;
            }
          }
        }
      }
      if (base && paid && paid >= base) {
        $app.logger().warn("lava/checkout: скидка на подарок НЕ применилась",
          "contract", contractId, "currency", currency,
          "paid", String(paid), "base", String(base),
          "promo", promoCode ? "есть" : "нет",
          "offer", OFFER);
      }
    } catch (_) {}
  }

  try {
    const col = $app.findCollectionByNameOrId("lava_invoices");
    const rec = new Record(col);
    rec.set("contract_id", contractId);
    // Кому открывать доступ, а не кто платил: у подарка это партнёр.
    rec.set("user_uid", recipientUid);
    rec.set("email", email);
    rec.set("status", String(data.status || "NEW").toUpperCase());
    rec.set("granted", false);
    // Пусто — счёт за Togetherly+; иначе ключ владения, который выдаст крон,
    // если вебхук по этой оплате потеряется.
    rec.set("feature", feature);
    // Кто подарил. Пусто у обычной покупки; по нему получатель узнаёт, от кого
    // прилетел доступ, а поддержка отличает подарок от своей оплаты.
    rec.set("gifted_by", giftedBy);
    $app.save(rec);
  } catch (err) {
    // Счёт уже создан на стороне lava, ронять покупку из-за своей записи
    // нельзя: вебхук всё равно откроет доступ по совпадению почты.
    $app.logger().warn("lava/checkout: запись счёта не сохранилась",
      "contract", contractId, "err", String(err));
  }

  return e.json(200, {
    ok: true, url: payUrl, contractId: contractId, gift: gift,
  });
}, $apis.requireAuth());

/// Что показать на кнопке подарка: есть ли кому дарить, нужен ли он вообще и
/// какая на него скидка.
///
/// Отдельный роут, а не поле в карточке партнёра: витрине нужны ещё цена и
/// размер скидки, а они живут в кабинете lava и меняются без релиза. Клиент
/// рисует плашку по числу `discount`, поэтому скидка появляется у людей в тот
/// же час, когда её включают на сервере, — переустанавливать приложение не
/// нужно.
///
/// Почту партнёра роут НЕ отдаёт: в приложении она нигде не показывается, и
/// подарок ей не нужен — адрес подставляет сам сервер при создании счёта.
routerAdd("GET", "/api/lava/gift", (e) => {
  const PLUS_OFFER = ($os.getenv("LAVA_PLUS_OFFER") ||
    "40364f0a-b0c5-44e8-8380-55d9cf492bb6").trim();
  const user = e.auth;
  if (!user) return e.json(401, { ok: false, error: "unauthorized" });

  const off = String($os.getenv("LAVA_PLUS_GIFT_ENABLED") || "1") === "0";
  let currency = "RUB";
  let groupId = "";
  try {
    const q = e.requestInfo().query || {};
    const c = String(q.currency || "").toUpperCase();
    if (c === "EUR" || c === "USD") currency = c;
    groupId = String(q.groupId || "").trim();
  } catch (_) {}

  // Живые пары человека читаем из Postgres по составу — та же выборка, что и
  // у самой покупки. `users.group_ids` тут не годится: он отстаёт, и у
  // только что собравшейся пары список получателей вышел бы пустым.
  let groups = [];
  try {
    const r = $http.send({
      url: "http://127.0.0.1:8120/internal/groups-of?live=1&uid="
        + encodeURIComponent(user.id),
      method: "GET",
      timeout: 8,
    });
    groups = (r && r.json && r.json.items) || [];
  } catch (_) { groups = []; }

  // Отдаём ВСЕХ, кому этот человек может подарить: выбирает он сам, листом в
  // приложении. Гадать за него нельзя — у части людей связей несколько, и
  // молчаливый выбор «первой живой» предложил бы подарок не тому.
  const partners = [];
  for (let i = 0; i < groups.length; i++) {
    const rec = groups[i];
    const gid = String(rec.id || "");
    if (groupId && gid !== groupId) continue;
    const members = Array.isArray(rec.members) ? rec.members : [];
    const names = rec.member_names || {};
    const avatars = rec.member_avatars || {};
    for (let j = 0; j < members.length; j++) {
      const uid = String(members[j] || "");
      if (!uid || uid === user.id) continue;
      let name = String((names && names[uid]) || "");
      let hasPlus = false;
      let avatar = String((avatars && avatars[uid]) || "");
      try {
        const p = $app.findRecordById("users", uid);
        hasPlus = p.getBool("plus") === true;
        if (!name) name = String(p.getString("display_name") || "");
        if (!avatar) avatar = String(p.getString("avatar_url") || "");
      } catch (_) { continue; }
      partners.push({
        uid: uid,
        groupId: gid,
        name: name,
        avatar: avatar,
        already: hasPlus,
      });
    }
  }

  // Цены тарифов держим в памяти, но НЕ вечно: цену правят в кабинете lava, и
  // без срока годности приложение показывало бы прежнюю сумму до перезапуска
  // сервера. Полчаса — достаточно редко для их API и достаточно быстро, чтобы
  // новая цена доехала до людей сама. 24.08.2026 цена евро сменилась с 8,57 на
  // 10 ровно так — правкой в кабинете, без единой строчки кода.
  const PRICE_TTL_MS = 30 * 60 * 1000;
  const giftOffer = ($os.getenv("LAVA_PLUS_GIFT_OFFER") || "").trim();
  const promo = ($os.getenv("LAVA_PLUS_GIFT_PROMO") || "").trim();
  // Скидка на обычную покупку живёт теми же двумя ручками, что и подарочная.
  const saleOffer = ($os.getenv("LAVA_PLUS_SALE_OFFER") || "").trim();
  const salePromo = ($os.getenv("LAVA_PLUS_PROMO") || "").trim();

  const priceAge = Date.now() - Number($app.store().get("lavaPricesAt") || 0);
  const fresh = priceAge >= 0 && priceAge < PRICE_TTL_MS;
  let base = fresh ? Number($app.store().get("lavaPlusBase_" + currency) || 0) : 0;
  let giftPrice = (fresh && giftOffer)
    ? Number($app.store().get("lavaGiftBase_" + currency) || 0)
    : 0;
  let salePrice = (fresh && saleOffer)
    ? Number($app.store().get("lavaSaleBase_" + currency) || 0)
    : 0;
  if (!base || (giftOffer && !giftPrice) || (saleOffer && !salePrice)) {
    try {
      const apiKey = $os.getenv("LAVA_API_KEY") || "";
      const pr = $http.send({
        url: "https://gate.lava.top/api/v2/products?showInactive=true",
        method: "GET",
        headers: { "X-Api-Key": apiKey },
        timeout: 8,
      });
      // Тело разбираем сами: у GET-ответа `res.json` в этой сборке JSVM
      // приходит пустым, и цена молча оставалась нулевой — витрина показывала
      // кнопку без суммы (поймал живой регресс).
      let parsed = pr && pr.json;
      if (!parsed || !parsed.items) {
        try { parsed = JSON.parse(String((pr && pr.raw) || "{}")); } catch (_) { parsed = null; }
      }
      const items = (parsed && parsed.items) || [];
      if (!items.length) {
        $app.logger().warn("lava/gift: каталог не прочитан",
          "status", String((pr && pr.statusCode) || 0),
          "body", String((pr && pr.raw) || "").slice(0, 200));
      }
      for (let i = 0; i < items.length; i++) {
        // Товар лежит в элементе НАПРЯМУЮ: обёртки `data` у `/api/v2/products`
        // нет (её показывает только swagger-пример), и разбор через неё
        // молча давал нулевую цену.
        const d = items[i] || {};
        const offers = d.offers || [];
        for (let j = 0; j < offers.length; j++) {
          const id = String(offers[j].id || "").toLowerCase();
          const isPlus = id === PLUS_OFFER.toLowerCase();
          const isGift = giftOffer && id === giftOffer.toLowerCase();
          const isSale = saleOffer && id === saleOffer.toLowerCase();
          if (!isPlus && !isGift && !isSale) continue;
          const key = isPlus ? "lavaPlusBase_"
            : isGift ? "lavaGiftBase_" : "lavaSaleBase_";
          const prices = offers[j].prices || [];
          for (let k = 0; k < prices.length; k++) {
            const cur = String(prices[k].currency || "");
            const amt = Number(prices[k].amount || 0);
            if (!cur || !amt) continue;
            $app.store().set(key + cur, String(amt));
            if (cur === currency) {
              if (isPlus) base = amt;
              else if (isGift) giftPrice = amt;
              else salePrice = amt;
            }
          }
        }
      }
      if (base) $app.store().set("lavaPricesAt", String(Date.now()));
    } catch (err) {
      // Молчать тут нельзя: без цены кнопка выглядит недоделанной, а причина
      // (упавший запрос, чужой ключ, авария их API) не видна больше нигде.
      // 24.08.2026 lava полчаса отвечала 500 на список товаров и 404 на все
      // офферы разом, пока в кабинете сохраняли товар.
      $app.logger().warn("lava/gift: цены не прочитаны", "err", String(err));
    }
  }

  // Скидка считается по ценам тарифов, а при промокоде берётся из окружения:
  // сколько снимет код, до создания счёта не знает никто.
  const discountOf = (special, promoCode, percentEnv) => {
    if (special && base && special < base) {
      return { price: special, percent: Math.round((1 - special / base) * 100) };
    }
    if (promoCode) {
      const p = Math.round(Number($os.getenv(percentEnv) || 0));
      if (p > 0 && p < 100 && base) {
        return { price: Math.round(base * (100 - p)) / 100, percent: p };
      }
    }
    return { price: base, percent: 0 };
  };

  const giftDeal = discountOf(giftPrice, promo, "LAVA_PLUS_GIFT_DISCOUNT");
  const saleDeal = discountOf(salePrice, salePromo, "LAVA_PLUS_DISCOUNT");
  const discount = giftDeal.percent;
  const price = giftDeal.price;

  return e.json(200, {
    ok: true,
    enabled: !off,
    partners: partners,
    currency: currency,
    // Подарок.
    price: price,
    basePrice: base,
    discount: discount > 0 && discount < 100 ? discount : 0,
    // Обычная покупка Togetherly+ в той же валюте. Отсюда витрина берёт сумму
    // на кнопку «Купить»: в сборках с сайта магазина нет, и до этого цену
    // человек узнавал только на странице оплаты.
    plusPrice: saleDeal.price,
    plusBasePrice: base,
    plusDiscount: saleDeal.percent > 0 && saleDeal.percent < 100
      ? saleDeal.percent : 0,
  });
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
        // Подарок: получатель ничего не покупал, и без уведомления он увидит
        // открывшийся доступ как непонятную перемену в приложении.
        const giftedBy = String(rec.getString("gifted_by") || "");
        if (giftedBy) {
          try {
            let from = "";
            try {
              from = String($app.findRecordById("users", giftedBy)
                .getString("display_name") || "");
            } catch (_) {}
            const push = require(`${__hooks}/apns_push.js`);
            push.sendTo(
              user.id,
              "Togetherly+ — подарок 💜",
              from ? from + " подарил(а) вам полный доступ" : "Вам подарили полный доступ",
              "plusgift");
          } catch (err) {
            $app.logger().warn("lava/poll: уведомление о подарке не ушло",
              "contract", contractId, "err", String(err));
          }
        }
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
