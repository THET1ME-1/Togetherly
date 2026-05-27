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

/**
 * Admin Panel: полноценная админ-панель со списком пользователей,
 * группами и воспоминаниями.
 *
 * Использование (браузер):
 *   https://REGION-PROJECT.cloudfunctions.net/adminPanel?key=СЕКРЕТ
 *
 * JSON (для постраничной загрузки):
 *   https://REGION-PROJECT.cloudfunctions.net/adminPanel?key=СЕКРЕТ&format=json&page=1&perPage=50
 */
const { defineSecret } = require("firebase-functions/params");
const adminKey = defineSecret("ADMIN_LOOKUP_KEY");

const ADMIN_HTML = `<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Togetherly Admin</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#0f1117;color:#e1e4e8;padding:20px}
.container{max-width:1400px;margin:0 auto}
h1{font-size:22px;color:#58a6ff;margin-bottom:16px;display:flex;align-items:center;gap:12px}
h1 small{font-size:13px;color:#8b949e;font-weight:400}
.toolbar{display:flex;gap:10px;flex-wrap:wrap;margin-bottom:20px;align-items:center}
.toolbar input,.toolbar select,.toolbar button{padding:8px 12px;border-radius:6px;border:1px solid #30363d;background:#161b22;color:#e1e4e8;font-size:14px}
.toolbar input{flex:1;min-width:200px}
.toolbar input:focus,.toolbar select:focus{border-color:#58a6ff;outline:none}
.toolbar button{background:#238636;border-color:#2ea043;cursor:pointer;font-weight:600}
.toolbar button:hover{background:#2ea043}
.per-page{display:flex;align-items:center;gap:6px;color:#8b949e;font-size:13px}
.pagination{display:flex;gap:6px;align-items:center;margin-bottom:20px;flex-wrap:wrap}
.pagination button{padding:6px 14px;border-radius:6px;border:1px solid #30363d;background:#161b22;color:#e1e4e8;cursor:pointer;font-size:13px}
.pagination button:hover{border-color:#58a6ff;color:#58a6ff}
.pagination button.active{background:#1f6feb;border-color:#1f6feb;color:#fff}
.pagination button:disabled{opacity:0.4;cursor:default}
.pagination .info{color:#8b949e;font-size:13px;margin-left:auto}
.user-card{background:#161b22;border:1px solid #30363d;border-radius:8px;margin-bottom:12px;overflow:hidden}
.user-header{display:flex;align-items:center;gap:14px;padding:14px 18px;cursor:pointer;transition:background .15s}
.user-header:hover{background:#1c2128}
.user-header .avatar{width:44px;height:44px;border-radius:50%;object-fit:cover;background:#21262d}
.user-header .info{flex:1;min-width:0}
.user-header .name{font-size:15px;font-weight:600}
.user-header .email{font-size:13px;color:#8b949e}
.user-header .meta{font-size:12px;color:#8b949e;display:flex;gap:10px;flex-wrap:wrap;margin-top:2px}
.user-header .online{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:4px}
.user-header .online.yes{background:#3fb950}
.user-header .online.no{background:#484f58}
.user-header .expand-arrow{color:#8b949e;font-size:18px;transition:transform .2s}
.user-header.expanded .expand-arrow{transform:rotate(180deg)}
.user-body{padding:0 18px 14px;display:none;border-top:1px solid #30363d}
.user-body.open{display:block}
.group-card{background:#0d1117;border:1px solid #21262d;border-radius:6px;margin-top:10px;padding:12px}
.group-card h4{font-size:13px;color:#8b949e;margin-bottom:6px}
.group-card .member{display:inline-block;font-size:13px;background:#21262d;padding:2px 8px;border-radius:4px;margin:2px}
.group-card .badge{display:inline-block;font-size:10px;padding:1px 6px;border-radius:3px;margin-left:6px}
.group-card .badge.disbanded{background:#da3633;color:#fff}
.memories-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:8px;margin-top:8px}
.memory-item{position:relative;border-radius:4px;overflow:hidden;background:#161b22;aspect-ratio:1;cursor:pointer}
.memory-item img{width:100%;height:100%;object-fit:cover;display:block;transition:transform .2s}
.memory-item:hover img{transform:scale(1.05)}
.memory-item .overlay{position:absolute;bottom:0;left:0;right:0;background:rgba(0,0,0,.7);padding:4px 6px;font-size:10px;color:#8b949e;opacity:0;transition:opacity .2s}
.memory-item:hover .overlay{opacity:1}
.memory-item .type-badge{position:absolute;top:4px;right:4px;background:rgba(0,0,0,.7);color:#fff;font-size:10px;padding:1px 5px;border-radius:3px}
.no-memories{color:#484f58;font-size:13px;padding:8px 0}
.loading{text-align:center;padding:40px;color:#8b949e;font-size:16px}
.error{color:#f85149;padding:12px;background:rgba(248,81,73,.1);border-radius:6px;margin-bottom:12px}
summary{cursor:pointer;font-size:13px;color:#58a6ff;margin-top:6px}
</style>
</head>
<body>
<div class="container">
<h1>🔧 Togetherly Admin <small id="status"></small></h1>
<div class="toolbar">
  <input id="search" type="text" placeholder="Фильтр по имени или email..." oninput="filterUsers()">
  <div class="per-page">
    Показывать:
    <select id="perPage" onchange="loadPage(1)">
      <option value="10">10</option>
      <option value="50" selected>50</option>
      <option value="100">100</option>
    </select>
  </div>
</div>
<div class="pagination" id="pagination"></div>
<div id="loading" class="loading">Загрузка...</div>
<div id="users"></div>
<div class="pagination" id="pagination2"></div>
<div id="error" class="error" style="display:none"></div>
</div>
<script>
const KEY = sessionStorage.getItem('admin_key') || new URLSearchParams(location.search).get('key') || '';
if (!sessionStorage.getItem('admin_key') && KEY) sessionStorage.setItem('admin_key', KEY);
if (!KEY) { document.body.innerHTML='<div class="container"><h1>🔧 Togetherly Admin</h1><p style="color:#f85149">Нет ключа доступа. Добавь ?key=ВАШ_СЕКРЕТ в URL.</p></div>'; }
const BASE = location.pathname;
let allUsers = [];
let currentPage = 1;
let currentPerPage = 50;
let totalCount = 0;

async function loadPage(page) {
  currentPage = page;
  currentPerPage = parseInt(document.getElementById('perPage').value, 10);
  document.getElementById('loading').style.display = 'block';
  document.getElementById('loading').textContent = 'Загрузка пользователей... (страница ' + page + ')';
  document.getElementById('error').style.display = 'none';
  document.getElementById('users').innerHTML = '';
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 30000);
    const res = await fetch(BASE + '?key=' + KEY + '&format=json&page=' + page + '&perPage=' + currentPerPage, { signal: controller.signal });
    clearTimeout(timeout);
    if (!res.ok) {
      if (res.status === 403) { document.getElementById('error').style.display='block'; document.getElementById('error').textContent='Ошибка: неверный ключ доступа. sessionStorage очищен.'; sessionStorage.removeItem('admin_key'); return; }
      throw new Error('HTTP ' + res.status);
    }
    const data = await res.json();
    allUsers = data.users;
    totalCount = data.total;
    renderUsers(allUsers);
    renderPagination();
    document.getElementById('status').textContent = data.total + ' пользователей • стр. ' + data.page + ' из ' + data.totalPages;
  } catch(e) {
    document.getElementById('error').style.display='block';
    document.getElementById('error').textContent = 'Ошибка загрузки: ' + e.message;
  }
  document.getElementById('loading').style.display = 'none';
}

function renderUsers(users) {
  const container = document.getElementById('users');
  if (!users.length) { container.innerHTML = '<p style="color:#8b949e;padding:20px;text-align:center">Нет пользователей</p>'; return; }
  let html = '';
  for (const u of users) {
    const online = u.user.isOnline ? '<span class="online yes"></span>онлайн' : '<span class="online no"></span>офлайн';
    const avatar = u.user.avatarUrl || '';
    const appVer = u.user.appVersion || '—';
    const updated = fmtDate(u.user.updatedAt);
    html += '<div class="user-card">';
    html += '<div class="user-header" onclick="this.classList.toggle(\'expanded\');var b=this.nextElementSibling;b.classList.toggle(\'open\')">';
    html += (avatar ? '<img class="avatar" src="' + htmlEscape(avatar) + '" alt="">' : '<div class="avatar" style="display:flex;align-items:center;justify-content:center;font-size:18px;background:#21262d">👤</div>');
    html += '<div class="info"><div class="name">' + htmlEscape(u.user.displayName || '—') + '</div>';
    html += '<div class="email">' + htmlEscape(u.user.email || '—') + '</div>';
    html += '<div class="meta"><span>' + online + '</span><span>📱 v' + appVer + '</span><span>🆔 ' + htmlEscape(u.uid) + '</span><span>🕐 ' + updated + '</span><span>👥 ' + u.groups.length + ' групп(а)</span></div></div>';
    html += '<div class="expand-arrow">▼</div></div>';
    html += '<div class="user-body">';
    if (!u.groups.length) {
      html += '<p style="color:#484f58;font-size:13px;padding:8px 0">Нет групп</p>';
    }
    for (const g of u.groups) {
      const memberNames = g.memberNames || {};
      const membersHtml = (g.members || []).map(m => {
        const name = memberNames[m] || '?';
        return '<span class="member">' + htmlEscape(name) + ' <span style="color:#484f58;font-size:10px">' + htmlEscape(m.substring(0,8)) + '</span></span>';
      }).join('');
      const disbanded = g.disbanded ? '<span class="badge disbanded">disbanded</span>' : '';
      html += '<div class="group-card">';
      html += '<h4>Группа: ' + htmlEscape(g.groupId) + ' ' + disbanded + ' <span style="color:#484f58;font-size:11px">с ' + fmtDateShort(g.startDate) + '</span></h4>';
      html += '<div>' + membersHtml + '</div>';
      if (g.memories === 0) {
        html += '<p class="no-memories">Нет воспоминаний</p>';
      } else {
        html += '<details><summary>📷 ' + g.memories + ' воспоминаний</summary><div class="memories-grid">';
        for (const m of g.memoriesData || []) {
          const imgUrl = m.imageUrl || (m.imageUrls && m.imageUrls[0]) || '';
          const isPhoto = m.type === 'photo' || m.type === 'image';
          const author = m.authorName || htmlEscape(m.authorUid || '').substring(0,8);
          const date = fmtDateShort(m.createdAt);
          if (imgUrl) {
            html += '<div class="memory-item" onclick="window.open(\'' + htmlEscape(imgUrl) + '\',\'_blank\')">';
            if (isPhoto) {
              html += '<img src="' + htmlEscape(imgUrl) + '" loading="lazy" alt="">';
              html += '<div class="type-badge">📷</div>';
            } else {
              html += '<div style="width:100%;height:100%;display:flex;align-items:center;justify-content:center;background:#21262d;color:#8b949e;font-size:32px">🎵</div>';
              html += '<div class="type-badge">🎵</div>';
            }
            html += '<div class="overlay">' + htmlEscape(author) + ' • ' + date + '</div>';
            html += '</div>';
          }
        }
        html += '</div></details>';
      }
      html += '</div>';
    }
    html += '</div></div>';
  }
  container.innerHTML = html;
}

function renderPagination() {
  const totalPages = Math.ceil(totalCount / currentPerPage);
  const pag1 = document.getElementById('pagination');
  const pag2 = document.getElementById('pagination2');
  let html = '<button onclick="loadPage(1)" ' + (currentPage<=1?'disabled':'') + '>«</button>';
  html += '<button onclick="loadPage(' + (currentPage-1) + ')" ' + (currentPage<=1?'disabled':'') + '>‹</button>';
  const start = Math.max(1, currentPage - 2);
  const end = Math.min(totalPages, currentPage + 2);
  for (let i = start; i <= end; i++) {
    html += '<button class="' + (i===currentPage?'active':'') + '" onclick="loadPage(' + i + ')">' + i + '</button>';
  }
  html += '<button onclick="loadPage(' + (currentPage+1) + ')" ' + (currentPage>=totalPages?'disabled':'') + '>›</button>';
  html += '<button onclick="loadPage(' + totalPages + ')" ' + (currentPage>=totalPages?'disabled':'') + '>»</button>';
  html += '<span class="info">' + totalCount + ' всего • стр. ' + currentPage + '/' + totalPages + '</span>';
  pag1.innerHTML = html;
  pag2.innerHTML = html;
}

function filterUsers() {
  const q = document.getElementById('search').value.toLowerCase().trim();
  if (!q) { renderUsers(allUsers); return; }
  const filtered = allUsers.filter(u => {
    const name = (u.user.displayName || '').toLowerCase();
    const email = (u.user.email || '').toLowerCase();
    return name.includes(q) || email.includes(q);
  });
  const container = document.getElementById('users');
  if (!filtered.length) { container.innerHTML = '<p style="color:#8b949e;padding:20px;text-align:center">Ничего не найдено</p>'; return; }
  renderUsers(filtered);
}

loadPage(1);
</script>
</body>
</html>`;

exports.adminPanel = onRequest(
  { secrets: [adminKey], cors: true },
  async (req, res) => {
    if (req.query.key !== adminKey.value()) {
      res.status(403).send("Forbidden");
      return;
    }

    const format = req.query.format;
    if (format === "json") {
      await handleJsonRequest(req, res);
    } else {
      res.set("Content-Type", "text/html; charset=utf-8");
      res.send(ADMIN_HTML);
    }
  }
);

async function handleJsonRequest(req, res) {
  const db = getFirestore();
  const page = Math.max(1, parseInt(req.query.page, 10) || 1);
  const perPage = Math.min(100, Math.max(1, parseInt(req.query.perPage, 10) || 50));

  try {
    // Total count
    const [countSnap, userSnap] = await Promise.all([
      db.collection("users").count().get(),
      db.collection("users")
        .orderBy("updatedAt", "desc")
        .offset((page - 1) * perPage)
        .limit(perPage)
        .get(),
    ]);

    const total = countSnap.data().count || 0;
    const totalPages = Math.ceil(total / perPage);

    // Fetch groups + memories for all users in parallel
    const users = await Promise.all(
      userSnap.docs.map(async (doc) => {
        const uid = doc.id;
        const userData = doc.data();
        const pairIds = userData.pairIds || (userData.pairId ? [userData.pairId] : []);

        const groups = await Promise.all(
          pairIds.map(async (groupId) => {
            try {
              const [groupSnap, memSnap] = await Promise.all([
                db.collection("groups").doc(groupId).get(),
                db.collection("groups").doc(groupId)
                  .collection("memories").orderBy("createdAt", "desc").limit(50).get(),
              ]);
              if (!groupSnap.exists) return null;
              const groupData = groupSnap.data();
              return {
                groupId,
                members: groupData.members || [],
                memberNames: groupData.memberNames || {},
                startDate: groupData.startDate,
                disbanded: groupData.disbanded || false,
                memories: memSnap.size,
                memoriesData: memSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
              };
            } catch (_) { return null; }
          })
        );

        return { uid, user: userData, groups: groups.filter(Boolean) };
      })
    );

    console.log(`[adminPanel] page=${page}/${totalPages}, perPage=${perPage}, returned=${users.length}, total=${total}`);
    res.json({ users, page, perPage, total, totalPages });
  } catch (e) {
    console.error(`[adminPanel] error: ${e}`);
    res.status(500).json({ error: e.message });
  }
}


