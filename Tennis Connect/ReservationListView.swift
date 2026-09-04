import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

private enum StudentReservationUI {
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
    let weatherCancellationStatus: String
    let weatherCancellationRequesterRole: String
    let refundAmount: Int
    let reviewId: String
    let pricePerHour: Int
    let totalPrice: Int
    let courtName: String
    let courtAddress: String
    let court: String
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
        weatherCancellationStatus: String = "",
        weatherCancellationRequesterRole: String = "",
        refundAmount: Int = 0,
        reviewId: String = "",
        times: [String] = [],
        pricePerHour: Int = 0,
        totalPrice: Int = 0,
        courtName: String = "",
        courtAddress: String = "",
        court: String = "",
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
        self.weatherCancellationStatus = weatherCancellationStatus
        self.weatherCancellationRequesterRole = weatherCancellationRequesterRole
        self.refundAmount = refundAmount
        self.reviewId = reviewId
        self.times = times.isEmpty && !time.isEmpty ? [time] : times
        self.pricePerHour = pricePerHour
        self.totalPrice = totalPrice
        self.courtName = courtName
        self.courtAddress = courtAddress
        self.court = court
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
    @State private var coachImageURLs: [String: String] = [:]
    @State private var selectedCategory: ReservationCategory = .upcoming
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var isLoggedIn = false
    @State private var showLogin = false

    @State private var selectedCoachIdForNavigation: String?
    @State private var selectedReservationForNavigation: ReservationItem?
    @State private var showCoachProfile = false
    @State private var showReservationDetail = false

    private let db = Firestore.firestore()

    var body: some View {
        Group {
            if isLoggedIn {
                ZStack {
                    StudentReservationUI.background
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        VStack(
                            alignment: .leading,
                            spacing: 5
                        ) {
                            Text("予約")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(
                                    StudentReservationUI.textPrimary
                                )

                            Text(
                                "レッスンの予定・支払い状況・履歴を確認できます"
                            )
                            .font(.subheadline)
                            .foregroundStyle(
                                StudentReservationUI.textSecondary
                            )
                        }
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                        categoryPicker
                            .padding(.top, 14)

                        Group {
                            if isLoading &&
                                reservations.isEmpty {
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .tint(
                                            StudentReservationUI.brandGreen
                                        )

                                    Text("予約を読み込み中…")
                                        .font(.subheadline)
                                        .foregroundStyle(
                                            StudentReservationUI.textSecondary
                                        )
                                }
                                .frame(
                                    maxWidth: .infinity,
                                    maxHeight: .infinity
                                )

                            } else if filteredReservations.isEmpty {
                                emptyState
                                    .frame(
                                        maxWidth: .infinity,
                                        maxHeight: .infinity
                                    )

                            } else {
                                reservationList
                            }
                        }
                    }
                }
            } else {
                loggedOutView
            }
        }
        .tint(StudentReservationUI.brandGreen)
        .navigationTitle("予約一覧")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if isLoggedIn &&
                !errorMessage.isEmpty {
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
            isLoggedIn =
                Auth.auth().currentUser != nil

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
        .navigationDestination(
            isPresented: $showCoachProfile
        ) {
            if let coachId =
                selectedCoachIdForNavigation {
                CoachProfileDestinationView(
                    coachId: coachId
                )
            }
        }
        .navigationDestination(
            isPresented: $showReservationDetail
        ) {
            if let reservation =
                selectedReservationForNavigation {
                StudentReservationDetailView(
                    reservation: reservation,
                    coachImageURL:
                        coachImageURLs[
                            reservation.coachId
                        ] ?? ""
                ) {
                    loadReservations()
                }
            }
        }
    }

    private var loggedOutView: some View {
        ZStack {
            StudentReservationUI.background
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(
                            StudentReservationUI.softGreen
                        )
                        .frame(
                            width: 88,
                            height: 88
                        )

                    Image(
                        systemName:
                            "calendar.badge.person.crop"
                    )
                    .font(.system(size: 38))
                    .foregroundStyle(
                        StudentReservationUI.brandGreen
                    )
                }

                Text("予約を確認するにはログインが必要です")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        StudentReservationUI.textPrimary
                    )
                    .multilineTextAlignment(.center)

                Text(
                    "ログインすると、承認待ち・今後の予約・予約履歴を確認できます。"
                )
                .font(.subheadline)
                .foregroundStyle(
                    StudentReservationUI.textSecondary
                )
                .multilineTextAlignment(.center)

                Button {
                    showLogin = true
                } label: {
                    Label(
                        "ログイン・新規会員登録",
                        systemImage:
                            "person.crop.circle.badge.plus"
                    )
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        StudentReservationUI.brandGreen
                    )
                    .foregroundStyle(.white)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 15,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 6)

                Spacer()
            }
            .padding(.horizontal, 28)
        }
    }

    private var categoryPicker: some View {
        HStack(spacing: 4) {
            ForEach(
                ReservationCategory.allCases
            ) { category in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedCategory = category
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(category.title)
                            .font(
                                .system(
                                    size: 13,
                                    weight: .semibold
                                )
                            )

                        Text(
                            "\(categoryCount(category))"
                        )
                        .font(
                            .system(
                                size: 10,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(
                            selectedCategory == category
                                ? .white
                                : StudentReservationUI.textSecondary
                        )
                        .frame(
                            minWidth: 20,
                            minHeight: 20
                        )
                        .background(
                            selectedCategory == category
                                ? StudentReservationUI.brandGreen
                                : Color.black.opacity(0.05)
                        )
                        .clipShape(Capsule())
                    }
                    .foregroundStyle(
                        selectedCategory == category
                            ? StudentReservationUI.brandGreen
                            : StudentReservationUI.textSecondary
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 44
                    )
                    .background(
                        selectedCategory == category
                            ? Color.white
                            : Color.clear
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 13,
                            style: .continuous
                        )
                    )
                    .overlay {
                        if selectedCategory == category {
                            RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                            .stroke(
                                StudentReservationUI.brandGreen.opacity(0.28),
                                lineWidth: 1
                            )
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Color.black.opacity(0.045)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var reservationList: some View {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: 12
            ) {
                Text(sectionTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        StudentReservationUI.textSecondary
                    )
                    .padding(.horizontal, 2)

                ForEach(
                    filteredReservations
                ) { reservation in
                    HStack(
                        alignment: .top,
                        spacing: 12
                    ) {
                        Button {
                            selectedCoachIdForNavigation =
                                reservation.coachId
                            showCoachProfile = true
                        } label: {
                            ReservationCoachAvatarView(
                                imageURL:
                                    coachImageURLs[
                                        reservation.coachId
                                    ] ?? "",
                                size: 52
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "\(reservation.coachName)コーチのプロフィール"
                        )

                        Button {
                            selectedReservationForNavigation =
                                reservation
                            showReservationDetail = true
                        } label: {
                            reservationCardMainContent(
                                reservation
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
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
                            StudentReservationUI.border,
                            lineWidth: 1
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .refreshable {
            loadReservations()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        StudentReservationUI.softGreen
                    )
                    .frame(
                        width: 78,
                        height: 78
                    )

                Image(
                    systemName: emptyStateIcon
                )
                .font(.system(size: 32))
                .foregroundStyle(
                    StudentReservationUI.brandGreen
                )
            }

            Text(emptyStateTitle)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(
                    StudentReservationUI.textPrimary
                )

            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundStyle(
                    StudentReservationUI.textSecondary
                )
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
    private func reservationCardMainContent(
        _ reservation: ReservationItem
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            HStack(
                alignment: .top,
                spacing: 10
            ) {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(reservation.coachName)
                        .font(.headline)
                        .foregroundStyle(
                            StudentReservationUI.textPrimary
                        )

                    Text(
                        statusDescription(
                            reservation
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(
                        StudentReservationUI.textSecondary
                    )
                    .lineLimit(2)
                }

                Spacer(minLength: 6)

                statusBadge(reservation)
            }

            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    Label(
                        displayDate(
                            reservation.date
                        ),
                        systemImage: "calendar"
                    )

                    Spacer()

                    Label(
                        combinedTimeRange(
                            reservation.times
                        ),
                        systemImage: "clock"
                    )
                }

                HStack(spacing: 14) {
                    Label(
                        "\(max(reservation.times.count, 1))時間",
                        systemImage: "hourglass"
                    )

                    Spacer()

                    if reservation.totalPrice > 0 {
                        Label(
                            "¥\(reservation.totalPrice.formatted())",
                            systemImage:
                                "yensign.circle"
                        )
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            StudentReservationUI.brandGreen
                        )
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(
                StudentReservationUI.textSecondary
            )
            .padding(12)
            .background(
                StudentReservationUI.softGreen.opacity(0.48)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 13,
                    style: .continuous
                )
            )

            if let location =
                reservationLocationText(
                    reservation
                ) {
                HStack(
                    alignment: .top,
                    spacing: 7
                ) {
                    Image(
                        systemName:
                            "mappin.and.ellipse"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        StudentReservationUI.brandGreen
                    )

                    Text(location)
                        .font(.caption)
                        .foregroundStyle(
                            StudentReservationUI.textSecondary
                        )
                        .lineLimit(2)
                }
            }

            HStack {
                if reservation.status ==
                    "confirmed" &&
                    !isRefunded(
                        reservation
                    ) {
                    Label(
                        "支払いが必要です",
                        systemImage:
                            "creditcard.fill"
                    )
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        StudentReservationUI.brandGreen
                    )
                } else {
                    Text("予約詳細を見る")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            StudentReservationUI.brandGreen
                        )
                }

                Spacer()

                Image(
                    systemName:
                        "chevron.right"
                )
                .font(
                    .system(
                        size: 11,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    StudentReservationUI.brandGreen
                )
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .contentShape(Rectangle())
    }

    private func reservationLocationText(
        _ reservation: ReservationItem
    ) -> String? {
        let name =
            reservation.courtName
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        let address =
            reservation.courtAddress
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        let legacy =
            reservation.court
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        if !name.isEmpty &&
            !address.isEmpty {
            return "\(name)（\(address)）"
        }

        if !name.isEmpty {
            return name
        }

        if !address.isEmpty {
            return address
        }

        if !legacy.isEmpty {
            return legacy
        }

        return nil
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
            if reservation.status == "weather_cancelled" ||
                reservation.cancellationSource == "weather" {
                return "雨天・施設都合キャンセル・全額返金済み"
            }

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
            if reservation.status == "weather_cancelled" ||
                reservation.cancellationSource == "weather" {
                return "雨天・施設都合キャンセル・全額返金処理中"
            }
            return "返金を処理しています"
        }

        if reservation.weatherCancellationStatus == "pending" {
            return reservation.weatherCancellationRequesterRole == "student"
                ? "雨天・施設都合キャンセル・コーチの回答待ち"
                : "コーチから雨天・施設都合キャンセル申請があります"
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

        case "weather_cancelled":
            return "雨天・施設都合で双方合意キャンセル"

        case "student_cancelled":
            if reservation.cancellationRefundPercent == 0 {
                return "生徒都合でキャンセル済み・返金なし"
            } else if reservation.cancellationRefundPercent == 50 {
                return "生徒都合でキャンセル済み・50%返金"
            } else {
                return "生徒都合でキャンセル済み・全額返金"
            }

        case "cancelled", "canceled":
            if reservation.cancellationSource == "student_withdrawal" ||
                reservation.cancellationSource == "block" {
                return "取り下げた予約です"
            }
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
                            weatherCancellationStatus:
                                data["weatherCancellationStatus"] as? String
                                ?? "",
                            weatherCancellationRequesterRole:
                                data["weatherCancellationRequesterRole"] as? String
                                ?? "",
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
                            courtName:
                                data["courtName"] as? String
                                ?? "",
                            courtAddress:
                                data["courtAddress"] as? String
                                ?? "",
                            court:
                                data["court"] as? String
                                ?? "",
                            createdAt:
                                data["createdAt"] as? Timestamp
                        )
                    } ?? []

                    reservations = loadedReservations
                    errorMessage = ""

                    loadCoachImages(
                        for: loadedReservations
                    )
                }
            }
    }

    private func loadCoachImages(
        for reservations: [ReservationItem]
    ) {
        let coachIds = Set(
            reservations
                .map(\.coachId)
                .filter { !$0.isEmpty }
        )

        guard !coachIds.isEmpty else {
            coachImageURLs = [:]
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var loadedImages: [String: String] = [:]

        for coachId in coachIds {
            group.enter()

            db.collection("coaches")
                .document(coachId)
                .getDocument { snapshot, _ in
                    let imageURL =
                        snapshot?.data()?["imageURL"]
                        as? String ?? ""

                    lock.lock()
                    loadedImages[coachId] = imageURL
                    lock.unlock()

                    group.leave()
                }
        }

        group.notify(queue: .main) {
            coachImageURLs = loadedImages
        }
    }

    @ViewBuilder
    private func statusBadge(
        _ reservation: ReservationItem
    ) -> some View {
        if isRefunded(reservation) {
            reservationBadge(
                title:
                    reservation.status ==
                        "student_cancelled" &&
                    reservation.cancellationRefundPercent == 50
                        ? "50%返金済み"
                        : "返金済み",
                icon:
                    "arrow.uturn.backward",
                color: .purple
            )

        } else if isRefundFailed(
            reservation
        ) {
            reservationBadge(
                title: "返金確認中",
                icon:
                    "exclamationmark.triangle",
                color: .red
            )

        } else if
            reservation
                .weatherCancellationStatus
                == "pending" {
            reservationBadge(
                title:
                    reservation
                        .weatherCancellationRequesterRole
                        == "student"
                        ? "回答待ち"
                        : "要回答",
                icon: "cloud.rain",
                color: .orange
            )

        } else if isRefundProcessing(
            reservation
        ) {
            reservationBadge(
                title: "返金処理中",
                icon:
                    "arrow.triangle.2.circlepath",
                color: .orange
            )

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
            reservationBadge(
                title: "支払い待ち",
                icon: "creditcard",
                color:
                    StudentReservationUI.brandGreen
            )

        case "paid":
            reservationBadge(
                title: "予約確定",
                icon: "checkmark.circle",
                color:
                    StudentReservationUI.brandGreen
            )

        case "rejected":
            reservationBadge(
                title: "却下",
                icon: "xmark.circle",
                color: .red
            )

        case "reserved":
            reservationBadge(
                title: "予約済み",
                icon: "checkmark.circle",
                color:
                    StudentReservationUI.brandGreen
            )

        case "coach_cancelled":
            reservationBadge(
                title: "コーチ都合",
                icon: "minus.circle",
                color: .purple
            )

        case "weather_cancelled":
            reservationBadge(
                title: "雨天中止",
                icon: "cloud.rain",
                color: .blue
            )

        case "student_cancelled":
            reservationBadge(
                title: "キャンセル",
                icon: "minus.circle",
                color:
                    StudentReservationUI.textSecondary
            )

        case "cancelled", "canceled":
            reservationBadge(
                title: "キャンセル",
                icon: "minus.circle",
                color:
                    StudentReservationUI.textSecondary
            )

        case "completed":
            reservationBadge(
                title: "受講済み",
                icon: "checkmark.seal",
                color:
                    StudentReservationUI.textSecondary
            )

        default:
            reservationBadge(
                title: "承認待ち",
                icon: "clock",
                color: .orange
            )
        }
    }

    private func reservationBadge(
        title: String,
        icon: String,
        color: Color
    ) -> some View {
        Label(
            title,
            systemImage: icon
        )
        .font(
            .system(
                size: 10,
                weight: .semibold
            )
        )
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .frame(height: 27)
        .background(
            color.opacity(0.10)
        )
        .clipShape(Capsule())
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
    let coachImageURL: String
    let onCancellationCompleted: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var reviewSubmitted: Bool
    @State private var hasReviewedCoach = false
    @State private var isCheckingCoachReview = true
    @State private var reviewEligibilityError = ""

    @State private var canMessageCoach = false
    @State private var isCheckingChatAccess = false

    @State private var isCancelling = false
    @State private var showCancellationConfirmation = false
    @State private var showCancellationResult = false
    @State private var cancellationResultTitle = ""
    @State private var cancellationResultMessage = ""
    @State private var cancellationErrorMessage = ""

    @State private var isWithdrawingReservation = false
    @State private var showReservationWithdrawalConfirmation = false
    @State private var showReservationWithdrawalResult = false
    @State private var reservationWithdrawalResultMessage = ""
    @State private var reservationWithdrawalErrorMessage = ""

    @State private var weatherCancellationStatus: String
    @State private var weatherCancellationRequesterRole: String
    @State private var isUpdatingWeatherCancellation = false
    @State private var weatherErrorMessage = ""
    @State private var showWeatherRequestConfirmation = false
    @State private var showWeatherWithdrawConfirmation = false
    @State private var showWeatherApproveConfirmation = false
    @State private var showWeatherRejectConfirmation = false
    @State private var showWeatherResult = false
    @State private var weatherResultTitle = ""
    @State private var weatherResultMessage = ""

    private let db = Firestore.firestore()
    private let functions = Functions.functions(region: "asia-northeast1")

    init(
        reservation: ReservationItem,
        coachImageURL: String = "",
        onCancellationCompleted: @escaping () -> Void = {}
    ) {
        self.reservation = reservation
        self.coachImageURL = coachImageURL
        self.onCancellationCompleted = onCancellationCompleted
        _reviewSubmitted = State(
            initialValue: !reservation.reviewId.isEmpty
        )
        _weatherCancellationStatus = State(
            initialValue: reservation.weatherCancellationStatus
        )
        _weatherCancellationRequesterRole = State(
            initialValue: reservation.weatherCancellationRequesterRole
        )
    }

    private var coach: Coach {
        Coach(
            id: reservation.coachId,
            name: reservation.coachName,
            price: reservation.pricePerHour,
            area: "",
            imageURL: coachImageURL,
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
        ZStack {
            StudentReservationUI.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    statusHeader

                    coachInformationCard

                    reservationInformationCard

                    if currentReservationAllowsChat &&
                        canMessageCoach &&
                        !isCheckingChatAccess {
                        NavigationLink {
                            ChatView(coach: coach)
                        } label: {
                            actionButtonLabel(
                                title: "メッセージを送る",
                                icon: "message.fill"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if canWithdrawUnpaidReservation {
                        withdrawalCard
                    }

                    if reservation.status ==
                        "confirmed" {
                        NavigationLink {
                            PaymentView(
                                reservationId:
                                    reservation.id,
                                coach: coach,
                                date: lessonDate,
                                times:
                                    reservation.times,
                                totalPrice:
                                    reservation.totalPrice
                            )
                        } label: {
                            actionButtonLabel(
                                title: "支払いへ進む",
                                icon: "creditcard.fill"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if shouldShowWeatherCancellationSection {
                        weatherCancellationSection
                    }

                    if canCancelPaidReservation {
                        paidCancellationCard
                    }

                    reviewSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
        }
        .tint(StudentReservationUI.brandGreen)
        .navigationTitle("予約詳細")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkExistingCoachReview()
            loadChatAccessState()
        }
        .confirmationDialog(
            reservation.status == "pending"
                ? "予約申請を取り下げますか？"
                : "承認済み予約を取り下げますか？",
            isPresented: $showReservationWithdrawalConfirmation,
            titleVisibility: .visible
        ) {
            Button("取り下げる", role: .destructive) {
                withdrawReservationRequest()
            }

            Button("戻る", role: .cancel) {}
        } message: {
            Text(
                "まだ支払いは発生していません。取り下げると予約はキャンセルされ、この時間枠は再び予約可能になります。"
            )
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
        .confirmationDialog(
            "雨天・施設都合でキャンセル申請しますか？",
            isPresented: $showWeatherRequestConfirmation,
            titleVisibility: .visible
        ) {
            Button("相手に申請する") {
                requestWeatherCancellation()
            }
            Button("戻る", role: .cancel) {}
        } message: {
            Text(
                "相手が同意した場合のみ予約がキャンセルされ、全額返金されます。"
            )
        }
        .confirmationDialog(
            "雨天キャンセル申請を取り下げますか？",
            isPresented: $showWeatherWithdrawConfirmation,
            titleVisibility: .visible
        ) {
            Button("申請を取り下げる", role: .destructive) {
                withdrawWeatherCancellation()
            }
            Button("戻る", role: .cancel) {}
        } message: {
            Text("取り下げると予約はそのまま継続します。")
        }
        .confirmationDialog(
            "キャンセルに同意しますか？",
            isPresented: $showWeatherApproveConfirmation,
            titleVisibility: .visible
        ) {
            Button("同意して全額返金", role: .destructive) {
                respondWeatherCancellation(approve: true)
            }
            Button("戻る", role: .cancel) {}
        } message: {
            Text(
                "同意すると予約はキャンセルされ、全額返金の手続きが開始されます。"
            )
        }
        .confirmationDialog(
            "キャンセル申請を拒否しますか？",
            isPresented: $showWeatherRejectConfirmation,
            titleVisibility: .visible
        ) {
            Button("拒否する", role: .destructive) {
                respondWeatherCancellation(approve: false)
            }
            Button("戻る", role: .cancel) {}
        } message: {
            Text("拒否した場合、予約はそのまま継続します。")
        }
        .alert(
            "予約を取り下げました",
            isPresented: $showReservationWithdrawalResult
        ) {
            Button("OK") {
                onCancellationCompleted()
                dismiss()
            }
        } message: {
            Text(reservationWithdrawalResultMessage)
        }
        .alert(
            weatherResultTitle,
            isPresented: $showWeatherResult
        ) {
            Button("OK") {
                onCancellationCompleted()
                if reservation.status == "weather_cancelled" ||
                    weatherCancellationStatus == "refund_processing" {
                    dismiss()
                }
            }
        } message: {
            Text(weatherResultMessage)
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


    private var coachInformationCard: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            HStack {
                Text("担当コーチ")
                    .font(.headline)
                    .foregroundStyle(
                        StudentReservationUI.textPrimary
                    )

                Spacer()

                Text("画像をタップしてプロフィール")
                    .font(.caption2)
                    .foregroundStyle(
                        StudentReservationUI.textSecondary
                    )
            }

            HStack(spacing: 14) {
                NavigationLink {
                    CoachProfileDestinationView(
                        coachId:
                            reservation.coachId
                    )
                } label: {
                    ReservationCoachAvatarView(
                        imageURL: coachImageURL,
                        size: 58
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(reservation.coachName)コーチのプロフィール"
                )

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text(
                        reservation.coachName
                    )
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        StudentReservationUI.textPrimary
                    )

                    Text("予約したコーチ")
                        .font(.caption)
                        .foregroundStyle(
                            StudentReservationUI.textSecondary
                        )
                }

                Spacer()

                Image(
                    systemName:
                        "chevron.right"
                )
                .font(
                    .system(
                        size: 11,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    StudentReservationUI.brandGreen
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
                StudentReservationUI.border,
                lineWidth: 1
            )
        }
    }

    private var reservationInformationCard: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(
                        StudentReservationUI.brandGreen
                    )

                Text("レッスン情報")
                    .font(.headline)
                    .foregroundStyle(
                        StudentReservationUI.textPrimary
                    )
            }

            detailRow(
                title: "日付",
                value:
                    displayDate(
                        reservation.date
                    )
            )

            Divider()

            detailRow(
                title: "時間",
                value:
                    combinedTimeRange(
                        reservation.times
                    )
            )

            Divider()

            detailRow(
                title: "レッスン時間",
                value:
                    "\(max(reservation.times.count, 1))時間"
            )

            Divider()

            detailRow(
                title: "料金",
                value:
                    "¥\(reservation.totalPrice.formatted())"
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
                    StudentReservationUI.brandGreen
                )

                if !reservation.courtName
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty {
                    Text(reservation.courtName)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            StudentReservationUI.textPrimary
                        )
                }

                if !reservation.courtAddress
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty {
                    Text(reservation.courtAddress)
                        .font(.subheadline)
                        .foregroundStyle(
                            StudentReservationUI.textSecondary
                        )
                }

                if reservation.courtName
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty &&
                    reservation.courtAddress
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty {
                    Text(
                        reservation.court
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty
                            ? "場所未登録"
                            : reservation.court
                    )
                    .font(.subheadline)
                    .foregroundStyle(
                        StudentReservationUI.textSecondary
                    )
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .padding(12)
            .background(
                StudentReservationUI.softGreen.opacity(0.45)
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
                StudentReservationUI.border,
                lineWidth: 1
            )
        }
    }

    private func actionButtonLabel(
        title: String,
        icon: String
    ) -> some View {
        HStack(spacing: 8) {
            Spacer()

            Image(systemName: icon)

            Text(title)
                .fontWeight(.semibold)

            Spacer()
        }
        .frame(height: 50)
        .foregroundStyle(.white)
        .background(
            StudentReservationUI.brandGreen
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 15,
                style: .continuous
            )
        )
    }

    private var withdrawalCard: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Label(
                reservation.status == "pending"
                    ? "予約申請の取り下げ"
                    : "予約の取り下げ",
                systemImage:
                    "arrow.uturn.backward.circle"
            )
            .font(.headline)
            .foregroundStyle(
                StudentReservationUI.textPrimary
            )

            Text(
                reservation.status == "pending"
                    ? "コーチが承認する前であれば、予約申請を取り下げられます。"
                    : "まだ支払いは完了していません。取り下げると予約枠は再び予約可能になります。"
            )
            .font(.caption)
            .foregroundStyle(
                StudentReservationUI.textSecondary
            )

            Button {
                showReservationWithdrawalConfirmation = true
            } label: {
                HStack {
                    Spacer()

                    if isWithdrawingReservation {
                        ProgressView()
                    } else {
                        Text(
                            reservation.status == "pending"
                                ? "予約申請を取り下げる"
                                : "予約を取り下げる"
                        )
                        .fontWeight(.semibold)
                    }

                    Spacer()
                }
                .frame(height: 46)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(isWithdrawingReservation)

            if !reservationWithdrawalErrorMessage.isEmpty {
                Text(
                    reservationWithdrawalErrorMessage
                )
                .font(.caption)
                .foregroundStyle(.red)
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
                Color.red.opacity(0.15),
                lineWidth: 1
            )
        }
    }

    private var paidCancellationCard: some View {
        VStack(
            alignment: .leading,
            spacing: 12
        ) {
            Label(
                "予約キャンセル",
                systemImage:
                    "exclamationmark.circle"
            )
            .font(.headline)
            .foregroundStyle(
                StudentReservationUI.textPrimary
            )

            Text("キャンセル時の返金")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(cancellationPolicyPreview)
                .font(.caption)
                .foregroundStyle(
                    StudentReservationUI.textSecondary
                )

            Text(
                "最終的な返金率・返金額は、キャンセル実行時にサーバー側で確定します。"
            )
            .font(.caption2)
            .foregroundStyle(
                StudentReservationUI.textSecondary
            )

            Button {
                showCancellationConfirmation = true
            } label: {
                HStack {
                    Spacer()

                    if isCancelling {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Label(
                            "予約をキャンセルする",
                            systemImage:
                                "xmark.circle.fill"
                        )
                        .fontWeight(.semibold)
                    }

                    Spacer()
                }
                .frame(height: 48)
                .foregroundStyle(.white)
                .background(Color.red)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(isCancelling)

            if !cancellationErrorMessage.isEmpty {
                Text(
                    cancellationErrorMessage
                )
                .font(.caption)
                .foregroundStyle(.red)
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
                Color.red.opacity(0.15),
                lineWidth: 1
            )
        }
    }

    @ViewBuilder
    private var reviewSection: some View {
        if reviewSubmitted {
            Label(
                "レビュー投稿済み",
                systemImage:
                    "checkmark.seal.fill"
            )
            .fontWeight(.semibold)
            .foregroundStyle(
                StudentReservationUI.brandGreen
            )
            .frame(
                maxWidth: .infinity
            )
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
                    StudentReservationUI.border,
                    lineWidth: 1
                )
            }

        } else if canWriteReview {
            if isCheckingCoachReview {
                ProgressView(
                    "レビュー状況を確認中…"
                )
                .font(.caption)
                .foregroundStyle(
                    StudentReservationUI.textSecondary
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)

            } else if
                !reviewEligibilityError.isEmpty {
                VStack(spacing: 10) {
                    Text(
                        "レビュー状況を確認できませんでした"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        StudentReservationUI.textSecondary
                    )

                    Button("再確認") {
                        checkExistingCoachReview()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(
                    maxWidth: .infinity
                )

            } else if !hasReviewedCoach {
                NavigationLink {
                    ReviewSubmissionView(
                        reservationId:
                            reservation.id,
                        coachName:
                            reservation.coachName
                    ) {
                        reviewSubmitted = true
                        hasReviewedCoach = true
                    }
                } label: {
                    actionButtonLabel(
                        title: "レビューを書く",
                        icon: "star.fill"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var weatherCancellationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                "雨天・施設都合",
                systemImage: "cloud.rain.fill"
            )
            .font(.headline)
            .foregroundStyle(StudentReservationUI.brandGreen)

            if weatherCancellationStatus == "pending" {
                if weatherCancellationRequesterRole == "student" {
                    Text(
                        "コーチへキャンセル申請を送信しています。コーチが同意すると、予約はキャンセルされ全額返金されます。"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Button {
                        showWeatherWithdrawConfirmation = true
                    } label: {
                        Label(
                            "申請を取り下げる",
                            systemImage: "arrow.uturn.backward"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isUpdatingWeatherCancellation)
                } else {
                    Text(
                        "コーチから雨天・施設都合によるキャンセル申請が届いています。同意すると全額返金、拒否すると予約は継続します。"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            showWeatherApproveConfirmation = true
                        } label: {
                            Label(
                                "同意する",
                                systemImage: "checkmark.circle.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(isUpdatingWeatherCancellation)

                        Button {
                            showWeatherRejectConfirmation = true
                        } label: {
                            Label(
                                "同意しない",
                                systemImage: "xmark.circle"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(isUpdatingWeatherCancellation)
                    }
                }
            } else if canRequestWeatherCancellation {
                Text(
                    "レッスン開始24時間前から、雨天やコート利用不可を理由にキャンセル申請できます。相手の同意があった場合のみ全額返金されます。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button {
                    showWeatherRequestConfirmation = true
                } label: {
                    Label(
                        "雨天・施設都合でキャンセル申請",
                        systemImage: "cloud.rain"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .disabled(isUpdatingWeatherCancellation)
            }

            if isUpdatingWeatherCancellation {
                HStack {
                    Spacer()
                    ProgressView("処理中…")
                    Spacer()
                }
                .font(.caption)
            }

            if !weatherErrorMessage.isEmpty {
                Text(weatherErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color.white)
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                StudentReservationUI.border,
                lineWidth: 1
            )
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    private var shouldShowWeatherCancellationSection: Bool {
        weatherCancellationStatus == "pending" ||
        canRequestWeatherCancellation
    }

    private var canRequestWeatherCancellation: Bool {
        guard reservation.status == "paid",
              reservation.paymentStatus == "paid",
              weatherCancellationStatus != "pending",
              !isRefundProcessing,
              let lessonStartDate else {
            return false
        }

        let interval = lessonStartDate.timeIntervalSinceNow
        let twentyFourHours = 24.0 * 60.0 * 60.0

        return interval > 0 &&
            interval <= twentyFourHours
    }

    private func loadChatAccessState() {
        guard currentReservationAllowsChat else {
            canMessageCoach = false
            isCheckingChatAccess = false
            return
        }

        guard
            let studentId =
                Auth.auth().currentUser?.uid,
            !reservation.coachId.isEmpty
        else {
            canMessageCoach = false
            isCheckingChatAccess = false
            return
        }

        isCheckingChatAccess = true
        canMessageCoach = false

        functions
            .httpsCallable(
                "getChatMessagingStatus"
            )
            .call(
                [
                    "studentId": studentId,
                    "coachId":
                        reservation.coachId
                ]
            ) { result, error in
                DispatchQueue.main.async {
                    isCheckingChatAccess = false

                    if let error {
                        canMessageCoach = false
                        print(
                            "予約詳細チャット利用可否確認失敗:",
                            error.localizedDescription
                        )
                        return
                    }

                    guard
                        let data =
                            result?.data
                            as? [String: Any]
                    else {
                        canMessageCoach = false
                        return
                    }

                    canMessageCoach =
                        data["canSend"]
                        as? Bool
                        ?? false
                }
            }
    }

    private func withdrawReservationRequest() {
        guard !isWithdrawingReservation else {
            return
        }

        isWithdrawingReservation = true
        reservationWithdrawalErrorMessage = ""

        functions
            .httpsCallable("withdrawReservationRequest")
            .call(["reservationId": reservation.id]) { result, error in
                DispatchQueue.main.async {
                    isWithdrawingReservation = false

                    if let error {
                        reservationWithdrawalErrorMessage =
                            "予約を取り下げられませんでした: " +
                            error.localizedDescription
                        return
                    }

                    let data = result?.data as? [String: Any]
                    let alreadyWithdrawn =
                        data?["alreadyWithdrawn"] as? Bool ?? false

                    reservationWithdrawalResultMessage =
                        alreadyWithdrawn
                        ? "この予約はすでに取り下げ済みです。"
                        : "予約を取り下げました。予約枠は再び予約可能になっています。"
                    showReservationWithdrawalResult = true
                }
            }
    }

    private func requestWeatherCancellation() {
        guard !isUpdatingWeatherCancellation else {
            return
        }

        isUpdatingWeatherCancellation = true
        weatherErrorMessage = ""

        functions
            .httpsCallable("requestWeatherCancellation")
            .call(["reservationId": reservation.id]) { _, error in
                DispatchQueue.main.async {
                    isUpdatingWeatherCancellation = false

                    if let error {
                        weatherErrorMessage =
                            "雨天キャンセルを申請できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    weatherCancellationStatus = "pending"
                    weatherCancellationRequesterRole = "student"
                    weatherResultTitle = "申請を送信しました"
                    weatherResultMessage =
                        "コーチが同意すると、予約はキャンセルされ全額返金されます。"
                    showWeatherResult = true
                }
            }
    }

    private func withdrawWeatherCancellation() {
        guard !isUpdatingWeatherCancellation else {
            return
        }

        isUpdatingWeatherCancellation = true
        weatherErrorMessage = ""

        functions
            .httpsCallable("withdrawWeatherCancellation")
            .call(["reservationId": reservation.id]) { _, error in
                DispatchQueue.main.async {
                    isUpdatingWeatherCancellation = false

                    if let error {
                        weatherErrorMessage =
                            "申請を取り下げられませんでした: " +
                            error.localizedDescription
                        return
                    }

                    weatherCancellationStatus = "withdrawn"
                    weatherCancellationRequesterRole = ""
                    weatherResultTitle = "申請を取り下げました"
                    weatherResultMessage =
                        "予約はキャンセルされず、そのまま継続します。"
                    showWeatherResult = true
                }
            }
    }

    private func respondWeatherCancellation(
        approve: Bool
    ) {
        guard !isUpdatingWeatherCancellation else {
            return
        }

        isUpdatingWeatherCancellation = true
        weatherErrorMessage = ""

        functions
            .httpsCallable("respondWeatherCancellation")
            .call([
                "reservationId": reservation.id,
                "approve": approve
            ]) { result, error in
                DispatchQueue.main.async {
                    isUpdatingWeatherCancellation = false

                    if let error {
                        weatherErrorMessage =
                            "雨天キャンセルへ回答できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    if approve {
                        let data =
                            result?.data as? [String: Any]
                        let refundAmount =
                            integerValue(data?["refundAmount"])

                        weatherCancellationStatus =
                            "refund_processing"
                        weatherResultTitle =
                            "キャンセルに同意しました"
                        weatherResultMessage =
                            refundAmount > 0
                            ? "予約をキャンセルし、¥\(refundAmount)の全額返金手続きを開始しました。"
                            : "予約をキャンセルし、全額返金の手続きを開始しました。"
                    } else {
                        weatherCancellationStatus = "rejected"
                        weatherCancellationRequesterRole = ""
                        weatherResultTitle =
                            "キャンセル申請を拒否しました"
                        weatherResultMessage =
                            "予約はキャンセルされず、そのまま継続します。"
                    }

                    showWeatherResult = true
                }
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
                    reservation.status == "weather_cancelled" ||
                    reservation.cancellationSource == "weather"
                    ? "双方合意による雨天・施設都合キャンセルです"
                    : reservation.status == "student_cancelled"
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

        case "weather_cancelled":
            statusMessage(
                icon: "cloud.rain.fill",
                color: .blue,
                title: "雨天・施設都合でキャンセル",
                message: "双方合意により全額返金の対象となった予約です"
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

    private var currentReservationAllowsChat: Bool {
        // この予約詳細では「別の予約で支払い実績があるか」ではなく、
        // 今開いている予約そのものに支払い実績があることを必須にする。
        //
        // getChatMessagingStatusは生徒×コーチ単位の最終安全確認として
        // 引き続き利用するため、UI条件とサーバー条件の両方を満たした時だけ
        // チャットボタンが表示される。
        let hasPaidRecord =
            reservation.status == "paid" ||
            reservation.status == "completed" ||
            [
                "paid",
                "partially_refunded",
                "refund_processing",
                "refund_failed"
            ]
            .contains(
                reservation.paymentStatus
            )

        guard hasPaidRecord else {
            return false
        }

        // 全額返金扱いの予約からはチャット導線を出さない。
        if reservation.paymentStatus == "refunded" {
            return false
        }

        return true
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

    private var canWithdrawUnpaidReservation: Bool {
        guard ["pending", "confirmed"].contains(reservation.status),
              reservation.paymentStatus != "paid",
              !isRefundProcessing else {
            return false
        }

        return true
    }

    private var canCancelPaidReservation: Bool {
        guard reservation.status == "paid",
              reservation.paymentStatus == "paid",
              weatherCancellationStatus != "pending",
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
        [
            "coach_cancelled",
            "student_cancelled",
            "weather_cancelled",
            "cancelled",
            "canceled"
        ].contains(reservation.status)
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
        HStack(
            alignment: .top,
            spacing: 14
        ) {
            ZStack {
                Circle()
                    .fill(
                        color.opacity(0.10)
                    )
                    .frame(
                        width: 48,
                        height: 48
                    )

                Image(systemName: icon)
                    .font(
                        .system(
                            size: 20,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(color)
            }

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(
                        StudentReservationUI.textPrimary
                    )

                Text(message)
                    .font(.caption)
                    .foregroundStyle(
                        StudentReservationUI.textSecondary
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }

            Spacer()
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
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
                color.opacity(0.18),
                lineWidth: 1
            )
        }
    }

    private func detailRow(
        title: String,
        value: String
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(
                    StudentReservationUI.textSecondary
                )

            Spacer()

            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(
                    StudentReservationUI.textPrimary
                )
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

private struct ReservationCoachAvatarView: View {

    let imageURL: String
    let size: CGFloat

    var body: some View {
        AsyncImage(
            url: URL(string: imageURL)
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
            StudentReservationUI.softGreen
        )
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(
                    Color(.separator).opacity(0.25),
                    lineWidth: 0.5
                )
        )
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .resizable()
            .scaledToFit()
            .padding(size * 0.22)
            .foregroundStyle(StudentReservationUI.brandGreen)
    }
}


#Preview {
    NavigationStack {
        ReservationListView()
    }
}
