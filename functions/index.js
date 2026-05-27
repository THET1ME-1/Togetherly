/**
 * Cloud Function: onMissYouEvent
 *
 * Срабатывает при добавлении документа в groups/{groupId}/missYouEvents/{eventId}.
 * Отправляет push-уведомление всем участникам группы, кроме отправителя.
 *
 * Поддерживает vibeType: miss_you | thinking_of_you | want_hug | custom
 * Поддерживает:
 *  - fcmTokens (array) — несколько устройств / переустановка приложения
 *  - fcmToken  (string) — обратная совместимость
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

/**
 * Строит тип и тело уведомления в зависимости от vibeType.
 * Тело — запасной текст на случай если клиент не поддерживает тип.
 * Клиент всегда переопределяет заголовок локализованной строкой.
 */
function buildVibePayload(vibeType, customText) {
  switch (vibeType) {
    case "thinking_of_you":
      return { type: "thinking_of_you", body: "Думает о тебе 💭" };
    case "want_hug":
      return { type: "want_hug", body: "Хочет обнять тебя 🤗" };
    case "custom":
      return { type: "custom", body: customText || "✉️" };
    default:
      return { type: "miss_you", body: "Думает о вас и вспоминает 💭" };
  }
}

exports.onMissYouEvent = onDocumentCreated(
  "groups/{groupId}/missYouEvents/{eventId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const data = snapshot.data();
    const senderUid = data.senderUid;
    const senderName = data.senderName || "Your partner";
    const vibeType = data.vibeType || "miss_you";
    const customText = (data.customText || "").trim();
    const groupId = event.params.groupId;

    const db = getFirestore();

    // Получаем участников группы
    const groupDoc = await db.collection("groups").doc(groupId).get();
    if (!groupDoc.exists) return;

    const members = groupDoc.data().members || [];
    // Отправляем всем, кроме отправителя
    const recipients = members.filter((uid) => uid !== senderUid);

    if (recipients.length === 0) return;

    // Собираем FCM-токены всех получателей (поддержка массива и одиночного поля)
    const tokenToUid = {}; // token → uid (для очистки устаревших)
    for (const uid of recipients) {
      const userDoc = await db.collection("users").doc(uid).get();
      if (!userDoc.exists) continue;

      const userData = userDoc.data();

      // Приоритет: массив fcmTokens, затем одиночный fcmToken
      const tokensList = userData.fcmTokens;

      // Проверяем настройку уведомлений.
      // Кастомные сообщения (custom) всегда доставляются — пользователь
      // специально написал текст, блокировать его настройкой "Я скучаю" неправильно.
      // Для остальных типов уважаем настройку notifMissYou.
      const notifEnabled =
        vibeType === "custom" || userData.notifMissYou !== false;
      if (!notifEnabled) {
        console.log(`VibeEvent [${groupId}] type=${type}: notifications disabled for uid=${uid}, skipping`);
        continue;
      }

      if (Array.isArray(tokensList) && tokensList.length > 0) {
        for (const t of tokensList) {
          if (t) tokenToUid[t] = uid;
        }
      } else if (userData.fcmToken) {
        tokenToUid[userData.fcmToken] = uid;
      }
    }

    const tokens = Object.keys(tokenToUid);
    if (tokens.length === 0) {
      console.log(`MissYou [${groupId}]: no FCM tokens found for recipients`);
      return;
    }

    const { type, body } = buildVibePayload(vibeType, customText);

    // Формируем data-only push-сообщение.
    // Заголовок собирается на клиенте (локализация + никнейм отправителя).
    // body — запасной текст; для custom это сам текст пользователя.
    const messageData = {
      type,
      groupId,
      senderUid,
      senderName,
      body,
    };
    if (customText) messageData.customText = customText;

    const message = {
      data: messageData,
      android: {
        priority: "high",
      },
      apns: {
        headers: {
          "apns-priority": "10",
        },
        payload: {
          aps: {
            sound: "default",
            badge: 1,
            contentAvailable: true,
          },
        },
      },
    };

    const messaging = getMessaging();
    const results = await Promise.allSettled(
      tokens.map((token) => messaging.send({ ...message, token }))
    );

    // Находим устаревшие токены
    const staleTokens = [];
    results.forEach((result, i) => {
      if (
        result.status === "rejected" &&
        (result.reason?.code ===
          "messaging/registration-token-not-registered" ||
          result.reason?.code === "messaging/invalid-registration-token")
      ) {
        staleTokens.push(tokens[i]);
      }
    });

    // Удаляем устаревшие токены из Firestore (и из массива, и из одиночного поля)
    for (const staleToken of staleTokens) {
      const uid = tokenToUid[staleToken];
      if (!uid) continue;
      try {
        const userRef = db.collection("users").doc(uid);
        const userSnap = await userRef.get();
        if (!userSnap.exists) continue;

        const updates = {
          fcmTokens: FieldValue.arrayRemove(staleToken),
        };
        // Если одиночный fcmToken совпадает — тоже очищаем
        if (userSnap.data().fcmToken === staleToken) {
          updates.fcmToken = "";
        }
        await userRef.update(updates);
      } catch (e) {
        console.warn(`Failed to remove stale token for uid=${uid}: ${e}`);
      }
    }

    const successCount = results.filter((r) => r.status === "fulfilled").length;
    console.log(
      `VibeEvent [${groupId}] type=${type}: sent=${successCount}/${tokens.length}, stale=${staleTokens.length}`
    );
  }
);

/**
 * Cloud Function: onWidgetDataEvent
 *
 * Срабатывает когда пользователь меняет статус/настроение/сообщение/музыку.
 * Отправляет FCM data-сообщение партнёру с type=widget_update, чтобы
 * виджет рабочего стола обновился мгновенно даже когда Flutter-процесс убит.
 * После отправки удаляет триггерный документ.
 */
exports.onWidgetDataEvent = onDocumentCreated(
  "groups/{groupId}/widgetDataEvents/{eventId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const data = snapshot.data();
    const senderUid = data.senderUid;
    const groupId = event.params.groupId;

    const db = getFirestore();

    // Получаем участников группы
    const groupDoc = await db.collection("groups").doc(groupId).get();
    if (!groupDoc.exists) {
      await snapshot.ref.delete();
      return;
    }

    const members = groupDoc.data().members || [];
    const recipients = members.filter((uid) => uid !== senderUid);

    if (recipients.length === 0) {
      await snapshot.ref.delete();
      return;
    }

    // Собираем FCM-токены получателей
    const tokens = [];
    for (const uid of recipients) {
      const userDoc = await db.collection("users").doc(uid).get();
      if (!userDoc.exists) continue;
      const userData = userDoc.data();
      if (Array.isArray(userData.fcmTokens)) {
        tokens.push(...userData.fcmTokens.filter(Boolean));
      } else if (userData.fcmToken) {
        tokens.push(userData.fcmToken);
      }
    }

    if (tokens.length > 0) {
      // Data-only сообщение — не показывает уведомление, только обновляет виджет
      const messageData = {
        type: "widget_update",
        status: data.status || "",
        moodLabel: data.moodLabel || "",
        message: data.message || "",
        musicTitle: data.musicTitle || "",
        musicArtist: data.musicArtist || "",
      };

      const messaging = getMessaging();
      await Promise.allSettled(
        tokens.map((token) =>
          messaging.send({
            token,
            data: messageData,
            android: { priority: "high" },
            apns: {
              headers: { "apns-priority": "5" },
              payload: { aps: { contentAvailable: true } },
            },
          })
        )
      );

      console.log(
        `WidgetDataEvent [${groupId}]: sent widget_update to ${tokens.length} token(s)`
      );
    }

    // Удаляем триггерный документ — он больше не нужен
    await snapshot.ref.delete();
  }
);

const { defineSecret } = require("firebase-functions/params");
const adminKey = defineSecret("ADMIN_LOOKUP_KEY");

exports.adminPanel = onRequest(
  { secrets: [adminKey], cors: true },
  async (req, res) => {
    const keyOk = req.query.key === adminKey.value();
    if (req.query.format === "json") {
      if (!keyOk) { res.status(403).json({ error: "Forbidden" }); return; }
      await handleJson(req, res);
    } else if (req.query.ssr === "1" || !keyOk) {
      // Server-side rendered HTML
      if (!keyOk) {
        res.set("Content-Type", "text/html; charset=utf-8");
        res.send(`<!DOCTYPE html><html lang="ru"><head><meta charset="utf-8"><title>Togetherly Admin</title></head>
<body style="background:#0f1117;color:#e1e4e8;font-family:sans-serif;padding:40px">
<h1 style="color:#58a6ff">🔧 Togetherly Admin</h1>
<p style="color:#f85149">Неверный ключ доступа.</p>
</body></html>`);
        return;
      }
      await handleSsr(req, res);
    } else {
      // HTML with inline JS (fallback)
      res.set({
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
      });
      res.send(getHtmlShell());
    }
  }
);

function getHtmlShell() {
  return `<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Togetherly Admin</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#0f1117;color:#e1e4e8;padding:20px}
.container{max-width:1400px;margin:0 auto}
h1{font-size:22px;color:#58a6ff;margin-bottom:16px;display:flex;align-items:center;gap:12px}
h1 small{font-size:13px;color:#8b949e;font-weight:400}
.toolbar{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:16px;align-items:center}
.toolbar button,.toolbar select{padding:7px 14px;border-radius:6px;border:1px solid #30363d;background:#161b22;color:#e1e4e8;font-size:13px;cursor:pointer}
.toolbar button:hover{border-color:#58a6ff;color:#58a6ff}
.toolbar .active{background:#1f6feb;border-color:#1f6feb;color:#fff}
.toolbar .info{color:#8b949e;font-size:13px;margin-left:auto}
.user-card{background:#161b22;border:1px solid #30363d;border-radius:8px;margin-bottom:10px;overflow:hidden}
.user-hdr{display:flex;align-items:center;gap:12px;padding:12px 16px;cursor:pointer}
.user-hdr:hover{background:#1c2128}
.avatar{width:40px;height:40px;border-radius:50%;object-fit:cover;background:#21262d;flex-shrink:0}
.avatar-placeholder{width:40px;height:40px;border-radius:50%;background:#21262d;display:flex;align-items:center;justify-content:center;font-size:18px;flex-shrink:0}
.usr-info{flex:1;min-width:0}
.usr-name{font-weight:600;font-size:14px}
.usr-email{font-size:12px;color:#8b949e}
.usr-meta{font-size:11px;color:#8b949e;display:flex;gap:8px;flex-wrap:wrap}
.online-dot{display:inline-block;width:7px;height:7px;border-radius:50%;margin-right:3px}
.online-dot.yes{background:#3fb950}
.online-dot.no{background:#484f58}
.arr{color:#8b949e;font-size:16px;transition:transform .2s;flex-shrink:0}
.arr.open{transform:rotate(180deg)}
.user-body{display:none;padding:0 16px 12px;border-top:1px solid #30363d}
.user-body.open{display:block}
.grp{background:#0d1117;border:1px solid #21262d;border-radius:6px;margin-top:8px;padding:10px}
.grp h4{font-size:12px;color:#8b949e;margin-bottom:4px}
.grp .member{display:inline-block;font-size:12px;background:#21262d;padding:2px 7px;border-radius:4px;margin:2px}
.badge-d{display:inline-block;font-size:10px;padding:1px 5px;border-radius:3px;background:#da3633;color:#fff;margin-left:5px}
.mem-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(140px,1fr));gap:6px;margin-top:6px}
.mem-item{position:relative;border-radius:4px;overflow:hidden;background:#161b22;aspect-ratio:1;cursor:pointer}
.mem-item img{width:100%;height:100%;object-fit:cover;display:block;transition:transform .2s}
.mem-item:hover img{transform:scale(1.05)}
.mem-item .lbl{position:absolute;bottom:0;left:0;right:0;background:rgba(0,0,0,.7);padding:3px 5px;font-size:10px;color:#8b949e;opacity:0;transition:opacity .2s}
.mem-item:hover .lbl{opacity:1}
.mem-item .typ{position:absolute;top:3px;right:3px;background:rgba(0,0,0,.7);color:#fff;font-size:10px;padding:1px 4px;border-radius:3px}
.no-mem{color:#484f58;font-size:12px;padding:6px 0}
.err{color:#f85149;padding:10px;background:rgba(248,81,73,.1);border-radius:6px;margin-bottom:10px}
</style>
</head>
<body>
<div class="container">
<h1>🔧 Togetherly Admin <small id="info"></small></h1>
<div class="toolbar" id="pg"></div>
<div id="users"><p style="color:#8b949e;padding:20px;text-align:center">Загрузка...</p></div>
<div class="toolbar" id="pg2"></div>
</div>
<script>
const K=sessionStorage.getItem('ak')||new URLSearchParams(location.search).get('key')||'';
if(K&&!sessionStorage.getItem('ak'))sessionStorage.setItem('ak',K);
if(!K){document.querySelector('#users').innerHTML='<p style="color:#f85149">Нет ключа. Добавь ?key=...</p>';}
const U=window.location.origin+location.pathname;
async function L(p){const pp=parseInt(document.getElementById('pp').value,10);document.getElementById('users').innerHTML='<p style="color:#8b949e;padding:20px;text-align:center">Загрузка...</p>';
try{const r=await fetch(U+'?key='+K+'&format=json&page='+p+'&perPage='+pp);if(!r.ok)throw Error('HTTP '+r.status);
const d=await r.json();R(d.users);P(d.page,d.totalPages,d.total,d.perPage);document.getElementById('info').textContent=d.total+' пользователей • стр '+d.page+'/'+d.totalPages}
catch(e){document.getElementById('users').innerHTML='<div class="err">Ошибка: '+e.message+'<br><br>Если не грузится — попробуй серверный режим: <a href="'+U+'?key='+K+'&ssr=1" style="color:#58a6ff">?key='+K+'&ssr=1</a></div>'}}
function R(us){let h='';for(const u of us){const on=u.user.isOnline?'<span class="online-dot yes"></span>онлайн':'<span class="online-dot no"></span>офлайн';
const av=u.user.avatarUrl||'';const uv=u.user.appVersion||'—';const ut=u.user.updatedAt?F(u.user.updatedAt):'—';
h+='<div class="user-card"><div class="user-hdr" onclick="var b=this.nextElementSibling,n=this.querySelector(\'.arr\');b.classList.toggle(\'open\');n.classList.toggle(\'open\')">';
h+=(av?'<img class="avatar" src="'+E(av)+'">':'<div class="avatar-placeholder">👤</div>');
h+='<div class="usr-info"><div class="usr-name">'+E(u.user.displayName||'—')+'</div><div class="usr-email">'+E(u.user.email||'—')+'</div>';
h+='<div class="usr-meta"><span>'+on+'</span><span>📱v'+uv+'</span><span>🆔'+E(u.uid)+'</span><span>🕐'+ut+'</span><span>👥'+u.groups.length+'гр</span></div></div><div class="arr">▼</div></div>';
h+='<div class="user-body">';
if(!u.groups.length)h+='<p class="no-mem">Нет групп</p>';
for(const g of u.groups){const mn=g.memberNames||{};const mh=(g.members||[]).map(m=>'<span class="member">'+E(mn[m]||'?')+' <span style="color:#484f58">'+E(m.substring(0,7))+'</span></span>').join('');
const db=g.disbanded?'<span class="badge-d">disbanded</span>':'';h+='<div class="grp"><h4>'+E(g.groupId)+' '+db+'</h4><div>'+mh+'</div>';
if(g.memories===0)h+='<p class="no-mem">Нет воспоминаний</p>';
else{h+='<details style="margin-top:4px"><summary style="cursor:pointer;font-size:12px;color:#58a6ff">📷 '+g.memories+' воспоминаний</summary><div class="mem-grid">';
for(const m of g.memoriesData||[]){const iu=m.imageUrl||(m.imageUrls&&m.imageUrls[0])||'';const au=m.authorName||'';const da=m.createdAt?FS(m.createdAt):'';
if(iu){h+='<div class="mem-item" onclick="window.open(\''+E(iu)+'\',\'_blank\')"><img src="'+E(iu)+'" loading="lazy"><div class="typ">📷</div><div class="lbl">'+E(au)+' • '+da+'</div></div>';}}
h+='</div></details>';}h+='</div>';}h+='</div></div>';}
document.getElementById('users').innerHTML=h;}
function P(cp,tp,t,pp){let h='<button onclick="L(1)"'+(cp<=1?' disabled':'')+'>«</button><button onclick="L('+(cp-1)+')"'+(cp<=1?' disabled':'')+'>‹</button>';
const s=Math.max(1,cp-2),e=Math.min(tp,cp+2);for(let i=s;i<=e;i++)h+='<button'+(i===cp?' class="active"':'')+' onclick="L('+i+')">'+i+'</button>';
h+='<button onclick="L('+(cp+1)+')"'+(cp>=tp?' disabled':'')+'>›</button><button onclick="L('+tp+')"'+(cp>=tp?' disabled':'')+'>»</button>';
h+='<span class="info">'+t+' всего</span>';
const ppC='<select id="pp" onchange="L(1)"><option value="10"'+(pp===10?' selected':'')+'>10</option><option value="50"'+(pp===50?' selected':'')+'>50</option><option value="100"'+(pp===100?' selected':'')+'>100</option></select>';
document.getElementById('pg').innerHTML=h+ppC;document.getElementById('pg2').innerHTML=h;}
function F(ts){if(!ts)return'—';const d=ts._seconds?new Date(ts._seconds*1000):new Date(ts);return d.toLocaleString('ru-RU')}
function FS(ts){if(!ts)return'';const d=ts._seconds?new Date(ts._seconds*1000):new Date(ts);return d.toLocaleDateString('ru-RU')}
function E(s){if(typeof s!=='string')return'';return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')}
L(1);
</script>
</body>
</html>`; }

async function handleJson(req, res) {
  const db = getFirestore();
  const page = Math.max(1, parseInt(req.query.page, 10) || 1);
  const perPage = Math.min(100, Math.max(1, parseInt(req.query.perPage, 10) || 10));

  try {
    const [countSnap, userSnap] = await Promise.all([
      db.collection("users").count().get(),
      db.collection("users").orderBy("updatedAt", "desc")
        .offset((page - 1) * perPage).limit(perPage).get(),
    ]);
    const total = countSnap.data().count || 0;
    const users = await Promise.all(userSnap.docs.map(async (doc) => {
      const uid = doc.id, userData = doc.data();
      const pairIds = userData.pairIds || (userData.pairId ? [userData.pairId] : []);
      const groups = await Promise.all(pairIds.map(async (gid) => {
        try {
          const [gs, ms] = await Promise.all([
            db.collection("groups").doc(gid).get(),
            db.collection("groups").doc(gid).collection("memories")
              .orderBy("createdAt", "desc").limit(500).get(),
          ]);
          if (!gs.exists) return null;
          const gd = gs.data();
          return { groupId: gid, members: gd.members || [], memberNames: gd.memberNames || {},
            startDate: gd.startDate, disbanded: gd.disbanded || false,
            memories: ms.size, memoriesData: ms.docs.map(d => ({ id: d.id, ...d.data() })) };
        } catch (_) { return null; }
      }));
      return { uid, user: userData, groups: groups.filter(Boolean) };
    }));
    console.log(`[adminPanel] p=${page}/${Math.ceil(total/perPage)}, ${users.length} users`);
    res.json({ users, page, perPage, total, totalPages: Math.ceil(total / perPage) });
  } catch (e) {
    console.error(`[adminPanel]`, e);
    res.status(500).json({ error: e.message });
  }
}

async function handleSsr(req, res) {
  const db = getFirestore();
  const page = Math.max(1, parseInt(req.query.page, 10) || 1);
  const perPage = Math.min(100, Math.max(1, parseInt(req.query.perPage, 10) || 10));
  const key = req.query.key;

  try {
    const [countSnap, userSnap] = await Promise.all([
      db.collection("users").count().get(),
      db.collection("users").orderBy("updatedAt", "desc")
        .offset((page - 1) * perPage).limit(perPage).get(),
    ]);
    const total = countSnap.data().count || 0;
    const totalPages = Math.ceil(total / perPage);

    const users = await Promise.all(userSnap.docs.map(async (doc) => {
      const uid = doc.id, userData = doc.data();
      const pairIds = userData.pairIds || (userData.pairId ? [userData.pairId] : []);
      const groups = await Promise.all(pairIds.map(async (gid) => {
        try {
          const [gs, ms] = await Promise.all([
            db.collection("groups").doc(gid).get(),
            db.collection("groups").doc(gid).collection("memories")
              .orderBy("createdAt", "desc").limit(500).get(),
          ]);
          if (!gs.exists) return null;
          const gd = gs.data();
          return { groupId: gid, members: gd.members || [], memberNames: gd.memberNames || {},
            startDate: gd.startDate, disbanded: gd.disbanded || false,
            memories: ms.size, memoriesData: ms.docs.map(d => ({ id: d.id, ...d.data() })) };
        } catch (_) { return null; }
      }));
      return { uid, user: userData, groups: groups.filter(Boolean) };
    }));

    let html = buildSsrPage(users, page, total, totalPages, perPage, key);
    res.set({ "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" });
    res.send(html);
  } catch (e) {
    console.error(`[adminPanel] ssr error:`, e);
    res.status(500).send(`Error: ${e.message}`);
  }
}

function esc(s) {
  if (typeof s !== "string") return "";
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function fmtDate(ts) {
  if (!ts) return "—";
  const d = ts._seconds ? new Date(ts._seconds * 1000) : new Date(ts);
  return d.toLocaleString("ru-RU");
}

function fmtDateShort(ts) {
  if (!ts) return "";
  const d = ts._seconds ? new Date(ts._seconds * 1000) : new Date(ts);
  return d.toLocaleDateString("ru-RU");
}

function buildSsrPage(users, page, total, totalPages, perPage, key) {
  let userHtml = "";
  for (const u of users) {
    const online = u.user.isOnline
      ? '<span class="online-dot yes"></span>онлайн'
      : '<span class="online-dot no"></span>офлайн';
    const avatar = u.user.avatarUrl || "";
    const appVer = esc(u.user.appVersion || "—");
    const updated = fmtDate(u.user.updatedAt);
    const uid = esc(u.uid);

    userHtml += '<div class="user-card">';
    userHtml += '<div class="user-hdr" onclick="var b=this.nextElementSibling,n=this.querySelector(\'.arr\');b.classList.toggle(\'open\');n.classList.toggle(\'open\')">';
    if (avatar) {
      userHtml += '<img class="avatar" src="' + esc(avatar) + '">';
    } else {
      userHtml += '<div class="avatar-placeholder">👤</div>';
    }
    userHtml += '<div class="usr-info"><div class="usr-name">' + esc(u.user.displayName || "—") + '</div>';
    userHtml += '<div class="usr-email">' + esc(u.user.email || "—") + '</div>';
    userHtml += '<div class="usr-meta"><span>' + online + '</span><span>📱v' + appVer + '</span><span>🆔' + uid + '</span><span>🕐' + updated + '</span><span>👥' + u.groups.length + 'гр</span></div></div>';
    userHtml += '<div class="arr">▼</div></div>';

    userHtml += '<div class="user-body">';
    if (!u.groups.length) {
      userHtml += '<p class="no-mem">Нет групп</p>';
    }
    for (const g of u.groups) {
      const mn = g.memberNames || {};
      const membersHtml = (g.members || []).map(m =>
        '<span class="member">' + esc(mn[m] || "?") + ' <span style="color:#484f58">' + esc(m.substring(0, 7)) + '</span></span>'
      ).join("");
      const disbanded = g.disbanded ? '<span class="badge-d">disbanded</span>' : "";
      userHtml += '<div class="grp"><h4>' + esc(g.groupId) + ' ' + disbanded + '</h4><div>' + membersHtml + '</div>';
      if (g.memories === 0) {
        userHtml += '<p class="no-mem">Нет воспоминаний</p>';
      } else {
        userHtml += '<details style="margin-top:4px"><summary style="cursor:pointer;font-size:12px;color:#58a6ff">📷 ' + g.memories + ' воспоминаний</summary><div class="mem-grid">';
        for (const m of g.memoriesData || []) {
          const imgUrl = m.imageUrl || (m.imageUrls && m.imageUrls[0]) || "";
          const author = esc(m.authorName || "");
          const date = fmtDateShort(m.createdAt);
          if (imgUrl) {
            userHtml += '<div class="mem-item" onclick="window.open(\'' + esc(imgUrl) + '\',\'_blank\')">';
            userHtml += '<img src="' + esc(imgUrl) + '" loading="lazy"><div class="typ">📷</div><div class="lbl">' + author + ' • ' + date + '</div></div>';
          }
        }
        userHtml += '</div></details>';
      }
      userHtml += '</div>';
    }
    userHtml += '</div></div>';
  }

  const qsKey = "key=" + esc(key);
  let pagHtml = "";
  pagHtml += '<a href="?' + qsKey + '&ssr=1&page=1&perPage=' + perPage + '"><button' + (page <= 1 ? ' disabled' : '') + '>«</button></a>';
  pagHtml += '<a href="?' + qsKey + '&ssr=1&page=' + (page - 1) + '&perPage=' + perPage + '"><button' + (page <= 1 ? ' disabled' : '') + '>‹</button></a>';
  const start = Math.max(1, page - 2);
  const end = Math.min(totalPages, page + 2);
  for (let i = start; i <= end; i++) {
    pagHtml += '<a href="?' + qsKey + '&ssr=1&page=' + i + '&perPage=' + perPage + '"><button' + (i === page ? ' class="active"' : '') + '>' + i + '</button></a>';
  }
  pagHtml += '<a href="?' + qsKey + '&ssr=1&page=' + (page + 1) + '&perPage=' + perPage + '"><button' + (page >= totalPages ? ' disabled' : '') + '>›</button></a>';
  pagHtml += '<a href="?' + qsKey + '&ssr=1&page=' + totalPages + '&perPage=' + perPage + '"><button' + (page >= totalPages ? ' disabled' : '') + '>»</button></a>';
  pagHtml += '<span class="info">' + total + ' всего • стр ' + page + '/' + totalPages + '</span>';

  const perPageOpts = [10, 50, 100];
  const perPageHtml = perPageOpts.map(v =>
    '<a href="?' + qsKey + '&ssr=1&page=1&perPage=' + v + '"><button' + (v === perPage ? ' class="active"' : '') + '>' + v + '</button></a>'
  ).join("");

  return `<!DOCTYPE html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Togetherly Admin</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#0f1117;color:#e1e4e8;padding:20px}
.container{max-width:1400px;margin:0 auto}
h1{font-size:22px;color:#58a6ff;margin-bottom:16px}
h1 small{font-size:13px;color:#8b949e;font-weight:400}
.toolbar{display:flex;gap:6px;flex-wrap:wrap;margin-bottom:16px;align-items:center}
.toolbar button{padding:7px 14px;border-radius:6px;border:1px solid #30363d;background:#161b22;color:#e1e4e8;font-size:13px;cursor:pointer}
.toolbar a{text-decoration:none}
.toolbar button:hover{border-color:#58a6ff;color:#58a6ff}
.toolbar .active{background:#1f6feb;border-color:#1f6feb;color:#fff}
.toolbar .info{color:#8b949e;font-size:13px;margin-left:auto}
.user-card{background:#161b22;border:1px solid #30363d;border-radius:8px;margin-bottom:10px;overflow:hidden}
.user-hdr{display:flex;align-items:center;gap:12px;padding:12px 16px;cursor:pointer}
.user-hdr:hover{background:#1c2128}
.avatar{width:40px;height:40px;border-radius:50%;object-fit:cover;background:#21262d;flex-shrink:0}
.avatar-placeholder{width:40px;height:40px;border-radius:50%;background:#21262d;display:flex;align-items:center;justify-content:center;font-size:18px;flex-shrink:0}
.usr-info{flex:1;min-width:0}
.usr-name{font-weight:600;font-size:14px}
.usr-email{font-size:12px;color:#8b949e}
.usr-meta{font-size:11px;color:#8b949e;display:flex;gap:8px;flex-wrap:wrap}
.online-dot{display:inline-block;width:7px;height:7px;border-radius:50%;margin-right:3px}
.online-dot.yes{background:#3fb950}
.online-dot.no{background:#484f58}
.arr{color:#8b949e;font-size:16px;transition:transform .2s;flex-shrink:0}
.arr.open{transform:rotate(180deg)}
.user-body{display:none;padding:0 16px 12px;border-top:1px solid #30363d}
.user-body.open{display:block}
.grp{background:#0d1117;border:1px solid #21262d;border-radius:6px;margin-top:8px;padding:10px}
.grp h4{font-size:12px;color:#8b949e;margin-bottom:4px}
.grp .member{display:inline-block;font-size:12px;background:#21262d;padding:2px 7px;border-radius:4px;margin:2px}
.badge-d{display:inline-block;font-size:10px;padding:1px 5px;border-radius:3px;background:#da3633;color:#fff;margin-left:5px}
.mem-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(140px,1fr));gap:6px;margin-top:6px}
.mem-item{position:relative;border-radius:4px;overflow:hidden;background:#161b22;aspect-ratio:1;cursor:pointer}
.mem-item img{width:100%;height:100%;object-fit:cover;display:block;transition:transform .2s}
.mem-item:hover img{transform:scale(1.05)}
.mem-item .lbl{position:absolute;bottom:0;left:0;right:0;background:rgba(0,0,0,.7);padding:3px 5px;font-size:10px;color:#8b949e;opacity:0;transition:opacity .2s}
.mem-item:hover .lbl{opacity:1}
.mem-item .typ{position:absolute;top:3px;right:3px;background:rgba(0,0,0,.7);color:#fff;font-size:10px;padding:1px 4px;border-radius:3px}
.no-mem{color:#484f58;font-size:12px;padding:6px 0}
</style>
</head><body>
<div class="container">
<h1>🔧 Togetherly Admin <small>` + total + ` пользователей</small></h1>
<div class="toolbar">` + pagHtml + `</div>
<div class="toolbar">Показать: ` + perPageHtml + `</div>
<div id="users">` + userHtml + `</div>
<div class="toolbar" style="margin-top:12px">` + pagHtml + `</div>
</div>
</body></html>`;
}





