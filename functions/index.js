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
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");
const { getStorage } = require("firebase-admin/storage");
const crypto = require("crypto");
const https = require("https");

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

// ═══════════════════════════════════════════════════════════════════════════
// КОИНЫ — серверно-авторитетный экономический модуль
// ═══════════════════════════════════════════════════════════════════════════
//
// Все начисления и списания коинов идут только через эти callable-функции.
// Клиент НЕ может писать поля coins/ownedThemes/devCoinsGranted/dailyBonus*/
// adRewards* напрямую — это блокируется Firestore Rules.
//
// Источник правды о ценах и премиум-темах — этот файл (зеркало lib/theme/app_theme.dart).

const PREMIUM_THEME_PRICES = {
  5: 30,  // Midnight
  6: 30,  // Lavender
  7: 30,  // Cherry
  8: 30,  // Mint
  9: 30,  // Sunset
  10: 30, // Monochrome
  11: 30, // Forest
  12: 30, // Ocean
};

const DEV_EMAIL = "badzoff@gmail.com";
const DEV_GRANT_AMOUNT = 1000;

const DAILY_BONUS_AMOUNT = 1;
const DAILY_BONUS_COOLDOWN_MS = 20 * 60 * 60 * 1000; // 20ч (защита от тонких манипуляций tz)

const AD_REWARD_AMOUNT = 3;
const AD_REWARDS_PER_DAY = 3;

const MEMORY_REWARD_AMOUNT = 1;
const MEMORY_REWARD_COOLDOWN_MS = 20 * 60 * 60 * 1000; // 20ч = 1 раз в день

const PARTNER_INVITE_REWARD = 50;

const MOOD_STREAK_REWARD = 10;
const MOOD_STREAK_COOLDOWN_MS = 7 * 24 * 60 * 60 * 1000; // 7 дней

function requireAuth(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Требуется авторизация");
  }
  return request.auth;
}

/**
 * Покупка премиум-темы за коины.
 * Транзакционно: списывает price, добавляет themeId в ownedThemes.
 * Безопасно от race conditions, двойных списаний, обхода цены клиентом.
 */
exports.purchaseTheme = onCall(async (request) => {
  const auth = requireAuth(request);
  const themeId = Number(request.data && request.data.themeId);
  if (!Number.isInteger(themeId)) {
    throw new HttpsError("invalid-argument", "themeId должен быть числом");
  }
  const price = PREMIUM_THEME_PRICES[themeId];
  if (!price) {
    throw new HttpsError("invalid-argument", "Тема не премиум или не существует");
  }

  const db = getFirestore();
  const userRef = db.collection("users").doc(auth.uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.exists ? snap.data() : {};
    const coins = Number(data.coins || 0);
    const owned = Array.isArray(data.ownedThemes) ? data.ownedThemes : [];

    if (owned.includes(themeId)) {
      return { ok: true, alreadyOwned: true, coins, ownedThemes: owned };
    }
    if (coins < price) {
      throw new HttpsError("failed-precondition", "Недостаточно монет");
    }

    const newCoins = coins - price;
    const newOwned = [...owned, themeId].sort((a, b) => a - b);
    tx.set(userRef, {
      coins: newCoins,
      ownedThemes: newOwned,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    return { ok: true, alreadyOwned: false, coins: newCoins, ownedThemes: newOwned };
  });
});

/**
 * Ежедневный бонус. 1 🪙 раз в ~24 часа (20ч с запасом).
 * Серверное время — единственный источник истины, клиент не может подделать.
 */
exports.grantDailyBonus = onCall(async (request) => {
  const auth = requireAuth(request);
  const db = getFirestore();
  const userRef = db.collection("users").doc(auth.uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.exists ? snap.data() : {};
    const lastClaim = data.lastDailyBonusAt;
    const now = Date.now();
    if (lastClaim && lastClaim.toMillis && now - lastClaim.toMillis() < DAILY_BONUS_COOLDOWN_MS) {
      const waitMs = DAILY_BONUS_COOLDOWN_MS - (now - lastClaim.toMillis());
      throw new HttpsError("failed-precondition", `Слишком рано: ${Math.ceil(waitMs / 1000 / 60)} мин`);
    }
    const coins = Number(data.coins || 0) + DAILY_BONUS_AMOUNT;
    tx.set(userRef, {
      coins,
      lastDailyBonusAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return { ok: true, coins, awarded: DAILY_BONUS_AMOUNT };
  });
});

/**
 * Server-Side Verification callback от AdMob.
 *
 * Google присылает GET-запрос на этот URL после показа rewarded-рекламы
 * с подписанными ECDSA параметрами. Мы проверяем подпись против публичных
 * ключей Google — если подпись валидна, начисляем коины пользователю.
 *
 * Защита от:
 *   • поддельных вызовов (без подписи Google — не пройдёт верификацию)
 *   • повторов (transaction_id хранится в Firestore — second insert упадёт)
 *   • read-replay (защищено суточным лимитом 3 раза)
 *
 * URL для AdMob SSV setting:
 *   https://us-central1-togetherly-d4856.cloudfunctions.net/adSsvCallback
 *
 * Документация: https://developers.google.com/admob/android/ssv
 */

// Кэш публичных ключей Google (5 мин).
let _keysCache = { keys: null, fetchedAt: 0 };
const KEYS_URL = "https://www.gstatic.com/admob/reward/verifier-keys.json";
const KEYS_TTL_MS = 5 * 60 * 1000;

function fetchAdMobKeys() {
  return new Promise((resolve, reject) => {
    https.get(KEYS_URL, (res) => {
      let body = "";
      res.on("data", (chunk) => { body += chunk; });
      res.on("end", () => {
        try {
          const parsed = JSON.parse(body);
          resolve(parsed.keys || []);
        } catch (e) {
          reject(e);
        }
      });
    }).on("error", reject);
  });
}

async function getKey(keyId) {
  const now = Date.now();
  if (!_keysCache.keys || (now - _keysCache.fetchedAt) > KEYS_TTL_MS) {
    _keysCache.keys = await fetchAdMobKeys();
    _keysCache.fetchedAt = now;
  }
  return _keysCache.keys.find((k) => String(k.keyId) === String(keyId));
}

/**
 * AdMob SSV использует ECDSA с SHA-256 над «query string без signature и key_id».
 * Подпись и key_id — последние два параметра в URL, остальное — body для верификации.
 */
function buildVerificationBody(rawQuery) {
  const sigIdx = rawQuery.indexOf("&signature=");
  if (sigIdx === -1) return null;
  return rawQuery.substring(0, sigIdx);
}

function base64UrlToBuffer(s) {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "=";
  return Buffer.from(s, "base64");
}

exports.adSsvCallback = onRequest({ cors: false }, async (req, res) => {
  try {
    const params = req.query;
    const rawQuery = req.url.includes("?") ? req.url.split("?")[1] : "";

    const signature = params.signature;
    const keyId = params.key_id;
    const customData = params.custom_data; // uid пользователя
    const transactionId = params.transaction_id;
    const rewardAmount = Number(params.reward_amount || 0);

    if (!signature || !keyId) {
      console.warn("SSV: missing signature/keyId", Object.keys(params));
      res.status(400).send("bad request");
      return;
    }

    // 1. Проверка подписи
    const key = await getKey(keyId);
    if (!key) {
      console.warn(`SSV: unknown keyId=${keyId}`);
      res.status(400).send("unknown key");
      return;
    }
    const body = buildVerificationBody(rawQuery);
    if (body == null) {
      res.status(400).send("malformed");
      return;
    }
    const verifier = crypto.createVerify("SHA256");
    verifier.update(body);
    const sigBuf = base64UrlToBuffer(signature);
    const ok = verifier.verify(
      { key: key.pem, format: "pem" },
      sigBuf,
    );
    if (!ok) {
      console.warn(`SSV: signature verification FAILED uid=${customData} tx=${transactionId}`);
      res.status(403).send("bad signature");
      return;
    }

    // Тестовый callback из AdMob-консоли — подпись валидна, но user/tx пустые.
    // Не пытаемся ничего начислять, просто отвечаем 200, чтобы валидация прошла.
    if (!customData || !transactionId) {
      console.log("SSV: test callback verified OK (no customData/transactionId)");
      res.status(200).send("ok (test)");
      return;
    }

    // 2. Idempotency + дневной лимит — в одной транзакции
    const db = getFirestore();
    const today = new Date().toISOString().slice(0, 10);
    const userRef = db.collection("users").doc(customData);
    const txRef = userRef.collection("adRewards").doc(transactionId);

    const award = rewardAmount > 0 ? rewardAmount : AD_REWARD_AMOUNT;

    const result = await db.runTransaction(async (t) => {
      const txSnap = await t.get(txRef);
      if (txSnap.exists) {
        return { duplicate: true };
      }
      const userSnap = await t.get(userRef);
      const data = userSnap.exists ? userSnap.data() : {};
      const lastDate = data.adRewardsDate;
      const countToday = (lastDate === today) ? Number(data.adRewardsToday || 0) : 0;
      if (countToday >= AD_REWARDS_PER_DAY) {
        return { rateLimited: true };
      }
      const coins = Number(data.coins || 0) + award;
      t.set(userRef, {
        coins,
        adRewardsDate: today,
        adRewardsToday: countToday + 1,
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
      t.set(txRef, {
        amount: award,
        at: FieldValue.serverTimestamp(),
      });
      return { coins, awarded: award };
    });

    if (result.duplicate) {
      console.log(`SSV: duplicate tx=${transactionId} uid=${customData} — ignored`);
    } else if (result.rateLimited) {
      console.warn(`SSV: rate-limited uid=${customData} tx=${transactionId}`);
    } else {
      console.log(`SSV: awarded ${result.awarded} 🪙 to uid=${customData} (balance=${result.coins})`);
    }

    // AdMob ожидает 200 OK всегда (иначе будет ретраить часами).
    res.status(200).send("ok");
  } catch (e) {
    console.error("SSV handler error:", e);
    // Намеренно 200, чтобы AdMob не спамил ретраями — ошибку увидим в логах.
    res.status(200).send("error logged");
  }
});

// ── IAP — пополнение монет через In-App Purchase ────────────────────────────

/// Соответствие productId → количество коинов.
/// Зеркало kCoinPacks в lib/services/iap_service.dart.
const COIN_PACKS = {
  "coins_10":  10,
  "coins_50":  50,
  "coins_120": 120,
  "coins_300": 300,
};

/**
 * Начисляет монеты после подтверждённой IAP-покупки.
 *
 * Клиент передаёт:
 *   - productId      — ID продукта ("coins_10" / "coins_50" / "coins_120" / "coins_300")
 *   - purchaseToken  — токен от Google Play или App Store (для идемпотентности)
 *
 * Защита:
 *   - requireAuth: только авторизованный пользователь
 *   - productId валидируется по COIN_PACKS — нельзя передать произвольное количество
 *   - purchaseToken хранится в Firestore: повторный вызов с тем же токеном
 *     вернёт ok=true без повторного начисления (idempotency)
 *
 * ВАЖНО: полная верификация receipt/token от магазина здесь не реализована,
 * так как для неё нужны учётные данные Google Play Developer API / App Store
 * Server API. Рекомендуется добавить верификацию через RevenueCat или
 * Google Play Developer API перед продакшн-релизом.
 */
exports.grantCoinsPurchase = onCall(async (request) => {
  const auth = requireAuth(request);
  const { productId, purchaseToken } = request.data || {};

  if (!productId || typeof productId !== "string") {
    throw new HttpsError("invalid-argument", "productId обязателен");
  }
  if (!purchaseToken || typeof purchaseToken !== "string") {
    throw new HttpsError("invalid-argument", "purchaseToken обязателен");
  }

  const coinsToGrant = COIN_PACKS[productId];
  if (!coinsToGrant) {
    throw new HttpsError("invalid-argument", `Неизвестный productId: ${productId}`);
  }

  const db = getFirestore();
  const userRef = db.collection("users").doc(auth.uid);
  // Каждый purchaseToken хранится как отдельный документ — idempotency key.
  const tokenRef = userRef.collection("iapPurchases").doc(purchaseToken);

  return db.runTransaction(async (tx) => {
    const tokenSnap = await tx.get(tokenRef);
    if (tokenSnap.exists) {
      // Повторный вызов с тем же токеном — уже начислено, возвращаем текущий баланс.
      const userSnap = await tx.get(userRef);
      const coins = Number((userSnap.exists ? userSnap.data() : {}).coins || 0);
      return { ok: true, alreadyGranted: true, coins };
    }

    const userSnap = await tx.get(userRef);
    const data = userSnap.exists ? userSnap.data() : {};
    const newCoins = Number(data.coins || 0) + coinsToGrant;

    tx.set(userRef, {
      coins: newCoins,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    tx.set(tokenRef, {
      productId,
      amount: coinsToGrant,
      at: FieldValue.serverTimestamp(),
    });

    console.log(`IAP: granted ${coinsToGrant} 🪙 to uid=${auth.uid} (product=${productId}, balance=${newCoins})`);
    return { ok: true, alreadyGranted: false, coins: newCoins, awarded: coinsToGrant };
  });
});

/**
 * Единоразовая выдача 1000 🪙 разработчику.
 * Проверка email — на сервере по токену авторизации, подделать невозможно.
 */
exports.grantDevCoins = onCall(async (request) => {
  const auth = requireAuth(request);
  const email = (auth.token && auth.token.email) || "";
  if (email.toLowerCase() !== DEV_EMAIL.toLowerCase()) {
    throw new HttpsError("permission-denied", "Только для разработчика");
  }
  const db = getFirestore();
  const userRef = db.collection("users").doc(auth.uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.exists ? snap.data() : {};
    if (data.devCoinsGranted === true) {
      return { ok: true, alreadyGranted: true, coins: Number(data.coins || 0) };
    }
    const coins = Number(data.coins || 0) + DEV_GRANT_AMOUNT;
    tx.set(userRef, {
      coins,
      devCoinsGranted: true,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return { ok: true, alreadyGranted: false, coins, awarded: DEV_GRANT_AMOUNT };
  });
});

/**
 * Награда за добавление воспоминания. 1 🪙 раз в ~24 часа.
 * Клиент вызывает после успешного сохранения memory; сервер проверяет cooldown.
 */
exports.grantMemoryReward = onCall(async (request) => {
  const auth = requireAuth(request);
  const db = getFirestore();
  const userRef = db.collection("users").doc(auth.uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.exists ? snap.data() : {};
    const lastClaim = data.lastMemoryRewardAt;
    const now = Date.now();
    if (lastClaim && lastClaim.toMillis && now - lastClaim.toMillis() < MEMORY_REWARD_COOLDOWN_MS) {
      return { ok: false, cooldown: true, coins: Number(data.coins || 0) };
    }
    const coins = Number(data.coins || 0) + MEMORY_REWARD_AMOUNT;
    tx.set(userRef, {
      coins,
      lastMemoryRewardAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return { ok: true, coins, awarded: MEMORY_REWARD_AMOUNT };
  });
});

/**
 * Единоразовая награда за приглашение партнёра. 50 🪙.
 * Флаг partnerInviteRewardGranted гарантирует идемпотентность.
 */
exports.grantPartnerInviteReward = onCall(async (request) => {
  const auth = requireAuth(request);
  const db = getFirestore();
  const userRef = db.collection("users").doc(auth.uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.exists ? snap.data() : {};
    if (data.partnerInviteRewardGranted === true) {
      return { ok: false, alreadyGranted: true, coins: Number(data.coins || 0) };
    }
    const coins = Number(data.coins || 0) + PARTNER_INVITE_REWARD;
    tx.set(userRef, {
      coins,
      partnerInviteRewardGranted: true,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return { ok: true, coins, awarded: PARTNER_INVITE_REWARD };
  });
});

/**
 * Награда за 7-дневный стрик настроения обоих партнёров. 10 монет раз в 7 дней.
 * Каждый пользователь получает монеты независимо — cooldown хранится на уровне
 * пользователя (lastMoodStreakRewardAt_<groupId>), а не группы.
 * Это гарантирует что ОБА партнёра получают награду, каждый из своего клиента.
 */
// ─── Signed URL ───────────────────────────────────────────────────────────────

// Пути, доступ к которым определяется groupId (second path segment).
const GROUP_PREFIXES = ["memories", "groups", "music", "timer_backgrounds", "widget"];

function extractGroupId(gsPath) {
  const parts = gsPath.split("/");
  if (GROUP_PREFIXES.includes(parts[0]) && parts.length >= 2) return parts[1];
  return null;
}

/**
 * Выдаёт download URL после проверки членства в группе.
 * Использует Firebase Storage download token (метаданные файла) вместо
 * Signed URL, что не требует iam.serviceAccounts.signBlob.
 * Token создаётся лениво при первом обращении через эту функцию —
 * клиент без членства в группе никогда его не получит.
 *
 * Вызывать: FirebaseFunctions.instance.httpsCallable('getSignedUrl').call({'gsPath': path})
 */
exports.getSignedUrl = onCall(async (request) => {
  const auth = requireAuth(request);
  const gsPath = (request.data && request.data.gsPath) || "";
  if (!gsPath) throw new HttpsError("invalid-argument", "gsPath required");

  // Запрещаем обходные пути
  if (gsPath.includes("..") || gsPath.startsWith("/")) {
    throw new HttpsError("invalid-argument", "Invalid path");
  }

  const parts = gsPath.split("/");
  const prefix = parts[0];

  if (GROUP_PREFIXES.includes(prefix)) {
    const groupId = extractGroupId(gsPath);
    if (!groupId) throw new HttpsError("invalid-argument", "Cannot determine groupId");

    const db = getFirestore();
    const groupDoc = await db.collection("groups").doc(groupId).get();
    if (!groupDoc.exists) throw new HttpsError("not-found", "Group not found");

    const members = groupDoc.data().members || [];
    if (!members.includes(auth.uid)) {
      throw new HttpsError("permission-denied", "Not a group member");
    }
  } else if (prefix === "avatars") {
    // Аватарки доступны любому аутентифицированному пользователю
  } else if (prefix === "wallpapers") {
    // Публичные
  } else {
    throw new HttpsError("permission-denied", "Unknown path prefix");
  }

  const expiresAt = Date.now() + 60 * 60 * 1000; // 1 час
  const bucket = getStorage().bucket();
  const file = bucket.file(gsPath);

  const [url] = await file.getSignedUrl({
    action: "read",
    expires: expiresAt,
    version: "v4",
  });

  return { url, expiresAt };
});

// ──────────────────────────────────────────────────────────────────────────────

exports.grantMoodStreakReward = onCall(async (request) => {
  const auth = requireAuth(request);
  const groupId = (request.data && request.data.groupId) || "";
  if (!groupId) throw new HttpsError("invalid-argument", "groupId required");

  const db = getFirestore();
  const userRef = db.collection("users").doc(auth.uid);
  // Ключ cooldown уникален для каждого пользователя + группы
  const cooldownKey = `lastMoodStreakRewardAt_${groupId}`;

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.exists ? snap.data() : {};

    const lastReward = data[cooldownKey];
    const now = Date.now();
    if (lastReward && lastReward.toMillis && now - lastReward.toMillis() < MOOD_STREAK_COOLDOWN_MS) {
      return { ok: false, cooldown: true, coins: Number(data.coins || 0) };
    }

    const coins = Number(data.coins || 0) + MOOD_STREAK_REWARD;
    tx.set(userRef, {
      coins,
      [cooldownKey]: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return { ok: true, coins, awarded: MOOD_STREAK_REWARD };
  });
});

