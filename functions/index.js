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
const stripeConnectWebhookSecret = defineSecret(
  "STRIPE_CONNECT_WEBHOOK_SECRET",
);

setGlobalOptions({
  region: REGION,
  maxInstances: 10,
});

const PLATFORM_FEE_PERCENT = 10;
const COACH_SHARE_PERCENT = 90;
const COACH_PAYOUT_HOLD_HOURS = 24;


/**
 * Stripe Connectの状態をアプリ用の安全な形に整えます。
 * StripeのアカウントID自体はクライアントへ返しません。
 *
 * @param {object} account Stripe Connected Account
 * @return {object} Connect状態
 */
function coachConnectStatusFromAccount(account) {
  const transfersStatus = String(
    account.capabilities?.transfers || "inactive",
  );
  const currentlyDue = Array.isArray(
    account.requirements?.currently_due,
  ) ?
    account.requirements.currently_due :
    [];
  const pastDue = Array.isArray(
    account.requirements?.past_due,
  ) ?
    account.requirements.past_due :
    [];
  const disabledReason = String(
    account.requirements?.disabled_reason || "",
  );
  const detailsSubmitted = Boolean(account.details_submitted);
  const payoutsEnabled = Boolean(account.payouts_enabled);
  const readyForPayouts =
    detailsSubmitted &&
    payoutsEnabled &&
    transfersStatus === "active" &&
    !disabledReason;

  return {
    detailsSubmitted,
    payoutsEnabled,
    transfersStatus,
    readyForPayouts,
    disabledReason,
    currentlyDueCount: currentlyDue.length,
    pastDueCount: pastDue.length,
  };
}

/**
 * Firebase UIDに紐づくStripe Connectアカウントを取得します。
 * 未作成なら、日本のコーチ向けConnected Accountを作成します。
 *
 * - Stripeが本人確認情報を収集
 * - Express Dashboardを利用
 * - tennis-connectがStripe手数料と負残高リスクを負担
 * - transfersのみを要求し、決済自体はプラットフォーム側で行う
 *
 * @param {string} uid Firebase Authentication UID
 * @param {object} coach コーチプロフィール
 * @param {Stripe} stripe Stripeクライアント
 * @param {FirebaseFirestore.Firestore} db Firestore
 * @return {Promise<object>} Stripe Connected Account
 */
async function getOrCreateCoachConnectAccount(
  uid,
  coach,
  stripe,
  db,
) {
  const connectRef = db
    .collection("stripeConnectAccounts")
    .doc(uid);
  const connectSnap = await connectRef.get();
  const savedAccountId = String(
    connectSnap.data()?.stripeAccountId || "",
  ).trim();

  if (savedAccountId) {
    try {
      return await stripe.accounts.retrieve(savedAccountId);
    } catch (error) {
      if (error?.code !== "resource_missing") {
        throw error;
      }

      logger.warn(
        "保存済みのStripe Connectアカウントが見つかりません。",
        {
          uid,
          stripeAccountId: savedAccountId,
        },
      );
    }
  }

  let email = "";

  try {
    const user = await getAuth().getUser(uid);
    email = String(user.email || "").trim();
  } catch (error) {
    logger.warn("Firebaseユーザー情報を取得できませんでした。", {
      uid,
      firebaseErrorMessage: error?.message || String(error),
      firebaseErrorCode: error?.code || "",
    });
  }

  const coachName = String(coach.name || "")
    .trim()
    .slice(0, 100);

  const accountParams = {
    display_name: coachName || "Tennis Connect Coach",
    identity: {
      country: "jp",
    },
    configuration: {
      recipient: {
        capabilities: {
          stripe_balance: {
            stripe_transfers: {
              requested: true,
            },
          },
        },
      },
    },
    dashboard: "express",
    defaults: {
      currency: "jpy",
      locales: ["ja-JP"],
      responsibilities: {
        fees_collector: "application",
        losses_collector: "application",
      },
      profile: {
        product_description:
          "Tennis coaching services provided through Tennis Connect.",
      },
    },
    metadata: {
      firebaseUid: uid,
      platformRole: "coach",
    },
    include: [
      "configuration.recipient",
      "identity",
      "requirements",
      "defaults",
    ],
  };

  if (email) {
    accountParams.contact_email = email;
  }

  logger.info("Stripe Accounts v2でコーチ口座作成を開始します。", {
    uid,
    country: "JP",
  });

  const response = await fetch(
    "https://api.stripe.com/v2/core/accounts",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${stripeSecretKey.value()}`,
        "Content-Type": "application/json",
        "Stripe-Version": "2026-07-29.dahlia",
        "Idempotency-Key": `coach_connect_account_${uid}_v3`,
      },
      body: JSON.stringify(accountParams),
      signal: AbortSignal.timeout(15000),
    },
  );

  const rawBody = await response.text();

  let v2Account;

  try {
    v2Account = JSON.parse(rawBody);
  } catch (_) {
    throw new Error(
      `Stripe Accounts v2の応答を解析できませんでした。` +
      ` status=${response.status} body=${rawBody.slice(0, 500)}`,
    );
  }

  if (!response.ok) {
    const stripeMessage =
      v2Account?.error?.message ||
      v2Account?.message ||
      "Stripe Accounts v2でアカウントを作成できませんでした。";
    const stripeCode =
      v2Account?.error?.code ||
      v2Account?.code ||
      "";

    const error = new Error(stripeMessage);
    error.code = stripeCode;
    error.statusCode = response.status;
    error.type =
      v2Account?.error?.type ||
      v2Account?.type ||
      "StripeAccountsV2Error";
    error.param =
      v2Account?.error?.param ||
      v2Account?.param ||
      "";
    error.requestId =
      response.headers.get("request-id") || "";
    throw error;
  }

  const accountId = String(v2Account?.id || "").trim();

  if (!accountId) {
    throw new Error(
      "Stripe Accounts v2の応答にアカウントIDがありません。",
    );
  }

  logger.info("Stripe Accounts v2のアカウント作成が完了しました。", {
    uid,
    stripeAccountId: accountId,
  });

  // Accounts v2で作成したIDは、多くのAccounts v1 APIでも利用できます。
  // 既存の状態判定・Account Link処理を壊さないため、
  // v1 Account形式で取得し直して以降の処理へ渡します。
  const account = await stripe.accounts.retrieve(accountId);
  const status = coachConnectStatusFromAccount(account);

  await connectRef.set(
    {
      stripeAccountId: accountId,
      country: String(account.country || "JP"),
      accountsApiVersion: "v2",
      ...status,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );

  logger.info("コーチ用Stripe Connectアカウントを保存しました。", {
    uid,
    stripeAccountId: accountId,
  });

  return account;
}

/**
 * コーチ本人がStripeの本人確認・銀行口座登録へ進むための
 * 1回限りのAccount Linkを発行します。
 */
exports.createCoachConnectOnboardingLink = onCall(
  {secrets: [stripeSecretKey]},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "売上受取設定にはログインが必要です。",
      );
    }

    const uid = request.auth.uid;
    const db = getFirestore();
    const coachRef = db.collection("coaches").doc(uid);
    const coachSnap = await coachRef.get();

    if (!coachSnap.exists) {
      throw new HttpsError(
        "failed-precondition",
        "先にコーチプロフィールを登録してください。",
      );
    }

    const stripe = new Stripe(stripeSecretKey.value(), {
      maxNetworkRetries: 0,
      timeout: 15000,
    });
    let account;

    try {
      account = await getOrCreateCoachConnectAccount(
        uid,
        coachSnap.data(),
        stripe,
        db,
      );
    } catch (error) {
      logger.error("Stripe Connectアカウント準備に失敗しました。", {
        uid,
        stripeErrorMessage: error?.message || String(error),
        stripeErrorCode: error?.code || "",
        stripeErrorType: error?.type || "",
        stripeErrorParam: error?.param || "",
        stripeErrorStatusCode: error?.statusCode || null,
        stripeRequestId: error?.requestId || "",
      });

      throw new HttpsError(
        "internal",
        "売上受取用アカウントを準備できませんでした。",
      );
    }

    const projectId =
      process.env.GCLOUD_PROJECT ||
      process.env.GOOGLE_CLOUD_PROJECT ||
      "tennis-connect-3f6bd";
    const resultUrl =
      `https://${REGION}-${projectId}` +
      ".cloudfunctions.net/connectOnboardingResult";

    let accountLink;

    try {
      accountLink = await stripe.accountLinks.create({
        account: account.id,
        refresh_url: `${resultUrl}?result=refresh`,
        return_url: `${resultUrl}?result=return`,
        type: "account_onboarding",
      });
    } catch (error) {
      logger.error("Stripe Account Linkの作成に失敗しました。", {
        uid,
        stripeAccountId: account.id,
        stripeErrorMessage: error?.message || String(error),
        stripeErrorCode: error?.code || "",
        stripeErrorType: error?.type || "",
        stripeErrorParam: error?.param || "",
        stripeErrorStatusCode: error?.statusCode || null,
        stripeRequestId: error?.requestId || "",
      });

      throw new HttpsError(
        "internal",
        "本人確認ページを開けませんでした。",
      );
    }

    return {
      onboardingUrl: accountLink.url,
      ...coachConnectStatusFromAccount(account),
    };
  },
);

/**
 * コーチ本人のStripe Connect状態を最新化して返します。
 * 銀行口座情報などの機微情報は返しません。
 */
exports.getCoachConnectStatus = onCall(
  {secrets: [stripeSecretKey]},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "売上受取設定の確認にはログインが必要です。",
      );
    }

    const uid = request.auth.uid;
    const db = getFirestore();
    const connectRef = db
      .collection("stripeConnectAccounts")
      .doc(uid);
    const connectSnap = await connectRef.get();
    const stripeAccountId = String(
      connectSnap.data()?.stripeAccountId || "",
    ).trim();

    if (!stripeAccountId) {
      return {
        accountCreated: false,
        detailsSubmitted: false,
        payoutsEnabled: false,
        transfersStatus: "inactive",
        readyForPayouts: false,
        disabledReason: "",
        currentlyDueCount: 0,
        pastDueCount: 0,
      };
    }

    const stripe = new Stripe(stripeSecretKey.value(), {
      maxNetworkRetries: 0,
      timeout: 15000,
    });
    let account;

    try {
      account = await stripe.accounts.retrieve(stripeAccountId);
    } catch (error) {
      logger.error("Stripe Connect状態の取得に失敗しました。", {
        uid,
        stripeAccountId,
        stripeErrorMessage: error?.message || String(error),
        stripeErrorCode: error?.code || "",
        stripeErrorType: error?.type || "",
        stripeErrorParam: error?.param || "",
        stripeErrorStatusCode: error?.statusCode || null,
        stripeRequestId: error?.requestId || "",
      });

      throw new HttpsError(
        "internal",
        "売上受取設定の状態を確認できませんでした。",
      );
    }

    const status = coachConnectStatusFromAccount(account);

    await connectRef.set(
      {
        country: String(account.country || "JP"),
        ...status,
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    return {
      accountCreated: true,
      ...status,
    };
  },
);

/**
 * Stripe-hosted onboardingから戻ったときに表示するページです。
 * Account Linkは再利用できないため、期限切れ時はアプリから
 * 新しいリンクを発行してもらいます。
 */
exports.connectOnboardingResult = onRequest(
  (request, response) => {
    const shouldRetry = request.query.result === "refresh";
    const title = shouldRetry ?
      "本人確認リンクの有効期限が切れました" :
      "売上受取設定を受け付けました";
    const message = shouldRetry ?
      "Tennis Connectアプリに戻って、もう一度「売上受取設定」を開いてください。" :
      "Tennis Connectアプリに戻って、設定状況をご確認ください。";

    response
      .status(200)
      .set("Content-Type", "text/html; charset=utf-8")
      .send(`<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${title}</title>
</head>
<body style="
  font-family: -apple-system, BlinkMacSystemFont, sans-serif;
  text-align: center;
  padding: 48px 20px;
  line-height: 1.6;
">
  <h1>${title}</h1>
  <p>${message}</p>
</body>
</html>`);
  },
);

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
 * Stripe Refundの状態をFirestoreへ反映します。
 * コーチ都合・生徒都合のどちらにも対応し、
 * Webhook再送時も通知IDを固定して重複作成を防ぎます。
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

    const metadataSource = String(
      refund.metadata?.cancellationSource || "",
    );
    const storedSource = String(
      reservation.cancellationSource || "",
    );
    const cancellationSource =
      metadataSource === "student" ||
      storedSource === "student" ||
      reservation.status === "student_cancelled" ?
        "student" :
        "coach";

    const cancellationStatus = cancellationSource === "student" ?
      "student_cancelled" :
      "coach_cancelled";
    const refundStatus = String(refund.status || "pending");
    const refundAmount = Number(refund.amount || 0);
    const amountPaid = Number(
      reservation.amountPaid ||
      reservation.totalPrice ||
      0,
    );
    const isPartialRefund =
      cancellationSource === "student" &&
      amountPaid > 0 &&
      refundAmount > 0 &&
      refundAmount < amountPaid;

    const update = {
      status: cancellationStatus,
      cancellationSource,
      refundStatus,
      stripeRefundId: refund.id,
      stripeRefundEventId: eventId,
      refundAmount,
      updatedAt: FieldValue.serverTimestamp(),
    };

    if (refundStatus === "succeeded") {
      update.paymentStatus = isPartialRefund ?
        "partially_refunded" :
        "refunded";
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

    if (cancellationSource === "student") {
      const storedPercent = Number(
        reservation.cancellationRefundPercent,
      );
      const refundPercent =
        Number.isFinite(storedPercent) && storedPercent >= 0 ?
          storedPercent :
          amountPaid > 0 ?
            Math.round((refundAmount / amountPaid) * 100) :
            0;

      if (refundStatus === "succeeded") {
        notificationId =
          `student_refund_succeeded_${reservationId}`;
        notificationType = "studentCancellationRefunded";
        title = "キャンセルの返金が完了しました";
        message =
          `キャンセル規定に基づく${refundPercent}%返金が` +
          "完了しました。";
      } else if (
        refundStatus === "failed" ||
        refundStatus === "canceled"
      ) {
        notificationId =
          `student_refund_failed_${reservationId}`;
        notificationType = "studentCancellationRefundFailed";
        title = "返金状況をご確認ください";
        message =
          "生徒都合キャンセルの返金処理を" +
          "完了できませんでした。運営が確認します。";
      }
    } else if (refundStatus === "succeeded") {
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
          studentId: reservation.studentId,
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
            cancellationSource: "coach",
            cancellationRefundPercent: 100,
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
            cancellationSource: "coach",
            refundPercent: "100",
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

/**
 * 支払い済み予約を生徒都合でキャンセルします。
 * 返金率はサーバー側で予約開始時刻から自動判定します。
 *
 * 24時間より前: 100%返金
 * 12時間より前〜24時間以内: 50%返金
 * 12時間以内: 返金なし
 */
exports.requestStudentCancellation = onCall(
  {secrets: [stripeSecretKey]},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "キャンセルにはログインが必要です。",
      );
    }

    const reservationId = String(
      request.data?.reservationId || "",
    ).trim();

    if (!reservationId) {
      throw new HttpsError(
        "invalid-argument",
        "予約IDがありません。",
      );
    }

    const uid = request.auth.uid;
    const db = getFirestore();
    const reservationRef = db
      .collection("reservations")
      .doc(reservationId);

    const prepared = await db.runTransaction(
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

        if (data.studentId !== uid) {
          throw new HttpsError(
            "permission-denied",
            "この予約はキャンセルできません。",
          );
        }

        if (data.status === "coach_cancelled") {
          throw new HttpsError(
            "failed-precondition",
            "この予約はコーチ都合でキャンセル済みです。",
          );
        }

        if (data.status === "student_cancelled") {
          const expectedRefundAmount = Number(
            data.cancellationRefundAmountExpected || 0,
          );
          const refundPercent = Number(
            data.cancellationRefundPercent || 0,
          );
          const shouldCreateRefund =
            expectedRefundAmount > 0 &&
            !data.stripeRefundId &&
            ["creating", "failed_to_create"].includes(
              String(data.refundStatus || ""),
            );

          return {
            ...data,
            alreadyCancelled: true,
            expectedRefundAmount,
            refundPercent,
            shouldCreateRefund,
          };
        }

        if (
          data.status !== "paid" ||
          data.paymentStatus !== "paid"
        ) {
          throw new HttpsError(
            "failed-precondition",
            "支払い済みの予約だけこのキャンセル処理を利用できます。",
          );
        }

        if (!data.stripePaymentIntentId) {
          throw new HttpsError(
            "failed-precondition",
            "決済情報を確認できませんでした。",
          );
        }

        const policy = studentCancellationPolicy(data);
        const amountPaid = Number(
          data.amountPaid ||
          data.totalPrice ||
          0,
        );

        if (
          !Number.isInteger(amountPaid) ||
          amountPaid <= 0
        ) {
          throw new HttpsError(
            "failed-precondition",
            "支払い金額を確認できませんでした。",
          );
        }

        const expectedRefundAmount = Math.floor(
          amountPaid * policy.refundPercent / 100,
        );
        const times = Array.isArray(data.times) ?
          data.times.map((time) => String(time)) :
          data.time ? [String(data.time)] : [];
        const dateId = String(data.date || "")
          .replaceAll("/", "-");
        const refundRequired = expectedRefundAmount > 0;

        transaction.set(
          reservationRef,
          {
            status: "student_cancelled",
            cancellationSource: "student",
            cancellationRefundPercent:
              policy.refundPercent,
            cancellationRefundAmountExpected:
              expectedRefundAmount,
            studentCancelledAt:
              FieldValue.serverTimestamp(),
            cancelledAt: FieldValue.serverTimestamp(),
            refundRequestedBy: uid,
            refundRequestedAt:
              refundRequired ?
                FieldValue.serverTimestamp() :
                FieldValue.delete(),
            refundStatus:
              refundRequired ?
                "creating" :
                "not_applicable",
            refundAmount:
              refundRequired ?
                FieldValue.delete() :
                0,
            paymentStatus:
              refundRequired ?
                "refund_processing" :
                "paid",
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );

        if (
          data.coachId &&
          dateId &&
          times.length > 0
        ) {
          const availabilityRef = db
            .collection("coachAvailability")
            .doc(data.coachId)
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

        if (data.coachId) {
          const notificationRef = db
            .collection("notifications")
            .doc(`student_cancel_${reservationId}`);

          let cancellationMessage =
            "生徒都合で予約がキャンセルされました。";

          if (policy.refundPercent === 100) {
            cancellationMessage +=
              "全額返金の手続きを開始しました。";
          } else if (policy.refundPercent === 50) {
            cancellationMessage +=
              "50%返金の手続きを開始しました。";
          } else {
            cancellationMessage +=
              "キャンセル規定により返金はありません。";
          }

          transaction.set(
            notificationRef,
            {
              recipientId: data.coachId,
              coachId: data.coachId,
              studentId: uid,
              reservationId,
              type: "studentCancellation",
              title: "生徒都合で予約がキャンセルされました",
              message: cancellationMessage,
              date: data.date || "",
              times,
              isRead: false,
              createdAt: FieldValue.serverTimestamp(),
            },
            {merge: true},
          );
        }

        return {
          ...data,
          alreadyCancelled: false,
          expectedRefundAmount,
          refundPercent: policy.refundPercent,
          shouldCreateRefund: refundRequired,
        };
      },
    );

    if (!prepared.shouldCreateRefund) {
      const storedRefundAmount = Number(
        prepared.refundAmount || 0,
      );
      const storedRefundStatus = String(
        prepared.refundStatus ||
        (
          prepared.expectedRefundAmount > 0 ?
            "pending" :
            "not_applicable"
        ),
      );

      return {
        cancelled: true,
        alreadyCancelled: Boolean(
          prepared.alreadyCancelled,
        ),
        reservationId,
        refundPercent: Number(
          prepared.refundPercent || 0,
        ),
        refundAmount: storedRefundAmount,
        refundStatus: storedRefundStatus,
        refundId: String(
          prepared.stripeRefundId || "",
        ),
      };
    }

    const stripe = new Stripe(stripeSecretKey.value());
    let refund;

    try {
      refund = await stripe.refunds.create(
        {
          payment_intent:
            prepared.stripePaymentIntentId,
          amount: prepared.expectedRefundAmount,
          metadata: {
            reservationId,
            coachId: prepared.coachId || "",
            studentId: uid,
            cancellationSource: "student",
            refundPercent: String(
              prepared.refundPercent,
            ),
          },
        },
        {
          idempotencyKey:
            `student_refund_${reservationId}`,
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

      logger.error(
        "生徒都合キャンセルの返金作成に失敗しました。",
        {
          reservationId,
          studentId: uid,
          message: error.message,
        },
      );

      throw new HttpsError(
        "internal",
        "予約はキャンセルされましたが、返金処理を開始できませんでした。",
      );
    }

    await markReservationRefund(
      refund,
      `callable_student_cancel_${reservationId}`,
    );

    logger.info("生徒都合キャンセルを受け付けました。", {
      reservationId,
      studentId: uid,
      coachId: prepared.coachId || "",
      refundPercent: prepared.refundPercent,
      refundAmount: Number(refund.amount || 0),
      refundStatus: refund.status,
    });

    return {
      cancelled: true,
      alreadyCancelled: Boolean(
        prepared.alreadyCancelled,
      ),
      reservationId,
      refundPercent: Number(
        prepared.refundPercent || 0,
      ),
      refundAmount: Number(refund.amount || 0),
      refundStatus: String(
        refund.status || "pending",
      ),
      refundId: refund.id,
    };
  },
);

/**
 * Stripe Connectの連結アカウントIDから、
 * Tennis Connect側のコーチConnectドキュメントを取得します。
 *
 * @param {FirebaseFirestore.Firestore} db Firestore
 * @param {string} stripeAccountId Stripe Connected Account ID
 * @return {Promise<object|null>} Connect情報
 */
async function findCoachConnectByStripeAccountId(
  db,
  stripeAccountId,
) {
  if (!stripeAccountId) {
    return null;
  }

  const snapshot = await db
    .collection("stripeConnectAccounts")
    .where("stripeAccountId", "==", stripeAccountId)
    .limit(1)
    .get();

  if (snapshot.empty) {
    return null;
  }

  const document = snapshot.docs[0];

  return {
    uid: document.id,
    ref: document.ref,
    data: document.data() || {},
  };
}

/**
 * payoutオブジェクトからTennis Connect側の
 * payoutRequestを特定します。
 *
 * Stripe Payout作成時にmetadataへpayoutRequestIdを
 * 保存しているため、それを最優先で使います。
 *
 * @param {FirebaseFirestore.DocumentReference} connectRef Connect参照
 * @param {object} payout Stripe Payout
 * @return {Promise<object|null>} payoutRequest情報
 */
async function findCoachPayoutRequestForWebhook(
  connectRef,
  payout,
) {
  const metadataRequestId = String(
    payout.metadata?.payoutRequestId || "",
  ).trim();

  if (metadataRequestId) {
    const requestRef = connectRef
      .collection("payoutRequests")
      .doc(metadataRequestId);
    const requestSnap = await requestRef.get();

    if (requestSnap.exists) {
      return {
        id: requestSnap.id,
        ref: requestRef,
        data: requestSnap.data() || {},
      };
    }
  }

  const payoutId = String(payout.id || "").trim();

  if (!payoutId) {
    return null;
  }

  const snapshot = await connectRef
    .collection("payoutRequests")
    .where("stripePayoutId", "==", payoutId)
    .limit(1)
    .get();

  if (snapshot.empty) {
    return null;
  }

  const document = snapshot.docs[0];

  return {
    id: document.id,
    ref: document.ref,
    data: document.data() || {},
  };
}

/**
 * Stripe ConnectのPayoutイベントを
 * Firestoreの出金状態へ反映します。
 *
 * payout.created / payout.updated / payout.paid / payout.failed
 * すべてでPayoutオブジェクトのstatusを基準に処理します。
 *
 * @param {object} event Stripe Event
 * @return {Promise<void>}
 */
async function handleCoachPayoutWebhookEvent(event) {
  const db = getFirestore();
  const payout = event.data?.object || {};
  const stripeAccountId = String(
    event.account || "",
  ).trim();
  const payoutId = String(payout.id || "").trim();
  const payoutStatus = String(
    payout.status || "",
  ).trim();

  if (!stripeAccountId || !payoutId) {
    logger.warn(
      "Connect Payoutイベントに必要な情報がありません。",
      {
        eventId: event.id,
        eventType: event.type,
        stripeAccountId,
        payoutId,
      },
    );
    return;
  }

  const connect = await findCoachConnectByStripeAccountId(
    db,
    stripeAccountId,
  );

  if (!connect) {
    // Tennis Connectと紐付いていないテスト用Connectアカウント等の
    // イベントはエラーにせず無視します。
    logger.info(
      "Tennis Connect未登録のConnected Accountイベントです。",
      {
        eventId: event.id,
        eventType: event.type,
        stripeAccountId,
        payoutId,
      },
    );
    return;
  }

  const payoutRequest =
    await findCoachPayoutRequestForWebhook(
      connect.ref,
      payout,
    );

  if (!payoutRequest) {
    logger.warn(
      "Payoutに対応するpayoutRequestが見つかりません。",
      {
        uid: connect.uid,
        eventId: event.id,
        eventType: event.type,
        stripeAccountId,
        payoutId,
        payoutStatus,
      },
    );
    return;
  }

  const reservationIds = Array.isArray(
    payoutRequest.data.reservationIds,
  ) ?
    payoutRequest.data.reservationIds :
    [];

  const commonPayoutUpdate = {
    stripePayoutId: payoutId,
    stripePayoutStatus: payoutStatus,
    lastStripePayoutEventId: event.id,
    lastStripePayoutEventType: event.type,
    lastStripePayoutEventCreated:
      Number(event.created || 0),
    updatedAt: FieldValue.serverTimestamp(),
  };

  if (payoutStatus === "paid") {
    await payoutRequest.ref.set(
      {
        ...commonPayoutUpdate,
        status: "paid",
        paidAt: FieldValue.serverTimestamp(),
        failureCode: FieldValue.delete(),
        failureMessage: FieldValue.delete(),
        errorMessage: FieldValue.delete(),
      },
      {merge: true},
    );

    await updateReservationsForCoachPayout(
      db,
      reservationIds,
      {
        coachPayoutStatus: "paid",
        coachPayoutPaidAt: FieldValue.serverTimestamp(),
        coachStripePayoutId: payoutId,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );

    const latestConnectSnap = await connect.ref.get();
    const latestConnectData =
      latestConnectSnap.data() || {};
    const activeRequestId = String(
      latestConnectData.activePayoutRequestId || "",
    ).trim();
    const retryRequestId = String(
      latestConnectData.retryPayoutRequestId || "",
    ).trim();

    const connectUpdate = {
      lastPayoutPaidAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    };

    if (activeRequestId === payoutRequest.id) {
      connectUpdate.activePayoutRequestId =
        FieldValue.delete();
    }

    if (retryRequestId === payoutRequest.id) {
      connectUpdate.retryPayoutRequestId =
        FieldValue.delete();
    }

    await connect.ref.set(
      connectUpdate,
      {merge: true},
    );

    logger.info(
      "コーチの銀行出金が完了しました。",
      {
        uid: connect.uid,
        payoutRequestId: payoutRequest.id,
        stripePayoutId: payoutId,
        amount: Number(payout.amount || 0),
        currency: String(payout.currency || ""),
      },
    );

    return;
  }

  if (
    payoutStatus === "failed" ||
    payoutStatus === "canceled"
  ) {
    const failureCode = String(
      payout.failure_code || "",
    );
    const failureMessage = String(
      payout.failure_message || "",
    );

    await payoutRequest.ref.set(
      {
        ...commonPayoutUpdate,
        status: "payout_failed",
        failedAt: FieldValue.serverTimestamp(),
        failureCode,
        failureMessage,
      },
      {merge: true},
    );

    await updateReservationsForCoachPayout(
      db,
      reservationIds,
      {
        coachPayoutStatus: "payout_failed",
        coachStripePayoutId: payoutId,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );

    await connect.ref.set(
      {
        activePayoutRequestId: FieldValue.delete(),
        retryPayoutRequestId: payoutRequest.id,
        lastPayoutFailedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    logger.error(
      "コーチの銀行出金が失敗しました。",
      {
        uid: connect.uid,
        payoutRequestId: payoutRequest.id,
        stripePayoutId: payoutId,
        failureCode,
        failureMessage,
      },
    );

    return;
  }

  // pending / in_transit などは「出金処理中」として保持します。
  await payoutRequest.ref.set(
    {
      ...commonPayoutUpdate,
      status: "payout_pending",
    },
    {merge: true},
  );

  await updateReservationsForCoachPayout(
    db,
    reservationIds,
    {
      coachPayoutStatus: "payout_pending",
      coachStripePayoutId: payoutId,
      updatedAt: FieldValue.serverTimestamp(),
    },
  );

  await connect.ref.set(
    {
      activePayoutRequestId: payoutRequest.id,
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );

  logger.info(
    "コーチの銀行出金は処理中です。",
    {
      uid: connect.uid,
      payoutRequestId: payoutRequest.id,
      stripePayoutId: payoutId,
      payoutStatus,
    },
  );
}

/**
 * Stripe Connect専用Payout Webhook。
 *
 * Stripe Dashboardでは必ず
 * 「Events on Connected accounts / 連結アカウントのイベント」
 * として登録します。
 *
 * 対象:
 * - payout.created
 * - payout.updated
 * - payout.paid
 * - payout.failed
 */
exports.stripeConnectPayoutWebhook = onRequest(
  {
    secrets: [
      stripeSecretKey,
      stripeConnectWebhookSecret,
    ],
    invoker: "public",
  },
  async (request, response) => {
    if (request.method !== "POST") {
      response.status(405).send("Method Not Allowed");
      return;
    }

    const signature =
      request.headers["stripe-signature"];

    if (typeof signature !== "string") {
      response
        .status(400)
        .send("Stripe signature is missing");
      return;
    }

    const stripe = new Stripe(
      stripeSecretKey.value(),
    );
    let event;

    try {
      event = stripe.webhooks.constructEvent(
        request.rawBody,
        signature,
        stripeConnectWebhookSecret.value(),
      );
    } catch (error) {
      logger.error(
        "Stripe Connect Webhookの署名確認に失敗しました。",
        {
          message: error?.message || String(error),
        },
      );

      response
        .status(400)
        .send("Webhook signature failed");
      return;
    }

    try {
      const supportedTypes = new Set([
        "payout.created",
        "payout.updated",
        "payout.paid",
        "payout.failed",
      ]);

      if (supportedTypes.has(event.type)) {
        await handleCoachPayoutWebhookEvent(event);
      } else {
        logger.info(
          "未処理のStripe Connectイベントです。",
          {
            eventId: event.id,
            type: event.type,
            account: event.account || "",
          },
        );
      }

      // Webhook受信履歴を残します。
      await getFirestore()
        .collection("stripeConnectWebhookEvents")
        .doc(event.id)
        .set(
          {
            type: event.type,
            stripeAccountId:
              String(event.account || ""),
            objectId:
              String(event.data?.object?.id || ""),
            livemode: Boolean(event.livemode),
            processedAt:
              FieldValue.serverTimestamp(),
          },
          {merge: true},
        );

      response
        .status(200)
        .json({received: true});
    } catch (error) {
      logger.error(
        "Stripe Connect Payout Webhookの処理に失敗しました。",
        {
          eventId: event?.id || "",
          type: event?.type || "",
          account: event?.account || "",
          message: error?.message || String(error),
        },
      );

      response
        .status(500)
        .send("Webhook handling failed");
    }
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
 * 予約情報からレッスン開始日時を取得します。
 * 予約日時は日本時間として扱います。
 *
 * @param {object} reservation 予約データ
 * @return {Date|null} レッスン開始日時
 */
function lessonStartDateFromReservation(reservation) {
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

  const sortedTimes = [...rawTimes]
    .map((time) => String(time || "").replaceAll("~", "〜"))
    .sort();
  const firstSlot = sortedTimes[0] || "";
  const startTime = firstSlot.split("〜")[0]?.trim() || "";

  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(startTime)) {
    return null;
  }

  const parsed = new Date(`${rawDate}T${startTime}:00+09:00`);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

/**
 * 生徒都合キャンセルの返金率を決定します。
 * 24時間より前は100%、12時間より前は50%、
 * 12時間以内は返金なしです。
 *
 * @param {object} reservation 予約データ
 * @param {Date} now 現在日時
 * @return {{lessonStartDate: Date, refundPercent: number}}
 */
function studentCancellationPolicy(
  reservation,
  now = new Date(),
) {
  const lessonStartDate =
    lessonStartDateFromReservation(reservation);

  if (!lessonStartDate) {
    throw new HttpsError(
      "failed-precondition",
      "予約日時を確認できませんでした。",
    );
  }

  const millisecondsUntilLesson =
    lessonStartDate.getTime() - now.getTime();

  if (millisecondsUntilLesson <= 0) {
    throw new HttpsError(
      "failed-precondition",
      "レッスン開始後はキャンセルできません。",
    );
  }

  const twelveHours = 12 * 60 * 60 * 1000;
  const twentyFourHours = 24 * 60 * 60 * 1000;
  let refundPercent = 0;

  if (millisecondsUntilLesson > twentyFourHours) {
    refundPercent = 100;
  } else if (millisecondsUntilLesson > twelveHours) {
    refundPercent = 50;
  }

  return {
    lessonStartDate,
    refundPercent,
  };
}

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
 * 予約1件について、Tennis Connect手数料10%と
 * コーチ受取額90%を計算します。
 *
 * 完了済み返金だけを売上から差し引きます。
 * 返金処理中・返金失敗中は出金可能にしません。
 *
 * @param {object} reservation 予約データ
 * @param {Date} now 現在日時
 * @return {object} ウォレット計算結果
 */
function coachWalletAmountsForReservation(
  reservation,
  now = new Date(),
) {
  const status = String(reservation.status || "");
  const paymentStatus = String(
    reservation.paymentStatus || "",
  );
  const refundStatus = String(
    reservation.refundStatus || "",
  );

  const originalAmount = Math.max(
    0,
    Math.floor(
      Number(
        reservation.amountPaid ||
        reservation.totalPrice ||
        0,
      ),
    ),
  );

  const result = {
    originalAmount,
    refundAmount: 0,
    netPaidAmount: 0,
    platformFeeAmount: 0,
    coachAmount: 0,
    payoutAvailableAt: null,
    state: "not_eligible",
    reason: "",
  };

  if (originalAmount <= 0) {
    result.reason = "支払い金額がありません。";
    return result;
  }

  const hasPaidRecord =
    ["paid", "partially_refunded", "refunded"].includes(
      paymentStatus,
    ) ||
    (
      paymentStatus === "" &&
      status === "paid"
    );

  if (!hasPaidRecord) {
    result.reason = "支払い完了前です。";
    return result;
  }

  if (status === "coach_cancelled") {
    result.reason = "コーチ都合キャンセルのため売上対象外です。";
    return result;
  }

  const refundIsUnresolved =
    ["refund_processing", "refund_failed"].includes(
      paymentStatus,
    ) ||
    [
      "creating",
      "pending",
      "requires_action",
      "failed",
      "canceled",
      "failed_to_create",
    ].includes(refundStatus);

  if (refundIsUnresolved) {
    result.state = "pending";
    result.reason = "返金処理の確定待ちです。";
    return result;
  }

  const refundSucceeded =
    refundStatus === "succeeded" ||
    ["partially_refunded", "refunded"].includes(
      paymentStatus,
    );

  let completedRefundAmount = 0;

  if (refundSucceeded) {
    completedRefundAmount = Math.max(
      0,
      Math.floor(Number(reservation.refundAmount || 0)),
    );

    if (
      paymentStatus === "refunded" &&
      completedRefundAmount <= 0
    ) {
      completedRefundAmount = originalAmount;
    }

    completedRefundAmount = Math.min(
      completedRefundAmount,
      originalAmount,
    );
  }

  const netPaidAmount = Math.max(
    0,
    originalAmount - completedRefundAmount,
  );

  if (netPaidAmount <= 0) {
    result.refundAmount = completedRefundAmount;
    result.reason = "全額返金済みです。";
    return result;
  }

  const coachAmount = Math.floor(
    netPaidAmount * COACH_SHARE_PERCENT / 100,
  );
  const platformFeeAmount =
    netPaidAmount - coachAmount;

  result.refundAmount = completedRefundAmount;
  result.netPaidAmount = netPaidAmount;
  result.platformFeeAmount = platformFeeAmount;
  result.coachAmount = coachAmount;

  const lessonEndDate =
    lessonEndDateFromReservation(reservation);

  if (!lessonEndDate) {
    result.state = "pending";
    result.reason = "レッスン終了日時を確認できません。";
    return result;
  }

  const payoutAvailableAt = new Date(
    lessonEndDate.getTime() +
    COACH_PAYOUT_HOLD_HOURS * 60 * 60 * 1000,
  );

  result.payoutAvailableAt = payoutAvailableAt;

  if (now < payoutAvailableAt) {
    result.state = "pending";
    result.reason =
      `レッスン終了${COACH_PAYOUT_HOLD_HOURS}時間後に` +
      "出金可能になります。";
    return result;
  }

  result.state = "available";
  result.reason = "";
  return result;
}

/**
 * payout requestに紐づく予約をまとめて更新します。
 *
 * @param {FirebaseFirestore.Firestore} db Firestore
 * @param {Array<string>} reservationIds 予約ID
 * @param {object} values 更新内容
 * @return {Promise<void>}
 */
async function updateReservationsForCoachPayout(
  db,
  reservationIds,
  values,
) {
  const chunks = [];

  for (let index = 0; index < reservationIds.length; index += 400) {
    chunks.push(reservationIds.slice(index, index + 400));
  }

  for (const chunk of chunks) {
    const batch = db.batch();

    for (const reservationId of chunk) {
      batch.set(
        db.collection("reservations").doc(reservationId),
        values,
        {merge: true},
      );
    }

    await batch.commit();
  }
}

/**
 * Connected Accountの銀行出金をmanualにします。
 * Tennis Connectの「出金する」操作をした時だけ銀行送金されるようにします。
 *
 * @param {string} stripeAccountId Connected Account ID
 * @return {Promise<void>}
 */
async function ensureManualPayoutSchedule(stripeAccountId) {
  const body = new URLSearchParams();
  body.set(
    "payments[payouts][schedule][interval]",
    "manual",
  );

  const response = await fetch(
    "https://api.stripe.com/v1/balance_settings",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${stripeSecretKey.value()}`,
        "Stripe-Account": stripeAccountId,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body,
      signal: AbortSignal.timeout(15000),
    },
  );

  if (response.ok) {
    return;
  }

  const rawBody = await response.text();
  let parsed = {};

  try {
    parsed = JSON.parse(rawBody);
  } catch (_) {
    // JSONではない場合はrawBodyをそのまま使用します。
  }

  const error = new Error(
    parsed?.error?.message ||
    "銀行口座への出金スケジュールを設定できませんでした。",
  );
  error.code = parsed?.error?.code || "";
  error.statusCode = response.status;
  throw error;
}

/**
 * Stripe残高から指定通貨のavailable金額を取得します。
 *
 * @param {object} balance Stripe Balance
 * @param {string} currency 通貨
 * @return {number} available残高
 */
function availableBalanceAmount(balance, currency) {
  const target = String(currency || "").toLowerCase();

  return (balance.available || []).reduce(
    (total, item) => {
      if (
        String(item.currency || "").toLowerCase() === target
      ) {
        return total + Number(item.amount || 0);
      }

      return total;
    },
    0,
  );
}

/**
 * Transfer済みだが銀行Payoutまで完了していない
 * payoutRequestを探します。
 *
 * 途中でFunctionが失敗しても、Transferを二重実行せず
 * 続きのPayoutだけ再開するために使います。
 *
 * @param {FirebaseFirestore.DocumentReference} connectRef Connect参照
 * @return {Promise<object|null>} 回復対象
 */
async function findRecoverableCoachPayoutRequest(connectRef) {
  const snapshot = await connectRef
    .collection("payoutRequests")
    .get();

  const recoverableStatuses = new Set([
    "transfer_succeeded",
    "waiting_for_stripe_balance",
    "payout_failed",
  ]);

  const candidates = snapshot.docs
    .map((document) => {
      const data = document.data() || {};
      const createdAtMillis =
        data.createdAt?.toMillis?.() ||
        data.updatedAt?.toMillis?.() ||
        0;

      return {
        id: document.id,
        data,
        createdAtMillis,
      };
    })
    .filter((item) => {
      const status = String(item.data.status || "");
      const transferId = String(
        item.data.stripeTransferId || "",
      ).trim();
      const amount = Number(item.data.amount || 0);

      return (
        recoverableStatuses.has(status) &&
        transferId &&
        amount > 0
      );
    })
    .sort(
      (first, second) =>
        second.createdAtMillis - first.createdAtMillis,
    );

  return candidates[0] || null;
}

/**
 * 進行中のpayoutをStripeから再確認し、
 * paid / failed をFirestoreへ反映します。
 *
 * @param {string} uid コーチUID
 * @param {FirebaseFirestore.DocumentReference} connectRef Connect参照
 * @param {object} connectData Connectデータ
 * @param {Stripe} stripe Stripeクライアント
 * @param {FirebaseFirestore.Firestore} db Firestore
 * @return {Promise<void>}
 */
async function reconcileActiveCoachPayout(
  uid,
  connectRef,
  connectData,
  stripe,
  db,
) {
  const activeRequestId = String(
    connectData.activePayoutRequestId || "",
  ).trim();

  if (!activeRequestId) {
    return;
  }

  const payoutRef = connectRef
    .collection("payoutRequests")
    .doc(activeRequestId);
  const payoutSnap = await payoutRef.get();

  if (!payoutSnap.exists) {
    await connectRef.set(
      {
        activePayoutRequestId: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    return;
  }

  const payoutData = payoutSnap.data() || {};
  const payoutId = String(payoutData.stripePayoutId || "").trim();
  const stripeAccountId = String(
    connectData.stripeAccountId || "",
  ).trim();

  if (!payoutId || !stripeAccountId) {
    return;
  }

  let payout;

  try {
    payout = await stripe.payouts.retrieve(
      payoutId,
      {
        stripeAccount: stripeAccountId,
      },
    );
  } catch (error) {
    logger.warn("Stripe Payout状態を取得できませんでした。", {
      uid,
      payoutRequestId: activeRequestId,
      stripePayoutId: payoutId,
      stripeErrorMessage: error?.message || String(error),
      stripeErrorCode: error?.code || "",
    });
    return;
  }

  const reservationIds = Array.isArray(
    payoutData.reservationIds,
  ) ?
    payoutData.reservationIds :
    [];

  if (payout.status === "paid") {
    await payoutRef.set(
      {
        status: "paid",
        paidAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    await updateReservationsForCoachPayout(
      db,
      reservationIds,
      {
        coachPayoutStatus: "paid",
        coachPayoutPaidAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
    );

    await connectRef.set(
      {
        activePayoutRequestId: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    return;
  }

  if (["failed", "canceled"].includes(payout.status)) {
    await payoutRef.set(
      {
        status: "payout_failed",
        stripePayoutStatus: payout.status,
        failureCode: payout.failure_code || "",
        failureMessage: payout.failure_message || "",
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    await updateReservationsForCoachPayout(
      db,
      reservationIds,
      {
        coachPayoutStatus: "payout_failed",
        updatedAt: FieldValue.serverTimestamp(),
      },
    );

    await connectRef.set(
      {
        activePayoutRequestId: FieldValue.delete(),
        retryPayoutRequestId: activeRequestId,
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  }
}

/**
 * コーチ本人向けの売上残高サマリーを返します。
 *
 * 手数料10%、コーチ受取90%、レッスン終了24時間後という
 * 出金条件に加え、出金処理中・出金済みの金額も返します。
 */
exports.getCoachWalletSummary = onCall(
  {secrets: [stripeSecretKey]},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "売上残高の確認にはログインが必要です。",
      );
    }

    const uid = request.auth.uid;
    const db = getFirestore();
    const connectRef = db
      .collection("stripeConnectAccounts")
      .doc(uid);
    const connectSnap = await connectRef.get();
    const connectData = connectSnap.data() || {};

    if (connectSnap.exists && connectData.stripeAccountId) {
      try {
        const stripe = new Stripe(stripeSecretKey.value(), {
          maxNetworkRetries: 1,
          timeout: 15000,
        });

        await reconcileActiveCoachPayout(
          uid,
          connectRef,
          connectData,
          stripe,
          db,
        );
      } catch (error) {
        logger.warn("出金状態の再確認に失敗しました。", {
          uid,
          stripeErrorMessage: error?.message || String(error),
          stripeErrorCode: error?.code || "",
        });
      }
    }

    let refreshedConnectSnap = await connectRef.get();
    let refreshedConnectData =
      refreshedConnectSnap.data() || {};
    let retryPayoutRequestId = String(
      refreshedConnectData.retryPayoutRequestId || "",
    ).trim();

    if (!retryPayoutRequestId) {
      const recoverable =
        await findRecoverableCoachPayoutRequest(connectRef);

      if (recoverable) {
        retryPayoutRequestId = recoverable.id;

        await connectRef.set(
          {
            retryPayoutRequestId,
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );

        refreshedConnectSnap = await connectRef.get();
        refreshedConnectData =
          refreshedConnectSnap.data() || {};
      }
    }

    let retryablePayoutAmount = 0;
    let retryablePayoutCount = 0;

    if (retryPayoutRequestId) {
      const retrySnap = await connectRef
        .collection("payoutRequests")
        .doc(retryPayoutRequestId)
        .get();

      if (retrySnap.exists) {
        const retryData = retrySnap.data() || {};
        const retryStatus = String(retryData.status || "");

        if (
          [
            "transfer_succeeded",
            "waiting_for_stripe_balance",
            "payout_failed",
          ].includes(retryStatus)
        ) {
          retryablePayoutAmount =
            Number(retryData.amount || 0);
          retryablePayoutCount =
            Array.isArray(retryData.reservationIds) ?
              retryData.reservationIds.length :
              0;
        }
      }
    }

    const snapshot = await db
      .collection("reservations")
      .where("coachId", "==", uid)
      .get();

    const now = new Date();
    let pendingAmount = 0;
    let availableAmount = retryablePayoutAmount;
    let processingAmount = 0;
    let paidOutAmount = 0;
    let totalCoachEarnings = 0;
    let totalPlatformFee = 0;
    let pendingCount = 0;
    let availableCount = retryablePayoutCount;
    let processingCount = 0;
    let nextAvailableAt = null;

    for (const document of snapshot.docs) {
      const data = document.data();
      const wallet = coachWalletAmountsForReservation(
        data,
        now,
      );

      if (wallet.coachAmount <= 0) {
        continue;
      }

      totalCoachEarnings += wallet.coachAmount;
      totalPlatformFee += wallet.platformFeeAmount;

      const coachPayoutStatus = String(
        data.coachPayoutStatus || "",
      );
      const coachPayoutRequestId = String(
        data.coachPayoutRequestId || "",
      ).trim();

      if (coachPayoutStatus === "paid") {
        paidOutAmount += Number(
          data.coachPayoutAmount || wallet.coachAmount,
        );
        continue;
      }

      if (
        coachPayoutRequestId &&
        coachPayoutRequestId === retryPayoutRequestId
      ) {
        // retryablePayoutAmountとして上でまとめて加算済みです。
        continue;
      }

      if (
        [
          "claimed",
          "transferred",
          "payout_pending",
        ].includes(coachPayoutStatus)
      ) {
        processingAmount += Number(
          data.coachPayoutAmount || wallet.coachAmount,
        );
        processingCount += 1;
        continue;
      }

      if (coachPayoutStatus === "payout_failed") {
        // retryPayoutRequestIdの金額として上で加算するため、
        // ここでは二重計上しません。
        continue;
      }

      if (wallet.state === "available") {
        availableAmount += wallet.coachAmount;
        availableCount += 1;
        continue;
      }

      if (wallet.state === "pending") {
        pendingAmount += wallet.coachAmount;
        pendingCount += 1;

        if (
          wallet.payoutAvailableAt &&
          (
            !nextAvailableAt ||
            wallet.payoutAvailableAt < nextAvailableAt
          )
        ) {
          nextAvailableAt = wallet.payoutAvailableAt;
        }
      }
    }

    return {
      currency: "jpy",
      platformFeePercent: PLATFORM_FEE_PERCENT,
      coachSharePercent: COACH_SHARE_PERCENT,
      payoutHoldHours: COACH_PAYOUT_HOLD_HOURS,
      pendingAmount,
      availableAmount,
      processingAmount,
      paidOutAmount,
      totalCoachEarnings,
      totalPlatformFee,
      pendingCount,
      availableCount,
      processingCount,
      nextAvailableAtMillis:
        nextAvailableAt ?
          nextAvailableAt.getTime() :
          null,
    };
  },
);

/**
 * コーチが「銀行口座へ出金する」を押した時の処理です。
 *
 * 新規の出金では、
 * 1. Tennis ConnectのStripe残高 -> Connected AccountへTransfer
 * 2. Connected Account -> 登録済み銀行口座へPayout
 *
 * の順で実行します。
 *
 * Payoutだけ失敗した場合はTransferをやり直さず、
 * 次回の出金操作で同じ残高からPayoutだけ再試行します。
 */
exports.requestCoachPayout = onCall(
  {
    secrets: [stripeSecretKey],
    invoker: "public",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "出金にはログインが必要です。",
      );
    }

    const uid = request.auth.uid;
    const db = getFirestore();
    const connectRef = db
      .collection("stripeConnectAccounts")
      .doc(uid);

    const lockTimeoutMillis = 5 * 60 * 1000;

    await db.runTransaction(async (transaction) => {
      const snap = await transaction.get(connectRef);

      if (!snap.exists) {
        throw new HttpsError(
          "failed-precondition",
          "先に売上受取設定を完了してください。",
        );
      }

      const data = snap.data() || {};
      const locked = Boolean(data.payoutInProgress);
      const lockAt = data.payoutLockAt?.toDate?.();
      const lockIsFresh =
        lockAt &&
        Date.now() - lockAt.getTime() < lockTimeoutMillis;

      if (locked && lockIsFresh) {
        throw new HttpsError(
          "aborted",
          "すでに出金処理中です。少し待ってから更新してください。",
        );
      }

      transaction.set(
        connectRef,
        {
          payoutInProgress: true,
          payoutLockAt: new Date(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    });

    try {
      const connectSnap = await connectRef.get();
      const connectData = connectSnap.data() || {};
      const stripeAccountId = String(
        connectData.stripeAccountId || "",
      ).trim();

      if (!stripeAccountId) {
        throw new HttpsError(
          "failed-precondition",
          "Stripeの受取アカウントがありません。",
        );
      }

      const stripe = new Stripe(stripeSecretKey.value(), {
        maxNetworkRetries: 1,
        timeout: 15000,
      });
      const account = await stripe.accounts.retrieve(
        stripeAccountId,
      );
      const connectStatus =
        coachConnectStatusFromAccount(account);

      if (!connectStatus.readyForPayouts) {
        throw new HttpsError(
          "failed-precondition",
          "本人確認または銀行口座設定が完了していません。",
        );
      }

      await ensureManualPayoutSchedule(stripeAccountId);

      let retryRequestId = String(
        connectData.retryPayoutRequestId || "",
      ).trim();

      if (!retryRequestId) {
        const recoverable =
          await findRecoverableCoachPayoutRequest(connectRef);

        if (recoverable) {
          retryRequestId = recoverable.id;

          await connectRef.set(
            {
              retryPayoutRequestId: retryRequestId,
              updatedAt: FieldValue.serverTimestamp(),
            },
            {merge: true},
          );
        }
      }

      let payoutRef;
      let payoutRequestId;
      let reservationIds = [];
      let payoutAmount = 0;
      let transferId = "";

      if (retryRequestId) {
        payoutRequestId = retryRequestId;
        payoutRef = connectRef
          .collection("payoutRequests")
          .doc(payoutRequestId);

        const retrySnap = await payoutRef.get();

        if (!retrySnap.exists) {
          await connectRef.set(
            {
              retryPayoutRequestId: FieldValue.delete(),
              updatedAt: FieldValue.serverTimestamp(),
            },
            {merge: true},
          );
          throw new HttpsError(
            "failed-precondition",
            "再出金データを確認できませんでした。もう一度お試しください。",
          );
        }

        const retryData = retrySnap.data() || {};
        reservationIds = Array.isArray(
          retryData.reservationIds,
        ) ?
          retryData.reservationIds :
          [];
        payoutAmount = Number(retryData.amount || 0);
        transferId = String(
          retryData.stripeTransferId || "",
        );

        if (!transferId || payoutAmount <= 0) {
          throw new HttpsError(
            "failed-precondition",
            "再出金データが不完全です。",
          );
        }
      } else {
        const reservationSnapshot = await db
          .collection("reservations")
          .where("coachId", "==", uid)
          .get();

        const now = new Date();
        const eligible = [];

        for (const document of reservationSnapshot.docs) {
          const data = document.data();
          const wallet =
            coachWalletAmountsForReservation(data, now);
          const existingRequestId = String(
            data.coachPayoutRequestId || "",
          ).trim();
          const existingStatus = String(
            data.coachPayoutStatus || "",
          );

          if (
            wallet.state === "available" &&
            wallet.coachAmount > 0 &&
            !existingRequestId &&
            !existingStatus
          ) {
            eligible.push({
              id: document.id,
              amount: wallet.coachAmount,
            });
          }
        }

        payoutAmount = eligible.reduce(
          (total, item) => total + item.amount,
          0,
        );
        reservationIds = eligible.map((item) => item.id);

        if (payoutAmount <= 0 || reservationIds.length === 0) {
          throw new HttpsError(
            "failed-precondition",
            "現在、出金可能な売上はありません。",
          );
        }

        const platformBalance = await stripe.balance.retrieve();
        const platformAvailableJpy =
          availableBalanceAmount(platformBalance, "jpy");

        if (platformAvailableJpy < payoutAmount) {
          throw new HttpsError(
            "failed-precondition",
            "Stripe側で売上金がまだ利用可能残高になっていません。" +
            "時間をおいてからもう一度お試しください。",
          );
        }

        payoutRef = connectRef
          .collection("payoutRequests")
          .doc();
        payoutRequestId = payoutRef.id;

        await payoutRef.set({
          coachId: uid,
          amount: payoutAmount,
          currency: "jpy",
          reservationIds,
          status: "creating",
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });

        await updateReservationsForCoachPayout(
          db,
          reservationIds,
          {
            coachPayoutRequestId: payoutRequestId,
            coachPayoutStatus: "claimed",
            updatedAt: FieldValue.serverTimestamp(),
          },
        );

        try {
          const transfer = await stripe.transfers.create(
            {
              amount: payoutAmount,
              currency: "jpy",
              destination: stripeAccountId,
              description:
                "Tennis Connect coach earnings",
              metadata: {
                coachUid: uid,
                payoutRequestId,
              },
            },
            {
              idempotencyKey:
                `coach_payout_transfer_${payoutRequestId}`,
            },
          );

          transferId = transfer.id;

          await payoutRef.set(
            {
              status: "transfer_succeeded",
              stripeTransferId: transfer.id,
              transferredAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            },
            {merge: true},
          );

          await updateReservationsForCoachPayout(
            db,
            reservationIds,
            {
              coachPayoutStatus: "transferred",
              coachPayoutAmount: 0,
              coachStripeTransferId: transfer.id,
              updatedAt: FieldValue.serverTimestamp(),
            },
          );

          // 各予約の90%額を保存します。
          for (const reservationId of reservationIds) {
            const reservationRef = db
              .collection("reservations")
              .doc(reservationId);
            const reservationSnap = await reservationRef.get();

            if (!reservationSnap.exists) {
              continue;
            }

            const wallet = coachWalletAmountsForReservation(
              reservationSnap.data(),
              now,
            );

            await reservationRef.set(
              {
                coachPayoutAmount: wallet.coachAmount,
                updatedAt: FieldValue.serverTimestamp(),
              },
              {merge: true},
            );
          }
        } catch (error) {
          await payoutRef.set(
            {
              status: "transfer_failed",
              errorMessage: error?.message || String(error),
              updatedAt: FieldValue.serverTimestamp(),
            },
            {merge: true},
          );

          for (const reservationId of reservationIds) {
            await db
              .collection("reservations")
              .doc(reservationId)
              .set(
                {
                  coachPayoutRequestId: FieldValue.delete(),
                  coachPayoutStatus: FieldValue.delete(),
                  coachPayoutAmount: FieldValue.delete(),
                  updatedAt: FieldValue.serverTimestamp(),
                },
                {merge: true},
              );
          }

          throw error;
        }
      }

      const connectedBalance = await stripe.balance.retrieve(
        {},
        {
          stripeAccount: stripeAccountId,
        },
      );
      const connectedAvailableJpy =
        availableBalanceAmount(connectedBalance, "jpy");

      if (connectedAvailableJpy < payoutAmount) {
        await payoutRef.set(
          {
            status: "waiting_for_stripe_balance",
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );

        await connectRef.set(
          {
            retryPayoutRequestId: payoutRequestId,
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );

        await updateReservationsForCoachPayout(
          db,
          reservationIds,
          {
            coachPayoutStatus: "transferred",
            updatedAt: FieldValue.serverTimestamp(),
          },
        );

        return {
          success: true,
          status: "waiting_for_stripe_balance",
          amount: payoutAmount,
          message:
            "売上をStripeのコーチ残高へ移しました。" +
            "Stripe側で利用可能になり次第、銀行口座への出金を再実行できます。",
        };
      }

      try {
        const payout = await stripe.payouts.create(
          {
            amount: payoutAmount,
            currency: "jpy",
            method: "standard",
            description:
              "Tennis Connect coach payout",
            metadata: {
              coachUid: uid,
              payoutRequestId,
            },
          },
          {
            stripeAccount: stripeAccountId,
            idempotencyKey:
              `coach_bank_payout_${payoutRequestId}`,
          },
        );

        await payoutRef.set(
          {
            status: "payout_pending",
            stripePayoutId: payout.id,
            stripePayoutStatus: payout.status || "pending",
            payoutCreatedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );

        await updateReservationsForCoachPayout(
          db,
          reservationIds,
          {
            coachPayoutStatus: "payout_pending",
            coachStripePayoutId: payout.id,
            updatedAt: FieldValue.serverTimestamp(),
          },
        );

        await connectRef.set(
          {
            retryPayoutRequestId: FieldValue.delete(),
            activePayoutRequestId: payoutRequestId,
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );

        return {
          success: true,
          status: "payout_pending",
          amount: payoutAmount,
          message:
            "銀行口座への出金手続きを開始しました。",
        };
      } catch (error) {
        await payoutRef.set(
          {
            status: "payout_failed",
            errorMessage: error?.message || String(error),
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );

        await connectRef.set(
          {
            retryPayoutRequestId: payoutRequestId,
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );

        await updateReservationsForCoachPayout(
          db,
          reservationIds,
          {
            coachPayoutStatus: "payout_failed",
            updatedAt: FieldValue.serverTimestamp(),
          },
        );

        throw error;
      }
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error("コーチ出金処理に失敗しました。", {
        uid,
        stripeErrorMessage: error?.message || String(error),
        stripeErrorCode: error?.code || "",
        stripeErrorType: error?.type || "",
        stripeErrorParam: error?.param || "",
        stripeErrorStatusCode: error?.statusCode || "",
      });

      throw new HttpsError(
        "internal",
        "出金処理を開始できませんでした。",
      );
    } finally {
      await connectRef.set(
        {
          payoutInProgress: false,
          payoutLockAt: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    }
  },
);

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

  if (
    [
      "coach_cancelled",
      "student_cancelled",
      "cancelled",
      "canceled",
    ].includes(status)
  ) {
    return "";
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
