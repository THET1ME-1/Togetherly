/**
 * Cloud Function: onMissYouEvent
 *
 * Срабатывает при добавлении документа в groups/{groupId}/missYouEvents/{eventId}.
 * Отправляет push-уведомление всем участникам группы, кроме отправителя.
 *
 * Для работы нужно:
 * 1. `firebase deploy --only functions`
 * 2. У каждого пользователя в Firestore (users/{uid}) должно быть поле `fcmToken`
 * 3. В приложении при старте нужно сохранять FCM-токен в Firestore
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

exports.onMissYouEvent = onDocumentCreated(
  "groups/{groupId}/missYouEvents/{eventId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const data = snapshot.data();
    const senderUid = data.senderUid;
    const senderName = data.senderName || "Your partner";
    const groupId = event.params.groupId;

    const db = getFirestore();

    // Get group members
    const groupDoc = await db.collection("groups").doc(groupId).get();
    if (!groupDoc.exists) return;

    const members = groupDoc.data().members || [];
    // Send to everyone except the sender
    const recipients = members.filter((uid) => uid !== senderUid);

    if (recipients.length === 0) return;

    // Get FCM tokens for all recipients
    const tokens = [];
    for (const uid of recipients) {
      const userDoc = await db.collection("users").doc(uid).get();
      if (userDoc.exists) {
        const token = userDoc.data().fcmToken;
        if (token) tokens.push(token);
      }
    }

    if (tokens.length === 0) return;

    // Send push notification
    const message = {
      notification: {
        title: `${senderName} скучает по вам 💕`,
        body: "Думает о вас и вспоминает 💭",
      },
      data: {
        type: "miss_you",
        groupId: groupId,
        senderUid: senderUid,
        senderName: senderName,
      },
      android: {
        notification: {
          channelId: "miss_you",
          priority: "high",
          defaultSound: true,
          defaultVibrateTimings: true,
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    const messaging = getMessaging();
    const results = await Promise.allSettled(
      tokens.map((token) =>
        messaging.send({ ...message, token })
      )
    );

    // Clean up stale tokens
    const staleTokens = [];
    results.forEach((result, i) => {
      if (
        result.status === "rejected" &&
        result.reason?.code === "messaging/registration-token-not-registered"
      ) {
        staleTokens.push(tokens[i]);
      }
    });

    // Remove stale tokens from Firestore
    for (const staleToken of staleTokens) {
      const usersSnap = await db
        .collection("users")
        .where("fcmToken", "==", staleToken)
        .get();
      for (const doc of usersSnap.docs) {
        await doc.ref.update({ fcmToken: "" });
      }
    }

    console.log(
      `MissYou: sent to ${tokens.length} devices, ${staleTokens.length} stale`
    );
  }
);
