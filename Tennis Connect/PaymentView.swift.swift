import SwiftUI
import FirebaseFirestore
import FirebaseFunctions

private enum PaymentUI {
    static let brandGreen = Color(
        red: 42 / 255,
        green: 174 / 255,
        blue: 102 / 255
    )

    static let softGreen = Color(
        red: 232 / 255,
        green: 245 / 255,
        blue: 236 / 255
    )

    static let background = Color(
        red: 248 / 255,
        green: 250 / 255,
        blue: 249 / 255
    )

    static let textPrimary = Color(
        red: 34 / 255,
        green: 34 / 255,
        blue: 34 / 255
    )

    static let textSecondary = Color(
        red: 102 / 255,
        green: 110 / 255,
        blue: 105 / 255
    )

    static let border = Color.black.opacity(0.08)
}

struct PaymentView: View {
    let reservationId: String
    let coach: Coach
    let date: Date
    let times: [String]
    let totalPrice: Int

    @Environment(\.openURL) private var openURL

    @State private var showComplete = false
    @State private var isPaying = false
    @State private var errorMessage = ""
    @State private var paymentListener: ListenerRegistration?

    @State private var courtName = ""
    @State private var courtAddress = ""
    @State private var legacyCourt = ""
    @State private var isLoadingReservationDetails = true

    @State private var latestCoachImageURL = ""

    private let db = Firestore.firestore()
    private let functions = Functions.functions(
        region: "asia-northeast1"
    )

    private var lessonLocationTitle: String {
        let trimmedName =
            courtName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if !trimmedName.isEmpty {
            return trimmedName
        }

        let trimmedLegacy =
            legacyCourt.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if !trimmedLegacy.isEmpty {
            return trimmedLegacy
        }

        return "場所未登録"
    }

    private var lessonLocationAddress: String {
        courtAddress.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private var effectiveCoachImageURL: String {
        let latest =
            latestCoachImageURL.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if !latest.isEmpty {
            return latest
        }

        return coach.imageURL.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    var body: some View {
        ZStack {
            PaymentUI.background
                .ignoresSafeArea()

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 18
                ) {
                    headerSection

                    coachCard

                    lessonInformationCard

                    paymentSummaryCard

                    stripeSecurityCard

                    if !errorMessage.isEmpty {
                        errorCard
                    }

                    Color.clear
                        .frame(height: 96)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
        }
        .tint(PaymentUI.brandGreen)
        .navigationTitle("お支払い")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            paymentActionArea
        }
        .onAppear {
            startPaymentListener()
            loadLatestCoachImage()
        }
        .onDisappear {
            stopPaymentListener()
        }
        .navigationDestination(
            isPresented: $showComplete
        ) {
            BookingCompleteView(
                coach: coach,
                date: date,
                times: times,
                totalPrice: totalPrice
            )
        }
    }

    private var headerSection: some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            Text("レッスン料金のお支払い")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(
                    PaymentUI.textPrimary
                )

            Text(
                "予約内容と金額を確認して、Stripeの決済画面へ進みます"
            )
            .font(.subheadline)
            .foregroundStyle(
                PaymentUI.textSecondary
            )
        }
    }

    private var coachCard: some View {
        HStack(spacing: 14) {
            PaymentCoachAvatarView(
                imageURL: effectiveCoachImageURL,
                size: 60
            )

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Text("担当コーチ")
                    .font(.caption)
                    .foregroundStyle(
                        PaymentUI.textSecondary
                    )

                Text(coach.name)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        PaymentUI.textPrimary
                    )
                    .lineLimit(1)

                if !coach.area.isEmpty {
                    Label(
                        coach.area,
                        systemImage:
                            "mappin.and.ellipse"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        PaymentUI.textSecondary
                    )
                }
            }

            Spacer()

            Image(
                systemName:
                    "checkmark.seal.fill"
            )
            .font(.system(size: 20))
            .foregroundStyle(
                PaymentUI.brandGreen
            )
        }
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                PaymentUI.border,
                lineWidth: 1
            )
        }
    }

    private var lessonInformationCard: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            sectionTitle(
                "レッスン内容",
                systemImage: "calendar"
            )

            paymentDetailRow(
                title: "日付",
                value: displayDate(date),
                icon: "calendar"
            )

            Divider()

            paymentDetailRow(
                title: "時間",
                value:
                    combinedTimeRange(times),
                icon: "clock"
            )

            Divider()

            paymentDetailRow(
                title: "レッスン時間",
                value:
                    "\(max(times.count, 1))時間",
                icon: "hourglass"
            )

            Divider()

            VStack(
                alignment: .leading,
                spacing: 8
            ) {
                Label(
                    "レッスン場所",
                    systemImage:
                        "mappin.and.ellipse"
                )
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(
                    PaymentUI.brandGreen
                )

                if isLoadingReservationDetails {
                    HStack(spacing: 8) {
                        ProgressView()

                        Text("場所を確認中…")
                            .font(.caption)
                            .foregroundStyle(
                                PaymentUI.textSecondary
                            )
                    }
                } else {
                    Text(lessonLocationTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            PaymentUI.textPrimary
                        )

                    if !lessonLocationAddress.isEmpty {
                        Text(
                            lessonLocationAddress
                        )
                        .font(.subheadline)
                        .foregroundStyle(
                            PaymentUI.textSecondary
                        )
                    }
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .padding(12)
            .background(
                PaymentUI.softGreen.opacity(0.50)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 13,
                    style: .continuous
                )
            )
        }
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                PaymentUI.border,
                lineWidth: 1
            )
        }
    }

    private var paymentSummaryCard: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            sectionTitle(
                "お支払い金額",
                systemImage:
                    "yensign.circle"
            )

            HStack(
                alignment: .firstTextBaseline
            ) {
                Text("合計")
                    .font(.subheadline)
                    .foregroundStyle(
                        PaymentUI.textSecondary
                    )

                Spacer()

                Text(
                    "¥\(totalPrice.formatted())"
                )
                .font(
                    .system(
                        size: 32,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(
                    PaymentUI.brandGreen
                )
            }

            Divider()

            HStack(
                alignment: .top,
                spacing: 8
            ) {
                Image(
                    systemName:
                        "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(
                    PaymentUI.brandGreen
                )

                Text(
                    "表示されている金額は、予約申請時に確定したレッスン料金です。"
                )
                .font(.caption)
                .foregroundStyle(
                    PaymentUI.textSecondary
                )
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                PaymentUI.brandGreen.opacity(0.18),
                lineWidth: 1
            )
        }
    }

    private var stripeSecurityCard: some View {
        HStack(
            alignment: .top,
            spacing: 12
        ) {
            ZStack {
                Circle()
                    .fill(
                        PaymentUI.softGreen
                    )
                    .frame(
                        width: 42,
                        height: 42
                    )

                Image(
                    systemName:
                        "lock.shield.fill"
                )
                .font(
                    .system(
                        size: 17,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    PaymentUI.brandGreen
                )
            }

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Text("Stripeによる安全な決済")
                    .font(.headline)
                    .foregroundStyle(
                        PaymentUI.textPrimary
                    )

                Text(
                    "「Stripeで支払う」を押すとStripeの決済画面が開きます。利用できる支払い方法は、その画面に表示されます。"
                )
                .font(.caption)
                .foregroundStyle(
                    PaymentUI.textSecondary
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )

                Text(
                    "Tennis Connect内でカード番号を入力することはありません。"
                )
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(
                    PaymentUI.brandGreen
                )
                .padding(.top, 2)
            }

            Spacer()
        }
        .padding(16)
        .background(
            PaymentUI.softGreen.opacity(0.55)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    private var errorCard: some View {
        HStack(
            alignment: .top,
            spacing: 8
        ) {
            Image(
                systemName:
                    "exclamationmark.triangle.fill"
            )

            Text(errorMessage)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
        }
        .font(.caption)
        .foregroundStyle(.red)
        .padding(14)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color.red.opacity(0.06)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }

    private var paymentActionArea: some View {
        VStack(spacing: 8) {
            Button {
                openStripeCheckout()
            } label: {
                HStack(spacing: 8) {
                    Spacer()

                    if isPaying {
                        ProgressView()
                            .tint(.white)

                        Text(
                            "支払い画面を準備中…"
                        )
                        .fontWeight(.semibold)
                    } else {
                        Image(
                            systemName:
                                "lock.fill"
                        )

                        Text(
                            "Stripeで ¥\(totalPrice.formatted()) を支払う"
                        )
                        .fontWeight(.semibold)
                    }

                    Spacer()
                }
                .frame(height: 52)
                .foregroundStyle(.white)
                .background(
                    isPaying
                        ? Color.gray
                        : PaymentUI.brandGreen
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(isPaying)

            Text(
                "決済完了後、この画面へ戻ると予約が自動で確定します"
            )
            .font(.caption2)
            .foregroundStyle(
                PaymentUI.textSecondary
            )
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private func sectionTitle(
        _ title: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(
                    .system(
                        size: 15,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    PaymentUI.brandGreen
                )

            Text(title)
                .font(.headline)
                .foregroundStyle(
                    PaymentUI.textPrimary
                )
        }
    }

    private func paymentDetailRow(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        PaymentUI.softGreen
                    )
                    .frame(
                        width: 34,
                        height: 34
                    )

                Image(systemName: icon)
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        PaymentUI.brandGreen
                    )
            }

            Text(title)
                .foregroundStyle(
                    PaymentUI.textSecondary
                )

            Spacer()

            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(
                    PaymentUI.textPrimary
                )
                .multilineTextAlignment(
                    .trailing
                )
        }
    }

    private func openStripeCheckout() {
        guard !reservationId.isEmpty else {
            errorMessage =
                "予約情報を確認できませんでした"
            return
        }

        isPaying = true
        errorMessage = ""
        startPaymentListener()

        functions
            .httpsCallable(
                "createCheckoutSession"
            )
            .call(
                [
                    "reservationId":
                        reservationId
                ]
            ) { result, error in
                if let error = error {
                    finishWithError(
                        "支払い画面を準備できませんでした: " +
                        error.localizedDescription
                    )
                    return
                }

                guard
                    let data =
                        result?.data
                        as? [String: Any],
                    let urlString =
                        data["checkoutUrl"]
                        as? String,
                    let checkoutURL =
                        URL(
                            string:
                                urlString
                        )
                else {
                    finishWithError(
                        "Stripeの支払いURLを取得できませんでした"
                    )
                    return
                }

                DispatchQueue.main.async {
                    openURL(
                        checkoutURL
                    ) { accepted in
                        DispatchQueue.main.async {
                            isPaying = false

                            if !accepted {
                                errorMessage =
                                    "支払い画面を開けませんでした"
                            }
                        }
                    }
                }
            }
    }

    private func loadLatestCoachImage() {
        let coachId =
            coach.id.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !coachId.isEmpty else {
            return
        }

        db.collection("coaches")
            .document(coachId)
            .getDocument { snapshot, error in
                if let error {
                    print(
                        "支払い画面のコーチ画像取得失敗:",
                        error.localizedDescription
                    )
                    return
                }

                let loadedImageURL =
                    (
                        snapshot?.data()?["imageURL"]
                        as? String
                        ?? ""
                    )
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

                guard !loadedImageURL.isEmpty else {
                    return
                }

                DispatchQueue.main.async {
                    latestCoachImageURL =
                        loadedImageURL
                }
            }
    }

    private func startPaymentListener() {
        guard !reservationId.isEmpty else {
            isLoadingReservationDetails = false
            return
        }

        stopPaymentListener()

        paymentListener = db
            .collection("reservations")
            .document(reservationId)
            .addSnapshotListener {
                snapshot,
                error in

                if let error = error {
                    DispatchQueue.main.async {
                        isLoadingReservationDetails = false

                        if errorMessage.isEmpty {
                            errorMessage =
                                "支払い状況を確認できませんでした: " +
                                error.localizedDescription
                        }
                    }
                    return
                }

                guard
                    let data =
                        snapshot?.data()
                else {
                    DispatchQueue.main.async {
                        isLoadingReservationDetails = false
                    }
                    return
                }

                let status =
                    data["status"]
                    as? String
                    ?? ""

                let paymentStatus =
                    data["paymentStatus"]
                    as? String
                    ?? ""

                let loadedCourtName =
                    data["courtName"]
                    as? String
                    ?? ""

                let loadedCourtAddress =
                    data["courtAddress"]
                    as? String
                    ?? ""

                let loadedLegacyCourt =
                    data["court"]
                    as? String
                    ?? ""

                DispatchQueue.main.async {
                    courtName =
                        loadedCourtName
                    courtAddress =
                        loadedCourtAddress
                    legacyCourt =
                        loadedLegacyCourt
                    isLoadingReservationDetails =
                        false

                    if status == "paid" ||
                        paymentStatus == "paid" {
                        isPaying = false
                        errorMessage = ""
                        showComplete = true
                        stopPaymentListener()

                    } else if
                        paymentStatus ==
                            "failed" {
                        isPaying = false
                        errorMessage =
                            "支払いを確認できませんでした。" +
                            "もう一度お試しください。"

                    } else if
                        paymentStatus ==
                            "expired" {
                        isPaying = false
                        errorMessage =
                            "支払い画面の有効期限が切れました。" +
                            "もう一度お試しください。"
                    }
                }
            }
    }

    private func stopPaymentListener() {
        paymentListener?.remove()
        paymentListener = nil
    }

    private func finishWithError(
        _ message: String
    ) {
        DispatchQueue.main.async {
            isPaying = false
            errorMessage = message
        }
    }

    private func displayDate(
        _ date: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar =
            Calendar(identifier: .gregorian)
        formatter.locale =
            Locale(identifier: "ja_JP")
        formatter.dateFormat =
            "M/d（E）"
        return formatter.string(
            from: date
        )
    }

    private func combinedTimeRange(
        _ times: [String]
    ) -> String {
        guard
            let first =
                times.sorted().first,
            let last =
                times.sorted().last
        else {
            return ""
        }

        return
            "\(first)〜\(endTime(for: last))"
    }

    private func endTime(
        for startTime: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar =
            Calendar(identifier: .gregorian)
        formatter.locale =
            Locale(identifier: "en_US_POSIX")
        formatter.dateFormat =
            "HH:mm"

        guard
            let startDate =
                formatter.date(
                    from: startTime
                ),
            let endDate =
                Calendar.current.date(
                    byAdding: .hour,
                    value: 1,
                    to: startDate
                )
        else {
            return startTime
        }

        return formatter.string(
            from: endDate
        )
    }
}

private struct PaymentCoachAvatarView: View {
    let imageURL: String
    let size: CGFloat

    var body: some View {
        AsyncImage(
            url: URL(
                string: imageURL
            )
        ) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()

            case .failure:
                placeholder

            case .empty:
                if imageURL.isEmpty {
                    placeholder
                } else {
                    ProgressView()
                }

            @unknown default:
                placeholder
            }
        }
        .frame(
            width: size,
            height: size
        )
        .background(
            PaymentUI.softGreen
        )
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(
                    PaymentUI.border,
                    lineWidth: 1
                )
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(
            systemName:
                "person.fill"
        )
        .resizable()
        .scaledToFit()
        .padding(size * 0.22)
        .foregroundStyle(
            PaymentUI.brandGreen
        )
    }
}
