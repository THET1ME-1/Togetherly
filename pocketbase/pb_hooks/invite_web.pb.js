/// invite_web.pb.js — веб-часть приглашений на PocketBase-VPS (замена Firebase
/// Hosting, который гасится вместе с проектом Firebase).
///
/// Отдаёт:
///   GET /invite/{code}               → HTML-лендинг: пробует открыть приложение
///                                      (loveapp://invite/CODE), иначе кнопка
///                                      «скачать». Ничего в БД не читает (нет
///                                      энумерации кодов, нулевая нагрузка).
///   GET /.well-known/assetlinks.json → верификация Android App Links для домена
///                                      togetherly.day (те же отпечатки,
///                                      что были на Firebase Hosting).
///
/// Деплой: положить файл в /opt/pocketbase/pb_hooks/ на VPS и перезапустить
/// сервис (systemctl restart pocketbase). Только чтение/статика — БД не трогает.

// Ссылка без кода: "https://togetherly.day/invite/".
//
// Такие уходили людям постоянно: приложение склеивало адрес с ПУСТЫМ кодом,
// пока сервер не выдал новый (`inviteLink` в моделях чинит это с 20.08.2026,
// но разосланное живёт в чужих переписках). Роутер на "/invite/{code}" пустой
// параметр не матчит, запрос падал в статику, и партнёр получал «File not
// found» — 30 заходов с настоящих устройств за 18–19 августа. Отправитель
// поломки не видит: у него ссылка выглядит как обычно, поэтому жалоба звучит
// как «партнёр не может перейти по пригласительной ссылке».
//
// Приложение отсюда НЕ открываем автоматически: показывать ему нечего, кода
// нет. Человеку нужно объяснение и путь дальше.
routerAdd("GET", "/invite/", (e) => {
  // JSVM-изоляция: обработчик НЕ видит функции уровня файла, поэтому тело
  // повторяется в обоих роутах целиком (грабля описана в CLAUDE.md).
  const PLAY_URL =
    "https://play.google.com/store/apps/details?id=com.togetherly.love";
  const RUSTORE_URL = "https://www.rustore.ru/catalog/app/com.togetherly.love";
  const APK_URL = "https://github.com/THET1ME-1/Togetherly/releases/latest";
  const HTML = "text/html; charset=utf-8";
  const html = [
    '<!doctype html><html lang="ru"><head><meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width,initial-scale=1">',
    "<title>Приглашение в Togetherly</title>",
    "<style>body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#fff5f7;",
    "color:#33202a;display:flex;min-height:100vh;margin:0;align-items:center;justify-content:center;text-align:center}",
    ".card{max-width:340px;padding:28px}",
    ".btn{display:inline-block;margin-top:18px;padding:14px 26px;border-radius:14px;background:#e5578a;color:#fff;",
    "text-decoration:none;font-weight:700}",
    ".store{display:block;margin:10px auto 0;max-width:260px;padding:13px 20px;border-radius:14px;",
    "background:#fff;border:1px solid #f0c9d6;color:#33202a;text-decoration:none;font-weight:600}",
    ".hint{margin-top:24px;font-size:13px;color:#7a5c67;line-height:1.5}",
    "</style></head><body><div class=\"card\">",
    "<h2>В ссылке нет кода</h2>",
    "<p>Её отправили раньше, чем приложение успело получить код приглашения.</p>",
    "<p>Попросите партнёра открыть раздел «Связь» и прислать ссылку заново — там же виден и сам код, его можно ввести руками.</p>",
    '<a class="btn" href="loveapp://invite">Открыть Togetherly</a>',
    '<p class="hint">Приложения ещё нет? Поставьте, а код введёте после входа.</p>',
    '<a class="store" href="' + PLAY_URL + '">Google Play</a>',
    '<a class="store" href="' + RUSTORE_URL + '">RuStore</a>',
    '<a class="store" href="' + APK_URL + '">Скачать APK</a>',
    "</div></body></html>",
  ].join("");
  return e.blob(200, HTML, html);
});

routerAdd("GET", "/invite", (e) => {
  // JSVM-изоляция: обработчик НЕ видит функции уровня файла, поэтому тело
  // повторяется в обоих роутах целиком (грабля описана в CLAUDE.md).
  const PLAY_URL =
    "https://play.google.com/store/apps/details?id=com.togetherly.love";
  const RUSTORE_URL = "https://www.rustore.ru/catalog/app/com.togetherly.love";
  const APK_URL = "https://github.com/THET1ME-1/Togetherly/releases/latest";
  const HTML = "text/html; charset=utf-8";
  const html = [
    '<!doctype html><html lang="ru"><head><meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width,initial-scale=1">',
    "<title>Приглашение в Togetherly</title>",
    "<style>body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#fff5f7;",
    "color:#33202a;display:flex;min-height:100vh;margin:0;align-items:center;justify-content:center;text-align:center}",
    ".card{max-width:340px;padding:28px}",
    ".btn{display:inline-block;margin-top:18px;padding:14px 26px;border-radius:14px;background:#e5578a;color:#fff;",
    "text-decoration:none;font-weight:700}",
    ".store{display:block;margin:10px auto 0;max-width:260px;padding:13px 20px;border-radius:14px;",
    "background:#fff;border:1px solid #f0c9d6;color:#33202a;text-decoration:none;font-weight:600}",
    ".hint{margin-top:24px;font-size:13px;color:#7a5c67;line-height:1.5}",
    "</style></head><body><div class=\"card\">",
    "<h2>В ссылке нет кода</h2>",
    "<p>Её отправили раньше, чем приложение успело получить код приглашения.</p>",
    "<p>Попросите партнёра открыть раздел «Связь» и прислать ссылку заново — там же виден и сам код, его можно ввести руками.</p>",
    '<a class="btn" href="loveapp://invite">Открыть Togetherly</a>',
    '<p class="hint">Приложения ещё нет? Поставьте, а код введёте после входа.</p>',
    '<a class="store" href="' + PLAY_URL + '">Google Play</a>',
    '<a class="store" href="' + RUSTORE_URL + '">RuStore</a>',
    '<a class="store" href="' + APK_URL + '">Скачать APK</a>',
    "</div></body></html>",
  ].join("");
  return e.blob(200, HTML, html);
});

routerAdd("GET", "/invite/{code}", (e) => {
  // JSVM-изоляция: константы объявляем ВНУТРИ хендлера — модульный уровень
  // хендлеру не виден (иначе ReferenceError).
  //
  // Куда слать того, у кого приложения нет. До 28 июля тут стоял репозиторий
  // togetherly_app_releases — его удалили 23 июля, и ссылка «Скачать» отдавала
  // 404: человека звали в приложение, а он упирался в пустую страницу. Магазины
  // идут первыми, sideload остаётся для тех, кому магазины недоступны.
  const PLAY_URL =
    "https://play.google.com/store/apps/details?id=com.togetherly.love";
  const RUSTORE_URL = "https://www.rustore.ru/catalog/app/com.togetherly.love";
  const APK_URL = "https://github.com/THET1ME-1/Togetherly/releases/latest";
  // Санитизация: только буквы/цифры, максимум 12 символов — иначе это не наш
  // код (и защита от reflected-XSS при вставке в HTML/URL).
  // Path-параметр берём из url.path (pathValue роутером этой сборки PB не
  // наполняется): "/invite/CODE" → "CODE".
  const path = String((e.request && e.request.url && e.request.url.path) || "");
  const raw = path.split("/invite/")[1] || "";
  const code = raw.replace(/[^A-Za-z0-9]/g, "").slice(0, 12).toUpperCase();
  const HTML = "text/html; charset=utf-8";
  if (!code) return e.blob(400, HTML, "<h1>Неверная ссылка приглашения</h1>");

  // Кто зовёт. Сухая страница с одним кодом не объясняет, зачем её открыли, —
  // имя приглашающего единственное, что делает её человеческой. Аватар не
  // показываем: файлы в `media` защищены, публичной ссылки у них нет.
  //
  // Читаем прямым запросом (как в moderation.pb.js): record-хелперы в этой
  // сборке JSVM отдавали пустоту без единой ошибки в журнале.
  let inviterName = "";
  try {
    const row = new DynamicModel({ nm: "" });
    $app
      .db()
      .newQuery(
        "SELECT u.display_name AS nm FROM invite_codes ic" +
          " JOIN users u ON u.id = ic.owner_uid WHERE ic.code = {:c} LIMIT 1",
      )
      .bind({ c: code })
      .one(row);
    inviterName = String(row.nm || "").trim();
  } catch (err) {
    // Кода нет, он погашен или база занята — покажем страницу без имени.
    try { $app.logger().error("invite name lookup: " + String(err)); } catch (_) {}
    inviterName = "";
  }
  // В HTML вставляем только буквы, цифры, пробелы и дефис: имя приходит от
  // людей, а страница публичная. Диапазоны выписаны руками: движок хуков
  // (goja) не понимает `\p{L}` — с ним фильтр молча съедал имя целиком.
  const safeName = inviterName
    .replace(/[^A-Za-z\u0400-\u04FF0-9 \-]/g, "")
    .trim()
    .slice(0, 24);
  const initial = safeName ? safeName.slice(0, 1).toUpperCase() : "";

  const deep = "loveapp://invite/" + code;
  const html = [
    '<!doctype html><html lang="ru"><head><meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width,initial-scale=1">',
    "<title>Приглашение в Togetherly</title>",
    "<style>body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#fff5f7;",
    "color:#33202a;display:flex;min-height:100vh;margin:0;align-items:center;justify-content:center;text-align:center}",
    ".card{max-width:340px;padding:28px}.code{font-size:34px;font-weight:800;letter-spacing:8px;color:#e5578a;margin:14px 0}",
    ".btn{display:inline-block;margin-top:18px;padding:14px 26px;border-radius:14px;background:#e5578a;color:#fff;",
    "text-decoration:none;font-weight:700}",
    ".store{display:block;margin:10px auto 0;max-width:260px;padding:13px 20px;border-radius:14px;",
    "background:#fff;border:1px solid #f0c9d6;color:#33202a;text-decoration:none;font-weight:600}",
    ".hint{margin-top:24px;font-size:13px;color:#7a5c67;line-height:1.5}",
    ".who{width:64px;height:64px;border-radius:50%;background:#ffd9de;color:#90003b;",
    "display:flex;align-items:center;justify-content:center;font-size:26px;font-weight:800;margin:0 auto 14px}",
    "</style></head><body><div class=\"card\">",
    safeName ? '<div class="who">' + initial + "</div>" : "",
    safeName
      ? "<h2>" + safeName + " зовёт вас в Togetherly</h2>"
      : "<h2>💞 Тебя приглашают в Togetherly</h2>",
    "<p>Одно приложение на двоих: общий чат, настроение, лента воспоминаний и виджеты на экране.</p>",
    '<p style="margin-top:18px">Код приглашения:</p><div class="code">' + code + "</div>",
    "<p>Открываем приложение…</p>",
    '<a class="btn" href="' + deep + '">Открыть в приложении</a>',
    '<p class="hint">Приложения ещё нет? Поставьте — код подхватится сам.</p>',
    '<a class="store" href="' + PLAY_URL + '">Google Play</a>',
    '<a class="store" href="' + RUSTORE_URL + '">RuStore</a>',
    '<a class="store" href="' + APK_URL + '">Скачать APK</a>',
    "</div><script>setTimeout(function(){location.href=" + JSON.stringify(deep) + "},400);</script>",
    "</body></html>",
  ].join("");
  return e.blob(200, HTML, html);
});

// iOS Universal Links: apple-app-site-association. appID = TeamID.BundleID
// (Y2Z9V86248.com.togetherly.love). Раздаётся как application/json (e.json),
// без extension-файла — content-type тут гарантирован. Работает после того,
// как выйдет iOS-сборка с applinks:togetherly.day в entitlements.
routerAdd("GET", "/.well-known/apple-app-site-association", (e) => {
  return e.json(200, {
    applinks: {
      apps: [],
      details: [
        {
          appIDs: ["Y2Z9V86248.com.togetherly.love"],
          appID: "Y2Z9V86248.com.togetherly.love",
          components: [{ "/": "/invite/*", comment: "invite deep links" }],
          paths: ["/invite/*"],
        },
      ],
    },
  });
});

// Android App Links: подтверждение владения доменом. Те же SHA-256 отпечатки
// (upload+play), что раздавались с Firebase Hosting (hosting/.well-known/).
routerAdd("GET", "/.well-known/assetlinks.json", (e) => {
  return e.json(200, [
    {
      relation: [
        "delegate_permission/common.handle_all_urls",
        "delegate_permission/common.get_login_creds",
      ],
      target: {
        namespace: "android_app",
        package_name: "com.togetherly.love",
        sha256_cert_fingerprints: [
          "8F:DF:49:55:24:67:80:B8:AA:96:DF:FC:B8:65:2B:58:EB:E7:7B:E0:42:30:72:9A:72:20:1B:7C:23:B5:FC:C4",
          "1E:94:4F:00:FE:F1:17:D5:00:03:56:03:44:FC:BE:4F:9F:69:BF:FA:4C:F3:5B:A8:9F:26:D0:32:C3:3A:4E:13",
        ],
      },
    },
  ]);
});
