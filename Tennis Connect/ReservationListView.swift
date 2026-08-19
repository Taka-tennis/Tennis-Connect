import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

struct ReservationItem: Identifiable {
    let id: String
    let coachId: String
    let coachName: String
    let date: String
    let time: String
    let times: [String]
    let status: String
    let paymentStatus: String
    let refundStatus: String
    let cancellationSource: String
    let cancellationRefundPercent: Int
    let refundAmount: Int
    let reviewId: String
    let pricePerHour: Int
    let totalPrice: Int
    let createdAt: Timestamp?

    init(
        id: String,
        coachId: String,
        coachName: String,
        date: String,
        time: String,
        status: String,
        paymentStatus: String = "",
        refundStatus: String = "",
        cancellationSource: String = "",
        cancellationRefundPercent: Int = 0,
        refundAmount: Int = 0,
        reviewId: String = "",
        times: [String] = [],
        pricePerHour: Int = 0,
        totalPrice: Int = 0,
        createdAt: Timestamp? = nil
    ) {
        self.id = id
        self.coachId = coachId
        self.coachName = coachName
        self.date = date
        self.time = time
        self.status = status
        self.paymentStatus = paymentStatus
        self.refundStatus = refundStatus
        self.cancellationSource = cancellationSource
        self.cancellationRefundPercent = cancellationRefundPercent
        self.refundAmount = refundAmount
        self.reviewId = reviewId
        self.times = times.isEmpty && !time.isEmpty ? [time] : times
        self.pricePerHour = pricePerHour
        self.totalPrice = totalPrice
        self.createdAt = createdAt
    }
}

struct ReservationListView: View {

    private enum ReservationCategory: String, CaseIterable, Identifiable {
        case pending
        case upcoming
        case history

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pending:
                return "承認待ち"
            case .upcoming:
                return "今後"
            case .history:
                return "履歴"
            }
        }
    }

    @State private var reservations: [ReservationItem] = []
    @State private var selectedCategory: ReservationCategory = .upcoming
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var isLoggedIn = false
    @State private var showLogin = false

    private let db = Firestore.firestore()

    var body: some View {
        Group {
            if isLoggedIn {
                VStack(spacing: 0) {
                    categoryPicker

                    Group {
                        if isLoading && reservations.isEmpty {
                            ProgressView("予約を読み込み中…")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if filteredReservations.isEmpty {
                            emptyState
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            reservationList
                        }
                    }
                }
            } else {
                loggedOutView
            }
        }
        .navigationTitle("予約一覧")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if isLoggedIn && !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .onAppear {
            isLoggedIn = Auth.auth().currentUser != nil

            if isLoggedIn {
                loadReservations()
            } else {
                reservations = []
                errorMessage = ""
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginView {
                isLoggedIn = true
                loadReservations()
            }
        }
    }

    private var loggedOutView: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "calendar.badge.person.crop")
                .font(.system(size: 58))
                .foregroundStyle(.secondary)

            Text("予約を確認するにはログインが必要です")
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text("ログインすると、承認待ち・今後の予約・予約履歴を確認できます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showLogin = true
            } label: {
                Label("ログイン・新規会員登録", systemImage: "person.crop.circle.badge.plus")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.top, 6)

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var categoryPicker: some View {
        Picker("予約の種類", selection: $selectedCategory) {
            ForEach(ReservationCategory.allCases) { category in
                Text("\(category.title) \(categoryCount(category))")
                    .tag(category)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private var reservationList: some View {
        List {
            Section {
                ForEach(filteredReservations) { reservation in
                    NavigationLink {
                        StudentReservationDetailView(
                            reservation: reservation
                        ) {
                            loadReservations()
                        }
                    } label: {
                        reservationCard(reservation)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                Color.primary.opacity(0.06),
                                lineWidth: 1
                            )
                    }
                    .listRowInsets(
                        EdgeInsets(
                            top: 6,
                            leading: 16,
                            bottom: 6,
                            trailing: 16
                        )
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            } header: {
                Text(sectionTitle)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .refreshable {
            loadReservations()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text(emptyStateTitle)
                .font(.title3)
                .fontWeight(.semibold)

            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var filteredReservations: [ReservationItem] {
        let filtered = reservations.filter { reservation in
            category(for: reservation) == selectedCategory
        }

        return filtered.sorted { first, second in
            switch selectedCategory {
            case .pending, .upcoming:
                return upcomingSortDate(first) < upcomingSortDate(second)

            case .history:
                return historySortDate(first) > historySortDate(second)
            }
        }
    }

    private var sectionTitle: String {
        switch selectedCategory {
        case .pending:
            return "コーチの承認を待っている予約"

        case .upcoming:
            return "これからのレッスン"

        case .history:
            return "過去の予約・キャンセル"
        }
    }

    private var emptyStateIcon: String {
        switch selectedCategory {
        case .pending:
            return "clock"

        case .upcoming:
            return "calendar"

        case .history:
            return "clock.arrow.circlepath"
        }
    }

    private var emptyStateTitle: String {
        switch selectedCategory {
        case .pending:
            return "承認待ちの予約はありません"

        case .upcoming:
            return "今後の予約はありません"

        case .history:
            return "予約履歴はありません"
        }
    }

    private var emptyStateMessage: String {
        switch selectedCategory {
        case .pending:
            return "予約申請中のレッスンがここに表示されます"

        case .upcoming:
            return "承認済み・支払い済みのこれからのレッスンが表示されます"

        case .history:
            return "終了したレッスンや却下・キャンセルされた予約が表示されます"
        }
    }

    @ViewBuilder
    private func reservationCard(
        _ reservation: ReservationItem
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(reservation.coachName)
                        .font(.headline)

                    Text(statusDescription(reservation))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                statusBadge(reservation)
            }

            Divider()

            HStack(spacing: 18) {
                Label(
                    displayDate(reservation.date),
                    systemImage: "calendar"
                )

                Label(
                    combinedTimeRange(reservation.times),
                    systemImage: "clock"
                )
            }
            .font(.subheadline)

            HStack(spacing: 14) {
                Label(
                    "\(max(reservation.times.count, 1))時間",
                    systemImage: "hourglass"
                )

                if reservation.totalPrice > 0 {
                    Label(
                        "¥\(reservation.totalPrice)",
                        systemImage: "yensign.circle"
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if reservation.status == "confirmed" &&
                !isRefunded(reservation) {
                Label(
                    "タップして支払い手続きへ進めます",
                    systemImage: "creditcard.fill"
                )
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
            }
        }
    }

    private func categoryCount(
        _ targetCategory: ReservationCategory
    ) -> Int {
        reservations.filter {
            category(for: $0) == targetCategory
        }
        .count
    }

    private func category(
        for reservation: ReservationItem
    ) -> ReservationCategory {
        if reservation.status == "pending" {
            return .pending
        }

        let activeStatuses = [
            "confirmed",
            "paid",
            "reserved"
        ]

        if activeStatuses.contains(reservation.status),
           !isPast(reservation) {
            return .upcoming
        }

        return .history
    }

    private func upcomingSortDate(
        _ reservation: ReservationItem
    ) -> Date {
        lessonStartDate(reservation) ??
            reservation.createdAt?.dateValue() ??
            .distantFuture
    }

    private func historySortDate(
        _ reservation: ReservationItem
    ) -> Date {
        lessonStartDate(reservation) ??
            reservation.createdAt?.dateValue() ??
            .distantPast
    }

    private func isPast(
        _ reservation: ReservationItem
    ) -> Bool {
        guard let endDate = lessonEndDate(reservation) else {
            return false
        }

        return endDate < Date()
    }

    private func lessonStartDate(
        _ reservation: ReservationItem
    ) -> Date? {
        guard let firstTime = reservation.times.sorted().first else {
            return nil
        }

        return dateTime(
            date: reservation.date,
            time: startTime(from: firstTime)
        )
    }

    private func lessonEndDate(
        _ reservation: ReservationItem
    ) -> Date? {
        guard let lastTime = reservation.times.sorted().last else {
            return nil
        }

        return dateTime(
            date: reservation.date,
            time: endTime(for: lastTime)
        )
    }

    private func dateTime(
        date: String,
        time: String
    ) -> Date? {
        let normalizedDate =
            date.replacingOccurrences(of: "/", with: "-")

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.isLenient = false

        return formatter.date(
            from: "\(normalizedDate) \(time)"
        )
    }

    private func startTime(
        from value: String
    ) -> String {
        let normalized =
            value.replacingOccurrences(of: "~", with: "〜")

        return normalized
            .components(separatedBy: "〜")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? value
    }

    private func statusDescription(
        _ reservation: ReservationItem
    ) -> String {
        if isRefunded(reservation) {
            if reservation.status == "student_cancelled" {
                if reservation.cancellationRefundPercent == 50 {
                    return "生徒都合キャンセル・50%返金済み"
                }
                return "生徒都合キャンセル・全額返金済み"
            }

            return "コーチ都合キャンセル・全額返金済み"
        }

        if isRefundFailed(reservation) {
            return "返金状況を確認しています"
        }

        if isRefundProcessing(reservation) {
            return "返金を処理しています"
        }

        switch reservation.status {
        case "pending":
            return "コーチの承認を待っています"

        case "confirmed":
            return "承認済み・支払い手続きが必要です"

        case "paid":
            return "支払いが完了し、予約が確定しています"

        case "reserved":
            return "予約が確定しています"

        case "rejected":
            return "予約申請は却下されました"

        case "coach_cancelled":
            return "コーチ都合でキャンセルされました"

        case "student_cancelled":
            if reservation.cancellationRefundPercent == 0 {
                return "生徒都合でキャンセル済み・返金なし"
            } else if reservation.cancellationRefundPercent == 50 {
                return "生徒都合でキャンセル済み・50%返金"
            } else {
                return "生徒都合でキャンセル済み・全額返金"
            }

        case "cancelled", "canceled":
            return "キャンセル済みの予約です"

        case "completed":
            return "終了したレッスンです"

        default:
            return "予約状況をご確認ください"
        }
    }

    private func loadReservations() {
        guard let uid = Auth.auth().currentUser?.uid else {
            reservations = []
            errorMessage = ""
            isLoggedIn = false
            return
        }

        isLoading = true
        errorMessage = ""

        db.collection("reservations")
            .whereField("studentId", isEqualTo: uid)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    isLoading = false

                    if let error = error {
                        errorMessage =
                            "予約を取得できませんでした: \(error.localizedDescription)"
                        return
                    }

                    let loadedReservations: [ReservationItem] =
                        snapshot?.documents.map { document in

                        let data = document.data()
                        let legacyTime =
                            data["time"] as? String ?? ""
                        let savedTimes =
                            data["times"] as? [String] ?? []
                        let reservationTimes =
                            savedTimes.isEmpty
                            ? (
                                legacyTime.isEmpty
                                ? []
                                : [legacyTime]
                            )
                            : savedTimes.sorted()

                        let pricePerHour =
                            data["pricePerHour"] as? Int ?? 0

                        let totalPrice: Int

                        if let savedTotal =
                            data["totalPrice"] as? Int {
                            totalPrice = savedTotal
                        } else if let legacyPrice =
                            data["price"] as? Int {
                            totalPrice = legacyPrice
                        } else {
                            totalPrice =
                                pricePerHour *
                                reservationTimes.count
                        }

                        return ReservationItem(
                            id: document.documentID,
                            coachId:
                                data["coachId"] as? String ?? "",
                            coachName:
                                data["coachName"] as? String
                                ?? "コーチ名未登録",
                            date:
                                data["date"] as? String ?? "",
                            time:
                                reservationTimes.first
                                ?? legacyTime,
                            status:
                                data["status"] as? String
                                ?? "pending",
                            paymentStatus:
                                data["paymentStatus"] as? String
                                ?? "",
                            refundStatus:
                                data["refundStatus"] as? String
                                ?? "",
                            cancellationSource:
                                data["cancellationSource"] as? String
                                ?? "",
                            cancellationRefundPercent:
                                (data["cancellationRefundPercent"] as? NSNumber)?.intValue
                                ?? data["cancellationRefundPercent"] as? Int
                                ?? 0,
                            refundAmount:
                                (data["refundAmount"] as? NSNumber)?.intValue
                                ?? data["refundAmount"] as? Int
                                ?? 0,
                            reviewId:
                                data["reviewId"] as? String
                                ?? "",
                            times: reservationTimes,
                            pricePerHour: pricePerHour,
                            totalPrice: totalPrice,
                            createdAt:
                                data["createdAt"] as? Timestamp
                        )
                    } ?? []

                    reservations = loadedReservations
                    errorMessage = ""
                }
            }
    }

    @ViewBuilder
    private func statusBadge(
        _ reservation: ReservationItem
    ) -> some View {
        if isRefunded(reservation) {
            Label(
                reservation.status == "student_cancelled" &&
                reservation.cancellationRefundPercent == 50
                ? "50%返金済み"
                : "全額返金済み",
                systemImage:
                    "arrow.uturn.backward.circle.fill"
            )
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.purple)

        } else if isRefundFailed(reservation) {
            Label(
                "返金確認中",
                systemImage:
                    "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.red)

        } else if isRefundProcessing(reservation) {
            Label(
                "返金処理中",
                systemImage:
                    "arrow.triangle.2.circlepath"
            )
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.orange)

        } else {
            reservationStatusBadge(
                reservation.status
            )
        }
    }

    @ViewBuilder
    private func reservationStatusBadge(
        _ status: String
    ) -> some View {
        switch status {
        case "confirmed":
            Label(
                "承認済み",
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.blue)

        case "paid":
            Label(
                "支払い済み",
                systemImage: "creditcard.fill"
            )
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.green)

        case "rejected":
            Label(
                "却下済み",
                systemImage: "xmark.circle.fill"
            )
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.red)

        case "reserved":
            Label(
                "予約済み",
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.green)

        case "coach_cancelled":
            Label(
                "コーチ都合キャンセル",
                systemImage: "minus.circle.fill"
            )
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.purple)

        case "student_cancelled":
            Label(
                "生徒都合キャンセル",
                systemImage: "minus.circle.fill"
            )
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)

        case "cancelled", "canceled":
            Label(
                "キャンセル",
                systemImage: "minus.circle.fill"
            )
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)

        case "completed":
            Label(
                "受講済み",
                systemImage: "checkmark.seal.fill"
            )
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)

        default:
            Label(
                "承認待ち",
                systemImage: "clock.fill"
            )
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.orange)
        }
    }

    private func isRefunded(
        _ reservation: ReservationItem
    ) -> Bool {
        reservation.paymentStatus == "refunded" ||
        reservation.refundStatus == "succeeded"
    }

    private func isRefundFailed(
        _ reservation: ReservationItem
    ) -> Bool {
        reservation.paymentStatus == "refund_failed" ||
        [
            "failed",
            "canceled",
            "failed_to_create"
        ]
        .contains(reservation.refundStatus)
    }

    private func isRefundProcessing(
        _ reservation: ReservationItem
    ) -> Bool {
        reservation.paymentStatus == "refund_processing" ||
        [
            "creating",
            "pending",
            "requires_action"
        ]
        .contains(reservation.refundStatus)
    }

    private func displayDate(
        _ date: String
    ) -> String {
        date.replacingOccurrences(
            of: "-",
            with: "/"
        )
    }

    private func combinedTimeRange(
        _ times: [String]
    ) -> String {
        let sortedTimes = times.sorted()

        guard let first = sortedTimes.first,
              let last = sortedTimes.last else {
            return "時間未設定"
        }

        if sortedTimes.count == 1,
           (
            first.contains("〜") ||
            first.contains("~")
           ) {
            return first.replacingOccurrences(
                of: "~",
                with: "〜"
            )
        }

        return "\(first)〜\(endTime(for: last))"
    }

    private func endTime(
        for startTime: String
    ) -> String {
        if startTime.contains("〜") ||
            startTime.contains("~") {
            return startTime
                .replacingOccurrences(
                    of: "~",
                    with: "〜"
                )
                .components(
                    separatedBy: "〜"
                )
                .last ?? startTime
        }

        let formatter = DateFormatter()
        formatter.calendar =
            Calendar(identifier: .gregorian)
        formatter.locale =
            Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"

        guard let startDate =
                formatter.date(from: startTime),
              let endDate =
                Calendar.current.date(
                    byAdding: .hour,
                    value: 1,
                    to: startDate
                ) else {
            return startTime
        }

        return formatter.string(from: endDate)
    }
}

private struct StudentReservationDetailView: View {
    let reservation: ReservationItem
    let onCancellationCompleted: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var reviewSubmitted: Bool
    @State private var hasReviewedCoach = false
    @State private var isCheckingCoachReview = true
    @State private var reviewEligibilityError = ""

    @State private var isCancelling = false
    @State private var showCancellationConfirmation = false
    @State private var showCancellationResult = false
    @State private var cancellationResultTitle = ""
    @State private var cancellationResultMessage = ""
    @State private var cancellationErrorMessage = ""

    private let db = Firestore.firestore()
    private let functions = Functions.functions(region: "asia-northeast1")

    init(
        reservation: ReservationItem,
        onCancellationCompleted: @escaping () -> Void = {}
    ) {
        self.reservation = reservation
        self.onCancellationCompleted = onCancellationCompleted
        _reviewSubmitted = State(
            initialValue: !reservation.reviewId.isEmpty
        )
    }

    private var coach: Coach {
        Coach(
            id: reservation.coachId,
            name: reservation.coachName,
            price: reservation.pricePerHour,
            area: "",
            imageURL: "",
            availableTimes: [],
            ageGroup: "",
            careers: ["経歴未登録"],
            tennisExperience: "未登録",
            coachingExperience: "未登録",
            introduction: ""
        )
    }

    private var lessonDate: Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in ["yyyy-MM-dd", "yyyy/MM/dd"] {
            formatter.dateFormat = format

            if let date = formatter.date(from: reservation.date) {
                return date
            }
        }

        return Date()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                statusHeader

                VStack(spacing: 16) {
                    detailRow(
                        title: "コーチ",
                        value: reservation.coachName
                    )
                    Divider()
                    detailRow(
                        title: "日付",
                        value: displayDate(reservation.date)
                    )
                    Divider()
                    detailRow(
                        title: "時間",
                        value: combinedTimeRange(reservation.times)
                    )
                    Divider()
                    detailRow(
                        title: "レッスン時間",
                        value: "\(reservation.times.count)時間"
                    )
                    Divider()
                    detailRow(
                        title: "料金",
                        value: "¥\(reservation.totalPrice)"
                    )
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(18)

                if reservation.status == "confirmed" {
                    NavigationLink {
                        PaymentView(
                            reservationId: reservation.id,
                            coach: coach,
                            date: lessonDate,
                            times: reservation.times,
                            totalPrice: reservation.totalPrice
                        )
                    } label: {
                        Label(
                            "支払いへ進む",
                            systemImage: "creditcard.fill"
                        )
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }
                }

                if canCancelPaidReservation {
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("キャンセル時の返金")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Text(cancellationPolicyPreview)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("最終的な返金率・返金額は、キャンセル実行時にサーバー側で確定します。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            showCancellationConfirmation = true
                        } label: {
                            if isCancelling {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            } else {
                                Label(
                                    "予約をキャンセルする",
                                    systemImage: "xmark.circle.fill"
                                )
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                            }
                        }
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .disabled(isCancelling)

                        if !cancellationErrorMessage.isEmpty {
                            Text(cancellationErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding()
                    .background(Color.red.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                if reviewSubmitted {
                    Label(
                        "レビュー投稿済み",
                        systemImage: "checkmark.seal.fill"
                    )
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                } else if canWriteReview {
                    if isCheckingCoachReview {
                        ProgressView("レビュー状況を確認中…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    } else if !reviewEligibilityError.isEmpty {
                        VStack(spacing: 10) {
                            Text("レビュー状況を確認できませんでした")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button("再確認") {
                                checkExistingCoachReview()
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                    } else if !hasReviewedCoach {
                        NavigationLink {
                            ReviewSubmissionView(
                                reservationId: reservation.id,
                                coachName: reservation.coachName
                            ) {
                                reviewSubmitted = true
                                hasReviewedCoach = true
                            }
                        } label: {
                            Label(
                                "レビューを書く",
                                systemImage: "star.bubble.fill"
                            )
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("予約詳細")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkExistingCoachReview()
        }
        .confirmationDialog(
            "予約をキャンセルしますか？",
            isPresented: $showCancellationConfirmation,
            titleVisibility: .visible
        ) {
            Button("予約をキャンセル", role: .destructive) {
                requestStudentCancellation()
            }

            Button("戻る", role: .cancel) {}
        } message: {
            Text(cancellationPolicyPreview)
        }
        .alert(
            cancellationResultTitle,
            isPresented: $showCancellationResult
        ) {
            Button("OK") {
                onCancellationCompleted()
                dismiss()
            }
        } message: {
            Text(cancellationResultMessage)
        }
    }

    private func checkExistingCoachReview() {
        if reviewSubmitted {
            hasReviewedCoach = true
            isCheckingCoachReview = false
            reviewEligibilityError = ""
            return
        }

        guard canWriteReview else {
            hasReviewedCoach = false
            isCheckingCoachReview = false
            reviewEligibilityError = ""
            return
        }

        guard let uid = Auth.auth().currentUser?.uid,
              !reservation.coachId.isEmpty else {
            hasReviewedCoach = false
            isCheckingCoachReview = false
            reviewEligibilityError = "レビュー状況を確認できませんでした"
            return
        }

        isCheckingCoachReview = true
        reviewEligibilityError = ""

        db.collection("reviews")
            .whereField("studentId", isEqualTo: uid)
            .whereField("coachId", isEqualTo: reservation.coachId)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    isCheckingCoachReview = false

                    if let error = error {
                        hasReviewedCoach = false
                        reviewEligibilityError = error.localizedDescription
                        return
                    }

                    hasReviewedCoach =
                        !(snapshot?.documents.isEmpty ?? true)
                    reviewEligibilityError = ""
                }
            }
    }

    @ViewBuilder
    private var statusHeader: some View {
        if isRefunded {
            statusMessage(
                icon: "arrow.uturn.backward.circle.fill",
                color: .purple,
                title:
                    reservation.status == "student_cancelled" &&
                    reservation.cancellationRefundPercent == 50
                    ? "50%返金が完了しました"
                    : "全額返金が完了しました",
                message:
                    reservation.status == "student_cancelled"
                    ? "生徒都合でキャンセルした予約です"
                    : "コーチ都合でキャンセルされた予約です"
            )
        } else if isRefundFailed {
            statusMessage(
                icon: "exclamationmark.triangle.fill",
                color: .red,
                title: "返金状況を確認しています",
                message: "運営による確認をお待ちください"
            )
        } else if isRefundProcessing {
            statusMessage(
                icon: "arrow.triangle.2.circlepath",
                color: .orange,
                title: "返金を処理しています",
                message: "返金完了までしばらくお待ちください"
            )
        } else {
            reservationStatusHeader
        }
    }

    @ViewBuilder
    private var reservationStatusHeader: some View {
        switch reservation.status {
        case "confirmed":
            statusMessage(
                icon: "checkmark.circle.fill",
                color: .blue,
                title: "コーチが承認しました",
                message: "支払い手続きへ進んでください"
            )

        case "paid":
            statusMessage(
                icon: "creditcard.fill",
                color: .green,
                title: "支払い済み",
                message: "予約が確定しています"
            )

        case "rejected":
            statusMessage(
                icon: "xmark.circle.fill",
                color: .red,
                title: "予約申請は却下されました",
                message: "別の日時またはコーチを選択してください"
            )

        case "reserved":
            statusMessage(
                icon: "checkmark.circle.fill",
                color: .green,
                title: "予約済み",
                message: "予約内容をご確認ください"
            )

        case "coach_cancelled":
            statusMessage(
                icon: "minus.circle.fill",
                color: .purple,
                title: "コーチ都合でキャンセルされました",
                message: "返金状況をご確認ください"
            )

        case "student_cancelled":
            statusMessage(
                icon: "minus.circle.fill",
                color: .secondary,
                title: "生徒都合でキャンセルしました",
                message:
                    reservation.cancellationRefundPercent == 0
                    ? "キャンセル規定により返金はありません"
                    : "返金状況をご確認ください"
            )

        case "cancelled", "canceled":
            statusMessage(
                icon: "minus.circle.fill",
                color: .secondary,
                title: "キャンセル済み",
                message: "この予約はキャンセルされています"
            )

        default:
            statusMessage(
                icon: "clock.fill",
                color: .orange,
                title: "コーチの承認待ち",
                message: "承認されるまでしばらくお待ちください"
            )
        }
    }

    private var isRefunded: Bool {
        reservation.paymentStatus == "refunded" ||
        reservation.refundStatus == "succeeded"
    }

    private var isRefundFailed: Bool {
        reservation.paymentStatus == "refund_failed" ||
        ["failed", "canceled", "failed_to_create"].contains(
            reservation.refundStatus
        )
    }

    private var isRefundProcessing: Bool {
        reservation.paymentStatus == "refund_processing" ||
        ["creating", "pending", "requires_action"].contains(
            reservation.refundStatus
        )
    }

    private var canCancelPaidReservation: Bool {
        guard reservation.status == "paid",
              reservation.paymentStatus == "paid",
              !isCancelled,
              !isRefundProcessing,
              let lessonStartDate = lessonStartDate else {
            return false
        }

        return lessonStartDate > Date()
    }

    private var cancellationPolicyPreview: String {
        guard let lessonStartDate = lessonStartDate else {
            return "予約日時を確認できないため、返金条件を表示できません。"
        }

        let interval = lessonStartDate.timeIntervalSinceNow
        let twelveHours = 12.0 * 60.0 * 60.0
        let twentyFourHours = 24.0 * 60.0 * 60.0

        if interval > twentyFourHours {
            return "レッスン開始24時間より前のため、キャンセルすると100%返金予定です。"
        } else if interval > twelveHours {
            let estimatedAmount = reservation.totalPrice / 2
            return "レッスン開始12時間より前〜24時間以内のため、50%（約¥\(estimatedAmount)）返金予定です。"
        } else if interval > 0 {
            return "レッスン開始12時間以内のため、キャンセルしても返金はありません。"
        } else {
            return "レッスン開始後はキャンセルできません。"
        }
    }

    private var lessonStartDate: Date? {
        let normalizedDate = reservation.date
            .replacingOccurrences(of: "/", with: "-")
        let sortedTimes = reservation.times.sorted()

        guard let firstSlot = sortedTimes.first else {
            return nil
        }

        let normalizedSlot = firstSlot
            .replacingOccurrences(of: "~", with: "〜")
        let startTime = normalizedSlot
            .components(separatedBy: "〜")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return dateTime(
            date: normalizedDate,
            time: startTime
        )
    }

    private func requestStudentCancellation() {
        guard !isCancelling else {
            return
        }

        isCancelling = true
        cancellationErrorMessage = ""

        functions
            .httpsCallable("requestStudentCancellation")
            .call([
                "reservationId": reservation.id
            ]) { result, error in
                DispatchQueue.main.async {
                    isCancelling = false

                    if let error = error {
                        cancellationErrorMessage =
                            "キャンセルできませんでした: \(error.localizedDescription)"
                        return
                    }

                    guard let data =
                            result?.data as? [String: Any] else {
                        cancellationErrorMessage =
                            "キャンセル結果を確認できませんでした。"
                        return
                    }

                    let refundPercent =
                        integerValue(data["refundPercent"])
                    let refundAmount =
                        integerValue(data["refundAmount"])

                    cancellationResultTitle =
                        "予約をキャンセルしました"

                    switch refundPercent {
                    case 100:
                        cancellationResultMessage =
                            "¥\(refundAmount)の全額返金手続きを開始しました。返金の反映まで時間がかかる場合があります。"

                    case 50:
                        cancellationResultMessage =
                            "¥\(refundAmount)（50%）の返金手続きを開始しました。返金の反映まで時間がかかる場合があります。"

                    default:
                        cancellationResultMessage =
                            "キャンセル規定により返金はありません。"
                    }

                    showCancellationResult = true
                }
            }
    }

    private func integerValue(_ value: Any?) -> Int {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        return 0
    }

    private var canWriteReview: Bool {
        guard reservation.paymentStatus == "paid",
              ["paid", "completed"].contains(reservation.status),
              !isRefunded,
              !isCancelled,
              let lessonEndDate = lessonEndDate else {
            return false
        }

        return lessonEndDate <= Date()
    }

    private var isCancelled: Bool {
        ["coach_cancelled", "student_cancelled", "cancelled", "canceled"].contains(
            reservation.status
        )
    }

    private var lessonEndDate: Date? {
        let normalizedDate = reservation.date
            .replacingOccurrences(of: "/", with: "-")
        let sortedTimes = reservation.times.sorted()

        guard let lastSlot = sortedTimes.last else {
            return nil
        }

        let normalizedSlot = lastSlot
            .replacingOccurrences(of: "~", with: "〜")
        let parts = normalizedSlot.components(separatedBy: "〜")
        let startTime = parts.first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let endTime = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        guard let startDate = dateTime(
            date: normalizedDate,
            time: startTime
        ) else {
            return nil
        }

        if !endTime.isEmpty {
            guard let parsedEndDate = dateTime(
                date: normalizedDate,
                time: endTime
            ) else {
                return nil
            }

            if parsedEndDate <= startDate {
                return parsedEndDate.addingTimeInterval(
                    24 * 60 * 60
                )
            }

            return parsedEndDate
        }

        return startDate.addingTimeInterval(60 * 60)
    }

    private func dateTime(date: String, time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.isLenient = false

        return formatter.date(from: "\(date) \(time)")
    }

    private func statusMessage(
        icon: String,
        color: Color,
        title: String,
        message: String
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(color)

            Text(title)
                .font(.title3)
                .fontWeight(.bold)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
    }

    private func displayDate(_ date: String) -> String {
        date.replacingOccurrences(of: "-", with: "/")
    }

    private func combinedTimeRange(_ times: [String]) -> String {
        let sortedTimes = times.sorted()

        guard let first = sortedTimes.first,
              let last = sortedTimes.last else {
            return "時間未設定"
        }

        if sortedTimes.count == 1,
           (first.contains("〜") || first.contains("~")) {
            return first.replacingOccurrences(of: "~", with: "〜")
        }

        return "\(first)〜\(endTime(for: last))"
    }

    private func endTime(for startTime: String) -> String {
        if startTime.contains("〜") || startTime.contains("~") {
            return startTime
                .replacingOccurrences(of: "~", with: "〜")
                .components(separatedBy: "〜")
                .last ?? startTime
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"

        guard let startDate = formatter.date(from: startTime),
              let endDate = Calendar.current.date(
                byAdding: .hour,
                value: 1,
                to: startDate
              ) else {
            return startTime
        }

        return formatter.string(from: endDate)
    }
}

#Preview {
    NavigationStack {
        ReservationListView()
    }
}
