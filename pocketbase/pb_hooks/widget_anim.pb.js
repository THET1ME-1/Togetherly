/// Живое фото для парного виджета: сервер превращает видео или гифку в одну
/// картинку-раскадровку, телефоны только скачивают её.
///
/// Почему кадры готовит сервер, а не клиент: `ImageView` внутри виджета не
/// проигрывает ни видео, ни анимированный drawable (RemoteViews инфлейтит только
/// классы из белого списка), поэтому анимацию покадрово толкает приложение — ему
/// нужны кадры. Разбирать видео на телефоне партнёра дорого:
/// `MediaMetadataRetriever` тратит 100–200 мс на кадр, и на слабом аппарате
/// пульс рвётся. Здесь та же схема, что у HEIC-копий и миниатюр админки: файл
/// приезжает, скрипт делает облегчённую версию, клиент забирает результат.
///
/// Роуты:
///   POST /api/widget/anim/prepare  {mediaId} — сделать раскадровку (идемпотентно)
///   GET  /api/widget/anim/sheet?id= — отдать её (проверка членства в группе)
///
/// ВАЖНО (PB JSVM): обработчик изолирован и функций уровня файла НЕ видит,
/// поэтому проверки инлайнятся в каждый роут — выносить в общий хелпер нельзя.

// ── POST /api/widget/anim/prepare ────────────────────────────────────────────
routerAdd("POST", "/api/widget/anim/prepare", (e) => {
  const auth = e.auth;
  if (!auth) return e.json(401, { error: "unauthorized" });

  const info = e.requestInfo();
  const body = info.body || {};
  const mediaId = String(body["mediaId"] || "").replace(/[^a-zA-Z0-9_]/g, "");
  if (!mediaId) return e.json(400, { error: "no mediaId" });

  let rec;
  try {
    rec = $app.findRecordById("media", mediaId);
  } catch (_) {
    return e.json(404, { error: "media not found" });
  }

  // Членство проверяем сами: правило коллекции пускает участников читать, но
  // готовить раскадровку из чужого файла нельзя. `group_ids` — relation,
  // поэтому только getStringSlice: get() по нему в этой сборке JSVM врёт.
  const groupId = String(rec.getString("group_id") || "");
  let mine = false;
  try {
    const me = $app.findRecordById("users", auth.id);
    const groups = me.getStringSlice("group_ids") || [];
    for (let i = 0; i < groups.length; i++) {
      if (String(groups[i]) === groupId) { mine = true; break; }
    }
  } catch (_) {}
  if (!mine && String(rec.getString("uid") || "") !== auth.id) {
    return e.json(403, { error: "not your media" });
  }

  const sheet = "/opt/pocketbase/pb_data/widget_anim/" + mediaId + ".webp";
  const manifestPath = "/opt/pocketbase/pb_data/widget_anim/" + mediaId + ".json";

  // Уже готово — отвечаем сразу: клиент может позвать роут повторно после
  // потери сети, и второй прогон ffmpeg тут никому не нужен.
  try {
    const bytes = $os.readFile(manifestPath);
    const text = typeof bytes === "string" ? bytes : String.fromCharCode.apply(null, bytes);
    return e.json(200, { ok: true, ready: true, manifest: JSON.parse(text) });
  } catch (_) {}

  try {
    $os.exec("/opt/pocketbase/tools/widget_anim.py", "--ids", mediaId).output();
  } catch (err) {
    $app.logger().warn("widget_anim exec failed", "media", mediaId, "err", String(err));
    return e.json(500, { error: "prepare failed" });
  }

  try {
    const bytes = $os.readFile(manifestPath);
    const text = typeof bytes === "string" ? bytes : String.fromCharCode.apply(null, bytes);
    return e.json(200, { ok: true, ready: true, manifest: JSON.parse(text) });
  } catch (_) {
    $app.logger().warn("widget_anim no result", "media", mediaId);
    return e.json(422, { error: "unsupported file" });
  }
}, $apis.requireAuth());

// ── GET /api/widget/anim/sheet ───────────────────────────────────────────────
routerAdd("GET", "/api/widget/anim/sheet", (e) => {
  const auth = e.auth;
  if (!auth) return e.json(401, { error: "unauthorized" });

  const info = e.requestInfo();
  const q = info.query || {};
  const mediaId = String(q["id"] || "").replace(/[^a-zA-Z0-9_]/g, "");
  if (!mediaId) return e.json(400, { error: "no id" });

  let rec;
  try {
    rec = $app.findRecordById("media", mediaId);
  } catch (_) {
    return e.json(404, { error: "media not found" });
  }

  const groupId = String(rec.getString("group_id") || "");
  let mine = false;
  try {
    const me = $app.findRecordById("users", auth.id);
    const groups = me.getStringSlice("group_ids") || [];
    for (let i = 0; i < groups.length; i++) {
      if (String(groups[i]) === groupId) { mine = true; break; }
    }
  } catch (_) {}
  if (!mine && String(rec.getString("uid") || "") !== auth.id) {
    return e.json(403, { error: "not your media" });
  }

  try {
    const bytes = $os.readFile("/opt/pocketbase/pb_data/widget_anim/" + mediaId + ".webp");
    // Раскадровка по id неизменяема: кешируем надолго, чтобы виджет не тянул её
    // повторно при каждом обновлении.
    e.response.header().set("Cache-Control", "private, max-age=2592000, immutable");
    return e.blob(200, "image/webp", bytes);
  } catch (_) {
    return e.json(404, { error: "not prepared" });
  }
}, $apis.requireAuth());

// ── добор ────────────────────────────────────────────────────────────────────
// Если клиент не дозвался до prepare (упал, потерял сеть), раскадровка всё равно
// появится: раз в десять минут скрипт проходит свежие записи `kind=widget_anim`.
cronAdd("widgetAnimSweep", "*/10 * * * *", () => {
  try {
    $os.exec("/opt/pocketbase/tools/widget_anim.py").output();
  } catch (err) {
    $app.logger().warn("widget_anim sweep failed", "err", String(err));
  }
});
