/// <reference path="../pb_data/types.d.ts" />
// plus_pending.pb.js — оплаченное догоняет человека само.
//
// ЗАЧЕМ. Покупка на lava.top идёт по почте, а не по аккаунту. Если человека с
// такой почтой в базе ещё нет, сервер выпускает код и кладёт его в
// `redeem_codes` с `buyer_email` (см. lava.pb.js). Дальше по замыслу человек
// должен получить код у бота и ввести руками — и вот тут всё ломается:
//
//   • почту в платеже пишут с опечаткой (15.08.2026: оплата ушла с
//     `…@mail.com`, писала она с `…@mail.ru`, бот её не узнавал);
//   • код теряется в переписке, а до поддержки доходит один из десяти;
//   • человек просто не знает, что где-то надо вводить код.
//
// Поэтому оплаченное выдаётся само: при регистрации и при каждом входе сервер
// смотрит, нет ли непогашенного кода на почту этого человека, и гасит его.
// Никаких писем, кодов и переписки — человек входит, и Togetherly+ уже есть.
//
// ВАЖНО (PB JSVM): обработчик исполняется изолированно и НЕ видит функций
// своего файла — вся логика инлайном в каждом обработчике.

// ── при регистрации ──────────────────────────────────────────────────────────
onRecordAfterCreateSuccess((e) => {
  try {
    const почта = String(e.record.email() || "").trim().toLowerCase();
    if (почта) {
      $app.runInTransaction((txApp) => {
        let коды = [];
        try {
          коды = txApp.findRecordsByFilter(
            "redeem_codes", "used_by = ''", "-created", 200, 0) || [];
        } catch (_) { коды = []; }
        // Домен в платеже путают постоянно: 15.08.2026 оплата ушла с
        // «…@mail.com», человек писал с «…@mail.ru», а в приложение заходил
        // с «…@gmail.com». Поэтому сверяем сперва адрес целиком (включая
        // запасной в `given_to`), а если не совпал — часть до собачки, и
        // только когда она длинная: у «ksyu.afanaseva03» случайных двойников
        // не бывает, а у «anna» или «love» — сколько угодно.
        const часть = (a) => String(a || "").trim().toLowerCase().split("@")[0];
        const моя_часть = часть(почта);
        const мой = коды.find((к) => {
          const куплено = String(к.getString("buyer_email") || "").trim().toLowerCase();
          const запасной = String(к.getString("given_to") || "").trim().toLowerCase();
          if (куплено === почта || запасной === почта) return true;
          if (моя_часть.length < 12) return false;
          return часть(куплено) === моя_часть || часть(запасной) === моя_часть;
        });
        if (!мой) return;

        const user = txApp.findRecordById("users", e.record.id);
        мой.set("used_by", e.record.id);
        мой.set("used_at", Date.now());
        txApp.save(мой);

        if (мой.getBool("plus")) {
          user.set("plus", true);
          // Откуда доступ: код из покупки помечаем каналом оплаты, выданный
          // руками — «code». По этой паре поддержка потом видит причину.
          user.set("plus_platform", мой.getString("sku") ? "lava" : "code");
          user.set("last_plus_grant_ms", Date.now());
        }
        const монеты = мой.getInt("coins") || 0;
        if (монеты > 0) {
          user.set("coins", (user.getInt("coins") || 0) + монеты);
        }
        const ключ = мой.getString("feature") || "";
        if (ключ) {
          let owned = [];
          try { owned = JSON.parse(user.getString("owned_features") || "[]") || []; }
          catch (_) { owned = []; }
          if (owned.indexOf(ключ) === -1) {
            user.set("owned_features", JSON.stringify(owned.concat([ключ])));
          }
        }
        txApp.save(user);
        $app.logger().warn("оплаченное выдано при регистрации",
          "email", почта, "code", мой.getString("code"),
          "plus", String(мой.getBool("plus")));
      });
    }
  } catch (err) {
    // Регистрацию ломать нельзя: не вышло сейчас — выдастся при входе.
    console.log("plus_pending: регистрация", err);
  }
  e.next();
}, "users");

// ── при входе ────────────────────────────────────────────────────────────────
// Ловит тех, кто завёл аккаунт раньше, чем оплатил, и тех, у кого регистрация
// прошла мимо обработчика выше.
onRecordAuthRequest((e) => {
  try {
    const запись = e.record;
    const почта = String(запись.email() || "").trim().toLowerCase();
    if (почта) {
      $app.runInTransaction((txApp) => {
        let коды = [];
        try {
          коды = txApp.findRecordsByFilter(
            "redeem_codes", "used_by = ''", "-created", 200, 0) || [];
        } catch (_) { коды = []; }
        // Домен в платеже путают постоянно: 15.08.2026 оплата ушла с
        // «…@mail.com», человек писал с «…@mail.ru», а в приложение заходил
        // с «…@gmail.com». Поэтому сверяем сперва адрес целиком (включая
        // запасной в `given_to`), а если не совпал — часть до собачки, и
        // только когда она длинная: у «ksyu.afanaseva03» случайных двойников
        // не бывает, а у «anna» или «love» — сколько угодно.
        const часть = (a) => String(a || "").trim().toLowerCase().split("@")[0];
        const моя_часть = часть(почта);
        const мой = коды.find((к) => {
          const куплено = String(к.getString("buyer_email") || "").trim().toLowerCase();
          const запасной = String(к.getString("given_to") || "").trim().toLowerCase();
          if (куплено === почта || запасной === почта) return true;
          if (моя_часть.length < 12) return false;
          return часть(куплено) === моя_часть || часть(запасной) === моя_часть;
        });
        if (!мой) return;

        const user = txApp.findRecordById("users", запись.id);
        мой.set("used_by", запись.id);
        мой.set("used_at", Date.now());
        txApp.save(мой);

        if (мой.getBool("plus")) {
          user.set("plus", true);
          user.set("plus_platform", мой.getString("sku") ? "lava" : "code");
          user.set("last_plus_grant_ms", Date.now());
        }
        const монеты = мой.getInt("coins") || 0;
        if (монеты > 0) {
          user.set("coins", (user.getInt("coins") || 0) + монеты);
        }
        const ключ = мой.getString("feature") || "";
        if (ключ) {
          let owned = [];
          try { owned = JSON.parse(user.getString("owned_features") || "[]") || []; }
          catch (_) { owned = []; }
          if (owned.indexOf(ключ) === -1) {
            user.set("owned_features", JSON.stringify(owned.concat([ключ])));
          }
        }
        txApp.save(user);
        $app.logger().warn("оплаченное выдано при входе",
          "email", почта, "code", мой.getString("code"),
          "plus", String(мой.getBool("plus")));
      });
    }
  } catch (err) {
    // Вход важнее выдачи: не получилось — попробуем в следующий раз.
    console.log("plus_pending: вход", err);
  }
  e.next();
});
