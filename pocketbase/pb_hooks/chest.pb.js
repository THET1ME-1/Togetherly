/// Сундук недели: открывается за ролик, три раза в день, приз разыгрывает
/// сервер.
///
///   GET  /api/chest/state?tz=&platform=  — сколько осталось сегодня и шансы;
///   POST /api/chest/open                 — разыграть приз и выдать его;
///   POST /api/chest/keep                 — подарок из запаса себе на полку;
///   POST /api/chest/give                 — подарок из запаса партнёру.
///
/// В сундуке монеты, одиннадцать подарков, которых нет в витрине, рамки
/// аватарки и значки-жильцы (их список берётся из каталога) и Togetherly+.
/// Подарки, рамки и значки одной редкости выпадают с одинаковым шансом:
/// пул редкости (TIER_POOL) делится поровну между всеми её предметами. Шансы живут только здесь: экран сундука рисует ту таблицу,
/// что отдал `state`, поэтому проценты на экране всегда совпадают с розыгрышем.
///
/// Выпавший подарок сперва лежит в запасе: запись `chest_opens` с
/// `state = "stash"`. Человек решает сразу под сундуком или позже в ленте
/// «Из сундука» в магазине:
///   keep — на свою полку: запись `gifts` от отправителя `chest` самому себе,
///          сразу `reacted`, входящим не считается (отбор там по `sent`);
///   give — партнёру бесплатно: обычная запись `gifts` от меня партнёру с
///          нулевой ценой, приходит с анимацией и ждёт ответа, как любой.
/// Id подарка равен `openId`, поэтому повтор не создаёт второй записи.
/// `gifts/send` ключей сундука не знает — купить такой подарок нельзя.
///
/// Togetherly+ не выпадает на iPhone (там его не существует как понятия) и
/// тому, у кого он уже есть. Его доля уходит в «5 монет», и таблица, которую
/// видит человек, показывает ровно это.
///
/// «Сегодня» — по часам человека: `tz` — смещение от UTC в минутах. Подвинуть
/// часы можно, поэтому сверху стоит потолок за скользящие сутки.
///
/// ИДЕМПОТЕНТНОСТЬ: `openId` генерит клиент, он же `id` записи `chest_opens`.
/// Повтор после обрыва связи возвращает тот же приз и ничего не начисляет.
///
/// СЕЗОННЫЕ СУНДУКИ (08.10.2026) живут только на сервере: запись
/// `catalog_items` вида `chest` (id `chest_<ключ>`), в `data` — ключ, набор
/// вещей `set`, даты `from`/`until` (по часам человека, `until` не включая),
/// `perDay`, вес вещи по редкости `each` и всё, что рисует приложение.
/// `chest=<ключ>` в запросе — открыть сезонный: свои открытия в день (день
/// записи «<ключ>|ГГГГ-ММ-ДД», из копилки «+<ключ>|…»), свой потолок за сутки,
/// розыгрыш только вещей своего набора (`catalog_items.data.set`) плюс монеты
/// и Плюс как в обычном. Обычный сундук вещей с набором не выдаёт никогда —
/// иначе старые сборки получили бы то, чего не умеют показать. Гарантия
/// редкого общая на все сундуки. `state` обычного отдаёт `seasons` —
/// активные сезонные сундуки, по ним приложение строит галерею.
///
/// !!! ГРАБЛИ PB JSVM: обработчик исполняется в изолированном пуле и НЕ видит
/// функций уровня файла, поэтому таблица и хелперы продублированы в обоих.

routerAdd("GET", "/api/chest/state", (e) => {
  // Зеркало таблицы в /api/chest/open. Вес — в десятых долях процента.
  const ODDS = [
    ["coins5", "coins", 5, 301, "common"],
    ["coins10", "coins", 10, 180, "common"],
    ["coins25", "coins", 25, 75, "rare"],
    // Плюс навсегда — редчайший приз: выпавший Плюс навсегда снимает человека
    // с рекламы и с покупки. Неделя Плюса — чаще: попробовал и захотел
    // навсегда. Сумма «amount» у недели — число дней.
    ["plus", "plus", 0, 1, "legendary"],
    ["plus7", "plus_trial", 7, 10, "legendary"],
  ];
  // Гарантия: если PITY - 1 открытий подряд не принесли редкого или
  // легендарного приза (монеты не в счёт), следующее даёт его точно.
  const PITY = 10;
  // Подарки сундука. Своего веса у них нет: шанс считается из пула редкости
  // наравне с рамками и значками из каталога (TIER_POOL ниже).
  const GIFTS = [
    ["cookieheart", "common"], ["teddy", "common"], ["potion", "common"],
    ["throne", "rare"], ["champagne", "rare"], ["snowglobe", "rare"],
    ["rose", "rare"], ["perfume", "rare"], ["record", "rare"],
    ["locket", "legendary"], ["rings", "legendary"],
  ];
  // Пул редкости в десятых долях процента: делится поровну между ВСЕМИ её
  // предметами — подарком, рамкой и значком одной редкости выпадают одинаково.
  const TIER_POOL = { common: 252, rare: 144, legendary: 36 };
  let PER_DAY = 3;

  const me = e.auth.id;
  const q = e.request.url.query();
  let tz = parseInt(q.get("tz") || "0", 10);
  if (!isFinite(tz) || tz < -840 || tz > 840) tz = 0;
  const ios = (q.get("platform") || "") === "ios";
  // Рамки разыгрываются только сборкам, которые умеют их показать (`frames=1`).
  // Старым их доля целиком остаётся в «5 монет», таблица у них прежняя.
  const withFrames = (q.get("frames") || "") === "1";
  const shifted = new Date(Date.now() + tz * 60 * 1000);
  const day = shifted.toISOString().slice(0, 10);
  // Сезонные сундуки из каталога; активные уходят приложению списком.
  const chestKey = String(q.get("chest") || "").replace(/[^a-z0-9_]/g, "");
  const seasons = [];
  let season = null;
  try {
    const cs = $app.findRecordsByFilter("catalog_items", "enabled = true && kind = 'chest'", "sort", 20, 0);
    for (let i = 0; i < cs.length; i++) {
      let d = {};
      try { d = JSON.parse(cs[i].getString("data") || "{}") || {}; } catch (_) { d = {}; }
      if (!d.key || !d.set) continue;
      const on = (!d.from || day >= String(d.from)) && (!d.until || day < String(d.until));
      if (on) seasons.push(d);
      if (String(d.key) === chestKey && on) season = d;
    }
  } catch (_) {}
  const hw = !!chestKey;
  if (hw && !season) return e.json(403, { ok: false, error: "season_over" });
  const SET = hw ? String(season.set) : "";
  const EACH = (hw && season.each) || { common: 20, rare: 8, legendary: 3 };
  if (hw && season.perDay > 0) PER_DAY = season.perDay;
  // День записи: у сезонного своя приставка, счёт открытий раздельный.
  const dk = hw ? chestKey + "|" + day : day;
  const bk = hw ? "+" + chestKey + "|" + day : "b" + day;

  let user = null;
  try { user = $app.findRecordById("users", me); } catch (_) { user = null; }
  if (!user) return e.json(404, { ok: false, error: "no_user" });
  // Плюс разыгрывается и на iPhone: он там давно продаётся через App Store.
  // Прежде iOS исключался, и за неделю 5243 открытия с iPhone не дали ни
  // одного Плюса (04.10.2026).
  const noPlus = user.getBool("plus");
  // Страны, где реклама Яндекса недоступна (Украина: ноль показов РСЯ за
  // 30 дней, 08.10.2026). Там сундук открывается без ролика, но Плюс в таком
  // открытии не разыгрывается — решение владельца. Страну решает сервер по
  // адресу запроса, а не приложение: иначе блокировщик рекламы в России
  // открывал бы сундук даром. Список — CHEST_NO_AD_COUNTRIES, по умолчанию UA.
  let noAdZone = false;
  try {
    const zones = String($os.getenv("CHEST_NO_AD_COUNTRIES") || "UA").toUpperCase().split(",");
    const g = $http.send({ url: "http://127.0.0.1:8120/internal/geo?ip=" + encodeURIComponent(e.realIP()), method: "GET", timeout: 3 });
    const cc = g.statusCode === 200 && g.json ? String(g.json.country || "") : "";
    noAdZone = !!cc && zones.indexOf(cc) !== -1;
  } catch (_) { noAdZone = false; }

  // Всё, что разыгрывается по редкости: подарки сундука плюс рамки и
  // значки из каталога (`catalog_items`: вид `frame` и `badge` с `data.chest`).
  // Новая рамка или значок, заведённые на сервере, сами встают в розыгрыш.
  // Уже полученные рамки и значки выпадают; каталожное не получают и сборки
  // без флага `frames` (показать нечем). Их доля и остаток от деления уходят
  // в «5 монет», поэтому сумма таблицы всегда 1000.
  let ownedF = [];
  try { ownedF = JSON.parse(user.getString("owned_features") || "[]") || []; } catch (_) { ownedF = []; }
  let ownedI = [];
  try { ownedI = JSON.parse(user.getString("owned_icons") || "[]") || []; } catch (_) { ownedI = []; }
  let grantedI = [];
  try { grantedI = JSON.parse(user.getString("granted_badges") || "[]") || []; } catch (_) { grantedI = []; }
  // [id приза, вид, ярус, можно ли выдать, ключ во владении]
  const items = [];
  // Редкие призы обоих сундуков — для общей гарантии редкого.
  const rareAll = { plus: 1, plus7: 1 };
  for (let i = 0; i < GIFTS.length; i++) {
    if (GIFTS[i][1] !== "common") rareAll[GIFTS[i][0]] = 1;
    if (!hw) items.push([GIFTS[i][0], "gift", GIFTS[i][1], true, GIFTS[i][0]]);
  }
  try {
    const recs = $app.findRecordsByFilter("catalog_items", "enabled = true && (kind = 'frame' || kind = 'badge' || kind = 'gift')", "sort", 500, 0);
    for (let i = 0; i < recs.length; i++) {
      let d = {};
      try { d = JSON.parse(recs[i].getString("data") || "{}") || {}; } catch (_) { d = {}; }
      if (!d.key) continue;
      const kind = recs[i].getString("kind");
      const set = String(d.set || "");
      // Подарки из каталога разыгрываются только сезонные: обычные подарки
      // сундука перечислены в GIFTS выше.
      if (kind === "gift" && !set) continue;
      if (kind === "badge" && d.chest !== true) continue;
      const t = TIER_POOL[d.rarity] ? d.rarity : "common";
      const id = kind === "gift" ? String(d.key) : recs[i].id;
      if (t !== "common") rareAll[id] = 1;
      if (set !== SET) continue;
      const owned = kind === "frame"
        ? ownedF.indexOf("frame:" + recs[i].id) !== -1
        : kind === "badge" ? (ownedI.indexOf(d.key) !== -1 || grantedI.indexOf(d.key) !== -1) : false;
      items.push([id, kind, t, withFrames && !owned, String(d.key)]);
    }
  } catch (_) {}
  const tierCount = { common: 0, rare: 0, legendary: 0 };
  for (let i = 0; i < items.length; i++) tierCount[items[i][2]]++;
  const frameOdds = [];
  let frameSpare = 0;
  // Вес вещи: в обычном — доля пула редкости, в сезонном — своя на вещь.
  const wOf = (t) => hw ? (EACH[t] || 0) : (tierCount[t] ? Math.floor(TIER_POOL[t] / tierCount[t]) : 0);
  if (hw) {
    let sumOdds = 0, sumItems = 0;
    for (let i = 0; i < ODDS.length; i++) sumOdds += ODDS[i][3];
    for (let i = 0; i < items.length; i++) sumItems += EACH[items[i][2]] || 0;
    frameSpare = Math.max(0, 1000 - sumOdds - sumItems);
  } else {
    for (const t in TIER_POOL) {
      const each = tierCount[t] ? Math.floor(TIER_POOL[t] / tierCount[t]) : 0;
      frameSpare += TIER_POOL[t] - each * tierCount[t];
    }
  }
  for (let i = 0; i < items.length; i++) {
    const it = items[i];
    const w = wOf(it[2]);
    if (!it[3] || w <= 0) { frameSpare += w; continue; }
    frameOdds.push([it[0], it[1], 0, w, it[2], it[4]]);
  }

  let used = 0;
  try {
    used = $app.findRecordsByFilter("chest_opens", "user_uid = {:me} && day = {:day}", "", PER_DAY, 0,
      { me: me, day: dk }).length;
  } catch (_) { used = 0; }

  // Призы за сегодня по порядку, вместе с открытиями из копилки (их день
  // с приставкой «b»). Приз разыгрывается, как только ролик засчитан; ушёл
  // человек с экрана до анимации — без этого списка он не узнает, что выпало,
  // и решит, что попытка сгорела (письмо 29.09.2026). Вид восстанавливается
  // по ключу так же, как в повторе открытия.
  const today = [];
  try {
    const won = $app.findRecordsByFilter("chest_opens", "user_uid = {:me} && (day = {:day} || day = {:bday})", "created", 20, 0,
      { me: me, day: dk, bday: bk });
    for (let i = 0; i < won.length; i++) {
      const key = won[i].getString("prize");
      let kind = "gift";
      for (let j = 0; j < ODDS.length; j++) if (ODDS[j][0] === key) kind = ODDS[j][1];
      if (key.indexOf("frame_") === 0) kind = "frame";
      if (key.indexOf("badge_") === 0) kind = "badge";
      today.push({ key: key, kind: kind, amount: won[i].getInt("amount") });
    }
  } catch (_) {}

  // Неделя Плюса не выпадает тем, у кого Плюс или неделя уже идёт, и
  // сборкам без флага `frames`: показать её им нечем. Её доля — в «5 монет».
  const trialOn = (user.getInt("plus_trial_until") || 0) > Date.now();
  // Без ролика (noAdZone) Плюс не разыгрывается: ни навсегда, ни неделя.
  const skipRow = (r) => ((r[1] === "plus" || r[1] === "plus_trial") && noAdZone) ||
    (r[1] === "plus" && noPlus) || (r[1] === "plus_trial" && (noPlus || trialOn || !withFrames));
  let skippedW = 0;
  for (let i = 0; i < ODDS.length; i++) if (skipRow(ODDS[i])) skippedW += ODDS[i][3];
  // Гарантия общая: подряд считаются открытия обоих сундуков.
  const rarePlus = rareAll;
  let dry = 0;
  try {
    const last = $app.findRecordsByFilter("chest_opens", "user_uid = {:me}", "-created", PITY - 1, 0, { me: me });
    for (let i = 0; i < last.length; i++) { if (rarePlus[last[i].getString("prize")]) break; dry++; }
  } catch (_) { dry = 0; }

  const odds = [];
  for (let i = 0; i < ODDS.length; i++) {
    const r = ODDS[i];
    if (skipRow(r)) continue;
    let w = r[3];
    if (r[0] === "coins5") w += frameSpare + skippedW;
    odds.push({ key: r[0], kind: r[1], amount: r[2], weight: w, tier: r[4] });
  }
  for (let i = 0; i < frameOdds.length; i++) {
    const r = frameOdds[i];
    odds.push({ key: r[0], kind: r[1], amount: 0, weight: r[3], tier: r[4] });
  }
  // Копилка пары для блока на главной: `group` шлют сборки с копилкой.
  let jar = null;
  try { jar = require(`${__hooks}/pair_jar.js`).state(me, String(q.get("group") || "")); } catch (_) { jar = null; }
  return e.json(200, {
    ok: true, perDay: PER_DAY, left: Math.max(0, PER_DAY - used), day: day, odds: odds, jar: jar, today: today,
    // Через сколько открытий редкий приз гарантирован (1 — следующее).
    untilRare: PITY - dry,
    chest: hw ? chestKey : "main",
    // Рекламы здесь нет: приложение открывает без ролика и шлёт `noAd`.
    noAd: noAdZone,
    // Активные сезонные сундуки целиком (даты, цвета, файлы, названия):
    // приложение строит по ним галерею без своего кода под сезон.
    seasons: hw ? [] : seasons,
  });
}, $apis.requireAuth());

routerAdd("POST", "/api/chest/open", (e) => {
  const ODDS = [
    ["coins5", "coins", 5, 301, "common"],
    ["coins10", "coins", 10, 180, "common"],
    ["coins25", "coins", 25, 75, "rare"],
    // Плюс навсегда — редчайший приз: выпавший Плюс навсегда снимает человека
    // с рекламы и с покупки. Неделя Плюса — чаще: попробовал и захотел
    // навсегда. Сумма «amount» у недели — число дней.
    ["plus", "plus", 0, 1, "legendary"],
    ["plus7", "plus_trial", 7, 10, "legendary"],
  ];
  // Гарантия: если PITY - 1 открытий подряд не принесли редкого или
  // легендарного приза (монеты не в счёт), следующее даёт его точно.
  const PITY = 10;
  // Подарки сундука. Своего веса у них нет: шанс считается из пула редкости
  // наравне с рамками и значками из каталога (TIER_POOL ниже).
  const GIFTS = [
    ["cookieheart", "common"], ["teddy", "common"], ["potion", "common"],
    ["throne", "rare"], ["champagne", "rare"], ["snowglobe", "rare"],
    ["rose", "rare"], ["perfume", "rare"], ["record", "rare"],
    ["locket", "legendary"], ["rings", "legendary"],
  ];
  // Пул редкости в десятых долях процента: делится поровну между ВСЕМИ её
  // предметами — подарком, рамкой и значком одной редкости выпадают одинаково.
  const TIER_POOL = { common: 252, rare: 144, legendary: 36 };
  let PER_DAY = 3;
  // Потолок за скользящие сутки: против перевода часов туда-обратно. Свой у
  // каждого сундука — вдвое больше дневного.
  let PER_24H = 6;

  const body = new DynamicModel({ openId: "", groupId: "", tz: 0, platform: "", frames: false, bonus: false, chest: "", noAd: false });
  e.bindBody(body);
  // Открытие без ролика — только там, где рекламы нет (страну решает сервер,
  // см. /api/chest/state), и без Плюса в розыгрыше.
  const noAd = body.noAd === true;
  let noAdZone = false;
  if (noAd) {
    try {
      const zones = String($os.getenv("CHEST_NO_AD_COUNTRIES") || "UA").toUpperCase().split(",");
      const g = $http.send({ url: "http://127.0.0.1:8120/internal/geo?ip=" + encodeURIComponent(e.realIP()), method: "GET", timeout: 3 });
      const cc = g.statusCode === 200 && g.json ? String(g.json.country || "") : "";
      noAdZone = !!cc && zones.indexOf(cc) !== -1;
    } catch (_) { noAdZone = false; }
    if (!noAdZone) {
      $app.logger().warn("chest open: без ролика не из зоны без рекламы", "uid", e.auth.id, "ip", e.realIP());
      return e.json(403, { ok: false, error: "ad_required" });
    }
    // Каждое открытие без ролика — в журнал: по нему видно, не утекают ли
    // ролики через украинские VPN (`message like 'chest open: без ролика%'`).
    $app.logger().warn("chest open: без ролика", "uid", e.auth.id, "ip", e.realIP(), "openId", String(body.openId || ""));
  }
  const withFrames = body.frames === true;
  // Открытие из копилки пары: без ролика и сверх трёх в день. День такой
  // записи пишется с приставкой «b», поэтому в дневной счёт она не входит.
  const fromJar = body.bonus === true;
  const jarLib = require(`${__hooks}/pair_jar.js`);
  const openId = String(body.openId || "").trim();
  const groupId = String(body.groupId || "").trim();
  let tz = parseInt(String(body.tz), 10);
  if (!isFinite(tz) || tz < -840 || tz > 840) tz = 0;
  const ios = String(body.platform || "") === "ios";
  // Формат id записи PocketBase: он же станет id подарка на полке, а у
  // `gifts` поле id по умолчанию — 15 строчных букв и цифр.
  if (!/^[a-z0-9]{15}$/.test(openId) || !groupId) {
    return e.json(400, { ok: false, error: "bad_request" });
  }

  // Выключатель: app_config.chest_enabled = false — сундук не открывается,
  // а приложение прячет блок на главной. Одна команда на сервере, без релиза.
  try {
    const cfg = $app.findRecordsByFilter("app_config", "", "", 1, 0);
    if (cfg.length && !cfg[0].getBool("chest_enabled")) {
      return e.json(403, { ok: false, error: "chest_disabled" });
    }
  } catch (_) {}

  const me = e.auth.id;
  const now = Date.now();
  const day = new Date(now + tz * 60 * 1000).toISOString().slice(0, 10);
  const chestKey = String(body.chest || "").replace(/[^a-z0-9_]/g, "");
  let season = null;
  if (chestKey) {
    try {
      const cs = $app.findRecordsByFilter("catalog_items", "enabled = true && kind = 'chest'", "sort", 20, 0);
      for (let i = 0; i < cs.length; i++) {
        let d = {};
        try { d = JSON.parse(cs[i].getString("data") || "{}") || {}; } catch (_) { d = {}; }
        if (String(d.key) !== chestKey || !d.set) continue;
        if ((!d.from || day >= String(d.from)) && (!d.until || day < String(d.until))) season = d;
      }
    } catch (_) {}
  }
  const hw = !!chestKey;
  if (hw && !season) return e.json(403, { ok: false, error: "season_over" });
  const SET = hw ? String(season.set) : "";
  const EACH = (hw && season.each) || { common: 20, rare: 8, legendary: 3 };
  if (hw && season.perDay > 0) { PER_DAY = season.perDay; PER_24H = season.perDay * 2; }
  const dk = hw ? chestKey + "|" + day : day;
  const bk = hw ? "+" + chestKey + "|" + day : "b" + day;

  // Состав пары — из Postgres, как в gifts.pb.js: зеркало в SQLite отстаёт.
  let members = [];
  try {
    const r = $http.send({
      url: "http://127.0.0.1:8120/internal/group-read?id=" + encodeURIComponent(groupId),
      method: "GET",
      timeout: 8,
    });
    const rec = (r && r.json && r.json.record) || null;
    if (rec && Array.isArray(rec.members)) members = rec.members;
  } catch (_) { members = []; }
  let isMember = false;
  for (let i = 0; i < members.length; i++) if (String(members[i]) === me) isMember = true;

  let out = { s: 500, b: { ok: false, error: "internal" } };
  try {
    $app.runInTransaction((txApp) => {
      const user = txApp.findRecordById("users", me);

      let existing = null;
      try { existing = txApp.findRecordById("chest_opens", openId); } catch (_) { existing = null; }
      if (existing) {
        if (existing.getString("user_uid") !== me) {
          out = { s: 409, b: { ok: false, error: "conflict" } };
          return;
        }
        let usedNow = 0;
        try {
          usedNow = txApp.findRecordsByFilter("chest_opens", "user_uid = {:me} && day = {:day}", "", PER_DAY, 0,
            { me: me, day: existing.getString("day") }).length;
        } catch (_) { usedNow = 0; }
        const key = existing.getString("prize");
        let kind = "gift";
        for (let i = 0; i < ODDS.length; i++) if (ODDS[i][0] === key) kind = ODDS[i][1];
        if (key.indexOf("frame_") === 0) kind = "frame";
        if (key.indexOf("badge_") === 0) kind = "badge";
        let ownedNow = [];
        try { ownedNow = JSON.parse(user.getString("owned_features") || "[]") || []; } catch (_) { ownedNow = []; }
        let iconsNow = [];
        try { iconsNow = JSON.parse(user.getString("owned_icons") || "[]") || []; } catch (_) { iconsNow = []; }
        out = {
          s: 200,
          b: {
            ok: true, repeated: true,
            prize: { key: key, kind: kind, amount: existing.getInt("amount") },
            left: Math.max(0, PER_DAY - usedNow),
            coins: user.getInt("coins") || 0,
            plus: user.getBool("plus"),
            ownedFeatures: ownedNow,
            ownedIcons: iconsNow,
          },
        };
        return;
      }

      if (!isMember) {
        out = { s: 403, b: { ok: false, error: "not_member" } };
        return;
      }

      let today = 0, lastDay = 0;
      try {
        today = txApp.findRecordsByFilter("chest_opens", "user_uid = {:me} && day = {:day}", "", PER_DAY, 0,
          { me: me, day: dk }).length;
        const since = new Date(now - 24 * 60 * 60 * 1000).toISOString().replace("T", " ");
        lastDay = txApp.findRecordsByFilter("chest_opens",
          // Обычный: без копилки («b…») и без сезонных («…|…»). Сезонный: свой
          // ключ, без копилки («+…»).
          "user_uid = {:me} && created >= {:since} && " + (hw ? "day ~ {:pfx} && day !~ '+'" : "day !~ 'b' && day !~ '|'"), "", PER_24H, 0,
          { me: me, since: since, pfx: chestKey + "|" }).length;
      } catch (_) { today = 0; lastDay = 0; }
      if (fromJar) {
        if (!jarLib.takeBonus(txApp, groupId, me)) {
          out = { s: 409, b: { ok: false, error: "no_bonus", left: Math.max(0, PER_DAY - today) } };
          return;
        }
      } else if (today >= PER_DAY || lastDay >= PER_24H) {
        out = { s: 429, b: { ok: false, error: "chest_limit", left: 0 } };
        return;
      }

      // Розыгрыш по той же таблице, что показывает /api/chest/state.
      // iPhone наравне с Android: Плюс на iOS продаётся через App Store.
      const noPlus = user.getBool("plus");
      // Всё, что разыгрывается по редкости: подарки сундука плюс рамки и
      // значки из каталога (`catalog_items`: вид `frame` и `badge` с `data.chest`).
      // Новая рамка или значок, заведённые на сервере, сами встают в розыгрыш.
      // Уже полученные рамки и значки выпадают; каталожное не получают и сборки
      // без флага `frames` (показать нечем). Их доля и остаток от деления уходят
      // в «5 монет», поэтому сумма таблицы всегда 1000.
      let ownedF = [];
      try { ownedF = JSON.parse(user.getString("owned_features") || "[]") || []; } catch (_) { ownedF = []; }
      let ownedI = [];
      try { ownedI = JSON.parse(user.getString("owned_icons") || "[]") || []; } catch (_) { ownedI = []; }
      let grantedI = [];
      try { grantedI = JSON.parse(user.getString("granted_badges") || "[]") || []; } catch (_) { grantedI = []; }
      // [id приза, вид, ярус, можно ли выдать, ключ во владении]
      const items = [];
      // Редкие призы обоих сундуков — для общей гарантии редкого.
      const rareAll = { plus: 1, plus7: 1 };
      for (let i = 0; i < GIFTS.length; i++) {
        if (GIFTS[i][1] !== "common") rareAll[GIFTS[i][0]] = 1;
        if (!hw) items.push([GIFTS[i][0], "gift", GIFTS[i][1], true, GIFTS[i][0]]);
      }
      try {
        const recs = txApp.findRecordsByFilter("catalog_items", "enabled = true && (kind = 'frame' || kind = 'badge' || kind = 'gift')", "sort", 500, 0);
        for (let i = 0; i < recs.length; i++) {
          let d = {};
          try { d = JSON.parse(recs[i].getString("data") || "{}") || {}; } catch (_) { d = {}; }
          if (!d.key) continue;
          const kind = recs[i].getString("kind");
          const set = String(d.set || "");
          if (kind === "gift" && !set) continue;
          if (kind === "badge" && d.chest !== true) continue;
          const t = TIER_POOL[d.rarity] ? d.rarity : "common";
          const id = kind === "gift" ? String(d.key) : recs[i].id;
          if (t !== "common") rareAll[id] = 1;
          if (set !== SET) continue;
          const owned = kind === "frame"
            ? ownedF.indexOf("frame:" + recs[i].id) !== -1
            : kind === "badge" ? (ownedI.indexOf(d.key) !== -1 || grantedI.indexOf(d.key) !== -1) : false;
          items.push([id, kind, t, withFrames && !owned, String(d.key)]);
        }
      } catch (_) {}
      const tierCount = { common: 0, rare: 0, legendary: 0 };
      for (let i = 0; i < items.length; i++) tierCount[items[i][2]]++;
      const frameOdds = [];
      let frameSpare = 0;
      const wOf = (t) => hw ? (EACH[t] || 0) : (tierCount[t] ? Math.floor(TIER_POOL[t] / tierCount[t]) : 0);
      if (hw) {
        let sumOdds = 0, sumItems = 0;
        for (let i = 0; i < ODDS.length; i++) sumOdds += ODDS[i][3];
        for (let i = 0; i < items.length; i++) sumItems += EACH[items[i][2]] || 0;
        frameSpare = Math.max(0, 1000 - sumOdds - sumItems);
      } else {
        for (const t in TIER_POOL) {
          const each = tierCount[t] ? Math.floor(TIER_POOL[t] / tierCount[t]) : 0;
          frameSpare += TIER_POOL[t] - each * tierCount[t];
        }
      }
      for (let i = 0; i < items.length; i++) {
        const it = items[i];
        const w = wOf(it[2]);
        if (!it[3] || w <= 0) { frameSpare += w; continue; }
        frameOdds.push([it[0], it[1], 0, w, it[2], it[4]]);
      }

      const pool = [];
      let total = 0;
      const trialOn = (user.getInt("plus_trial_until") || 0) > now;
      // Без ролика Плюс не разыгрывается: ни навсегда, ни неделя.
      const skipRow = (r) => ((r[1] === "plus" || r[1] === "plus_trial") && noAd) ||
        (r[1] === "plus" && noPlus) || (r[1] === "plus_trial" && (noPlus || trialOn || !withFrames));
      let skippedW = 0;
      for (let i = 0; i < ODDS.length; i++) if (skipRow(ODDS[i])) skippedW += ODDS[i][3];
      for (let i = 0; i < ODDS.length; i++) {
        const r = ODDS[i];
        if (skipRow(r)) continue;
        let w = r[3];
        if (r[0] === "coins5") w += frameSpare + skippedW;
        pool.push([r[0], r[1], r[2], w]);
        total += w;
      }
      for (let i = 0; i < frameOdds.length; i++) {
        pool.push([frameOdds[i][0], frameOdds[i][1], 0, frameOdds[i][3], frameOdds[i][5]]);
        total += frameOdds[i][3];
      }
      // Гарантия редкого: считаем открытия подряд без редкого приза — в
      // обоих сундуках вместе.
      const rarePlus = rareAll;
      let dry = 0;
      try {
        const last = txApp.findRecordsByFilter("chest_opens", "user_uid = {:me}", "-created", PITY - 1, 0, { me: me });
        for (let i = 0; i < last.length; i++) { if (rarePlus[last[i].getString("prize")]) break; dry++; }
      } catch (_) { dry = 0; }
      if (dry >= PITY - 1) {
        const rare = pool.filter((p) => rarePlus[p[0]]);
        if (rare.length) {
          pool.length = 0;
          total = 0;
          for (let i = 0; i < rare.length; i++) { pool.push(rare[i]); total += rare[i][3]; }
        }
      }
      // Случайное число из криптостойкой строки, а не Math.random: пул JSVM
      // переиспользует рантаймы, и качеству его генератора верить незачем.
      const hex = $security.randomStringWithAlphabet(8, "0123456789abcdef");
      let roll = parseInt(hex, 16) % total;
      let prize = pool[0];
      for (let i = 0; i < pool.length; i++) {
        if (roll < pool[i][3]) { prize = pool[i]; break; }
        roll -= pool[i][3];
      }

      const rec = new Record(txApp.findCollectionByNameOrId("chest_opens"));
      rec.set("id", openId);
      rec.set("user_uid", me);
      rec.set("group_id", groupId);
      rec.set("day", fromJar ? bk : dk);
      rec.set("prize", prize[0]);
      rec.set("amount", prize[2]);
      rec.set("state", prize[1] === "gift" ? "stash" : "");
      txApp.save(rec);

      if (prize[1] === "coins") {
        user.set("coins", (user.getInt("coins") || 0) + prize[2]);
        txApp.save(user);
      } else if (prize[1] === "frame") {
        // Рамка — навсегда, тем же ключом владения, что и прочий каталог.
        const fk = "frame:" + prize[0];
        if (ownedF.indexOf(fk) === -1) ownedF.push(fk);
        user.set("owned_features", JSON.stringify(ownedF));
        txApp.save(user);
      } else if (prize[1] === "badge") {
        // Значок из сундука — в купленные значки (`owned_icons`), как и
        // оплаченный монетами: клиент читает владение оттуда.
        if (ownedI.indexOf(prize[4]) === -1) ownedI.push(prize[4]);
        user.set("owned_icons", JSON.stringify(ownedI));
        txApp.save(user);
      } else if (prize[1] === "plus_trial") {
        // Неделя Плюса — отдельным сроком: флаг `plus` не трогаем, иначе
        // покупка во время недели ответила бы «уже куплено», а снятие по сроку
        // задело бы тех, кто успел купить.
        const from = Math.max(user.getInt("plus_trial_until") || 0, now);
        user.set("plus_trial_until", from + prize[2] * 24 * 60 * 60 * 1000);
        txApp.save(user);
      } else if (prize[1] === "plus") {
        user.set("plus", true);
        user.set("plus_platform", "chest");
        user.set("last_plus_grant_ms", now);
        txApp.save(user);
      }

      out = {
        s: 200,
        b: {
          ok: true, repeated: false,
          prize: { key: prize[0], kind: prize[1], amount: prize[2] },
          left: Math.max(0, PER_DAY - today - (fromJar ? 0 : 1)),
          coins: user.getInt("coins") || 0,
          plus: user.getBool("plus"),
          jarBonus: jarLib.bonusLeft(txApp, groupId, me),
          ownedFeatures: ownedF,
          ownedIcons: ownedI,
          plusTrialUntil: user.getInt("plus_trial_until") || 0,
          untilRare: rarePlus[prize[0]] ? PITY : PITY - dry - 1,
        },
      };
    });
  } catch (err) {
    try {
      $http.send({
        url: "http://127.0.0.1:8000/api/1/store/",
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Sentry-Auth": "Sentry sentry_version=7, sentry_key=05953bce75c54cdb9fe149861d159da5",
        },
        body: JSON.stringify({
          message: "chest/open: " + String(err),
          level: "error",
          logger: "pb_hooks.chest",
          tags: { feature: "chest", route: "chest_open", open_id: openId, error_code: "server" },
        }),
        timeout: 5,
      });
    } catch (_) {}
    try { $app.logger().error("chest/open: " + String(err)); } catch (_) {}
    out = { s: 500, b: { ok: false, error: "internal" } };
  }
  // С Плюсом сундук открывается без ролика, и капля падает за само открытие;
  // остальным её кладёт роут награды за ролик.
  if (out.s === 200 && out.b && out.b.repeated === false && !fromJar) {
    try {
      const u = $app.findRecordById("users", me);
      if (u.getBool("plus") || (u.getInt("plus_trial_until") || 0) > Date.now()) {
        const jar = jarLib.addDrop(me, groupId);
        if (jar) { out.b.jar = jar; out.b.jarBonus = jar.bonus; }
      }
    } catch (_) {}
  }
  // Отказы и повторы роут пишет сам: PocketBase заносит в журнал только
  // ошибки своего уровня. Повтор — признак ответа, потерянного по дороге:
  // телефон не узнал о призе и спросил тем же номером снова.
  if (out.s !== 200 || (out.b && out.b.repeated === true)) {
    try {
      $app.logger().warn("chest open", "uid", me, "open_id", openId, "status", out.s,
        "result", String((out.b && out.b.error) || "repeated"), "jar", fromJar);
    } catch (_) {}
  }
  return e.json(out.s, out.b);
}, $apis.requireAuth());

// Подарок из запаса — себе на полку.
routerAdd("POST", "/api/chest/keep", (e) => {
  const body = new DynamicModel({ openId: "" });
  e.bindBody(body);
  const openId = String(body.openId || "").trim();
  if (!/^[a-z0-9]{15}$/.test(openId)) return e.json(400, { ok: false, error: "bad_request" });
  const me = e.auth.id;
  let out = { s: 500, b: { ok: false, error: "internal" } };
  try {
    $app.runInTransaction((txApp) => {
      let rec = null;
      try { rec = txApp.findRecordById("chest_opens", openId); } catch (_) { rec = null; }
      if (!rec || rec.getString("user_uid") !== me) {
        out = { s: 404, b: { ok: false, error: "not_found" } };
        return;
      }
      const state = rec.getString("state");
      if (state === "kept") {
        out = { s: 200, b: { ok: true, repeated: true } };
        return;
      }
      if (state !== "stash") {
        out = { s: 409, b: { ok: false, error: "already_used" } };
        return;
      }
      const now = Date.now();
      const g = new Record(txApp.findCollectionByNameOrId("gifts"));
      g.set("id", openId);
      g.set("group_id", rec.getString("group_id"));
      g.set("sender_uid", "chest");
      g.set("recipient_uid", me);
      g.set("gift_key", rec.getString("prize"));
      g.set("price", 0);
      g.set("refund", 0);
      g.set("state", "reacted");
      g.set("deliver_at", now);
      g.set("reacted_at", now);
      g.set("expires_at", now);
      txApp.save(g);
      rec.set("state", "kept");
      rec.set("gift_id", openId);
      txApp.save(rec);
      out = { s: 200, b: { ok: true, repeated: false } };
    });
  } catch (err) {
    try { $app.logger().error("chest/keep: " + String(err)); } catch (_) {}
    out = { s: 500, b: { ok: false, error: "internal" } };
  }
  return e.json(out.s, out.b);
}, $apis.requireAuth());

// Подарок из запаса — партнёру, бесплатно. Партнёр получает обычный подарок:
// анимация, отклик, полка. Нулевая цена значит, что отклик и отказ ничего не
// возвращают — монеты из воздуха не появляются (как у подарка за ролик).
routerAdd("POST", "/api/chest/give", (e) => {
  const LIFE_MS = 24 * 60 * 60 * 1000;
  const body = new DynamicModel({ openId: "", groupId: "" });
  e.bindBody(body);
  const openId = String(body.openId || "").trim();
  const groupId = String(body.groupId || "").trim();
  if (!/^[a-z0-9]{15}$/.test(openId) || !groupId) return e.json(400, { ok: false, error: "bad_request" });
  const me = e.auth.id;

  // Пара — из Postgres, как в gifts.pb.js: зеркало в SQLite отстаёт.
  let members = [];
  try {
    const r = $http.send({
      url: "http://127.0.0.1:8120/internal/group-read?id=" + encodeURIComponent(groupId),
      method: "GET",
      timeout: 8,
    });
    const g = (r && r.json && r.json.record) || null;
    if (g && Array.isArray(g.members)) members = g.members;
  } catch (_) { members = []; }
  let isMember = false, partner = "";
  for (let i = 0; i < members.length; i++) {
    const m = String(members[i]);
    if (m === me) isMember = true;
    else if (!partner) partner = m;
  }

  let out = { s: 500, b: { ok: false, error: "internal" } };
  try {
    $app.runInTransaction((txApp) => {
      let rec = null;
      try { rec = txApp.findRecordById("chest_opens", openId); } catch (_) { rec = null; }
      if (!rec || rec.getString("user_uid") !== me) {
        out = { s: 404, b: { ok: false, error: "not_found" } };
        return;
      }
      const state = rec.getString("state");
      if (state === "sent") {
        out = { s: 200, b: { ok: true, repeated: true } };
        return;
      }
      if (state !== "stash") {
        out = { s: 409, b: { ok: false, error: "already_used" } };
        return;
      }
      if (!isMember || !partner) {
        out = { s: 403, b: { ok: false, error: "not_member" } };
        return;
      }
      const now = Date.now();
      const g = new Record(txApp.findCollectionByNameOrId("gifts"));
      g.set("id", openId);
      g.set("group_id", groupId);
      g.set("sender_uid", me);
      g.set("recipient_uid", partner);
      g.set("gift_key", rec.getString("prize"));
      g.set("note", "");
      g.set("price", 0);
      g.set("state", "sent");
      g.set("deliver_at", now);
      g.set("expires_at", now + LIFE_MS);
      txApp.save(g);
      rec.set("state", "sent");
      rec.set("gift_id", openId);
      txApp.save(rec);
      out = { s: 200, b: { ok: true, repeated: false } };
    });
  } catch (err) {
    try { $app.logger().error("chest/give: " + String(err)); } catch (_) {}
    out = { s: 500, b: { ok: false, error: "internal" } };
  }
  return e.json(out.s, out.b);
}, $apis.requireAuth());
