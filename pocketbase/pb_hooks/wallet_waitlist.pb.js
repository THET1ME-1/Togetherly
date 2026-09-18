/// Список ожидания Togetherly Wallet и флаг его выхода.
///
/// Кнопка с купюрами на главной ведёт сюда, пока Wallet не вышел: стена
/// показывает, сколько людей ждут, и записывает в очередь. В день выхода
/// флаг в `app_config.wallet` переключается скриптом `wallet_release.py`, и та
/// же кнопка открывает Wallet без обновления Togetherly.
///
///   GET  /api/wallet/waitlist  → { count, joined, place, wallet }
///   POST /api/wallet/waitlist  → то же, человек уже в списке
///
/// `wallet` — содержимое `app_config.wallet`: где Wallet вышел
/// (`android`, `ios`) и ссылки на магазины. Клиент получает его и отсюда, и
/// вместе с остальным конфигом при заходе на главную.
///
/// Запись одна на человека (уникальный индекс по `user_uid`), поэтому повторное
/// нажатие не накручивает счётчик. Коллекция закрыта правилами целиком: читать
/// и писать её можно только через эти маршруты.
///
/// Хелперы повторены в каждом обработчике: JSVM не показывает обработчику
/// функции уровня файла (см. CLAUDE.md, «Грабли JSVM»).

routerAdd("GET", "/api/wallet/waitlist", (e) => {
  const uid = e.auth ? e.auth.id : "";
  if (!uid) return e.json(401, { error: "auth" });

  let wallet = {};
  try {
    const cfg = $app.findRecordsByFilter("app_config", "", "", 1, 0);
    if (cfg.length) wallet = JSON.parse(cfg[0].getString("wallet") || "{}") || {};
  } catch (_) { wallet = {}; }

  let mine = null;
  try {
    mine = $app.findFirstRecordByFilter("wallet_waitlist", "user_uid = {:u}", { u: uid });
  } catch (_) { mine = null; }

  const count = $app.countRecords("wallet_waitlist");
  let place = 0;
  if (mine) {
    place = $app.countRecords("wallet_waitlist",
      $dbx.exp("[[created]] <= {:c}", { c: mine.getString("created") }));
  }
  return e.json(200, { count: count, joined: !!mine, place: place, wallet: wallet });
}, $apis.requireAuth());

routerAdd("POST", "/api/wallet/waitlist", (e) => {
  const uid = e.auth ? e.auth.id : "";
  if (!uid) return e.json(401, { error: "auth" });

  let platform = "";
  try {
    const body = e.requestInfo().body || {};
    platform = String(body.platform || "").slice(0, 16);
  } catch (_) { platform = ""; }

  let wallet = {};
  try {
    const cfg = $app.findRecordsByFilter("app_config", "", "", 1, 0);
    if (cfg.length) wallet = JSON.parse(cfg[0].getString("wallet") || "{}") || {};
  } catch (_) { wallet = {}; }

  let mine = null;
  try {
    mine = $app.findFirstRecordByFilter("wallet_waitlist", "user_uid = {:u}", { u: uid });
  } catch (_) { mine = null; }

  if (!mine) {
    try {
      const rec = new Record($app.findCollectionByNameOrId("wallet_waitlist"));
      rec.set("user_uid", uid);
      rec.set("platform", platform);
      $app.save(rec);
      mine = rec;
    } catch (err) {
      // Двойное нажатие с двух телефонов: вторую вставку отбил уникальный
      // индекс, а запись уже есть — отвечаем так, будто всё прошло.
      try {
        mine = $app.findFirstRecordByFilter("wallet_waitlist", "user_uid = {:u}", { u: uid });
      } catch (_) {
        $app.logger().warn("wallet: не записали в ожидание", "uid", uid, "err", String(err));
        return e.json(500, { error: "save" });
      }
    }
  }

  const count = $app.countRecords("wallet_waitlist");
  const place = $app.countRecords("wallet_waitlist",
    $dbx.exp("[[created]] <= {:c}", { c: mine.getString("created") }));
  return e.json(200, { count: count, joined: true, place: place, wallet: wallet });
}, $apis.requireAuth());
