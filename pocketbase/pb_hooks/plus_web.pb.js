/// plus_web.pb.js — активация Togetherly+ на сайте, без участия приложения.
///
/// Зачем. Оплата на lava.top ставит `plus` сама, если почта платежа совпала с
/// почтой аккаунта (`lava.pb.js`). Не совпала — покупка превращается в код
/// `TG…`, его выдаёт бот. А погасить код можно было только на экране
/// Togetherly+, которого на iPhone нет вовсе: человек платил и упирался в
/// тупик. Эта страница закрывает разрыв — приложение о ней ничего не знает и
/// нигде её не показывает.
///
/// Отдаёт:
///   GET  /plus            → страница с формой (код + почта аккаунта)
///   POST /api/plus/activate → гасит код и ставит `plus` на аккаунт
///
/// Деплой: положить в /opt/pocketbase/pb_hooks/ и systemctl restart pocketbase.

routerAdd("GET", "/plus", (e) => {
  const HTML = "text/html; charset=utf-8";
  const page =
    '<!doctype html><html lang="ru"><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width,initial-scale=1">' +
    '<meta name="robots" content="noindex">' +
    "<title>Активация Togetherly+</title><style>" +
    ":root{color-scheme:light dark}" +
    "body{margin:0;min-height:100vh;display:grid;place-items:center;" +
    "font:16px/1.5 system-ui,sans-serif;background:#F6EFFB;color:#1D1B20}" +
    "@media(prefers-color-scheme:dark){body{background:#141218;color:#E6E0E9}" +
    ".card{background:#1D1B20}}" +
    ".card{background:#fff;border-radius:28px;padding:32px;max-width:420px;" +
    "width:calc(100% - 32px);box-shadow:0 8px 40px rgba(110,79,192,.12)}" +
    "h1{font-size:24px;margin:0 0 8px}p{margin:0 0 20px;opacity:.75}" +
    "label{display:block;font-size:13px;font-weight:600;margin:0 0 6px}" +
    "input{width:100%;box-sizing:border-box;padding:14px 16px;font-size:16px;" +
    "border:1.5px solid #CAC4D0;border-radius:16px;margin:0 0 16px;" +
    "background:transparent;color:inherit}" +
    "button{width:100%;padding:16px;font-size:16px;font-weight:600;color:#fff;" +
    "background:#6E4FC0;border:0;border-radius:999px;cursor:pointer}" +
    "button:disabled{opacity:.5;cursor:default}" +
    "#msg{margin:16px 0 0;font-size:15px;min-height:24px}" +
    ".ok{color:#2E7D32}.err{color:#B3261E}" +
    "</style></head><body><div class=card>" +
    "<h1>Активация Togetherly+</h1>" +
    "<p>Код пришёл после оплаты. Почту укажите ту, с которой вы входите в приложение.</p>" +
    '<label for=code>Код</label><input id=code placeholder="TG-XXXX-XXXX" autocomplete=off>' +
    '<label for=email>Почта аккаунта</label><input id=email type=email placeholder="you@example.com" autocomplete=email>' +
    "<button id=go>Активировать</button><p id=msg></p>" +
    "</div><script>" +
    "var go=document.getElementById('go'),msg=document.getElementById('msg');" +
    "go.onclick=function(){" +
    "var c=document.getElementById('code').value.trim();" +
    "var m=document.getElementById('email').value.trim();" +
    "if(!c||!m){msg.className='err';msg.textContent='Заполните оба поля';return}" +
    "go.disabled=true;msg.className='';msg.textContent='Проверяем…';" +
    "fetch('/api/plus/activate',{method:'POST'," +
    "headers:{'Content-Type':'application/json'}," +
    "body:JSON.stringify({code:c,email:m})})" +
    ".then(function(r){return r.json()})" +
    ".then(function(d){go.disabled=false;" +
    "if(d&&d.ok){msg.className='ok';" +
    "msg.textContent='Готово. Откройте приложение — всё уже работает.'}" +
    "else{msg.className='err';msg.textContent=(d&&d.error)||'Не получилось'}})" +
    ".catch(function(){go.disabled=false;msg.className='err';" +
    "msg.textContent='Сеть недоступна, попробуйте ещё раз'})};" +
    "</script></body></html>";
  return e.blob(200, HTML, page);
});

routerAdd("POST", "/api/plus/activate", (e) => {
  // ГРАБЛИ JSVM: обработчик исполняется в изолированном пуле и функций уровня
  // файла не видит. Всё нужное объявлено здесь же.
  //
  // Ещё грабли: json-поле в теле запроса приходит массивом байт, а
  // `findFirstRecordByFilter` в этой сборке молча отдавал пустоту — читаем
  // прямым SQL, как в moderation.pb.js и invite_web.pb.js.
  let body = {};
  try {
    body = e.requestInfo().body || {};
  } catch (_) {
    body = {};
  }

  const rawCode = String(body.code || "");
  const rawEmail = String(body.email || "");
  // Код: только латиница и цифры, дефисы из «красивого» вида отбрасываем.
  // \p{L} в этом движке не работает вовсе — диапазоны выписаны руками.
  const code = rawCode.replace(/[^A-Za-z0-9]/g, "").toUpperCase().slice(0, 16);
  const email = rawEmail.trim().toLowerCase().slice(0, 128);

  if (!code || email.indexOf("@") < 1) {
    return e.json(400, { ok: false, error: "Проверьте код и почту" });
  }

  // Ответ на «не тот код» и «не та почта» одинаковый: иначе форма превращается
  // в проверку, зарегистрирована ли почта.
  const DENY = { ok: false, error: "Код не найден или уже использован" };

  let out = DENY;
  try {
    $app.runInTransaction((txApp) => {
      const row = new DynamicModel({ id: "", plus: false, used_by: "" });
      try {
        txApp
          .db()
          .newQuery(
            "SELECT id, plus, used_by FROM redeem_codes" +
              " WHERE code = {:c} LIMIT 1",
          )
          .bind({ c: code })
          .one(row);
      } catch (_) {
        return; // кода нет — out остаётся DENY
      }

      const id = String(row.id || "");
      if (!id) return;
      // Погашенный код второй раз не работает.
      if (String(row.used_by || "")) return;
      // Код пополнения монет активируется в приложении, здесь только Плюс.
      if (!(row.plus === true || row.plus === 1)) return;

      const who = new DynamicModel({ id: "" });
      try {
        txApp
          .db()
          .newQuery("SELECT id FROM users WHERE email = {:e} LIMIT 1")
          .bind({ e: email })
          .one(who);
      } catch (_) {
        return;
      }
      const uid = String(who.id || "");
      if (!uid) return;

      const user = txApp.findRecordById("users", uid);
      user.set("plus", true);
      // Откуда доступ: по этому полю потом видно, что человек платил на сайте,
      // а не через магазин.
      user.set("plus_platform", "lava");
      txApp.save(user);

      const rec = txApp.findRecordById("redeem_codes", id);
      rec.set("used_by", uid);
      rec.set("used_at", Date.now());
      txApp.save(rec);

      out = { ok: true };
    });
  } catch (err) {
    // $app.logger().info в _logs не попадает — только warn и выше.
    try {
      $app.logger().warn("plus activate failed: " + String(err));
    } catch (_) {}
    return e.json(500, { ok: false, error: "Сервер занят, попробуйте позже" });
  }

  return e.json(out.ok ? 200 : 400, out);
});
