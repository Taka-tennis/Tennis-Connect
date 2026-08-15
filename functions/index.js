const {setGlobalOptions} = require("firebase-functions/v2");
const {
  onCall,
  onRequest,
  HttpsError,
} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {initializeApp} = require("firebase-admin/app");
const {
  getFirestore,
  FieldValue,
} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");
const Stripe = require("stripe");

initializeApp();

const REGION = "asia-northeast1";
const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");
const stripeWebhookSecret = defineSecret(
  "STRIPE_WEBHOOK_SECRET",
);

setGlobalOptions({
  region: REGION,
  maxInstances: 10,
});

/**
 * Checkout Sessionに保存した予約IDを取得します。
 *
 * @param {object} session Stripe Checkout Session
 * @return {string} 予約ID。取得できない場合は空文字
 */
function reservationIdFromSession(session) {
  return session.metadata?.reservationId ||
    session.client_reference_id ||
    "";
}

/**
 * 支払い成功をFirestoreへ反映します。
 * 同じWebhookが再送されても、
 * 二重処理にならないようにします。
 *
 * @param {object} session Stripe Checkout Session
 * @param {string} eventId Stripe Event ID
 * @return {Promise<void>}
 */
async function markReservationPaid(session, eventId) {
  if (session.payment_status !== "paid") {
    logger.info("Sessionはまだ支払い済みではありません。", {
      sessionId: session.id,
      paymentStatus: session.payment_status,
    });
    return;
  }

  const reservationId = reservationIdFromSession(session);

  if (!reservationId) {
    throw new Error("Checkout Sessionに予約IDがありません。");
  }

  const amountPaid = Number(session.amount_total || 0);
  const currency = String(session.currency || "").toLowerCase();
  const paymentIntentId =
    typeof session.payment_intent === "string" ?
      session.payment_intent :
      session.payment_intent?.id || "";

  const db = getFirestore();
  const reservationRef = db
    .collection("reservations")
    .doc(reservationId);

  await db.runTransaction(async (transaction) => {
    const reservationSnap = await transaction.get(
      reservationRef,
    );

    if (!reservationSnap.exists) {
      throw new Error(
        `予約が見つかりません: ${reservationId}`,
      );
    }

    const reservation = reservationSnap.data();

    if (
      reservation.stripeCheckoutSessionId &&
      reservation.stripeCheckoutSessionId !== session.id
    ) {
      throw new Error(
        "現在の予約とCheckout Sessionが一致しません。",
      );
    }

    const expectedTotal = Number(reservation.totalPrice || 0);

    if (
      expectedTotal <= 0 ||
      amountPaid !== expectedTotal ||
      currency !== "jpy"
    ) {
      throw new Error(
        "Stripeの決済金額と予約金額が一致しません。",
      );
    }

    if (
      reservation.paymentStatus === "paid" &&
      reservation.status === "paid"
    ) {
      return;
    }

    transaction.set(
      reservationRef,
      {
        status: "paid",
        paymentStatus: "paid",
        paymentMethod: "stripe_checkout",
        stripeCheckoutSessionId: session.id,
        stripePaymentIntentId: paymentIntentId,
        stripeEventId: eventId,
        amountPaid,
        currency,
        paidAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  });

  logger.info("予約の支払い完了を反映しました。", {
    reservationId,
    sessionId: session.id,
    eventId,
  });
}

/**
 * 未払いのCheckout Session状態をFirestoreへ反映します。
 *
 * @param {object} session Stripe Checkout Session
 * @param {string} paymentStatus 保存する支払い状態
 * @param {string} eventId Stripe Event ID
 * @return {Promise<void>}
 */
async function markCheckoutNotPaid(
  session,
  paymentStatus,
  eventId,
) {
  const reservationId = reservationIdFromSession(session);

  if (!reservationId) {
    logger.warn("予約IDのないSessionを受信しました。", {
      sessionId: session.id,
      eventId,
    });
    return;
  }

  const db = getFirestore();
  const reservationRef = db
    .collection("reservations")
    .doc(reservationId);

  await db.runTransaction(async (transaction) => {
    const reservationSnap = await transaction.get(
      reservationRef,
    );

    if (!reservationSnap.exists) {
      return;
    }

    const reservation = reservationSnap.data();

    if (
      reservation.paymentStatus === "paid" ||
      reservation.stripeCheckoutSessionId !== session.id
    ) {
      return;
    }

    transaction.set(
      reservationRef,
      {
        paymentStatus,
        stripeEventId: eventId,
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  });
}

/**
 * Refundに保存した予約IDを取得します。
 *
 * @param {object} refund Stripe Refund
 * @return {string} 予約ID。取得できない場合は空文字
 */
function reservationIdFromRefund(refund) {
  return refund.metadata?.reservationId || "";
}

/**
 * コーチ都合キャンセル後の返金状態をFirestoreへ反映します。
 * Stripe Webhookが再送されても同じ通知を重複作成しません。
 *
 * @param {object} refund Stripe Refund
 * @param {string} eventId Stripe Event ID
 * @return {Promise<void>}
 */
async function markReservationRefund(refund, eventId) {
  const reservationId = reservationIdFromRefund(refund);

  if (!reservationId) {
    logger.warn("予約IDのないRefundを受信しました。", {
      refundId: refund.id,
      eventId,
    });
    return;
  }

  const db = getFirestore();
  const reservationRef = db
    .collection("reservations")
    .doc(reservationId);

  await db.runTransaction(async (transaction) => {
    const reservationSnap = await transaction.get(
      reservationRef,
    );

    if (!reservationSnap.exists) {
      throw new Error(
        `返金対象の予約が見つかりません: ${reservationId}`,
      );
    }

    const reservation = reservationSnap.data();

    if (
      reservation.stripeRefundId &&
      reservation.stripeRefundId !== refund.id
    ) {
      throw new Error(
        "予約に保存されたRefund IDと一致しません。",
      );
    }

    const refundStatus = String(refund.status || "pending");
    const update = {
      status: "coach_cancelled",
      refundStatus,
      stripeRefundId: refund.id,
      stripeRefundEventId: eventId,
      refundAmount: Number(refund.amount || 0),
      updatedAt: FieldValue.serverTimestamp(),
    };

    if (refundStatus === "succeeded") {
      update.paymentStatus = "refunded";
      update.refundedAt = FieldValue.serverTimestamp();
    } else if (
      refundStatus === "failed" ||
      refundStatus === "canceled"
    ) {
      update.paymentStatus = "refund_failed";
      update.refundFailureReason =
        refund.failure_reason || "unknown";
    } else {
      update.paymentStatus = "refund_processing";
    }

    transaction.set(reservationRef, update, {merge: true});

    let notificationId = "";
    let notificationType = "";
    let title = "";
    let message = "";

    if (refundStatus === "succeeded") {
      notificationId = `refund_succeeded_${reservationId}`;
      notificationType = "coachCancellationRefunded";
      title = "返金が完了しました";
      message =
        "コーチ都合でキャンセルされた予約の" +
        "全額返金が完了しました。";
    } else if (
      refundStatus === "failed" ||
      refundStatus === "canceled"
    ) {
      notificationId = `refund_failed_${reservationId}`;
      notificationType = "coachCancellationRefundFailed";
      title = "返金状況をご確認ください";
      message =
        "コーチ都合キャンセルの返金処理を" +
        "完了できませんでした。運営が確認します。";
    }

    if (notificationId && reservation.studentId) {
      const notificationRef = db
        .collection("notifications")
        .doc(notificationId);

      transaction.set(
        notificationRef,
        {
          recipientId: reservation.studentId,
          coachId: reservation.coachId || "",
          reservationId,
          type: notificationType,
          title,
          message,
          date: reservation.date || "",
          times: reservation.times || [],
          isRead: false,
          createdAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    }
  });

  logger.info("予約の返金状態を反映しました。", {
    reservationId,
    refundId: refund.id,
    refundStatus: refund.status,
    eventId,
  });
}

exports.createCheckoutSession = onCall(
  {secrets: [stripeSecretKey]},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "支払いにはログインが必要です。",
      );
    }

    const reservationId = request.data?.reservationId;

    if (
      typeof reservationId !== "string" ||
      reservationId.trim() === ""
    ) {
      throw new HttpsError(
        "invalid-argument",
        "予約IDがありません。",
      );
    }

    const db = getFirestore();
    const reservationRef = db
      .collection("reservations")
      .doc(reservationId);
    const reservationSnap = await reservationRef.get();

    if (!reservationSnap.exists) {
      throw new HttpsError(
        "not-found",
        "予約が見つかりません。",
      );
    }

    const reservation = reservationSnap.data();

    if (reservation.studentId !== request.auth.uid) {
      throw new HttpsError(
        "permission-denied",
        "この予約は支払えません。",
      );
    }

    if (
      !["confirmed", "approved"].includes(
        reservation.status,
      )
    ) {
      throw new HttpsError(
        "failed-precondition",
        "コーチの承認後に支払えます。",
      );
    }

    if (
      typeof reservation.coachId !== "string" ||
      reservation.coachId === ""
    ) {
      throw new HttpsError(
        "failed-precondition",
        "コーチ情報がありません。",
      );
    }

    const coachSnap = await db
      .collection("coaches")
      .doc(reservation.coachId)
      .get();

    if (!coachSnap.exists) {
      throw new HttpsError(
        "not-found",
        "コーチ情報が見つかりません。",
      );
    }

    const coach = coachSnap.data();
    const pricePerHour = Number(coach.price);

    const selectedTimes =
      Array.isArray(reservation.times) &&
      reservation.times.length > 0 ?
        reservation.times :
        typeof reservation.time === "string" &&
        reservation.time !== "" ?
          [reservation.time] : [];

    const lessonHours = selectedTimes.length;

    if (
      !Number.isInteger(pricePerHour) ||
      pricePerHour <= 0 ||
      lessonHours <= 0
    ) {
      throw new HttpsError(
        "failed-precondition",
        "料金または予約時間が正しくありません。",
      );
    }

    const stripe = new Stripe(stripeSecretKey.value());

    if (reservation.stripeCheckoutSessionId) {
      try {
        const oldSession =
          await stripe.checkout.sessions.retrieve(
            reservation.stripeCheckoutSessionId,
          );

        if (oldSession.payment_status === "paid") {
          throw new HttpsError(
            "already-exists",
            "この予約は支払い済みです。",
          );
        }

        if (oldSession.status === "open" && oldSession.url) {
          return {
            checkoutUrl: oldSession.url,
          };
        }

        if (oldSession.status === "complete") {
          throw new HttpsError(
            "failed-precondition",
            "現在、支払い結果を確認しています。",
          );
        }
      } catch (error) {
        if (error instanceof HttpsError) {
          throw error;
        }

        logger.warn(
          "既存のCheckout Sessionを確認できませんでした。",
          {
            reservationId,
            message: error.message,
          },
        );
      }
    }

    const projectId =
      process.env.GCLOUD_PROJECT ||
      process.env.GOOGLE_CLOUD_PROJECT ||
      "tennis-connect-3f6bd";

    const resultUrl =
      `https://${REGION}-${projectId}` +
      ".cloudfunctions.net/paymentResult";

    const commonMetadata = {
      reservationId,
      studentId: request.auth.uid,
      coachId: reservation.coachId,
      lessonHours: String(lessonHours),
    };

    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      locale: "ja",
      line_items: [
        {
          price_data: {
            currency: "jpy",
            unit_amount: pricePerHour,
            product_data: {
              name:
                `テニスレッスン（${
                  coach.name || "コーチ"
                }）`,
              description:
                `${reservation.date || ""} ` +
                selectedTimes.join(", "),
            },
          },
          quantity: lessonHours,
        },
      ],
      client_reference_id: reservationId,
      metadata: commonMetadata,
      payment_intent_data: {
        metadata: commonMetadata,
      },
      success_url:
        `${resultUrl}?result=success` +
        "&session_id={CHECKOUT_SESSION_ID}",
      cancel_url: `${resultUrl}?result=cancel`,
    });

    await reservationRef.set(
      {
        stripeCheckoutSessionId: session.id,
        paymentStatus: "checkout_created",
        pricePerHour,
        totalPrice: pricePerHour * lessonHours,
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    return {
      checkoutUrl: session.url,
    };
  },
);

exports.requestCoachRefund = onCall(
  {secrets: [stripeSecretKey]},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "返金にはコーチのログインが必要です。",
      );
    }

    const reservationId = request.data?.reservationId;

    if (
      typeof reservationId !== "string" ||
      reservationId.trim() === ""
    ) {
      throw new HttpsError(
        "invalid-argument",
        "予約IDがありません。",
      );
    }

    const db = getFirestore();
    const reservationRef = db
      .collection("reservations")
      .doc(reservationId);

    const reservation = await db.runTransaction(
      async (transaction) => {
        const reservationSnap = await transaction.get(
          reservationRef,
        );

        if (!reservationSnap.exists) {
          throw new HttpsError(
            "not-found",
            "予約が見つかりません。",
          );
        }

        const data = reservationSnap.data();

        if (data.coachId !== request.auth.uid) {
          throw new HttpsError(
            "permission-denied",
            "この予約を返金する権限がありません。",
          );
        }

        if (
          data.refundStatus === "succeeded" ||
          data.paymentStatus === "refunded"
        ) {
          return {
            ...data,
            alreadyRefunded: true,
          };
        }

        const refundablePaymentStatuses = [
          "paid",
          "refund_processing",
          "refund_failed",
        ];

        if (
          !refundablePaymentStatuses.includes(
            data.paymentStatus,
          ) ||
          !data.stripePaymentIntentId
        ) {
          throw new HttpsError(
            "failed-precondition",
            "支払い済みの予約だけ返金できます。",
          );
        }

        transaction.set(
          reservationRef,
          {
            status: "coach_cancelled",
            paymentStatus: "refund_processing",
            refundStatus: "creating",
            refundRequestedBy: request.auth.uid,
            refundRequestedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );

        return data;
      },
    );

    if (reservation.alreadyRefunded) {
      return {
        status: "succeeded",
        alreadyRefunded: true,
      };
    }

    const stripe = new Stripe(stripeSecretKey.value());
    let refund;

    try {
      refund = await stripe.refunds.create(
        {
          payment_intent: reservation.stripePaymentIntentId,
          metadata: {
            reservationId,
            coachId: reservation.coachId || "",
            studentId: reservation.studentId || "",
          },
        },
        {
          idempotencyKey: `coach_refund_${reservationId}`,
        },
      );
    } catch (error) {
      await reservationRef.set(
        {
          paymentStatus: "refund_failed",
          refundStatus: "failed_to_create",
          refundError: error.message,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );

      logger.error("Stripe返金の作成に失敗しました。", {
        reservationId,
        message: error.message,
      });

      throw new HttpsError(
        "internal",
        "返金処理を開始できませんでした。",
      );
    }

    await db.runTransaction(async (transaction) => {
      const latestSnap = await transaction.get(reservationRef);

      if (!latestSnap.exists) {
        throw new Error("返金対象の予約が見つかりません。");
      }

      const latest = latestSnap.data();
      const refundStatus = String(refund.status || "pending");
      const paymentStatus = refundStatus === "succeeded" ?
        "refunded" :
        "refund_processing";

      const update = {
        status: "coach_cancelled",
        paymentStatus,
        refundStatus,
        stripeRefundId: refund.id,
        refundAmount: Number(refund.amount || 0),
        coachCancelledAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      };

      if (refundStatus === "succeeded") {
        update.refundedAt = FieldValue.serverTimestamp();
      }

      transaction.set(reservationRef, update, {merge: true});

      const dateId = String(latest.date || "")
        .replaceAll("/", "-");
      const times = Array.isArray(latest.times) ?
        latest.times :
        latest.time ? [latest.time] : [];

      if (dateId && times.length > 0) {
        const availabilityRef = db
          .collection("coachAvailability")
          .doc(latest.coachId)
          .collection("dates")
          .doc(dateId);

        transaction.set(
          availabilityRef,
          {
            times: FieldValue.arrayUnion(...times),
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );
      }

      if (latest.studentId) {
        const notificationRef = db
          .collection("notifications")
          .doc(`coach_cancel_${reservationId}`);

        transaction.set(
          notificationRef,
          {
            recipientId: latest.studentId,
            coachId: latest.coachId || "",
            reservationId,
            type: "coachCancellationRefundStarted",
            title: "コーチ都合で予約がキャンセルされました",
            message:
              "予約はキャンセルされ、" +
              "全額返金の手続きを開始しました。",
            date: latest.date || "",
            times,
            isRead: false,
            createdAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );
      }
    });

    return {
      status: refund.status,
      refundId: refund.id,
    };
  },
);

exports.stripeWebhook = onRequest(
  {
    secrets: [stripeSecretKey, stripeWebhookSecret],
  },
  async (request, response) => {
    if (request.method !== "POST") {
      response.status(405).send("Method Not Allowed");
      return;
    }

    const signature = request.headers["stripe-signature"];

    if (typeof signature !== "string") {
      response.status(400).send("Stripe signature is missing");
      return;
    }

    const stripe = new Stripe(stripeSecretKey.value());
    let event;

    try {
      event = stripe.webhooks.constructEvent(
        request.rawBody,
        signature,
        stripeWebhookSecret.value(),
      );
    } catch (error) {
      logger.error("Stripe Webhookの署名確認に失敗しました。", {
        message: error.message,
      });
      response.status(400).send("Webhook signature failed");
      return;
    }

    try {
      const stripeObject = event.data.object;

      switch (event.type) {
        case "checkout.session.completed":
        case "checkout.session.async_payment_succeeded":
          await markReservationPaid(stripeObject, event.id);
          break;

        case "checkout.session.async_payment_failed":
          await markCheckoutNotPaid(
            stripeObject,
            "failed",
            event.id,
          );
          break;

        case "checkout.session.expired":
          await markCheckoutNotPaid(
            stripeObject,
            "expired",
            event.id,
          );
          break;

        case "refund.created":
        case "refund.updated":
        case "refund.failed":
          await markReservationRefund(stripeObject, event.id);
          break;

        default:
          logger.info("未処理のStripeイベントです。", {
            type: event.type,
            eventId: event.id,
          });
      }

      response.status(200).json({received: true});
    } catch (error) {
      logger.error("Stripe Webhookの処理に失敗しました。", {
        eventId: event.id,
        type: event.type,
        message: error.message,
      });
      response.status(500).send("Webhook handling failed");
    }
  },
);

exports.paymentResult = onRequest(
  (request, response) => {
    const succeeded = request.query.result === "success";
    const title = succeeded ?
      "支払い手続きを受け付けました" :
      "支払いをキャンセルしました";
    const message = succeeded ?
      "Tennis Connectアプリに戻って、" +
      "支払い状況をご確認ください。" :
      "Tennis Connectアプリに戻って、" +
      "もう一度お試しください。";

    response
      .status(200)
      .set("Content-Type", "text/html; charset=utf-8")
      .send(`<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta
    name="viewport"
    content="width=device-width, initial-scale=1"
  >
  <title>${title}</title>
</head>
<body style="
  font-family: -apple-system, sans-serif;
  text-align: center;
  padding: 48px 20px;
">
  <h1>${title}</h1>
  <p>${message}</p>
</body>
</html>`);
  },
);
