/// <reference path="../pb_data/types.d.ts" />
// user_card.pb.js — публичная карточка человека из своей пары.
//
// ЗАЧЕМ: правила коллекции `users` пускают читать ТОЛЬКО себя
// (`id = @request.auth.id`), поэтому `getOne(partnerUid)` с клиента всегда
// отвечал 404. Приложение спрашивало у него баннер профиля и значок партнёра —
// и молча получало пустоту. Жалоба 13 августа 2026: «не отображается баннер
// партнёра, хоть он и добавлен в профиль». Баннер к тому дню поставили 2372
// человека, и ни одного из них партнёр не видел ни разу.
//
// Открывать саму коллекцию нельзя: там почта, монеты, покупки и служебные
// отметки. Роут отдаёт ровно те поля, которые и так рисуются на экране пары.
//
// Членство сверяем по `users.group_ids` — то же быстрое правило, что и во всех
// парных коллекциях (через `@collection.groups` ответы уходили за 30 секунд).
//
// JSVM-грабли: обработчик не видит функций уровня файла, поэтому всё внутри.

routerAdd("GET", "/api/user/card", (e) => {
  const uid = String((e.requestInfo().query || {}).uid || "").trim();
  if (!uid) return e.json(400, { ok: false, error: "no uid" });

  const me = e.auth ? e.auth.id : "";
  if (!me) return e.json(401, { ok: false, error: "no auth" });

  // Свою карточку отдаём без сверки групп.
  if (uid !== me) {
    let mine = [];
    let theirs = [];
    try {
      mine = e.auth.getStringSlice("group_ids") || [];
      const other = $app.findRecordById("users", uid);
      theirs = other.getStringSlice("group_ids") || [];
    } catch (_) {
      return e.json(404, { ok: false, error: "not found" });
    }
    let shared = false;
    for (const g of mine) {
      if (g && theirs.indexOf(g) !== -1) { shared = true; break; }
    }
    if (!shared) return e.json(403, { ok: false, error: "not in your pair" });
  }

  let rec;
  try {
    rec = $app.findRecordById("users", uid);
  } catch (_) {
    return e.json(404, { ok: false, error: "not found" });
  }

  return e.json(200, {
    ok: true,
    id: rec.id,
    display_name: rec.getString("display_name"),
    avatar_url: rec.getString("avatar_url"),
    banner_url: rec.getString("banner_url"),
    badge: rec.getString("badge"),
    gender: rec.getString("gender"),
    birth_date: rec.getString("birth_date"),
    // Ночная сцена маскота: её показывают обоим, поле правит сам человек.
    mascot_sleep: rec.get("mascot_sleep"),
    granted_badges: rec.getStringSlice("granted_badges") || [],
  });
}, $apis.requireAuth());
