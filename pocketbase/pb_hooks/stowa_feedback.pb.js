/// stowa_feedback.pb.js — обращение из приложения Stowa (15.11.2026).
///
/// `POST /api/stowa/feedback {kind, text, email?, device?, app, platform, lang}`
/// без входа: у Stowa нет аккаунтов. Пределы — 5 в сутки с одного адреса и
/// 200 в сутки всего, счётчики в памяти (адрес нигде не пишется). Обращение
/// ложится в `stowa_feedback`, потом письмом в ящик support@; не легло — крон
/// раз в пять минут досылает. Правила и письмо — `stowa_feedback_mail.js`.
///
/// Деплой: оба файла в /opt/pocketbase/pb_hooks/ одним копированием,
/// PocketBase перечитает хуки сам. Живой прогон: `pocketbase/stowa_feedback.test.py`.

routerAdd("POST", "/api/stowa/feedback", (e) => {
  const F = require(`${__hooks}/stowa_feedback_mail.js`);
  const body = new DynamicModel({ kind: "", text: "", email: "", device: "", app: "", platform: "", lang: "" });
  e.bindBody(body);
  const f = {
    kind: String(body.kind || "").trim(),
    text: String(body.text || "").trim(),
    email: String(body.email || "").trim(),
    device: String(body.device || "").trim().slice(0, 200),
    app: String(body.app || "").trim().slice(0, 40),
    platform: String(body.platform || "").trim().slice(0, 20),
    lang: String(body.lang || "").trim().slice(0, 10),
  };
  const problem = F.problemOf(f);
  if (problem) return e.json(400, { ok: false, error: problem });

  const now = Date.now();
  const ipKey = F.dayKey(e.realIP(), now);
  const allKey = F.dayKey("all", now);
  const fromIp = Number($app.store().get(ipKey) || 0);
  const all = Number($app.store().get(allKey) || 0);
  if (fromIp >= F.PER_IP || all >= F.PER_DAY) {
    $app.logger().warn("stowa feedback: предел", "all", all);
    return e.json(429, { ok: false, error: "too_many" });
  }

  let rec;
  try {
    rec = new Record(F.ensureCollection());
    for (const name of ["kind", "text", "email", "device", "app", "platform", "lang"]) rec.set(name, f[name]);
    rec.set("delivered", false);
    $app.save(rec);
  } catch (err) {
    $app.logger().error("stowa feedback: запись не сохранилась", "err", String(err));
    return e.json(500, { ok: false, error: "internal" });
  }
  $app.store().set(ipKey, fromIp + 1);
  $app.store().set(allKey, all + 1);

  try {
    if (F.deliver(F.fieldsOf(rec))) {
      rec.set("delivered", true);
      $app.save(rec);
    }
  } catch (err) {
    $app.logger().warn("stowa feedback: письмо не легло, дошлёт крон", "id", rec.id, "err", String(err));
  }
  return e.json(200, { ok: true, id: rec.id });
});

// Досылка писем, которые не легли в ящик с первого раза.
cronAdd("stowaFeedbackDeliver", "*/5 * * * *", () => {
  const F = require(`${__hooks}/stowa_feedback_mail.js`);
  let waiting = [];
  try {
    waiting = $app.findRecordsByFilter("stowa_feedback", "delivered = false", "created", 20, 0);
  } catch (_) { waiting = []; }
  for (let i = 0; i < waiting.length; i++) {
    const rec = waiting[i];
    try {
      if (F.deliver(F.fieldsOf(rec))) {
        rec.set("delivered", true);
        $app.save(rec);
      }
    } catch (err) {
      $app.logger().warn("stowa feedback: досылка не прошла", "id", rec.id, "err", String(err));
      break;
    }
  }
});
