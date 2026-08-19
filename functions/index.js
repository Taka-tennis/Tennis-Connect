const {setGlobalOptions} = require("firebase-functions/v2");
const {
  onCall,
  onRequest,
  HttpsError,
} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {
  getFirestore,
  FieldValue,
} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
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


/**
 * 生徒の予約申請をサーバー側で確定します。
 * 空き枠確認・予約作成・空き枠除去・通知作成を
 * 1つのFirestore Transactionで処理します。
 */
exports.submitReservationRequest = onCall(
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "予約申請にはログインが必要です。",
      );
    }

    const coachId = String(
      request.data?.coachId || "",
    ).trim();
    const date = String(
      request.data?.date || "",
    )
      .trim()
      .replaceAll("/", "-");
    const rawTimes = Array.isArray(request.data?.times) ?
      request.data.times :
      [];
    const selectedTimes = rawTimes
      .map((time) => String(time || "").trim())
      .filter((time) => time !== "")
      .sort();

    if (!coachId) {
      throw new HttpsError(
        "invalid-argument",
        "コーチ情報がありません。",
      );
    }

    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      throw new HttpsError(
        "invalid-argument",
        "予約日が正しくありません。",
      );
    }

    if (
      selectedTimes.length === 0 ||
      selectedTimes.length > 13
    ) {
      throw new HttpsError(
        "invalid-argument",
        "予約時間が正しくありません。",
      );
    }

    if (
      selectedTimes.some(
        (time) => !/^([01]\d|2[0-3]):[0-5]\d$/.test(time),
      )
    ) {
      throw new HttpsError(
        "invalid-argument",
        "予約時間の形式が正しくありません。",
      );
    }

    if (new Set(selectedTimes).size !== selectedTimes.length) {
      throw new HttpsError(
        "invalid-argument",
        "同じ予約時間が重複しています。",
      );
    }

    const minuteValues = selectedTimes.map((time) => {
      const [hour, minute] = time.split(":").map(Number);
      return hour * 60 + minute;
    });

    for (let i = 1; i < minuteValues.length; i += 1) {
      if (minuteValues[i] - minuteValues[i - 1] !== 60) {
        throw new HttpsError(
          "invalid-argument",
          "連続した時間を選択してください。",
        );
      }
    }

    const db = getFirestore();
    const coachRef = db
      .collection("coaches")
      .doc(coachId);
    const availabilityRef = db
      .collection("coachAvailability")
      .doc(coachId)
      .collection("dates")
      .doc(date);
    const reservationRef = db
      .collection("reservations")
      .doc();
    const notificationRef = db
      .collection("notifications")
      .doc();

    const result = await db.runTransaction(
      async (transaction) => {
        const coachSnap = await transaction.get(coachRef);
        const availabilitySnap = await transaction.get(
          availabilityRef,
        );

        if (!coachSnap.exists) {
          throw new HttpsError(
            "not-found",
            "コーチ情報が見つかりません。",
          );
        }

        if (!availabilitySnap.exists) {
          throw new HttpsError(
            "failed-precondition",
            "選択した日の空き時間が見つかりません。",
          );
        }

        const coach = coachSnap.data();
        const availableTimes = Array.isArray(
          availabilitySnap.get("times"),
        ) ?
          availabilitySnap.get("times")
            .map((time) => String(time)) :
          [];

        const unavailableTimes = selectedTimes.filter(
          (time) => !availableTimes.includes(time),
        );

        if (unavailableTimes.length > 0) {
          throw new HttpsError(
            "failed-precondition",
            "選択した時間の一部が予約済みです。" +
            "時間を選び直してください。",
          );
        }

        const pricePerHour = Number(coach.price);

        if (
          !Number.isInteger(pricePerHour) ||
          pricePerHour <= 0
        ) {
          throw new HttpsError(
            "failed-precondition",
            "コーチの料金情報が正しくありません。",
          );
        }

        const remainingTimes = availableTimes
          .filter((time) => !selectedTimes.includes(time))
          .sort();
        const totalPrice =
          pricePerHour * selectedTimes.length;

        const firstTime = selectedTimes[0];
        const lastTime =
          selectedTimes[selectedTimes.length - 1];
        const [lastHour, lastMinute] =
          lastTime.split(":").map(Number);
        const endHour = (lastHour + 1) % 24;
        const endTime =
          `${String(endHour).padStart(2, "0")}:` +
          `${String(lastMinute).padStart(2, "0")}`;
        const timeRange =
          `${firstTime}〜${endTime}`;
        const displayDate =
          date.replaceAll("-", "/");

        transaction.set(
          reservationRef,
          {
            coachId,
            studentId: request.auth.uid,
            coachName: String(
              coach.name || "コーチ名未登録",
            ),
            date,
            time: firstTime,
            times: selectedTimes,
            durationHours: selectedTimes.length,
            pricePerHour,
            totalPrice,
            status: "pending",
            createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
        );

        transaction.set(
          availabilityRef,
          {
            times: remainingTimes,
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );

        transaction.set(
          notificationRef,
          {
            recipientId: coachId,
            coachId,
            studentId: request.auth.uid,
            reservationId: reservationRef.id,
            type: "reservationRequested",
            title: "新しい予約申請が届きました",
            message:
              `${displayDate} ${timeRange}の予約申請が` +
              "届きました。内容を確認してください。",
            date,
            times: selectedTimes,
            isRead: false,
            createdAt: FieldValue.serverTimestamp(),
          },
        );

        return {
          reservationId: reservationRef.id,
          totalPrice,
        };
      },
    );

    logger.info("予約申請を登録しました。", {
      reservationId: result.reservationId,
      studentId: request.auth.uid,
      coachId,
      date,
      times: selectedTimes,
    });

    return result;
  },
);

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

/**
 * 予約情報からレッスン終了日時を取得します。
 * 予約日時は日本時間として扱います。
 *
 * @param {object} reservation 予約データ
 * @return {Date|null} レッスン終了日時
 */
function lessonEndDateFromReservation(reservation) {
  const rawDate = String(reservation.date || "")
    .replaceAll("/", "-");
  const rawTimes = Array.isArray(reservation.times) &&
    reservation.times.length > 0 ?
    reservation.times :
    typeof reservation.time === "string" &&
    reservation.time !== "" ?
      [reservation.time] : [];

  if (!/^\d{4}-\d{2}-\d{2}$/.test(rawDate) || rawTimes.length === 0) {
    return null;
  }

  const sortedTimes = [...rawTimes].sort();
  const lastSlot = String(
    sortedTimes[sortedTimes.length - 1] || "",
  ).replaceAll("~", "〜");

  const rangeParts = lastSlot.split("〜");
  const startTime = rangeParts[0]?.trim() || "";
  const endTime = rangeParts[1]?.trim() || "";

  const parseJstDateTime = (time) => {
    if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(time)) {
      return null;
    }

    const parsed = new Date(`${rawDate}T${time}:00+09:00`);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  };

  const startDate = parseJstDateTime(startTime);

  if (!startDate) {
    return null;
  }

  if (endTime) {
    const parsedEndDate = parseJstDateTime(endTime);

    if (!parsedEndDate) {
      return null;
    }

    if (parsedEndDate <= startDate) {
      return new Date(parsedEndDate.getTime() + 24 * 60 * 60 * 1000);
    }

    return parsedEndDate;
  }

  return new Date(startDate.getTime() + 60 * 60 * 1000);
}

/**
 * アカウント削除前に、未処理の予約が残っていないか確認します。
 * この関数自体はデータ削除を行いません。
 *
 * @param {object} reservation 予約データ
 * @return {string} 削除を止める理由。問題なければ空文字
 */
function accountDeletionBlockReason(reservation) {
  const status = String(reservation.status || "");
  const paymentStatus = String(reservation.paymentStatus || "");
  const refundStatus = String(reservation.refundStatus || "");

  if (["pending", "confirmed", "approved"].includes(status)) {
    return "未処理の予約があります。";
  }

  if (
    paymentStatus === "refund_processing" ||
    paymentStatus === "refund_failed" ||
    refundStatus === "creating" ||
    refundStatus === "pending" ||
    refundStatus === "failed" ||
    refundStatus === "failed_to_create"
  ) {
    return "返金処理が完了していない予約があります。";
  }

  if (status === "paid" || paymentStatus === "paid") {
    const lessonEndDate = lessonEndDateFromReservation(reservation);

    if (!lessonEndDate) {
      return "予約日時を確認できない支払い済み予約があります。";
    }

    if (lessonEndDate > new Date()) {
      return "これから受講する支払い済み予約があります。";
    }
  }

  return "";
}

/**
 * アカウント削除を止める予約を取得します。
 * 生徒側・コーチ側の両方を確認し、同じ予約は1件にまとめます。
 *
 * @param {string} uid Firebase Authentication UID
 * @param {FirebaseFirestore.Firestore} db Firestore
 * @return {Promise<Array<object>>} 削除を止める予約一覧
 */
async function getAccountDeletionBlockers(uid, db) {
  const [
    studentReservationsSnap,
    coachReservationsSnap,
  ] = await Promise.all([
    db.collection("reservations")
      .where("studentId", "==", uid)
      .get(),
    db.collection("reservations")
      .where("coachId", "==", uid)
      .get(),
  ]);

  const reservationMap = new Map();

  for (const document of studentReservationsSnap.docs) {
    reservationMap.set(document.id, {
      document,
      role: "student",
    });
  }

  for (const document of coachReservationsSnap.docs) {
    const existing = reservationMap.get(document.id);

    reservationMap.set(document.id, {
      document,
      role: existing ? "student_and_coach" : "coach",
    });
  }

  const blockers = [];

  for (const [reservationId, entry] of reservationMap.entries()) {
    const reservation = entry.document.data();
    const reason = accountDeletionBlockReason(reservation);

    if (!reason) {
      continue;
    }

    blockers.push({
      reservationId,
      role: entry.role,
      reason,
      status: String(reservation.status || ""),
      paymentStatus: String(reservation.paymentStatus || ""),
      refundStatus: String(reservation.refundStatus || ""),
      date: String(reservation.date || ""),
      times: Array.isArray(reservation.times) ?
        reservation.times.map((time) => String(time)) :
        reservation.time ? [String(reservation.time)] : [],
    });
  }

  return blockers;
}

/**
 * 複数Queryに一致するドキュメントを重複なく削除します。
 *
 * @param {Array<FirebaseFirestore.Query>} queries 削除対象Query
 * @param {FirebaseFirestore.Firestore} db Firestore
 * @return {Promise<number>} 削除したドキュメント数
 */
async function deleteDocumentsByQueries(queries, db) {
  const snapshots = await Promise.all(
    queries.map((query) => query.get()),
  );
  const references = new Map();

  for (const snapshot of snapshots) {
    for (const document of snapshot.docs) {
      references.set(document.ref.path, document.ref);
    }
  }

  if (references.size === 0) {
    return 0;
  }

  const writer = db.bulkWriter();

  for (const reference of references.values()) {
    writer.delete(reference);
  }

  await writer.close();
  return references.size;
}

/**
 * 退会する生徒が投稿したレビューを削除し、
 * コーチ側の評価集計も同じTransaction内で戻します。
 *
 * @param {string} uid Firebase Authentication UID
 * @param {FirebaseFirestore.Firestore} db Firestore
 * @return {Promise<number>} 削除したレビュー数
 */
async function deleteReviewsWrittenByStudent(uid, db) {
  const snapshot = await db
    .collection("reviews")
    .where("studentId", "==", uid)
    .get();

  let deletedCount = 0;

  for (const reviewDocument of snapshot.docs) {
    const deleted = await db.runTransaction(async (transaction) => {
      const reviewSnap = await transaction.get(reviewDocument.ref);

      if (!reviewSnap.exists) {
        return false;
      }

      const review = reviewSnap.data();

      if (review.studentId !== uid) {
        return false;
      }

      const coachId = String(review.coachId || "");
      const reservationId = String(
        review.reservationId || reviewDocument.id,
      );
      const coachRef = coachId ?
        db.collection("coaches").doc(coachId) :
        null;
      const reservationRef = reservationId ?
        db.collection("reservations").doc(reservationId) :
        null;

      const coachSnap = coachRef ?
        await transaction.get(coachRef) :
        null;
      const reservationSnap = reservationRef ?
        await transaction.get(reservationRef) :
        null;

      if (coachRef && coachSnap?.exists) {
        const coach = coachSnap.data();
        const storedRatingCount = Number(
          coach.ratingCount ?? coach.reviewCount ?? 0,
        );
        const currentRatingCount =
          Number.isInteger(storedRatingCount) &&
          storedRatingCount >= 0 ?
            storedRatingCount : 0;
        const storedRatingSum = Number(coach.ratingSum);
        const fallbackAverage = Number(
          coach.ratingAverage ?? coach.rating ?? 0,
        );
        const currentRatingSum =
          Number.isFinite(storedRatingSum) &&
          storedRatingSum >= 0 ?
            storedRatingSum :
            Number.isFinite(fallbackAverage) &&
            fallbackAverage >= 0 ?
              fallbackAverage * currentRatingCount : 0;
        const reviewRating = Number(review.rating);
        const safeReviewRating =
          Number.isFinite(reviewRating) && reviewRating >= 0 ?
            reviewRating : 0;
        const nextRatingCount = Math.max(
          currentRatingCount - 1,
          0,
        );
        const nextRatingSum = Math.max(
          currentRatingSum - safeReviewRating,
          0,
        );
        const nextRatingAverage = nextRatingCount > 0 ?
          Math.round(
            (nextRatingSum / nextRatingCount) * 100,
          ) / 100 :
          0;

        transaction.set(
          coachRef,
          {
            ratingSum: nextRatingSum,
            ratingAverage: nextRatingAverage,
            ratingCount: nextRatingCount,
            rating: nextRatingAverage,
            reviewCount: nextRatingCount,
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );
      }

      if (reservationRef && reservationSnap?.exists) {
        transaction.set(
          reservationRef,
          {
            reviewId: FieldValue.delete(),
            reviewSubmittedAt: FieldValue.delete(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );
      }

      transaction.delete(reviewDocument.ref);
      return true;
    });

    if (deleted) {
      deletedCount += 1;
    }
  }

  return deletedCount;
}

/**
 * 退会するコーチに対するレビューを削除します。
 * 各生徒のレビュー済みマーカーも同時に削除します。
 *
 * @param {string} uid Firebase Authentication UID
 * @param {FirebaseFirestore.Firestore} db Firestore
 * @return {Promise<number>} 削除したレビュー数
 */
async function deleteReviewsForCoach(uid, db) {
  const snapshot = await db
    .collection("reviews")
    .where("coachId", "==", uid)
    .get();

  if (snapshot.empty) {
    return 0;
  }

  const writer = db.bulkWriter();

  for (const reviewDocument of snapshot.docs) {
    const review = reviewDocument.data();
    const studentId = String(review.studentId || "");

    writer.delete(reviewDocument.ref);

    if (studentId) {
      writer.delete(
        db.collection("students")
          .doc(studentId)
          .collection("reviewedCoaches")
          .doc(uid),
      );
    }
  }

  await writer.close();
  return snapshot.size;
}

/**
 * 予約そのものは取引履歴として残し、
 * 退会するユーザーを特定できるUIDだけを取り除きます。
 *
 * @param {string} uid Firebase Authentication UID
 * @param {FirebaseFirestore.Firestore} db Firestore
 * @return {Promise<number>} 更新した予約数
 */
async function anonymizeReservationsForDeletedAccount(uid, db) {
  const [
    studentReservationsSnap,
    coachReservationsSnap,
  ] = await Promise.all([
    db.collection("reservations")
      .where("studentId", "==", uid)
      .get(),
    db.collection("reservations")
      .where("coachId", "==", uid)
      .get(),
  ]);

  const updates = new Map();

  for (const document of studentReservationsSnap.docs) {
    updates.set(document.ref.path, {
      reference: document.ref,
      data: {
        studentId: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      },
    });
  }

  for (const document of coachReservationsSnap.docs) {
    const existing = updates.get(document.ref.path);

    updates.set(document.ref.path, {
      reference: document.ref,
      data: {
        ...(existing?.data || {}),
        coachId: FieldValue.delete(),
        coachName: "退会済みコーチ",
        updatedAt: FieldValue.serverTimestamp(),
      },
    });
  }

  if (updates.size === 0) {
    return 0;
  }

  const writer = db.bulkWriter();

  for (const entry of updates.values()) {
    writer.set(
      entry.reference,
      entry.data,
      {merge: true},
    );
  }

  await writer.close();
  return updates.size;
}

/**
 * 固定パスのコーチプロフィール画像を削除します。
 * ファイルが存在しない場合は正常扱いにします。
 *
 * @param {string} uid Firebase Authentication UID
 * @return {Promise<void>}
 */
async function deleteCoachProfileImage(uid) {
  const file = getStorage()
    .bucket()
    .file(`coachImages/${uid}.jpg`);

  try {
    await file.delete();
  } catch (error) {
    const statusCode = Number(
      error.code || error.statusCode || 0,
    );

    if (statusCode === 404) {
      return;
    }

    throw error;
  }
}

/**
 * アカウント削除が可能か確認します。
 * 生徒側・コーチ側の両方の予約を確認します。
 */
exports.checkAccountDeletionEligibility = onCall(
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "アカウント削除の確認にはログインが必要です。",
      );
    }

    const uid = request.auth.uid;
    const db = getFirestore();
    const blockers = await getAccountDeletionBlockers(uid, db);

    logger.info("アカウント削除可否を確認しました。", {
      uid,
      eligible: blockers.length === 0,
      blockerCount: blockers.length,
    });

    return {
      eligible: blockers.length === 0,
      blockers,
    };
  },
);

/**
 * アカウント本削除を行います。
 * 予約条件をサーバー側でも再確認し、
 * 関連データを削除・匿名化した後にAuthenticationを削除します。
 */
exports.deleteAccount = onCall(
  {timeoutSeconds: 120},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "アカウント削除にはログインが必要です。",
      );
    }

    if (request.data?.confirm !== true) {
      throw new HttpsError(
        "invalid-argument",
        "アカウント削除の確認が必要です。",
      );
    }

    const uid = request.auth.uid;
    const db = getFirestore();

    const blockers = await getAccountDeletionBlockers(uid, db);

    if (blockers.length > 0) {
      throw new HttpsError(
        "failed-precondition",
        blockers[0].reason ||
          "現在はアカウントを削除できません。",
        {
          blockers,
        },
      );
    }

    try {
      const writtenReviewCount =
        await deleteReviewsWrittenByStudent(uid, db);
      const coachReviewCount =
        await deleteReviewsForCoach(uid, db);

      const deletedRelatedDocumentCount =
        await deleteDocumentsByQueries(
          [
            db.collection("favorites")
              .where("studentId", "==", uid),
            db.collection("favorites")
              .where("coachId", "==", uid),
            db.collection("messages")
              .where("studentId", "==", uid),
            db.collection("messages")
              .where("coachId", "==", uid),
            db.collection("notifications")
              .where("recipientId", "==", uid),
            db.collection("notifications")
              .where("studentId", "==", uid),
            db.collection("notifications")
              .where("coachId", "==", uid),
            db.collection("inquiries")
              .where("userId", "==", uid),
          ],
          db,
        );

      const anonymizedReservationCount =
        await anonymizeReservationsForDeletedAccount(uid, db);

      await db.recursiveDelete(
        db.collection("students").doc(uid),
      );
      await db.recursiveDelete(
        db.collection("coachAvailability").doc(uid),
      );
      await db.recursiveDelete(
        db.collection("coaches").doc(uid),
      );

      await deleteCoachProfileImage(uid);

      await getAuth().deleteUser(uid);

      logger.info("アカウントを削除しました。", {
        uid,
        writtenReviewCount,
        coachReviewCount,
        deletedRelatedDocumentCount,
        anonymizedReservationCount,
      });

      return {
        deleted: true,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error("アカウント削除に失敗しました。", {
        uid,
        message: error.message,
        stack: error.stack,
      });

      throw new HttpsError(
        "internal",
        "アカウントを削除できませんでした。",
      );
    }
  },
);

/**
 * 受講済み予約に対するレビューを登録します。
 * 同じ生徒から同じコーチへのレビューは1件までに制限します。
 */
exports.submitReview = onCall(
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "レビュー投稿にはログインが必要です。",
      );
    }

    const reservationId = request.data?.reservationId;
    const rating = Number(request.data?.rating);
    const comment = String(request.data?.comment || "").trim();

    if (
      typeof reservationId !== "string" ||
      reservationId.trim() === ""
    ) {
      throw new HttpsError(
        "invalid-argument",
        "予約IDがありません。",
      );
    }

    if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
      throw new HttpsError(
        "invalid-argument",
        "評価は1〜5で選択してください。",
      );
    }

    if (comment.length < 1 || comment.length > 500) {
      throw new HttpsError(
        "invalid-argument",
        "レビュー本文は1〜500文字で入力してください。",
      );
    }

    const db = getFirestore();
    const reservationRef = db
      .collection("reservations")
      .doc(reservationId);
    const reviewRef = db
      .collection("reviews")
      .doc(reservationId);
    const studentRef = db
      .collection("students")
      .doc(request.auth.uid);

    const result = await db.runTransaction(async (transaction) => {
      const reservationSnap = await transaction.get(reservationRef);

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
          "この予約にはレビューを投稿できません。",
        );
      }

      if (
        reservation.paymentStatus !== "paid" ||
        !["paid", "completed"].includes(reservation.status)
      ) {
        throw new HttpsError(
          "failed-precondition",
          "支払い済みの受講予約だけレビューできます。",
        );
      }

      if (
        reservation.refundStatus === "succeeded" ||
        reservation.paymentStatus === "refunded" ||
        reservation.status === "coach_cancelled" ||
        reservation.status === "cancelled" ||
        reservation.status === "canceled"
      ) {
        throw new HttpsError(
          "failed-precondition",
          "キャンセルされた予約にはレビューできません。",
        );
      }

      const lessonEndDate = lessonEndDateFromReservation(reservation);

      if (!lessonEndDate) {
        throw new HttpsError(
          "failed-precondition",
          "予約日時を確認できませんでした。",
        );
      }

      if (lessonEndDate > new Date()) {
        throw new HttpsError(
          "failed-precondition",
          "レッスン終了後にレビューできます。",
        );
      }

      const coachId = String(reservation.coachId || "");

      if (!coachId) {
        throw new HttpsError(
          "failed-precondition",
          "コーチ情報がありません。",
        );
      }

      if (coachId === request.auth.uid) {
        throw new HttpsError(
          "failed-precondition",
          "自分自身のレッスンにはレビューできません。",
        );
      }

      const coachRef = db.collection("coaches").doc(coachId);
      const reviewUniquenessRef = studentRef
        .collection("reviewedCoaches")
        .doc(coachId);
      const existingStudentReviewsQuery = db
        .collection("reviews")
        .where("studentId", "==", request.auth.uid);

      const reviewSnap = await transaction.get(reviewRef);
      const studentSnap = await transaction.get(studentRef);
      const coachSnap = await transaction.get(coachRef);
      const reviewUniquenessSnap = await transaction.get(
        reviewUniquenessRef,
      );
      const existingStudentReviewsSnap = await transaction.get(
        existingStudentReviewsQuery,
      );

      if (reviewSnap.exists) {
        throw new HttpsError(
          "already-exists",
          "この予約のレビューは投稿済みです。",
        );
      }

      const alreadyReviewedCoach =
        reviewUniquenessSnap.exists ||
        existingStudentReviewsSnap.docs.some((document) => {
          return document.get("coachId") === coachId;
        });

      if (alreadyReviewedCoach) {
        throw new HttpsError(
          "already-exists",
          "このコーチへのレビューは投稿済みです。",
        );
      }

      if (!studentSnap.exists) {
        throw new HttpsError(
          "failed-precondition",
          "生徒プロフィールが見つかりません。",
        );
      }

      if (!coachSnap.exists) {
        throw new HttpsError(
          "not-found",
          "コーチ情報が見つかりません。",
        );
      }

      const student = studentSnap.data();
      const studentDisplayName = String(
        student.displayName || student.nickname || "",
      ).trim();

      if (!studentDisplayName) {
        throw new HttpsError(
          "failed-precondition",
          "レビュー投稿前に表示名を登録してください。",
        );
      }

      const coach = coachSnap.data();
      const storedRatingCount = Number(
        coach.ratingCount ?? coach.reviewCount ?? 0,
      );
      const currentRatingCount =
        Number.isInteger(storedRatingCount) && storedRatingCount >= 0 ?
          storedRatingCount : 0;
      const storedRatingSum = Number(coach.ratingSum);
      const fallbackAverage = Number(
        coach.ratingAverage ?? coach.rating ?? 0,
      );
      const currentRatingSum =
        Number.isFinite(storedRatingSum) && storedRatingSum >= 0 ?
          storedRatingSum :
          Number.isFinite(fallbackAverage) && fallbackAverage >= 0 ?
            fallbackAverage * currentRatingCount : 0;
      const nextRatingCount = currentRatingCount + 1;
      const nextRatingSum = currentRatingSum + rating;
      const nextRatingAverage = Math.round(
        (nextRatingSum / nextRatingCount) * 100,
      ) / 100;

      transaction.set(reviewRef, {
        reservationId,
        coachId,
        studentId: request.auth.uid,
        studentDisplayName,
        rating,
        comment,
        lessonDate: reservation.date || "",
        times: Array.isArray(reservation.times) ?
          reservation.times :
          reservation.time ? [reservation.time] : [],
        createdAt: FieldValue.serverTimestamp(),
      });

      transaction.set(reviewUniquenessRef, {
        studentId: request.auth.uid,
        coachId,
        reviewId: reservationId,
        createdAt: FieldValue.serverTimestamp(),
      });

      transaction.set(
        coachRef,
        {
          ratingSum: nextRatingSum,
          ratingAverage: nextRatingAverage,
          ratingCount: nextRatingCount,
          rating: nextRatingAverage,
          reviewCount: nextRatingCount,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );

      transaction.set(
        reservationRef,
        {
          reviewId: reservationId,
          reviewSubmittedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );

      return {
        reviewId: reservationId,
        ratingAverage: nextRatingAverage,
        ratingCount: nextRatingCount,
      };
    });

    logger.info("レビューを登録しました。", {
      reservationId,
      studentId: request.auth.uid,
      reviewId: result.reviewId,
    });

    return result;
  },
);
