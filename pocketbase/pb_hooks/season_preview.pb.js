/// <reference path="../pb_data/types.d.ts" />

// Предпросмотр сезона для приложения: в каком дне живёт этот человек и какие
// спрятанные сезонные наборы ему показывать (`day` пустой — настоящий
// календарь). Список — pb_data/.season_preview.json, см. season_preview.js.
routerAdd("GET", "/api/season/preview", (e) => {
  const preview = require(`${__hooks}/season_preview.js`);
  const day = preview.dayFor(e.auth.id);
  if (!day) return e.json(200, { ok: true, day: "", sets: [] });
  // наборы сезонных сундуков, идущих в этот день
  const sets = [];
  try {
    const cs = $app.findRecordsByFilter("catalog_items", "kind = 'chest'", "sort", 20, 0);
    for (let i = 0; i < cs.length; i++) {
      let d = {};
      try { d = JSON.parse(cs[i].getString("data") || "{}") || {}; } catch (_) { d = {}; }
      if (!d.set) continue;
      if ((!d.from || day >= String(d.from)) && (!d.until || day < String(d.until))) sets.push(String(d.set));
    }
  } catch (_) {}
  return e.json(200, { ok: true, day: day, sets: sets });
}, $apis.requireAuth());
