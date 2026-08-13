/// Сбор дохода из всех источников для вкладки «Доход» (см. income.pb.js).
///
/// Отдельный модуль, а НЕ хук: хендлеры JSVM изолированы и функций своего файла
/// не видят, поэтому один и тот же сбор нужен и крону, и роуту `?force=1`
/// (первый запуск после заливки, проверка после смены ключей). Имя файла без
/// `.pb.js` — иначе PocketBase примет его за хук.

module.exports = function collectIncome() {

  const OUT = "/opt/pocketbase/pb_data/.income.json";
  const now = new Date();
  const iso = (d) => d.toISOString().slice(0, 10);
  const result = { updated: now.toISOString(), sources: {}, rates: {} };

  // ── курсы: доллар всему голова, остальное приводим к нему ──
  let rubPerUsd = 0, eurPerUsd = 0;
  try {
    const r = $http.send({ url: "https://open.er-api.com/v6/latest/USD", method: "GET", timeout: 20 });
    if (r.statusCode === 200) {
      const j = r.json || JSON.parse(String(r.raw || "{}"));
      rubPerUsd = Number((j.rates || {}).RUB) || 0;
      eurPerUsd = Number((j.rates || {}).EUR) || 0;
    }
  } catch (_) {}
  if (!rubPerUsd) rubPerUsd = 80;   // запасной курс: лучше приблизительно, чем ничего
  if (!eurPerUsd) eurPerUsd = 0.92;
  result.rates = { rub_per_usd: rubPerUsd, eur_per_usd: eurPerUsd, taken: now.toISOString() };
  const toUsd = (amount, cur) => {
    if (cur === "USD") return amount;
    if (cur === "RUB") return amount / rubPerUsd;
    if (cur === "EUR") return amount / eurPerUsd;
    return amount;
  };

  // ── РСЯ ────────────────────────────────────────────────────────────────────
  (() => {
    let token = "";
    try {
      const b = $os.readFile("/opt/pocketbase/pb_data/.rsya_token");
      token = (typeof b === "string" ? b : String.fromCharCode.apply(null, b)).trim();
    } catch (_) {}
    if (!token) { result.sources.rsya = { ok: false, reason: "нет токена" }; return; }

    const ask = (params) => {
      const url = "https://partner.yandex.ru/api/statistics2/get.json?lang=ru&currency=USD&" + params;
      const r = $http.send({ url: url, method: "GET", headers: { "Authorization": "OAuth " + token }, timeout: 25 });
      if (r.statusCode !== 200) throw new Error("РСЯ ответила " + r.statusCode);
      const j = r.json || JSON.parse(String(r.raw || "{}"));
      if (!j.data) throw new Error("РСЯ вернула ошибку");
      return j.data;
    };
    const rows = (data, key) => (data.points || []).map((p) => {
      const dim = p.dimensions || {};
      const first = Object.keys(dim)[0];
      const val = first ? dim[first] : null;
      const m = (p.measures || [{}])[0];
      return {
        name: Array.isArray(val) ? String(val[0]) : (val == null ? "—" : String(val)),
        v: Number(m.partner_wo_nds) || 0,
        s: Number(m.shows) || 0,
      };
    });

    try {
      // Ряд по дням за 30 дней закрывает сразу «сегодня», «вчера» и текущий месяц.
      const dayData = ask("period=30days&dimension_field=date|day&field=partner_wo_nds&field=shows&field=hits");
      const days = rows(dayData).map((r) => ({ d: r.name, v: r.v, s: r.s }));
      const today = iso(now), month = today.slice(0, 7);
      const yest = iso(new Date(now.getTime() - 24 * 3600 * 1000));
      const pick = (d) => { const f = days.filter((x) => x.d === d)[0]; return f ? f : { v: 0, s: 0 }; };
      const sumMonth = days.filter((x) => x.d.slice(0, 7) === month)
        .reduce((a, x) => ({ v: a.v + x.v, s: a.s + x.s }), { v: 0, s: 0 });
      const tot30 = days.reduce((a, x) => ({ v: a.v + x.v, s: a.s + x.s }), { v: 0, s: 0 });

      let prevMonth = 0;
      try {
        const pm = ask("period=lastmonth&field=partner_wo_nds");
        prevMonth = Number(((pm.points || [{}])[0].measures || [{}])[0].partner_wo_nds) || 0;
      } catch (_) {}

      const slice = (params) => { try { return rows(ask(params)).sort((a, b) => b.v - a.v).slice(0, 8); } catch (_) { return []; } };

      result.sources.rsya = {
        ok: true, currency: "USD", title: "Яндекс, реклама",
        today: pick(today).v, today_shows: pick(today).s,
        yesterday: pick(yest).v, yesterday_shows: pick(yest).s,
        month: sumMonth.v, month_shows: sumMonth.s,
        prev_month: prevMonth,
        d30: tot30.v, d30_shows: tot30.s,
        days: days,
        formats: slice("period=30days&entity_field=block_type&field=partner_wo_nds&field=shows"),
        geo: slice("period=30days&dimension_field=geo|country&field=partner_wo_nds&field=shows"),
        os: slice("period=30days&entity_field=os&field=partner_wo_nds&field=shows"),
      };
    } catch (err) {
      result.sources.rsya = { ok: false, reason: String(err).slice(0, 200) };
    }
  })();

  // ── lava (Togetherly+ и разовые продажи) ───────────────────────────────────
  (() => {
    let key = ""; try { key = $os.getenv("LAVA_API_KEY") || ""; } catch (_) {}
    if (!key) { result.sources.lava = { ok: false, reason: "нет ключа" }; return; }

    const begin = new Date(now.getTime() - 40 * 24 * 3600 * 1000).toISOString();
    const items = [];
    try {
      let page = 1, total = 0;
      while (page < 30) {
        const url = "https://gate.lava.top/api/v1/invoices?beginDate=" + encodeURIComponent(begin) +
          "&endDate=" + encodeURIComponent(now.toISOString()) + "&size=20&page=" + page;
        const r = $http.send({ url: url, method: "GET", headers: { "X-Api-Key": key }, timeout: 25 });
        if (r.statusCode !== 200) throw new Error("lava ответила " + r.statusCode);
        const j = r.json || JSON.parse(String(r.raw || "{}"));
        const part = j.items || [];
        for (let i = 0; i < part.length; i++) items.push(part[i]);
        total = Number(j.total) || items.length;
        if (items.length >= total || !part.length) break;
        page++;
      }
    } catch (err) {
      result.sources.lava = { ok: false, reason: String(err).slice(0, 200) };
      return;
    }

    const byDay = {};
    let gross = 0, fee = 0, count = 0, monthNet = 0, todayNet = 0, yestNet = 0;
    const today = iso(now), month = today.slice(0, 7);
    const yest = iso(new Date(now.getTime() - 24 * 3600 * 1000));
    for (let i = 0; i < items.length; i++) {
      const it = items[i];
      if (String(it.status).toUpperCase() !== "COMPLETED") continue;
      const rec = it.receipt || {};
      const cur = String(rec.currency || "RUB");
      const g = toUsd(Number(rec.amount) || 0, cur);
      const f = toUsd(Number(rec.fee) || 0, cur);
      const d = String(it.datetime || "").slice(0, 10);
      gross += g; fee += f; count++;
      byDay[d] = (byDay[d] || 0) + (g - f);
      if (d.slice(0, 7) === month) monthNet += g - f;
      if (d === today) todayNet += g - f;
      if (d === yest) yestNet += g - f;
    }
    const days = Object.keys(byDay).sort().map((d) => ({ d: d, v: byDay[d] }));

    // Витринные покупки идут мимо нашего ключа и в контрактах не видны —
    // сводку по продуктам за всё время берём отдельным методом.
    // ВАЖНО: строка ответа несёт СТАТУС, и оплаченные лежат вперемешку с
    // брошенными. Продажей считается только `completed`; `new` — человек открыл
    // оплату и ушёл, `failed` — платёж отклонён. Без этой проверки у Моти
    // выходило 16 «продаж» на 80 $, хотя её не купил никто.
    let products = [], pending = [];
    try {
      const r = $http.send({ url: "https://gate.lava.top/api/v1/sales/?size=50", method: "GET", headers: { "X-Api-Key": key }, timeout: 25 });
      if (r.statusCode === 200) {
        const j = r.json || JSON.parse(String(r.raw || "{}"));
        const list = j.items || [];
        for (let i = 0; i < list.length; i++) {
          const sales = list[i].sales || [];
          const done = String(list[i].status || "").toLowerCase() === "completed";
          for (let k = 0; k < sales.length; k++) {
            (done ? products : pending).push({
              name: String(list[i].title || "—"),
              status: String(list[i].status || ""),
              count: Number(sales[k].count) || 0,
              amount: Number(sales[k].amountTotal) || 0,
              currency: String(sales[k].currency || "RUB"),
            });
          }
        }
        const byMoney = (a, b) => toUsd(b.amount, b.currency) - toUsd(a.amount, a.currency);
        products.sort(byMoney); pending.sort(byMoney);
      }
    } catch (_) {}

    result.sources.lava = {
      ok: true, currency: "USD", title: "lava, Togetherly+",
      today: todayNet, yesterday: yestNet, month: monthNet,
      d40_gross: gross, d40_fee: fee, d40_net: gross - fee, count: count,
      days: days, products: products, pending: pending,
    };
  })();

  // ── сколько продано на самом деле ──────────────────────────────────────────
  // Отчёты lava показывают ТОЛЬКО счета, заведённые нашим API-ключом: покупку
  // с витрины (прямая ссылка app.lava.top) они не отдают вовсе, а таких
  // большинство — их закрывает разбор почты продавца. Поэтому «сколько продано»
  // считаем по своей базе, где выданный доступ виден при любом канале оплаты.
  (() => {
    const sold = { plus: {}, plus_total: 0, features: {} };
    try {
      const rows = arrayOf(new DynamicModel({ p: "", n: 0 }));
      $app.db().newQuery(
        "SELECT COALESCE(NULLIF(plus_platform, ''), 'неизвестно') AS p, COUNT(*) AS n " +
        "FROM users WHERE plus = 1 GROUP BY p").all(rows);
      for (let i = 0; i < rows.length; i++) {
        sold.plus[String(rows[i].p)] = Number(rows[i].n) || 0;
        sold.plus_total += Number(rows[i].n) || 0;
      }

      // Платные элементы каталога лежат в users.owned_features ключами «вид:id».
      const feats = arrayOf(new DynamicModel({ f: "", n: 0 }));
      $app.db().newQuery(
        "SELECT 'mood_pack:moti' AS f, COUNT(*) AS n FROM users " +
        "WHERE owned_features LIKE '%mood_pack:moti%'").all(feats);
      for (let i = 0; i < feats.length; i++) {
        if (Number(feats[i].n) > 0) sold.features[String(feats[i].f)] = Number(feats[i].n);
      }
      sold.ok = true;
    } catch (err) {
      sold.ok = false;
      sold.reason = String(err).slice(0, 200);
    }
    result.sold = sold;
  })();

  // ── AdMob ──────────────────────────────────────────────────────────────────
  (() => {
    let cfg = null;
    try {
      const b = $os.readFile("/opt/pocketbase/pb_data/.admob_oauth.json");
      cfg = JSON.parse(typeof b === "string" ? b : String.fromCharCode.apply(null, b));
    } catch (_) {}
    if (!cfg || !cfg.refresh_token) { result.sources.admob = { ok: false, reason: "не настроен" }; return; }

    try {
      const tok = $http.send({
        url: "https://oauth2.googleapis.com/token", method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: "client_id=" + encodeURIComponent(cfg.client_id) +
          "&client_secret=" + encodeURIComponent(cfg.client_secret) +
          "&refresh_token=" + encodeURIComponent(cfg.refresh_token) +
          "&grant_type=refresh_token",
        timeout: 20,
      });
      if (tok.statusCode !== 200) throw new Error("Google не дал токен, " + tok.statusCode);
      const access = (tok.json || JSON.parse(String(tok.raw || "{}"))).access_token;

      const start = new Date(now.getTime() - 29 * 24 * 3600 * 1000);
      const dspec = (d) => ({ year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate() });
      const rep = $http.send({
        url: "https://admob.googleapis.com/v1/accounts/" + cfg.publisher_id + "/networkReport:generate",
        method: "POST",
        headers: { "Authorization": "Bearer " + access, "Content-Type": "application/json" },
        body: JSON.stringify({
          reportSpec: {
            dateRange: { startDate: dspec(start), endDate: dspec(now) },
            dimensions: ["DATE"],
            metrics: ["ESTIMATED_EARNINGS", "IMPRESSIONS"],
            localizationSettings: { currencyCode: "USD" },
          },
        }),
        timeout: 30,
      });
      if (rep.statusCode !== 200) throw new Error("AdMob ответил " + rep.statusCode);
      const body = rep.json || JSON.parse(String(rep.raw || "[]"));
      const days = [];
      for (let i = 0; i < body.length; i++) {
        const row = body[i].row;
        if (!row) continue;
        const dv = ((row.dimensionValues || {}).DATE || {}).value || "";
        const m = row.metricValues || {};
        // Заработок AdMob отдаёт в микроединицах валюты.
        const earn = Number(((m.ESTIMATED_EARNINGS || {}).microsValue) || 0) / 1e6;
        const imp = Number(((m.IMPRESSIONS || {}).integerValue) || 0);
        if (dv.length === 8) days.push({ d: dv.slice(0, 4) + "-" + dv.slice(4, 6) + "-" + dv.slice(6, 8), v: earn, s: imp });
      }
      days.sort((a, b) => a.d < b.d ? -1 : 1);
      const today = iso(now), month = today.slice(0, 7);
      const yest = iso(new Date(now.getTime() - 24 * 3600 * 1000));
      const pick = (d) => { const f = days.filter((x) => x.d === d)[0]; return f ? f.v : 0; };
      result.sources.admob = {
        ok: true, currency: "USD", title: "AdMob, реклама",
        today: pick(today), yesterday: pick(yest),
        month: days.filter((x) => x.d.slice(0, 7) === month).reduce((a, x) => a + x.v, 0),
        d30: days.reduce((a, x) => a + x.v, 0),
        days: days,
      };
    } catch (err) {
      result.sources.admob = { ok: false, reason: String(err).slice(0, 200) };
    }
  })();

  // ── Google Play ────────────────────────────────────────────────────────────
  // Отчёты Play лежат CSV-архивами в бакете Cloud Storage и требуют подписи JWT
  // служебным аккаунтом — криптографии в JSVM нет, поэтому файл готовит
  // /opt/income/play_income.py по крону, а хук только читает готовое.
  (() => {
    try {
      const b = $os.readFile("/opt/pocketbase/pb_data/.play_income.json");
      const j = JSON.parse(typeof b === "string" ? b : String.fromCharCode.apply(null, b));
      result.sources.play = j;
    } catch (_) {
      result.sources.play = { ok: false, reason: "не настроен" };
    }
  })();

  // ── общий итог ─────────────────────────────────────────────────────────────
  const sum = (field) => {
    let t = 0;
    const s = result.sources;
    for (const k in s) if (s[k] && s[k].ok && typeof s[k][field] === "number") t += s[k][field];
    return t;
  };
  result.totals = {
    currency: "USD",
    today: sum("today"), yesterday: sum("yesterday"), month: sum("month"),
  };

  // Файл читается обратно побайтово и склеивается через String.fromCharCode —
  // это latin-1, и русские названия стран доехали бы кракозябрами. Поэтому
  // всё не-ASCII уезжает \uXXXX-последовательностями (как ensure_ascii у питона).
  const ascii = JSON.stringify(result).replace(/[\u0080-\uFFFF]/g, (c) =>
    "\\u" + ("0000" + c.charCodeAt(0).toString(16)).slice(-4));
  try { $os.writeFile(OUT, ascii, 0o600); }
  catch (err) { $app.logger().warn("income: сводка не записалась", "err", String(err)); }

  return result;
};
