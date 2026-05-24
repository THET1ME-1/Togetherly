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
