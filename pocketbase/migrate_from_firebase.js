/**
 * Перенос данных Firebase → PocketBase (§8). Запуск:
 *   PB_PW=<superuser> node pocketbase/migrate_from_firebase.js email1 email2 ...
 *   PB_PW=<superuser> node pocketbase/migrate_from_firebase.js --all   (ВСЕ юзеры)
 *
 * Идемпотентно: id сохраняются → повтор обновляет/добавляет, не дублирует.
 * Со старого Firebase НИЧЕГО не удаляет (только читает). Медиа (gs://) пока
 * оставляем как есть — перезаливка в pb:// отдельным шагом.
 *
 * Auth: создаём users-запись с email + случайным паролем (вход — через Google,
 * PB линкует OAuth по email). Пароли Firebase (scrypt) НЕ переносятся.
 */
const admin = require(__dirname + '/../functions/node_modules/firebase-admin');
const sa = require(__dirname + '/../scripts/serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(sa),
  databaseURL: 'https://togetherly-d4856-default-rtdb.europe-west1.firebasedatabase.app',
});
const db = admin.firestore();
const rtdb = admin.database();

const PB = 'https://togetherly.duckdns.org';
const PB_PW = process.env.PB_PW;
let TOKEN = null;

async function pb(method, path, body) {
  const r = await fetch(PB + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(TOKEN ? { Authorization: TOKEN } : {}) },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const t = await r.text();
  return { status: r.status, data: t ? JSON.parse(t) : null };
}
async function authPb() {
  const r = await pb('POST', '/api/collections/_superusers/auth-with-password',
    { identity: 'badzoff@gmail.com', password: PB_PW });
  if (r.status !== 200) throw new Error('PB auth failed: ' + JSON.stringify(r.data));
  TOKEN = r.data.token;
}
async function upsertById(col, id, body) {
  let r = await pb('POST', `/api/collections/${col}/records`, { id, ...body });
  if (r.status === 200) return r;
  // POST 400 = либо id уже занят (повтор → PATCH), либо РЕАЛЬНЫЙ validation-провал
  // (id-паттерн/required/тип/maxSize). Раньше любое 400 слепо считалось «уже есть»
  // → провал валидации тихо терялся (PATCH несуществующего тоже падал, запись
  // дропалась). Теперь проверяем существование: PATCH только если запись реально есть.
  if (r.status === 400) {
    const ex = await pb('GET', `/api/collections/${col}/records/${id}`);
    if (ex.status === 200) {
      r = await pb('PATCH', `/api/collections/${col}/records/${id}`, body);
      if (r.status === 200) return r;
    }
  }
  console.log(`  ! ${col}/${id}: ${r.status} ${JSON.stringify(r.data).slice(0, 200)}`);
  bump('failed');
  return r;
}
async function upsertByFilter(col, filter, body) {
  const g = await pb('GET', `/api/collections/${col}/records?perPage=1&filter=${encodeURIComponent(filter)}`);
  if (g.data && g.data.items && g.data.items.length) {
    const r = await pb('PATCH', `/api/collections/${col}/records/${g.data.items[0].id}`, body);
    if (r.status !== 200) { console.log(`  ! ${col} PATCH: ${r.status} ${JSON.stringify(r.data).slice(0, 200)}`); bump('failed'); }
    return r;
  }
  const r = await pb('POST', `/api/collections/${col}/records`, body);
  if (r.status !== 200) { console.log(`  ! ${col}: ${r.status} ${JSON.stringify(r.data).slice(0, 200)}`); bump('failed'); }
  return r;
}

// Timestamp/Date/number/string → ISO-строка или null
function iso(v) {
  if (v == null) return null;
  if (typeof v === 'object' && typeof v.toDate === 'function') return v.toDate().toISOString();
  if (typeof v === 'object' && v._seconds != null) return new Date(v._seconds * 1000).toISOString();
  if (typeof v === 'string') return v || null;
  if (typeof v === 'number') return new Date(v).toISOString();
  return null;
}
// Глубокая конверсия Timestamp→ISO внутри произвольного объекта (для json-полей).
function deepIso(o) {
  if (o == null) return o;
  if (typeof o === 'object' && typeof o.toDate === 'function') return o.toDate().toISOString();
  if (typeof o === 'object' && o._seconds != null && o._nanoseconds != null) return new Date(o._seconds * 1000).toISOString();
  if (Array.isArray(o)) return o.map(deepIso);
  if (typeof o === 'object') { const r = {}; for (const k of Object.keys(o)) r[k] = deepIso(o[k]); return r; }
  return o;
}
function randPw() { return 'Mig_' + Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2) + 'A1!'; }

// ── Перенос медиа: Firebase Storage → PB media (pb://), дедуп по src ──────────
const mediaCache = new Map(); // src → pb://-ссылка (в рамках прогона)
// Разбирает Firebase-ссылку → {bucket, path} или null (не Firebase Storage).
function parseFbStorage(url) {
  if (typeof url !== 'string' || !url) return null;
  if (url.startsWith('gs://')) {
    const m = url.match(/^gs:\/\/([^/]+)\/(.+)$/);
    return m ? { bucket: m[1], path: m[2] } : null;
  }
  let m = url.match(/firebasestorage\.googleapis\.com\/v0\/b\/([^/]+)\/o\/([^?]+)/);
  if (m) return { bucket: m[1], path: decodeURIComponent(m[2]) };
  m = url.match(/storage\.googleapis\.com\/([^/]+)\/(.+?)(\?|$)/);
  if (m) return { bucket: m[1], path: m[2] };
  return null; // внешний http (постеры/обложки из API) — не трогаем
}
// Возвращает pb://-ссылку для Firebase-медиа, либо исходную ссылку как есть.
async function migUrl(url, kind, groupId) {
  const fb = parseFbStorage(url);
  if (!fb) return url || '';
  if (mediaCache.has(url)) return mediaCache.get(url);
  // дедуп между прогонами: уже залитый блоб по src?
  const ex = await pb('GET', `/api/collections/media/records?perPage=1&filter=${encodeURIComponent(`src="${url}"`)}`);
  if (ex.data && ex.data.items && ex.data.items.length) {
    const r = ex.data.items[0];
    const ref = `pb://media/${r.id}/${r.file}`;
    mediaCache.set(url, ref);
    return ref;
  }
  try {
    const [buf] = await admin.storage().bucket(fb.bucket).file(fb.path).download();
    const filename = fb.path.split('/').pop() || 'file';
    const fd = new FormData();
    fd.append('file', new Blob([buf]), filename);
    fd.append('kind', kind || '');
    if (groupId) fd.append('group_id', groupId);
    fd.append('src', url);
    const r = await fetch(PB + '/api/collections/media/records',
      { method: 'POST', headers: { Authorization: TOKEN }, body: fd });
    if (r.status !== 200) { console.log(`  ! media upload (${fb.path}): ${r.status}`); return url; }
    const rec = await r.json();
    const ref = `pb://media/${rec.id}/${rec.file}`;
    mediaCache.set(url, ref);
    bump('media');
    return ref;
  } catch (e) {
    console.log(`  ! media download ${fb.path}: ${(e.message || e).toString().slice(0, 80)}`);
    return url; // не вышло — оставляем исходную (потом догоним)
  }
}
async function migArr(arr, kind, groupId) {
  if (!Array.isArray(arr)) return arr;
  const out = [];
  for (const u of arr) out.push(await migUrl(u, kind, groupId));
  return out;
}

const stats = {};
const bump = (k) => stats[k] = (stats[k] || 0) + 1;

async function migrateUser(uid) {
  const snap = await db.collection('users').doc(uid).get();
  const d = snap.exists ? snap.data() : {};
  let email = d.email || '';
  try { const au = await admin.auth().getUser(uid); email = au.email || email; } catch (_) {}
  const body = {
    email: email || `${uid}@migrated.local`,
    emailVisibility: false,
    verified: true,
    display_name: d.displayName || '',
    avatar_url: await migUrl(d.avatarUrl, 'avatar'),
    gender: d.gender || '',
    coins: Number(d.coins || 0),
    owned_themes: Array.isArray(d.ownedThemes) ? d.ownedThemes : [],
    owned_icons: Array.isArray(d.ownedIcons) ? d.ownedIcons : [],
    owned_features: Array.isArray(d.ownedFeatures) ? d.ownedFeatures : [],
    granted_badges: Array.isArray(d.grantedBadges) ? d.grantedBadges : [],
    badge: d.badge || '',
    pair_id: d.pairId || '',
    pair_ids: Array.isArray(d.pairIds) ? d.pairIds : [],
    invite_code: d.inviteCode || '',
    birth_date: iso(d.birthDate),
    dev_coins_granted: d.devCoinsGranted === true,
    ad_rewards_date: d.adRewardsDate || '',
    ad_rewards_today: Number(d.adRewardsToday || 0),
    solo_timers: Array.isArray(d.soloTimers) ? deepIso(d.soloTimers) : [],
    updated_at: new Date().toISOString(),
  };
  // create требует password для auth-коллекции (вход реальный — через Google/
  // Apple, PB линкует OAuth по email).
  const pw = randPw();
  let r = await pb('POST', `/api/collections/users/records`,
    { id: uid, ...body, password: pw, passwordConfirm: pw });
  if (r.status === 200) { bump('users'); return; }
  // Не создалось. Либо запись уже есть (повтор) → обновляем данные; либо email
  // занят другим uid = СТАРЫЙ/повторный аккаунт того же человека → ПРОПУСКАЕМ
  // (пустышки не плодим; его данные и так привязаны к uid в группах).
  const exists = await pb('GET', `/api/collections/users/records/${uid}`);
  if (exists.status === 200) {
    const pe = { ...body }; delete pe.email; // email существующего не трогаем
    const u = await pb('PATCH', `/api/collections/users/records/${uid}`, pe);
    if (u.status === 200) bump('users'); else console.log(`  ! user PATCH/${uid}: ${u.status}`);
  } else {
    bump('users_skipped_dup'); // дубликат-аккаунт (email занят) — не создаём
  }
}

async function migrateGroup(gid) {
  const snap = await db.collection('groups').doc(gid).get();
  if (!snap.exists) return;
  const d = snap.data();
  await upsertById('groups', gid, {
    members: Array.isArray(d.members) ? d.members : [],
    member_names: d.memberNames || {},
    member_avatars: d.memberAvatars || {},
    member_moods: d.memberMoods || {},
    member_birthdays: d.memberBirthdays || {},
    max_members: Number(d.maxMembers || 2),
    relationship_type: d.relationshipType || 'couple',
    custom_relationship_label: d.customRelationshipLabel || '',
    custom_relationship_emoji: d.customRelationshipEmoji || '',
    custom_relationship_types: d.customRelationshipTypes || [],
    current_status: d.currentStatus || null,
    custom_statuses: d.customStatuses || [],
    start_date: iso(d.startDate),
    anniversary_date: iso(d.anniversaryDate),
    first_kiss_date: iso(d.firstKissDate),
    created_at: iso(d.createdAt),
    disbanded: d.disbanded === true,
    disbanded_at: iso(d.disbandedAt),
    memories_count: Number(d.memoriesCount || 0),
    drawings_count: Number(d.drawingsCount || 0),
    timers: Array.isArray(d.timers) ? deepIso(d.timers) : [],
    xp: Number(d.xp || 0),
    active_mascot_id: d.activeMascotId || '',
    mascot_position_x: Number(d.mascotPositionX || 0),
    mascot_position_y: Number(d.mascotPositionY || 0),
    mascot_scale: Number(d.mascotScale || 0),
    streak_days: Number(d.streakDays || 0),
    streak_last_opened_date: d.streakLastOpenedDate || '',
    streak_pending_date: d.streakPendingDate || '',
    streak_pending_uid: d.streakPendingUid || '',
  });
  bump('groups');

  // memories
  const mem = await db.collection('groups').doc(gid).collection('memories').get();
  for (const m of mem.docs) {
    const x = m.data();
    const data = deepIso(x); // вся карта воспоминания (camelCase, даты→ISO)
    // Фото/видео/музыка → перезаливаем в PB (pb://). Внешние http (постеры
    // фильмов/обложки из API) migUrl оставит как есть.
    for (const k of ['imageUrl', 'videoUrl', 'musicUrl', 'musicCoverUrl', 'thumbnailUrl']) {
      if (data[k]) data[k] = await migUrl(data[k], 'memory', gid);
    }
    if (Array.isArray(data.imageUrls)) data.imageUrls = await migArr(data.imageUrls, 'memory', gid);
    await upsertById('memories', m.id, {
      group_id: gid,
      type: x.type || 'note',
      author_uid: x.authorUid || '',
      author_name: x.authorName || '',
      author_avatar: x.authorAvatar || '',
      created_at: iso(x.createdAt),
      edited_at: iso(x.editedAt),
      is_pinned: x.isPinned === true,
      deleted: x.deleted === true,
      data: data,
    });
    bump('memories');
    // комментарии воспоминания (подколлекция memories/{id}/comments)
    const cms = await db.collection('groups').doc(gid)
      .collection('memories').doc(m.id).collection('comments').get();
    for (const c of cms.docs) {
      const cx = c.data();
      await upsertById('memory_comments', c.id, {
        group_id: gid, memory_id: m.id,
        author_uid: cx.authorUid || '', author_name: cx.authorName || '',
        author_avatar: cx.authorAvatar || '', text: cx.text || '',
        created_at: iso(cx.createdAt), deleted: cx.deleted === true,
      });
      bump('memory_comments');
    }
  }
  // widget_data
  const wd = await db.collection('groups').doc(gid).collection('widgetData').get();
  for (const w of wd.docs) {
    const x = w.data();
    await upsertByFilter('widget_data', `group_id="${gid}" && user_uid="${w.id}"`, {
      group_id: gid, user_uid: w.id,
      display_name: x.displayName || '', avatar_url: await migUrl(x.avatarUrl, 'avatar'), gender: x.gender || '',
      status: x.status || '', mood_emoji: x.moodEmoji || '', mood_label: x.moodLabel || '',
      message: x.message || '', music_title: x.musicTitle || '', music_artist: x.musicArtist || '',
      music_url: await migUrl(x.musicUrl, 'widget', gid), music_cover_url: await migUrl(x.musicCoverUrl, 'widget', gid),
      photo_url: await migUrl(x.photoUrl, 'widget', gid), photo_for_partner_url: await migUrl(x.photoForPartnerUrl, 'widget', gid),
      photo_for_partner_urls: await migArr(x.photoForPartnerUrls, 'widget', gid),
      photo_grid_count: Number(x.photoGridCount || 1), photo_grid_urls: await migArr(x.photoGridUrls, 'widget', gid),
      updated_at: iso(x.updatedAt) || new Date().toISOString(),
    });
    bump('widget_data');
  }
  // mascots
  const ms = await db.collection('groups').doc(gid).collection('mascots').get();
  for (const m of ms.docs) {
    const x = m.data();
    const mid = x.id || m.id;
    await upsertByFilter('mascots', `group_id="${gid}" && mascot_id="${mid}"`, {
      group_id: gid, mascot_id: mid, name: x.name || '', image_url: await migUrl(x.imageUrl, 'mascot', gid),
      default_asset: x.defaultAsset || '', created_by: x.createdBy || '',
      created_at: iso(x.createdAt), is_default: x.isDefault === true, record_streak: Number(x.recordStreak || 0),
    });
    bump('mascots');
  }
  // canvas_catalogue
  const cc = await db.collection('groups').doc(gid).collection('canvasCatalogue').get();
  for (const c of cc.docs) {
    const x = c.data();
    const cid = x.id || c.id;
    await upsertByFilter('canvas_catalogue', `group_id="${gid}" && canvas_id="${cid}"`, {
      group_id: gid, canvas_id: cid, name: x.name || '',
      created_at: Number(x.createdAt || 0), updated_at: Number(x.updatedAt || 0), created_by: x.createdBy || '',
    });
    bump('canvas_catalogue');
  }
  // canvas: штрихи (canvas_strokes) + мета (canvas_meta) для 'main' и каталога.
  const canvasIds = new Set(['main']);
  for (const c of cc.docs) canvasIds.add(c.id);
  for (const canvasId of canvasIds) {
    const cref = db.collection('groups').doc(gid).collection('canvas').doc(canvasId);
    const strokes = await cref.collection('strokes').get();
    for (const s of strokes.docs) {
      const sd = s.data() || {};
      await upsertById('canvas_strokes', s.id, {
        group_id: gid, canvas_id: canvasId,
        order_index: Number(sd.orderIndex || 0),
        data: deepIso(sd),
        deleted: sd.deleted === true,
      });
      bump('canvas_strokes');
    }
    const metaSnap = await cref.get();
    const md = metaSnap.exists ? metaSnap.data() : null;
    if (md) {
      await upsertByFilter('canvas_meta', `group_id="${gid}" && canvas_id="${canvasId}"`, {
        group_id: gid, canvas_id: canvasId,
        bg_color: Number(md.bgColor || 0),
        clear_version: Number(md.clearVersion || 0),
        canvas_rotation: Number(md.canvasRotation || 0),
        updated_at: iso(md.updatedAt) || new Date().toISOString(),
      });
      bump('canvas_meta');
    }
  }
  // RTDB chat messages
  const ch = await rtdb.ref('chats/' + gid + '/messages').get();
  if (ch.exists()) {
    const msgs = ch.val() || {};
    for (const key of Object.keys(msgs)) {
      const x = msgs[key];
      await upsertById('chat_messages', key, {
        group_id: gid, user_uid: x.uid || '', user_name: x.name || '', text: x.text || '',
        ts: Number(x.ts || 0), edited_ts: Number(x.editedTs || 0), deleted: x.deleted === true,
        reactions: x.reactions || {}, pin_id: x.pinId || '', pin_title: x.pinTitle || '', pin_thumb: x.pinThumb || '',
        face: x.face || '', color: Number(x.color || 0),
        face_x: Number(x.faceX || 0), face_y: Number(x.faceY || 0),
        reply_to_id: x.replyToId || '', reply_to_name: x.replyToName || '', reply_to_text: x.replyToText || '',
      });
      bump('chat_messages');
    }
  }
  // RTDB chat reads
  const rd = await rtdb.ref('chats/' + gid + '/reads').get();
  if (rd.exists()) {
    const reads = rd.val() || {};
    for (const uid of Object.keys(reads)) {
      await upsertByFilter('chat_reads', `group_id="${gid}" && user_uid="${uid}"`, {
        group_id: gid, user_uid: uid, last_read_ts: Number(reads[uid] || 0), updated_at: new Date().toISOString(),
      });
      bump('chat_reads');
    }
  }

  // mood_entries (Firestore moodCalendar → плоская коллекция).
  //   v2: groups/{gid}/moodCalendar/{uid}/months/{YYYY-MM}.entries{entryId:{...}}
  //   v1 legacy: groups/{gid}/moodCalendar/{uid}/entries/{entryId} (1 док = 1 запись)
  // id записи (`<uid>_<millis>`/`YYYY-MM-…`) совместим с PB-паттерном → upsertById.
  const moodMembers = Array.isArray(d.members) ? d.members : [];
  for (const uid of moodMembers) {
    const calBase = db.collection('groups').doc(gid).collection('moodCalendar').doc(uid);
    const writeMood = async (entryId, e) => {
      if (!entryId || !e || typeof e !== 'object') return;
      await upsertById('mood_entries', entryId, {
        group_id: gid, user_uid: uid,
        mood_id: e.moodId || '', image_path: e.imagePath || '', label: e.label || '',
        timestamp: iso(e.timestamp) || new Date().toISOString(),
      });
      bump('mood_entries');
    };
    const months = await calBase.collection('months').get();
    for (const mdoc of months.docs) {
      const entries = (mdoc.data() || {}).entries || {};
      for (const eid of Object.keys(entries)) await writeMood(eid, entries[eid]);
    }
    const legacy = await calBase.collection('entries').get();
    for (const ldoc of legacy.docs) await writeMood(ldoc.id, ldoc.data());
  }

  // miss_you (RTDB missYou/{gid}/counts/{uid} + legacy d.missYouCounts на group-доке).
  // max(существующий в PB, исходный) — повторный прогон не откатывает live-счётчик.
  const missCounts = {};
  const myRt = await rtdb.ref('missYou/' + gid + '/counts').get();
  if (myRt.exists()) {
    const v = myRt.val() || {};
    for (const u of Object.keys(v)) missCounts[u] = Number(v[u] || 0);
  }
  if (d.missYouCounts && typeof d.missYouCounts === 'object') {
    for (const u of Object.keys(d.missYouCounts)) {
      missCounts[u] = Math.max(missCounts[u] || 0, Number(d.missYouCounts[u] || 0));
    }
  }
  for (const uid of Object.keys(missCounts)) {
    const c = missCounts[uid];
    if (!c || c <= 0) continue;
    const ex = await pb('GET', `/api/collections/miss_you/records?perPage=1&filter=${encodeURIComponent(`group_id="${gid}" && user_uid="${uid}"`)}`);
    const cur = (ex.data && ex.data.items && ex.data.items[0]) ? Number(ex.data.items[0].count || 0) : 0;
    await upsertByFilter('miss_you', `group_id="${gid}" && user_uid="${uid}"`, {
      group_id: gid, user_uid: uid, count: Math.max(cur, c),
      updated_at: new Date().toISOString(),
    });
    bump('miss_you');
  }
}

(async () => {
  if (!PB_PW) throw new Error('PB_PW env required');
  await authPb();
  const args = process.argv.slice(2);
  // Сид: либо ВСЕ пользователи Firebase Auth (--all, пагинация по 1000), либо
  // список uid из email-аргументов.
  const seedUids = [];
  if (args.includes('--all')) {
    let pageToken;
    do {
      const res = await admin.auth().listUsers(1000, pageToken);
      res.users.forEach((u) => seedUids.push(u.uid));
      pageToken = res.pageToken;
    } while (pageToken);
    console.log(`--all: ${seedUids.length} пользователей из Firebase Auth`);
  } else {
    for (const email of args) {
      try { const u = await admin.auth().getUserByEmail(email); seedUids.push(u.uid); }
      catch (e) { console.log('email не найден:', email); }
    }
  }
  // Все группы сидов + все их участники (чтобы пары были целыми).
  const groupIds = new Set();
  for (const uid of seedUids) {
    const gq = await db.collection('groups').where('members', 'array-contains', uid).get();
    gq.docs.forEach((g) => groupIds.add(g.id));
  }
  const allUids = new Set(seedUids);
  for (const gid of groupIds) {
    const g = (await db.collection('groups').doc(gid).get()).data() || {};
    (g.members || []).forEach((u) => allUids.add(u));
  }
  console.log(`Сидов: ${seedUids.length} | групп: ${groupIds.size} | всего юзеров (с партнёрами): ${allUids.size}`);
  console.log('Переношу пользователей...');
  for (const uid of allUids) await migrateUser(uid);
  console.log('Переношу группы и их данные...');
  for (const gid of groupIds) await migrateGroup(gid);
  console.log('\n=== ИТОГ ПЕРЕНОСА ===');
  console.log(JSON.stringify(stats, null, 2));
  if (stats.failed) console.log(`\n⚠️  ПРОВАЛОВ: ${stats.failed} — записи НЕ перенесены (см. строки "!" выше)`);
  process.exit(stats.failed ? 1 : 0);
})().catch((e) => { console.error('FATAL', e); process.exit(1); });
