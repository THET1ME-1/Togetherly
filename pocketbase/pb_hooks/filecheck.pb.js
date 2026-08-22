/// <reference path="../pb_data/types.d.ts" />
// filecheck.pb.js — проверка права на защищённый файл, не трогая бакет.
//
// ЗАЧЕМ: кэш раздачи (nginx, /etc/nginx/conf.d/files_cache.conf) спрашивает у
// PocketBase разрешение на каждый файл из `media` подзапросом `auth_request`.
// Раньше это был HEAD на сам файл, а после переезда хранилища в S3 PocketBase
// на КАЖДЫЙ такой HEAD выкачивает объект из бакета целиком и выбрасывает тело.
// Замер 22.08.2026: 30 HEAD к файлу на 450 КБ стоили 12,6 МБ трафика бакета —
// проверка прав стоила ровно столько же, сколько выдача файла. На проде это
// 91 проверка в минуту мимо кэша разрешений, около 18 ГБ в сутки при
// оплаченном терабайте в месяц.
//
// Роут повторяет ту же проверку по базе: находит запись, сверяет, что файл
// действительно её и лежит в защищённом поле, валидирует файловый токен и
// прогоняет правило коллекции через `$app.canAccessRecord`. Самого файла не
// касается вовсе, поэтому стоит один индексный запрос вместо мегабайта.
//
// ВАЖНО: роут не имеет права быть мягче PocketBase. Любое сомнение — отказ.
// Отказ отвечает 403, и кэш по `error_page 401 403 ... = @pocketbase` уводит
// запрос в сам PocketBase: человек получает ровно тот код, что и раньше, а
// дырой такой отказ стать не может.
//
// JSVM-грабли: обработчик не видит функций уровня файла, поэтому всё внутри.

routerAdd("GET", "/api/filecheck", (e) => {
  const q = e.requestInfo().query || {};
  const rawPath = String(q.p || "");
  const token = String(q.token || "");

  const m = /^\/api\/files\/([A-Za-z0-9_]+)\/([A-Za-z0-9_-]+)\/([A-Za-z0-9._-]+)$/.exec(rawPath);
  if (!m) {
    return e.json(403, { ok: false, error: "bad path" });
  }

  const collectionName = m[1];
  const recordId = m[2];
  const filename = m[3];

  let collection;
  try {
    collection = $app.findCollectionByNameOrId(collectionName);
  } catch (_) {
    return e.json(403, { ok: false, error: "no collection" });
  }

  let record;
  try {
    record = $app.findRecordById(collectionName, recordId);
  } catch (_) {
    return e.json(403, { ok: false, error: "no record" });
  }

  // Файл должен принадлежать записи и лежать в защищённом поле. Публичные
  // файлы кэш сюда не присылает, и разрешать их этим роутом не надо.
  let fields = [];
  try {
    fields = JSON.parse(collection.fields.string());
  } catch (_) {
    return e.json(403, { ok: false, error: "no schema" });
  }

  let belongs = false;
  let isProtected = false;
  for (let i = 0; i < fields.length; i++) {
    const f = fields[i];
    if (!f || f.type !== "file") continue;

    let vals = [];
    try {
      vals = record.getStringSlice(f.name) || [];
    } catch (_) {
      vals = [];
    }
    if (!vals.length) {
      let one = "";
      try {
        one = record.getString(f.name);
      } catch (_) {
        one = "";
      }
      if (one) vals = [one];
    }

    for (let j = 0; j < vals.length; j++) {
      if (String(vals[j]) === filename) {
        belongs = true;
        if (f.protected) isProtected = true;
      }
    }
  }

  if (!belongs) return e.json(403, { ok: false, error: "not this record" });
  if (!isProtected) return e.json(403, { ok: false, error: "not protected" });

  if (!token) return e.json(403, { ok: false, error: "no token" });

  let auth = null;
  try {
    auth = $app.findAuthRecordByToken(token, "file");
  } catch (_) {
    auth = null;
  }
  if (!auth) return e.json(403, { ok: false, error: "bad token" });

  const info = new RequestInfo({
    auth: auth,
    method: "GET",
    context: "default",
    query: {},
    headers: {},
    body: {},
  });

  let allowed = false;
  try {
    allowed = $app.canAccessRecord(record, info, collection.viewRule);
  } catch (_) {
    allowed = false;
  }

  if (!allowed) return e.json(403, { ok: false, error: "denied" });

  return e.json(200, { ok: true });
});
