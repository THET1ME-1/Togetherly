/// feedback.pb.js — обращение из приложения (11.11.2026).
///
/// `POST /api/feedback {kind, text, app, platform, lang}` от вошедшего человека.
/// Обращение сперва ложится в коллекцию `app_feedback` (правила закрыты, пишут
/// только хуки), потом письмом в ящик поддержки. Не дошло письмо — запись
/// остаётся с `delivered = false`, и крон раз в пять минут досылает: обращение
/// не теряется, даже если почта лежит.
///
/// Правила проверки и письмо — в `feedback_mail.js` (обработчики JSVM функций
/// своего файла не видят). Живой прогон: `python3 pocketbase/feedback.test.py`.
///
/// Деплой: положить оба файла в /opt/pocketbase/pb_hooks/ одним копированием.

routerAdd("POST", "/api/feedback", (e) => {
  const F = require(`${__hooks}/feedback_mail.js`);
  const body = new DynamicModel({ kind: "", text: "", app: "", platform: "", lang: "" });
  e.bindBody(body);
  const kind = String(body.kind || "").trim();
  const text = String(body.text || "").trim();
  const problem = F.problemOf(kind, text);
  if (problem) return e.json(400, { ok: false, error: problem });

  // Дневной предел на человека: счётчик в памяти, перезапуск его обнуляет —
  // от потока с одного аккаунта этого хватает.
  const me = e.auth.id;
  const key = F.dayKey(me, Date.now());
  const sent = Number($app.store().get(key) || 0);
  if (sent >= F.PER_DAY) {
    $app.logger().warn("feedback: дневной предел", "uid", me);
    return e.json(429, { ok: false, error: "too_many" });
  }

  let rec;
  try {
    rec = new Record($app.findCollectionByNameOrId("app_feedback"));
    rec.set("uid", me);
    rec.set("email", String(e.auth.getString("email") || ""));
    rec.set("name", String(e.auth.getString("display_name") || e.auth.getString("name") || ""));
    rec.set("kind", kind);
    rec.set("text", text);
    rec.set("app", String(body.app || "").slice(0, 40));
    rec.set("platform", String(body.platform || "").slice(0, 20));
    rec.set("lang", String(body.lang || "").slice(0, 10));
    rec.set("delivered", false);
    $app.save(rec);
  } catch (err) {
    $app.logger().error("feedback: запись не сохранилась", "uid", me, "err", String(err));
    return e.json(500, { ok: false, error: "internal" });
  }
  $app.store().set(key, sent + 1);

  // Письмо в ящик. Сбой почты человеку не показываем: обращение уже у нас,
  // крон дошлёт.
  try {
    const sentNow = F.deliver({
      id: rec.id, uid: me, email: rec.getString("email"), name: rec.getString("name"),
      kind: kind, text: text, app: rec.getString("app"),
      platform: rec.getString("platform"), lang: rec.getString("lang"),
    });
    if (sentNow) {
      rec.set("delivered", true);
      $app.save(rec);
    }
  } catch (err) {
    $app.logger().warn("feedback: письмо не легло, дошлёт крон", "id", rec.id, "err", String(err));
  }
  if (F.urgent(kind)) {
    $app.logger().warn("feedback: срочное обращение", "id", rec.id, "kind", kind, "uid", me);
  }
  return e.json(200, { ok: true, id: rec.id });
}, $apis.requireAuth());

// Досылка: письма, которые не легли в ящик с первого раза.
cronAdd("feedbackDeliver", "*/5 * * * *", () => {
  const F = require(`${__hooks}/feedback_mail.js`);
  let waiting = [];
  try {
    waiting = $app.findRecordsByFilter("app_feedback", "delivered = false", "created", 20, 0);
  } catch (_) { waiting = []; }
  for (let i = 0; i < waiting.length; i++) {
    const rec = waiting[i];
    try {
      const ok = F.deliver({
        id: rec.id, uid: rec.getString("uid"), email: rec.getString("email"),
        name: rec.getString("name"), kind: rec.getString("kind"), text: rec.getString("text"),
        app: rec.getString("app"), platform: rec.getString("platform"), lang: rec.getString("lang"),
      });
      if (ok) {
        rec.set("delivered", true);
        $app.save(rec);
      }
    } catch (err) {
      $app.logger().warn("feedback: досылка не прошла", "id", rec.id, "err", String(err));
      break; // почта лежит — остальные попробуем в следующий раз
    }
  }
});
