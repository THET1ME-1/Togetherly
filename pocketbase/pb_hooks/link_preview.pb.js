/// Карточка товара по ссылке: GET /api/link/preview?url=…
///
/// ЗАЧЕМ: в списке «Хочу с тобой» появились вещи, а не только дела. Вбивать
/// руками название, цену и картинку с телефона — работа на минуту, и её никто
/// не делает: желание уходит ссылкой, а список превращается в свалку
/// одинаковых синих строк. Роут читает страницу магазина и достаёт то, что
/// нужно карточке.
///
/// Разбираем og-теги и микроразметку: `og:title`, `og:image`, `og:site_name`,
/// `product:price:amount`, `product:price:currency`, плюс JSON-LD Product и
/// `itemprop="price"`. Что не нашли — оставляем клиенту, он даст вписать руками.
///
/// ГРАНИЦЫ: ходим только по http(s), тянем не больше 512 КБ и не дольше 8 с,
/// внутренние адреса не трогаем. Это не парсер магазинов, а помощник: у кого
/// og-тегов нет, тот заполнит карточку сам.
///
/// ВАЖНО (PB JSVM): всё внутри обработчика — модульный уровень ему не виден.
/// Регулярки без `\p{...}`: этот движок их не понимает (см. invite_web.pb.js).

routerAdd("GET", "/api/link/preview", (e) => {
  const raw = String((e.requestInfo().query || {}).url || "").trim();
  if (!raw) return e.json(400, { success: false, message: "url required" });

  const low = raw.toLowerCase();
  if (low.indexOf("http://") !== 0 && low.indexOf("https://") !== 0) {
    return e.json(400, { success: false, message: "only http(s)" });
  }
  // Внутренняя сеть закрыта: роут ходит от имени сервера, и без этой проверки
  // им можно было бы простучать localhost и соседей по подсети.
  const host = (function () {
    let h = raw.substring(raw.indexOf("://") + 3);
    const slash = h.indexOf("/");
    if (slash !== -1) h = h.substring(0, slash);
    const at = h.indexOf("@");
    if (at !== -1) h = h.substring(at + 1);
    const colon = h.indexOf(":");
    if (colon !== -1) h = h.substring(0, colon);
    return h.toLowerCase();
  })();
  const blocked = ["localhost", "127.0.0.1", "0.0.0.0", "::1", "metadata.google.internal"];
  if (blocked.indexOf(host) !== -1 ||
      host.indexOf("192.168.") === 0 ||
      host.indexOf("10.") === 0 ||
      host.indexOf("172.16.") === 0 ||
      host.indexOf(".local") === host.length - 6) {
    return e.json(400, { success: false, message: "host not allowed" });
  }

  let html = "";
  try {
    const res = $http.send({
      method: "GET",
      url: raw,
      timeout: 8,
      headers: {
        // Без человеческого UA половина магазинов отдаёт заглушку.
        "User-Agent": "Mozilla/5.0 (compatible; TogetherlyBot/1.0; +https://togetherly.duckdns.org)",
        "Accept-Language": "ru,en;q=0.8",
      },
    });
    if (res.statusCode >= 400) {
      return e.json(200, { success: false, message: "shop answered " + res.statusCode });
    }
    html = String(res.raw || "");
  } catch (err) {
    return e.json(200, { success: false, message: "fetch failed" });
  }
  if (html.length > 512 * 1024) html = html.substring(0, 512 * 1024);

  const meta = (names) => {
    for (let i = 0; i < names.length; i++) {
      const n = names[i].replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const patterns = [
        new RegExp('<meta[^>]+(?:property|name|itemprop)\\s*=\\s*["\']' + n + '["\'][^>]*content\\s*=\\s*["\']([^"\']*)["\']', "i"),
        new RegExp('<meta[^>]+content\\s*=\\s*["\']([^"\']*)["\'][^>]*(?:property|name|itemprop)\\s*=\\s*["\']' + n + '["\']', "i"),
      ];
      for (let p = 0; p < patterns.length; p++) {
        const m = html.match(patterns[p]);
        if (m && m[1]) return m[1];
      }
    }
    return "";
  };

  const unescape = (s) => String(s || "")
    .replace(/&quot;/g, '"').replace(/&#0?39;/g, "'").replace(/&apos;/g, "'")
    .replace(/&nbsp;/g, " ").replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/\s+/g, " ").trim();

  let title = unescape(meta(["og:title", "twitter:title"]));
  if (!title) {
    const m = html.match(/<title[^>]*>([\s\S]{0,300}?)<\/title>/i);
    if (m) title = unescape(m[1]);
  }
  let image = unescape(meta(["og:image", "og:image:secure_url", "twitter:image"]));
  const site = unescape(meta(["og:site_name"])) || host.replace(/^www\./, "");
  let price = unescape(meta([
    "product:price:amount", "og:price:amount", "price", "twitter:data1",
  ]));
  let currency = unescape(meta(["product:price:currency", "og:price:currency", "priceCurrency"]));

  // JSON-LD Product — у крупных магазинов цена лежит именно там.
  if (!price) {
    const ld = html.match(/"price"\s*:\s*"?([0-9][0-9\s.,]*)"?/i);
    if (ld) price = ld[1];
  }
  if (!currency) {
    const cur = html.match(/"priceCurrency"\s*:\s*"([A-Za-z]{3})"/i);
    if (cur) currency = cur[1];
  }

  // Цена приходит как «12 990,00», «12990.00 RUB», «от 1 299 ₽» — оставляем
  // целые единицы: копейки в списке желаний никому не нужны.
  let amount = 0;
  if (price) {
    const digits = String(price).replace(/[^0-9.,]/g, "").replace(/\s/g, "");
    const cut = digits.replace(/[.,](\d{1,2})$/, "");
    const plain = cut.replace(/[.,]/g, "");
    const n = parseInt(plain, 10);
    if (!isNaN(n) && n > 0 && n < 1000000000) amount = n;
  }
  const sign = { RUB: "\u20BD", USD: "$", EUR: "\u20AC", KZT: "\u20B8", BYN: "Br", UAH: "\u20B4" };
  let cur = String(currency || "").toUpperCase();
  if (!cur && /[\u20BD]|руб/i.test(html.substring(0, 60000))) cur = "RUB";
  const currencySign = sign[cur] || (cur ? cur : "");

  // Относительная ссылка на картинку → абсолютная.
  if (image && image.indexOf("//") !== 0 && image.indexOf("http") !== 0) {
    const origin = raw.substring(0, raw.indexOf("://") + 3) + host;
    image = image.charAt(0) === "/" ? origin + image : origin + "/" + image;
  }
  if (image.indexOf("//") === 0) image = "https:" + image;

  return e.json(200, {
    success: true,
    title: title.substring(0, 120),
    image: image.substring(0, 500),
    shop: site.substring(0, 80),
    price: amount,
    currency: currencySign,
  });
}, $apis.requireAuth());
