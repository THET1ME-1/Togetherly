/// Приём уведомлений App Store Server Notifications V2.
///
/// Зачем. До этого о покупке на iPhone сервер узнавал единственным путём:
/// приложение доносило чек. Приложение вылетело, связь оборвалась, человек
/// снёс программу сразу после оплаты — деньги списаны, доступа нет, и никто
/// об этом не знает. 30 августа 2026 выдача стояла полдня именно так: сервер
/// отвечал 500, а увидели мы это по жалобе в чат, а не по своему журналу.
///
/// Apple шлёт уведомление сама, сразу после оплаты, и повторяет его, пока не
/// получит 200. Отсюда два правила: отвечать 200 на всё, что мы разобрали (в
/// том числе на «этого пользователя не нашли» — повтор тут не поможет), и
/// держать идемпотентность по `notificationUUID`.
///
/// Подпись проверяет служба на 8097 тем же кодом, что и чек покупки: цепочка
/// сертификатов до корня Apple, сроки, подписи звеньев. В JSVM такого не
/// сделать, поэтому сюда приходит уже разобранное уведомление.
///
/// ГРАБЛИ JSVM: обработчик исполняется изолированно и функций уровня файла не
/// видит — всё, что нужно, живёт внутри него.
routerAdd("POST", "/api/apple/notifications", (e) => {
  const body = (e.requestInfo().body || {});
  const payload = String(body.signedPayload || "");
  if (!payload) return e.json(400, { ok: false, error: "no_payload" });

  // Товары те же, что в `coins.pb.js`.
  const PLUS_PRODUCT = "togetherly_plus";
  const GIFT_PRODUCT = "togetherly_plus_gift";

  let verdict = null;
  try {
    const res = $http.send({
      url: "http://127.0.0.1:8097/apple/notification",
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ signedPayload: payload }),
      timeout: 20,
    });
    verdict = res.json;
  } catch (err) {
    // Своя авария: просим Apple прийти ещё раз, покупку терять нельзя.
    $app.logger().error("apple/notify: служба проверки молчит", "err", String(err));
    return e.json(503, { ok: false, error: "verifier_down" });
  }

  if (!verdict || verdict.valid !== true) {
    const reason = String((verdict && verdict.reason) || "unknown");
    $app.logger().error("apple/notify: подпись не сошлась", "reason", reason);
    return e.json(400, { ok: false, error: reason });
  }

  const kind = String(verdict.notificationType || "");
  const subtype = String(verdict.subtype || "");
  const tx = verdict.transaction || {};
  const uuid = String(verdict.notificationUUID || "");
  const productId = String(tx.productId || "");
  const txId = String(tx.transactionId || "");
  const accountToken = String(tx.appAccountToken || "");

  // Повтор Apple присылает по любому поводу — вплоть до нашей же задержки с
  // ответом. Разбирать его заново незачем.
  if (uuid) {
    let было = null;
    try { было = $app.findRecordById("apple_notifications", uuid); } catch (_) { было = null; }
    if (было) return e.json(200, { ok: true, repeated: true });
  }

  // Кому принадлежит покупка. В уведомлении нет ни почты, ни нашего uid —
  // только метка, которую приложение положило при оплате. Нет метки (старые
  // сборки) — покупку записываем и ждём, пока приложение донесёт чек само.
  let owner = null;
  if (accountToken) {
    try {
      owner = $app.findFirstRecordByFilter(
        "users", "apple_account_token = {:t}", { t: accountToken });
    } catch (_) { owner = null; }
  }

  let outcome = "ignored";

  // Оплата. `ONE_TIME_CHARGE` — разовая покупка StoreKit 2, наш случай.
  if (kind === "ONE_TIME_CHARGE" && !tx.revocationDate) {
    if (productId === GIFT_PRODUCT) {
      // Подарок выдать отсюда нельзя: получателя выбирают в приложении, а в
      // уведомлении его нет. Записываем и ждём чек от приложения.
      outcome = owner ? "gift_waits_app" : "no_owner";
    } else if (productId === PLUS_PRODUCT && owner) {
      if (owner.getBool("plus")) {
        outcome = "already";
      } else {
        try {
          owner.set("plus", true);
          owner.set("plus_platform", "appstore");
          owner.set("last_plus_grant_ms", Date.now());
          $app.save(owner);
          outcome = "granted";
          $app.logger().warn("apple/notify: Togetherly+ выдан по уведомлению",
            "uid", owner.id, "tx", txId);
        } catch (err) {
          $app.logger().error("apple/notify: выдача не удалась",
            "uid", owner.id, "tx", txId, "err", String(err));
          return e.json(500, { ok: false, error: "grant failed" });
        }
      }
    } else {
      outcome = "no_owner";
      $app.logger().warn("apple/notify: оплата без хозяина",
        "product", productId, "tx", txId, "token", accountToken || "нет");
    }
  }

  // Возврат денег и отзыв доступа. Плюс снимаем только с той покупки, которую
  // нашли по номеру сделки: ошибиться тут дороже, чем не сделать ничего.
  if (kind === "REFUND" || kind === "REVOKE" || tx.revocationDate) {
    outcome = "refund_unmatched";
    let purchase = null;
    if (txId) {
      try {
        purchase = $app.findFirstRecordByFilter(
          "iap_purchases", "transaction_id = {:t}", { t: txId });
      } catch (_) { purchase = null; }
    }
    if (purchase && String(purchase.getString("product_id")) === PLUS_PRODUCT) {
      try {
        const buyer = $app.findRecordById("users", purchase.getString("user_uid"));
        if (buyer.getBool("plus") && buyer.getString("plus_platform") === "appstore") {
          buyer.set("plus", false);
          buyer.set("plus_platform", "");
          $app.save(buyer);
          outcome = "refunded";
          $app.logger().warn("apple/notify: Плюс снят по возврату",
            "uid", buyer.id, "tx", txId);
        } else {
          // Доступ мог прийти другим каналом — lava, код, подарок. Чужой канал
          // возврат в App Store не отменяет.
          outcome = "refund_other_channel";
        }
      } catch (err) {
        $app.logger().warn("apple/notify: возврат не отработан",
          "tx", txId, "err", String(err));
      }
    } else {
      $app.logger().warn("apple/notify: возврат без нашей покупки",
        "product", productId, "tx", txId);
    }
  }

  if (uuid) {
    try {
      const col = $app.findCollectionByNameOrId("apple_notifications");
      const rec = new Record(col);
      rec.set("id", uuid);
      rec.set("kind", kind);
      rec.set("subtype", subtype);
      rec.set("product_id", productId);
      rec.set("transaction_id", txId);
      rec.set("original_transaction_id", String(tx.originalTransactionId || ""));
      rec.set("account_token", accountToken);
      rec.set("environment", String(verdict.environment || ""));
      rec.set("user_uid", owner ? owner.id : "");
      rec.set("outcome", outcome);
      rec.set("at", new Date().toISOString());
      $app.save(rec);
    } catch (err) {
      // Запись — журнал, а не условие выдачи: терять из-за неё оплату нельзя.
      $app.logger().warn("apple/notify: событие не записано",
        "uuid", uuid, "err", String(err));
    }
  }

  return e.json(200, { ok: true, outcome: outcome });
});
