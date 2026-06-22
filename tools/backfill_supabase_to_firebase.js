// Бэкфилл Supabase → Firebase для пар, у которых под Stage 4 запись в Firebase
// была отключена (данные ушли только в Supabase). АДДИТИВНЫЙ и БЕЗОПАСНЫЙ:
//   • пишет в Firebase ТОЛЬКО записи, которых там НЕТ (precondition exists:false
//     на каждом write → затереть существующий свежий Firebase невозможно);
//   • удалённые в Supabase (deleted=true) НЕ воскрешает;
//   • DRY-RUN по умолчанию — без --commit ничего не пишет, только считает.
//
// Доступ:
//   • Firebase — owner refresh_token из firebase CLI configstore (как admin_groups.js).
//   • Supabase — service-role ключ из переменной окружения SBKEY (в файлы НЕ писать).
//
// Использование:
//   SBKEY=... node tools/backfill_supabase_to_firebase.js memories            # dry-run, все stage4-группы
//   SBKEY=... node tools/backfill_supabase_to_firebase.js memories --group GID # одна группа
//   SBKEY=... node tools/backfill_supabase_to_firebase.js memories --limit 20  # первые 20 групп
//   SBKEY=... node tools/backfill_supabase_to_firebase.js memories --commit    # БОЕВОЙ прогон (пишет)

const fs = require("fs");
const os = require("os");
const https = require("https");

const PROJECT = "togetherly-d4856";
const FS_HOST = "firestore.googleapis.com";
const FS_BASE = `/v1/projects/${PROJECT}/databases/(default)/documents`;
const CID =
  "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com";
const CSEC = "j9iVZfS8kkCEFUPaAeJV0sAi";
const FRESH_DAYS = 21;

const SB_HOST = "xxjlzzkhrvyiqaexvymx.supabase.co";
const SBKEY = process.env.SBKEY || process.env.SUPABASE_SERVICE_ROLE_KEY || "";

const args = process.argv.slice(2);
const TYPE = args[0];
const COMMIT = args.includes("--commit");
const onlyGroup = (() => {
  const i = args.indexOf("--group");
  return i >= 0 ? args[i + 1] : null;
})();
const limitGroups = (() => {
  const i = args.indexOf("--limit");
  return i >= 0 ? parseInt(args[i + 1], 10) : null;
})();

function req(method, host, path, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const data =
      body == null ? null : typeof body === "string" ? body : JSON.stringify(body);
    const h = Object.assign({}, headers);
    if (data != null) h["Content-Length"] = Buffer.byteLength(data);
    const r = https.request({ host, path, method, headers: h }, (resp) => {
      let d = "";
      resp.on("data", (c) => (d += c));
      resp.on("end", () => resolve({ status: resp.statusCode, body: d }));
    });
    r.on("error", reject);
    if (data != null) r.write(data);
    r.end();
  });
}

async function getToken() {
  const f = os.homedir() + "/.config/configstore/firebase-tools.json";
  const j = JSON.parse(fs.readFileSync(f, "utf8"));
  if (!j.tokens || !j.tokens.refresh_token) throw new Error("Нет refresh_token — `firebase login`.");
  const form =
    "client_id=" + encodeURIComponent(CID) +
    "&client_secret=" + encodeURIComponent(CSEC) +
    "&refresh_token=" + encodeURIComponent(j.tokens.refresh_token) +
    "&grant_type=refresh_token";
  const tk = await req("POST", "oauth2.googleapis.com", "/token", form, {
    "Content-Type": "application/x-www-form-urlencoded",
  });
  if (tk.status !== 200) throw new Error("refresh_token обмен не удался: " + tk.body.slice(0, 200));
  return { token: JSON.parse(tk.body).access_token, email: (j.user && j.user.email) || "?" };
}

function fbHeaders(token, json = true) {
  const h = { Authorization: "Bearer " + token, "x-goog-user-project": PROJECT };
  if (json) h["Content-Type"] = "application/json";
  return h;
}
function sbHeaders() {
  return { apikey: SBKEY, Authorization: "Bearer " + SBKEY, "Content-Type": "application/json" };
}

// ── Firestore value helpers ──
function fv(field) {
  if (!field) return undefined;
  if ("stringValue" in field) return field.stringValue;
  if ("booleanValue" in field) return field.booleanValue;
  if ("integerValue" in field) return Number(field.integerValue);
  if ("doubleValue" in field) return field.doubleValue;
  if ("timestampValue" in field) return field.timestampValue;
  if ("nullValue" in field) return null;
  if ("arrayValue" in field) return (field.arrayValue.values || []).map(fv);
  if ("mapValue" in field) {
    const out = {};
    const fields = field.mapValue.fields || {};
    for (const k of Object.keys(fields)) out[k] = fv(fields[k]);
    return out;
  }
  return undefined;
}

const TS_KEYS = new Set(["createdAt", "editedAt"]);
function toFs(v, key) {
  if (v === null || v === undefined) return { nullValue: null };
  if (TS_KEYS.has(key) && typeof v === "string") {
    const d = Date.parse(v);
    if (!isNaN(d)) return { timestampValue: new Date(d).toISOString() };
  }
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number")
    return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === "string") return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map((e) => toFs(e)) } };
  if (typeof v === "object") {
    const fields = {};
    for (const k of Object.keys(v)) fields[k] = toFs(v[k], k);
    return { mapValue: { fields } };
  }
  return { stringValue: String(v) };
}
function toFsFields(map) {
  const fields = {};
  for (const k of Object.keys(map)) fields[k] = toFs(map[k], k);
  return fields;
}

// ── stage4 group discovery (same logic as backfill_scope.js) ──
async function scanStage4Groups(token) {
  const docs = [];
  let cursorName = null;
  for (;;) {
    const sq = {
      structuredQuery: {
        from: [{ collectionId: "groups" }],
        select: { fields: [{ fieldPath: "members" }, { fieldPath: "sbRead" }, { fieldPath: "disbanded" }] },
        orderBy: [{ field: { fieldPath: "__name__" }, direction: "ASCENDING" }],
        limit: 1000,
      },
    };
    if (cursorName) sq.structuredQuery.startAt = { before: false, values: [{ referenceValue: cursorName }] };
    const r = await req("POST", FS_HOST, `${FS_BASE}:runQuery`, sq, fbHeaders(token));
    if (r.status !== 200) throw new Error(`scan runQuery ${r.status}: ${r.body.slice(0, 200)}`);
    const rows = JSON.parse(r.body).filter((x) => x.document);
    if (!rows.length) break;
    for (const x of rows) docs.push(x.document);
    cursorName = rows[rows.length - 1].document.name;
    if (rows.length < 1000) break;
  }
  const nowMs = Date.now();
  const out = [];
  for (const doc of docs) {
    const f = doc.fields || {};
    if (fv(f.disbanded) === true) continue;
    const members = (fv(f.members) || []).filter((s) => s);
    const sbRead = fv(f.sbRead) || {};
    if (!members.length) continue;
    let allFresh = true;
    for (const m of members) {
      const ts = sbRead[m];
      const dt = ts ? Date.parse(ts) : NaN;
      if (isNaN(dt) || (nowMs - dt) / 86400000 > FRESH_DAYS) { allFresh = false; break; }
    }
    if (allFresh) out.push(doc.name.split("/").pop());
  }
  return out;
}

// ── Supabase: все строки таблицы по группе (постранично) ──
async function sbRows(table, gid, select) {
  const out = [];
  const PAGE = 1000;
  for (let from = 0; ; from += PAGE) {
    const path =
      `/rest/v1/${table}?group_id=eq.${encodeURIComponent(gid)}` +
      `&deleted=eq.false&select=${encodeURIComponent(select)}`;
    const r = await req("GET", SB_HOST, path, null, {
      ...sbHeaders(),
      Range: `${from}-${from + PAGE - 1}`,
      "Range-Unit": "items",
    });
    if (r.status !== 200 && r.status !== 206) throw new Error(`SB ${table} ${r.status}: ${r.body.slice(0, 200)}`);
    const rows = JSON.parse(r.body);
    out.push(...rows);
    if (rows.length < PAGE) break;
  }
  return out;
}

// ── Firebase: id существующих доков подколлекции группы ──
async function fbExistingIds(token, gid, sub) {
  const ids = new Set();
  const sq = {
    structuredQuery: {
      from: [{ collectionId: sub }],
      select: { fields: [{ fieldPath: "__name__" }] },
      limit: 20000,
    },
  };
  const r = await req("POST", FS_HOST, `${FS_BASE}/groups/${gid}:runQuery`, sq, fbHeaders(token));
  if (r.status !== 200) throw new Error(`FB existing ${sub} ${r.status}: ${r.body.slice(0, 200)}`);
  for (const x of JSON.parse(r.body)) {
    if (x.document) ids.add(x.document.name.split("/").pop());
  }
  return ids;
}

// ── Firebase: commit пачки create-only writes (exists:false) ──
async function fbCommitCreate(token, writes) {
  for (let i = 0; i < writes.length; i += 400) {
    const batch = writes.slice(i, i + 400);
    const r = await req("POST", FS_HOST, `${FS_BASE}:commit`, { writes: batch }, fbHeaders(token));
    if (r.status !== 200) throw new Error(`commit ${r.status}: ${r.body.slice(0, 300)}`);
  }
}

// ── MEMORIES ──
async function backfillMemories(token, gid) {
  const rows = await sbRows("memories", gid, "id,data");
  const existing = await fbExistingIds(token, gid, "memories");
  const missing = rows.filter((r) => r.id && !existing.has(r.id) && r.data);
  const writes = missing.map((r) => ({
    update: {
      name: `projects/${PROJECT}/databases/(default)/documents/groups/${gid}/memories/${r.id}`,
      fields: toFsFields(r.data),
    },
    currentDocument: { exists: false }, // только создание, никогда не перезапись
  }));
  if (COMMIT && writes.length) await fbCommitCreate(token, writes);
  return { sb: rows.length, fb: existing.size, add: missing.length };
}

const HANDLERS = { memories: backfillMemories };

async function main() {
  if (!SBKEY) throw new Error("SBKEY не задан. Запусти: SBKEY=<service-role> node tools/backfill_supabase_to_firebase.js ...");
  const handler = HANDLERS[TYPE];
  if (!handler) {
    console.log("Типы:", Object.keys(HANDLERS).join(", "));
    console.log("Пример: SBKEY=... node tools/backfill_supabase_to_firebase.js memories --group <GID>");
    process.exit(1);
  }
  const { token, email } = await getToken();
  console.log(`Firebase: ${email} | Supabase: ${SB_HOST}`);
  console.log(`Тип: ${TYPE} | режим: ${COMMIT ? "🔴 БОЕВОЙ (пишет)" : "🟢 DRY-RUN (только чтение)"}\n`);

  let groups;
  if (onlyGroup) {
    groups = [onlyGroup];
  } else {
    console.log("Ищу stage4-группы…");
    groups = await scanStage4Groups(token);
    console.log(`Найдено stage4-групп: ${groups.length}`);
    if (limitGroups) groups = groups.slice(0, limitGroups);
  }

  let totSb = 0, totAdd = 0, touched = 0, errs = 0;
  for (let i = 0; i < groups.length; i++) {
    const gid = groups[i];
    try {
      const res = await handler(token, gid);
      totSb += res.sb;
      totAdd += res.add;
      if (res.add > 0) {
        touched++;
        console.log(`  ${gid}: SB=${res.sb} FB=${res.fb} → ${COMMIT ? "долито" : "долить"} ${res.add}`);
      }
    } catch (e) {
      errs++;
      console.log(`  ${gid}: ОШИБКА ${e.message}`);
    }
    if ((i + 1) % 50 === 0) console.log(`  … ${i + 1}/${groups.length}`);
  }

  console.log(`\n=== ИТОГ (${TYPE}, ${COMMIT ? "БОЕВОЙ" : "DRY-RUN"}) ===`);
  console.log(`Групп обработано: ${groups.length}, с отсутствующими записями: ${touched}, ошибок: ${errs}`);
  console.log(`Записей в Supabase (сумма): ${totSb}`);
  console.log(`Записей ${COMMIT ? "долито" : "к доливке"} в Firebase: ${totAdd}`);
  if (!COMMIT && totAdd > 0) console.log(`\nЭто DRY-RUN. Для боевого прогона добавь --commit.`);
}

main().catch((e) => {
  console.error("Сбой:", e.message);
  process.exit(1);
});
