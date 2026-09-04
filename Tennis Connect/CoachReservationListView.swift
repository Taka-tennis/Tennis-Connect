// 修正版：コーチの予約一覧を「対応待ち・今後の予約・履歴」に整理

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

private enum CoachReservationUI {
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

struct CoachReservationListView: View {

    struct Reservation: Identifiable {
        let id: String
        let studentId: String
        let studentName: String
        let date: String
        let times: [String]
        let court: String
        let status: String
        let paymentStatus: String
        let refundStatus: String
        let cancellationSource: String
        let cancellationRefundPercent: Int
        let weatherCancellationStatus: String
        let weatherCancellationRequesterRole: String
        let totalPrice: Int
        let createdAt: Timestamp?
    }

    private enum ReservationCategory: String, CaseIterable, Identifiable {
        case pending
        case upcoming
        case history

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pending:
                return "対応待ち"
            case .upcoming:
                return "今後"
            case .history:
                return "履歴"
            }
        }
    }

    @State private var reservations: [Reservation] = []
    @State private var resolvedStudentNames: [String: String] = [:]
    @State private var resolvedStudentImageURLs: [String: String] = [:]
    @State private var currentCoachName = ""

    @State private var selectedStudentIdForNavigation: String?
    @State private var selectedStudentNameForNavigation = ""
    @State private var selectedStudentImageURLForNavigation = ""
    @State private var selectedReservationForNavigation: Reservation?

    @State private var showStudentProfile = false
    @State private var showReservationDetail = false

    @State private var selectedCategory: ReservationCategory = .pending
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var updatingReservationId: String?

    @State private var reservationToApprove: Reservation?
    @State private var showApproveAlert = false
    @State private var reservationToReject: Reservation?
    @State private var showRejectAlert = false
    @State private var reservationToRefund: Reservation?
    @State private var showRefundAlert = false

    @State private var reservationToWeatherRequest: Reservation?
    @State private var showWeatherRequestAlert = false
    @State private var reservationToWeatherWithdraw: Reservation?
    @State private var showWeatherWithdrawAlert = false
    @State private var reservationToWeatherApprove: Reservation?
    @State private var showWeatherApproveAlert = false
    @State private var reservationToWeatherReject: Reservation?
    @State private var showWeatherRejectAlert = false

    private let db = Firestore.firestore()

    var body: some View {
        ZStack {
            CoachReservationUI.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                categoryPicker

                Group {
                    if isLoading && reservations.isEmpty {
                        ProgressView("予約を読み込み中…")
                            .tint(CoachReservationUI.brandGreen)
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
        .tint(CoachReservationUI.brandGreen)
        .navigationTitle("予約一覧")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !errorMessage.isEmpty {
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
            loadReservations()
        }
        .navigationDestination(
            isPresented: $showStudentProfile
        ) {
            if let studentId =
                selectedStudentIdForNavigation {
                StudentPublicProfileView(
                    studentId: studentId,
                    initialDisplayName:
                        selectedStudentNameForNavigation,
                    initialImageURL:
                        selectedStudentImageURLForNavigation
                )
            }
        }
        .navigationDestination(
            isPresented: $showReservationDetail
        ) {
            if let reservation =
                selectedReservationForNavigation {
                CoachReservationDetailView(
                    reservation: reservation,
                    studentName:
                        displayStudentName(
                            for: reservation
                        ),
                    studentImageURL:
                        resolvedStudentImageURLs[
                            reservation.id
                        ] ?? "",
                    coachName:
                        currentCoachName
                )
            }
        }
        .alert("この予約を承認しますか？", isPresented: $showApproveAlert) {
            Button("キャンセル", role: .cancel) {
                reservationToApprove = nil
            }

            Button("承認する") {
                if let reservation = reservationToApprove {
                    approveReservation(reservation)
                }
                reservationToApprove = nil
            }
        } message: {
            Text("承認すると、生徒へ通知され、支払い手続きへ進めるようになります。")
        }
        .alert("予約申請を却下しますか？", isPresented: $showRejectAlert) {
            Button("キャンセル", role: .cancel) {
                reservationToReject = nil
            }

            Button("却下する", role: .destructive) {
                if let reservation = reservationToReject {
                    rejectReservation(reservation)
                }
                reservationToReject = nil
            }
        } message: {
            Text("却下すると、生徒へ通知され、この日時は再び予約可能な空き枠へ戻ります。")
        }
        .alert("この予約をキャンセルして全額返金しますか？", isPresented: $showRefundAlert) {
            Button("戻る", role: .cancel) {
                reservationToRefund = nil
            }

            Button("キャンセル・返金する", role: .destructive) {
                if let reservation = reservationToRefund {
                    requestCoachRefund(reservation)
                }
                reservationToRefund = nil
            }
        } message: {
            Text("予約をコーチ都合でキャンセルし、生徒へ全額返金します。空き枠も予約可能な状態へ戻ります。この操作は取り消せません。")
        }
        .alert(
            "雨天・施設都合でキャンセル申請しますか？",
            isPresented: $showWeatherRequestAlert
        ) {
            Button("戻る", role: .cancel) {
                reservationToWeatherRequest = nil
            }

            Button("生徒へ申請する") {
                if let reservation = reservationToWeatherRequest {
                    requestWeatherCancellation(reservation)
                }
                reservationToWeatherRequest = nil
            }
        } message: {
            Text("生徒が同意した場合のみ予約がキャンセルされ、全額返金されます。")
        }
        .alert(
            "雨天キャンセル申請を取り下げますか？",
            isPresented: $showWeatherWithdrawAlert
        ) {
            Button("戻る", role: .cancel) {
                reservationToWeatherWithdraw = nil
            }

            Button("取り下げる", role: .destructive) {
                if let reservation = reservationToWeatherWithdraw {
                    withdrawWeatherCancellation(reservation)
                }
                reservationToWeatherWithdraw = nil
            }
        } message: {
            Text("取り下げると予約はそのまま継続します。")
        }
        .alert(
            "生徒からの雨天キャンセル申請に同意しますか？",
            isPresented: $showWeatherApproveAlert
        ) {
            Button("戻る", role: .cancel) {
                reservationToWeatherApprove = nil
            }

            Button("同意して全額返金", role: .destructive) {
                if let reservation = reservationToWeatherApprove {
                    respondWeatherCancellation(
                        reservation,
                        approve: true
                    )
                }
                reservationToWeatherApprove = nil
            }
        } message: {
            Text("同意すると予約をキャンセルし、生徒への全額返金を開始します。")
        }
        .alert(
            "生徒からの雨天キャンセル申請を拒否しますか？",
            isPresented: $showWeatherRejectAlert
        ) {
            Button("戻る", role: .cancel) {
                reservationToWeatherReject = nil
            }

            Button("拒否する", role: .destructive) {
                if let reservation = reservationToWeatherReject {
                    respondWeatherCancellation(
                        reservation,
                        approve: false
                    )
                }
                reservationToWeatherReject = nil
            }
        } message: {
            Text("拒否した場合、予約はそのまま継続します。")
        }
    }

    private var categoryPicker: some View {
        HStack(spacing: 4) {
            ForEach(ReservationCategory.allCases) { category in
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

                        Text("\(categoryCount(category))")
                            .font(
                                .system(
                                    size: 10,
                                    weight: .bold
                                )
                            )
                            .frame(
                                minWidth: 19,
                                minHeight: 19
                            )
                            .background(
                                selectedCategory == category
                                    ? CoachReservationUI.brandGreen
                                    : Color.black.opacity(0.06)
                            )
                            .foregroundStyle(
                                selectedCategory == category
                                    ? Color.white
                                    : CoachReservationUI.textSecondary
                            )
                            .clipShape(Circle())
                    }
                    .foregroundStyle(
                        selectedCategory == category
                            ? CoachReservationUI.brandGreen
                            : CoachReservationUI.textSecondary
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        selectedCategory == category
                            ? Color.white
                            : Color.clear
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 11,
                            style: .continuous
                        )
                    )
                    .overlay {
                        if selectedCategory == category {
                            RoundedRectangle(
                                cornerRadius: 11,
                                style: .continuous
                            )
                            .stroke(
                                CoachReservationUI.brandGreen
                                    .opacity(0.38),
                                lineWidth: 1
                            )
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(category.title) \(categoryCount(category))件"
                )
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.045))
        .clipShape(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var reservationList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(sectionTitle)
                    .font(
                        .system(
                            size: 13,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(
                        CoachReservationUI.textSecondary
                    )
                    .padding(.horizontal, 2)
                    .padding(.top, 4)

                ForEach(filteredReservations) { reservation in
                    reservationCard(reservation)
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
                                CoachReservationUI.border,
                                lineWidth: 1
                            )
                        }
                        .shadow(
                            color: Color.black.opacity(0.035),
                            radius: 8,
                            x: 0,
                            y: 3
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
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
                    .fill(CoachReservationUI.softGreen)
                    .frame(width: 74, height: 74)

                Image(systemName: emptyStateIcon)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(
                        CoachReservationUI.brandGreen
                    )
            }

            Text(emptyStateTitle)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(
                    CoachReservationUI.textPrimary
                )

            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundStyle(
                    CoachReservationUI.textSecondary
                )
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private var filteredReservations: [Reservation] {
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
            return "承認または却下を選んでください"
        case .upcoming:
            return "これからのレッスン"
        case .history:
            return "過去の予約・却下済み"
        }
    }

    private var emptyStateIcon: String {
        switch selectedCategory {
        case .pending:
            return "checkmark.circle"
        case .upcoming:
            return "calendar"
        case .history:
            return "clock.arrow.circlepath"
        }
    }

    private var emptyStateTitle: String {
        switch selectedCategory {
        case .pending:
            return "対応待ちはありません"
        case .upcoming:
            return "今後の予約はありません"
        case .history:
            return "予約履歴はありません"
        }
    }

    private var emptyStateMessage: String {
        switch selectedCategory {
        case .pending:
            return "新しい予約申請が届くと、ここに表示されます"
        case .upcoming:
            return "承認した予約や支払い済みの予約が表示されます"
        case .history:
            return "過去のレッスンや却下した予約が表示されます"
        }
    }

    @ViewBuilder
    private func reservationCard(_ reservation: Reservation) -> some View {
        VStack(alignment: .leading, spacing: 14) {

            HStack(alignment: .top, spacing: 12) {
                Button {
                    selectedStudentIdForNavigation =
                        reservation.studentId
                    selectedStudentNameForNavigation =
                        displayStudentName(
                            for: reservation
                        )
                    selectedStudentImageURLForNavigation =
                        resolvedStudentImageURLs[
                            reservation.id
                        ] ?? ""
                    showStudentProfile = true
                } label: {
                    StudentReservationAvatarView(
                        imageURL:
                            resolvedStudentImageURLs[
                                reservation.id
                            ] ?? "",
                        size: 50
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "\(displayStudentName(for: reservation))さんのプロフィール"
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayStudentName(for: reservation))
                        .font(
                            .system(
                                size: 17,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            CoachReservationUI.textPrimary
                        )

                    Text(statusDescription(reservation))
                        .font(.caption)
                        .foregroundStyle(
                            CoachReservationUI.textSecondary
                        )
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                statusBadge(reservation)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    reservationInfoItem(
                        icon: "calendar",
                        text: displayDate(reservation.date)
                    )

                    reservationInfoItem(
                        icon: "clock",
                        text: combinedTimeRange(
                            reservation.times
                        )
                    )
                }

                HStack(spacing: 14) {
                    reservationInfoItem(
                        icon: "hourglass",
                        text:
                            "\(max(reservation.times.count, 1))時間"
                    )

                    if reservation.totalPrice > 0 {
                        reservationInfoItem(
                            icon: "yensign.circle",
                            text:
                                "¥\(reservation.totalPrice.formatted())"
                        )
                    }
                }

                if !reservation.court.isEmpty {
                    reservationInfoItem(
                        icon: "mappin.and.ellipse",
                        text: reservation.court
                    )
                }
            }
            .padding(12)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .background(
                CoachReservationUI.background
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 14,
                    style: .continuous
                )
            )

            if reservation.status == "pending" {
                if isPast(reservation) {
                    Label(
                        "予約日時を過ぎています",
                        systemImage:
                            "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                HStack(spacing: 10) {
                    Button {
                        reservationToApprove = reservation
                        showApproveAlert = true
                    } label: {
                        Label(
                            "承認する",
                            systemImage: "checkmark"
                        )
                        .font(
                            .system(
                                size: 14,
                                weight: .semibold
                            )
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(.white)
                        .background(
                            CoachReservationUI.brandGreen
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(updatingReservationId != nil)

                    Button(role: .destructive) {
                        reservationToReject = reservation
                        showRejectAlert = true
                    } label: {
                        Label(
                            "却下する",
                            systemImage: "xmark"
                        )
                        .font(
                            .system(
                                size: 14,
                                weight: .semibold
                            )
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(.red)
                        .background(Color.white)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 13,
                                style: .continuous
                            )
                            .stroke(
                                Color.red.opacity(0.38),
                                lineWidth: 1
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(updatingReservationId != nil)
                }
            }

            if reservation.weatherCancellationStatus == "pending" {
                weatherPendingSection(reservation)

            } else if canRequestWeatherCancellation(reservation) {
                Button {
                    reservationToWeatherRequest = reservation
                    showWeatherRequestAlert = true
                } label: {
                    Label(
                        "雨天・施設都合でキャンセル申請",
                        systemImage: "cloud.rain"
                    )
                    .font(
                        .system(
                            size: 13,
                            weight: .semibold
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .foregroundStyle(Color.blue)
                    .background(Color.blue.opacity(0.07))
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .disabled(updatingReservationId != nil)
            }

            if canRequestRefund(reservation) {
                Button(role: .destructive) {
                    reservationToRefund = reservation
                    showRefundAlert = true
                } label: {
                    Label(
                        refundActionTitle(reservation),
                        systemImage:
                            "arrow.uturn.backward.circle"
                    )
                    .font(
                        .system(
                            size: 13,
                            weight: .semibold
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .foregroundStyle(.red)
                    .background(Color.red.opacity(0.055))
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .disabled(updatingReservationId != nil)

            } else if isRefundProcessing(reservation) {
                Label(
                    "返金処理中です",
                    systemImage:
                        "arrow.triangle.2.circlepath"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Button {
                selectedReservationForNavigation =
                    reservation
                showReservationDetail = true
            } label: {
                HStack {
                    Image(
                        systemName:
                            "doc.text.magnifyingglass"
                    )

                    Text("予約詳細を見る")
                        .fontWeight(.semibold)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(
                            .system(
                                size: 11,
                                weight: .bold
                            )
                        )
                }
                .font(.subheadline)
                .foregroundStyle(
                    CoachReservationUI.brandGreen
                )
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.white)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                    .stroke(
                        CoachReservationUI.brandGreen
                            .opacity(0.28),
                        lineWidth: 1
                    )
                }
            }
            .buttonStyle(.plain)

            if updatingReservationId == reservation.id {
                HStack(spacing: 8) {
                    Spacer()

                    ProgressView()
                        .tint(
                            CoachReservationUI.brandGreen
                        )

                    Text("更新中…")
                        .font(.caption)
                        .foregroundStyle(
                            CoachReservationUI.textSecondary
                        )

                    Spacer()
                }
            }
        }
    }

    private func reservationInfoItem(
        icon: String,
        text: String
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 12,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    CoachReservationUI.brandGreen
                )

            Text(text)
                .font(.subheadline)
                .foregroundStyle(
                    CoachReservationUI.textPrimary
                )
                .lineLimit(2)
        }
    }

    private func categoryCount(_ targetCategory: ReservationCategory) -> Int {
        reservations.filter {
            self.category(for: $0) == targetCategory
        }.count
    }

    private func category(for reservation: Reservation) -> ReservationCategory {
        if reservation.status == "pending" {
            return .pending
        }

        let activeStatuses = ["confirmed", "paid", "reserved"]

        if activeStatuses.contains(reservation.status), !isPast(reservation) {
            return .upcoming
        }

        return .history
    }

    private func upcomingSortDate(_ reservation: Reservation) -> Date {
        lessonStartDate(reservation) ??
            reservation.createdAt?.dateValue() ??
            .distantFuture
    }

    private func historySortDate(_ reservation: Reservation) -> Date {
        lessonStartDate(reservation) ??
            reservation.createdAt?.dateValue() ??
            .distantPast
    }

    private func isPast(_ reservation: Reservation) -> Bool {
        guard let endDate = lessonEndDate(reservation) else {
            return false
        }

        return endDate < Date()
    }

    private func lessonStartDate(_ reservation: Reservation) -> Date? {
        guard let firstTime = reservation.times.sorted().first else {
            return nil
        }

        return dateTime(
            date: reservation.date,
            time: startTime(from: firstTime)
        )
    }

    private func lessonEndDate(_ reservation: Reservation) -> Date? {
        guard let lastTime = reservation.times.sorted().last else {
            return nil
        }

        return dateTime(
            date: reservation.date,
            time: endTime(for: lastTime)
        )
    }

    private func dateTime(date: String, time: String) -> Date? {
        let normalizedDate = date.replacingOccurrences(of: "/", with: "-")
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(normalizedDate) \(time)")
    }

    private func loadCurrentCoachName(
        coachId: String
    ) {
        db.collection("coaches")
            .document(coachId)
            .getDocument {
                snapshot,
                error in

                DispatchQueue.main.async {
                    if let error {
                        print(
                            "コーチ名取得失敗:",
                            error.localizedDescription
                        )
                        return
                    }

                    currentCoachName =
                        snapshot?
                            .data()?["name"]
                        as? String
                        ?? ""
                }
            }
    }

    private func loadReservations() {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "予約一覧の確認にはログインが必要です"
            reservations = []
            return
        }

        isLoading = true
        errorMessage = ""

        loadCurrentCoachName(
            coachId: uid
        )

        db.collection("reservations")
            .whereField("coachId", isEqualTo: uid)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    isLoading = false

                    if let error = error {
                        errorMessage =
                            "予約を取得できませんでした: \(error.localizedDescription)"
                        return
                    }

                    let loadedReservations: [Reservation] =
                        snapshot?.documents.map { document in
                            let data = document.data()
                            let legacyTime = data["time"] as? String ?? ""
                            let savedTimes = data["times"] as? [String] ?? []
                            let reservationTimes = savedTimes.isEmpty
                                ? (legacyTime.isEmpty ? [] : [legacyTime])
                                : savedTimes.sorted()

                            return Reservation(
                                id: document.documentID,
                                studentId: data["studentId"] as? String ?? "",
                                studentName: data["studentName"] as? String ?? "生徒",
                                date: data["date"] as? String ?? "",
                                times: reservationTimes,
                                court: data["court"] as? String ?? "",
                                status: data["status"] as? String ?? "pending",
                                paymentStatus: data["paymentStatus"] as? String ?? "",
                                refundStatus: data["refundStatus"] as? String ?? "",
                                cancellationSource: data["cancellationSource"] as? String ?? "",
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
                                totalPrice: data["totalPrice"] as? Int ?? 0,
                                createdAt: data["createdAt"] as? Timestamp
                            )
                        } ?? []

                    reservations = loadedReservations
                    loadStudentProfiles(
                        for: loadedReservations
                    )
                }
            }
    }

    private func displayStudentName(
        for reservation: Reservation
    ) -> String {
        if let resolvedName =
            resolvedStudentNames[reservation.id]?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
           !resolvedName.isEmpty {
            return resolvedName
        }

        let savedName =
            reservation.studentName
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        if !savedName.isEmpty &&
            savedName != "生徒" {
            return savedName
        }

        return "生徒"
    }

    private func loadStudentProfiles(
        for reservations: [Reservation]
    ) {
        guard !reservations.isEmpty else {
            resolvedStudentNames = [:]
            resolvedStudentImageURLs = [:]
            return
        }

        let functions = Functions.functions(
            region: "asia-northeast1"
        )

        functions
            .httpsCallable(
                "getCoachReservationStudentNames"
            )
            .call([:]) { result, error in
                DispatchQueue.main.async {
                    if let error {
                        // プロフィール補完だけの失敗で、
                        // 予約一覧全体をエラーにはしない。
                        print(
                            "生徒プロフィールを補完できませんでした:",
                            error.localizedDescription
                        )
                        return
                    }

                    guard
                        let data =
                            result?.data
                            as? [String: Any]
                    else {
                        return
                    }

                    var names: [String: String] = [:]
                    var imageURLs: [String: String] = [:]

                    if let rawNames =
                        data["names"]
                        as? [String: Any] {
                        for (reservationId, value)
                            in rawNames {
                            guard
                                let name = value as? String
                            else {
                                continue
                            }

                            let trimmedName =
                                name.trimmingCharacters(
                                    in:
                                        .whitespacesAndNewlines
                                )

                            if !trimmedName.isEmpty {
                                names[reservationId] =
                                    trimmedName
                            }
                        }
                    }

                    if let rawImageURLs =
                        data["imageURLs"]
                        as? [String: Any] {
                        for (reservationId, value)
                            in rawImageURLs {
                            guard
                                let imageURL =
                                    value as? String
                            else {
                                continue
                            }

                            let trimmedURL =
                                imageURL
                                    .trimmingCharacters(
                                        in:
                                            .whitespacesAndNewlines
                                    )

                            if !trimmedURL.isEmpty {
                                imageURLs[reservationId] =
                                    trimmedURL
                            }
                        }
                    }

                    resolvedStudentNames = names
                    resolvedStudentImageURLs = imageURLs
                }
            }
    }

    private func approveReservation(_ reservation: Reservation) {
        guard let coachId = Auth.auth().currentUser?.uid else {
            errorMessage = "予約の承認にはログインが必要です"
            return
        }

        updatingReservationId = reservation.id
        errorMessage = ""

        let reservationRef = db.collection("reservations")
            .document(reservation.id)
        let batch = db.batch()

        batch.updateData(
            [
                "status": "confirmed",
                "updatedAt": Timestamp()
            ],
            forDocument: reservationRef
        )

        addNotification(
            to: batch,
            reservation: reservation,
            coachId: coachId,
            type: "reservationApproved",
            title: "予約が承認されました",
            message: "\(displayDate(reservation.date)) \(combinedTimeRange(reservation.times))の予約が承認されました。支払い手続きへ進めます。"
        )

        batch.commit { error in
            DispatchQueue.main.async {
                updatingReservationId = nil

                if let error = error {
                    errorMessage =
                        "予約を承認できませんでした: \(error.localizedDescription)"
                    return
                }

                loadReservations()
            }
        }
    }

    private func rejectReservation(_ reservation: Reservation) {
        guard let coachId = Auth.auth().currentUser?.uid else {
            errorMessage = "予約の却下にはログインが必要です"
            return
        }

        updatingReservationId = reservation.id
        errorMessage = ""

        let reservationRef = db.collection("reservations")
            .document(reservation.id)

        let availabilityRef = db.collection("coachAvailability")
            .document(coachId)
            .collection("dates")
            .document(reservation.date)

        availabilityRef.getDocument { snapshot, error in
            if let error = error {
                DispatchQueue.main.async {
                    updatingReservationId = nil
                    errorMessage =
                        "空き枠を確認できませんでした: \(error.localizedDescription)"
                }
                return
            }

            var availableTimes = snapshot?.data()?["times"] as? [String] ?? []

            for time in reservation.times where !availableTimes.contains(time) {
                availableTimes.append(time)
            }
            availableTimes.sort()

            let batch = db.batch()

            batch.setData(
                ["times": availableTimes],
                forDocument: availabilityRef,
                merge: true
            )

            batch.updateData(
                [
                    "status": "rejected",
                    "updatedAt": Timestamp()
                ],
                forDocument: reservationRef
            )

            addNotification(
                to: batch,
                reservation: reservation,
                coachId: coachId,
                type: "reservationRejected",
                title: "予約が却下されました",
                message: "\(displayDate(reservation.date)) \(combinedTimeRange(reservation.times))の予約は却下されました。別の日時を選択してください。"
            )

            batch.commit { error in
                DispatchQueue.main.async {
                    updatingReservationId = nil

                    if let error = error {
                        errorMessage =
                            "予約を却下できませんでした: \(error.localizedDescription)"
                        return
                    }

                    loadReservations()
                }
            }
        }
    }

    @ViewBuilder
    private func weatherPendingSection(
        _ reservation: Reservation
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "雨天・施設都合キャンセル",
                systemImage: "cloud.rain.fill"
            )
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.blue)

            if reservation.weatherCancellationRequesterRole == "coach" {
                Text(
                    "生徒の回答待ちです。同意された場合のみキャンセル・全額返金となります。"
                )
                .font(.caption)
                .foregroundStyle(
                    CoachReservationUI.textSecondary
                )

                Button {
                    reservationToWeatherWithdraw = reservation
                    showWeatherWithdrawAlert = true
                } label: {
                    Label(
                        "申請を取り下げる",
                        systemImage:
                            "arrow.uturn.backward"
                    )
                    .font(
                        .system(
                            size: 13,
                            weight: .semibold
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .foregroundStyle(.blue)
                    .background(Color.white)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                        .stroke(
                            Color.blue.opacity(0.28),
                            lineWidth: 1
                        )
                    }
                }
                .buttonStyle(.plain)
                .disabled(updatingReservationId != nil)

            } else {
                Text(
                    "生徒から申請が届いています。同意すると全額返金、拒否すると予約は継続します。"
                )
                .font(.caption)
                .foregroundStyle(
                    CoachReservationUI.textSecondary
                )

                HStack(spacing: 10) {
                    Button {
                        reservationToWeatherApprove = reservation
                        showWeatherApproveAlert = true
                    } label: {
                        Text("同意する")
                            .font(
                                .system(
                                    size: 13,
                                    weight: .semibold
                                )
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .foregroundStyle(.white)
                            .background(
                                CoachReservationUI.brandGreen
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 12,
                                    style: .continuous
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(updatingReservationId != nil)

                    Button {
                        reservationToWeatherReject = reservation
                        showWeatherRejectAlert = true
                    } label: {
                        Text("同意しない")
                            .font(
                                .system(
                                    size: 13,
                                    weight: .semibold
                                )
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .foregroundStyle(.red)
                            .background(Color.white)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 12,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 12,
                                    style: .continuous
                                )
                                .stroke(
                                    Color.red.opacity(0.32),
                                    lineWidth: 1
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(updatingReservationId != nil)
                }
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.055))
        .clipShape(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }

    private func canRequestWeatherCancellation(
        _ reservation: Reservation
    ) -> Bool {
        guard reservation.status == "paid",
              reservation.paymentStatus == "paid",
              reservation.weatherCancellationStatus != "pending",
              let startDate = lessonStartDate(reservation) else {
            return false
        }

        let interval = startDate.timeIntervalSinceNow
        let twentyFourHours = 24.0 * 60.0 * 60.0

        return interval > 0 &&
            interval <= twentyFourHours
    }

    private func requestWeatherCancellation(
        _ reservation: Reservation
    ) {
        updatingReservationId = reservation.id
        errorMessage = ""

        let functions = Functions.functions(
            region: "asia-northeast1"
        )

        functions
            .httpsCallable("requestWeatherCancellation")
            .call([
                "reservationId": reservation.id
            ]) { _, error in
                DispatchQueue.main.async {
                    updatingReservationId = nil

                    if let error {
                        errorMessage =
                            "雨天キャンセルを申請できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    loadReservations()
                }
            }
    }

    private func withdrawWeatherCancellation(
        _ reservation: Reservation
    ) {
        updatingReservationId = reservation.id
        errorMessage = ""

        let functions = Functions.functions(
            region: "asia-northeast1"
        )

        functions
            .httpsCallable("withdrawWeatherCancellation")
            .call([
                "reservationId": reservation.id
            ]) { _, error in
                DispatchQueue.main.async {
                    updatingReservationId = nil

                    if let error {
                        errorMessage =
                            "雨天キャンセル申請を取り下げられませんでした: " +
                            error.localizedDescription
                        return
                    }

                    loadReservations()
                }
            }
    }

    private func respondWeatherCancellation(
        _ reservation: Reservation,
        approve: Bool
    ) {
        updatingReservationId = reservation.id
        errorMessage = ""

        let functions = Functions.functions(
            region: "asia-northeast1"
        )

        functions
            .httpsCallable("respondWeatherCancellation")
            .call([
                "reservationId": reservation.id,
                "approve": approve
            ]) { _, error in
                DispatchQueue.main.async {
                    updatingReservationId = nil

                    if let error {
                        errorMessage =
                            "雨天キャンセルへ回答できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    loadReservations()
                }
            }
    }

    private func requestCoachRefund(_ reservation: Reservation) {
        guard Auth.auth().currentUser?.uid != nil else {
            errorMessage = "返金にはコーチのログインが必要です"
            return
        }

        updatingReservationId = reservation.id
        errorMessage = ""

        let functions = Functions.functions(region: "asia-northeast1")
        functions
            .httpsCallable("requestCoachRefund")
            .call(["reservationId": reservation.id]) { _, error in
                DispatchQueue.main.async {
                    updatingReservationId = nil

                    if let error = error {
                        errorMessage =
                            "キャンセル・返金を開始できませんでした: \(error.localizedDescription)"
                        return
                    }

                    loadReservations()
                }
            }
    }

    private func addNotification(
        to batch: WriteBatch,
        reservation: Reservation,
        coachId: String,
        type: String,
        title: String,
        message: String
    ) {
        guard !reservation.studentId.isEmpty else {
            return
        }

        let notificationRef = db.collection("notifications").document()

        batch.setData(
            [
                "recipientId": reservation.studentId,
                "coachId": coachId,
                "reservationId": reservation.id,
                "type": type,
                "title": title,
                "message": message,
                "date": reservation.date,
                "times": reservation.times,
                "isRead": false,
                "createdAt": Timestamp()
            ],
            forDocument: notificationRef
        )
    }

    private func canRequestRefund(_ reservation: Reservation) -> Bool {
        let cancellableStatus =
            reservation.status == "paid" ||
            reservation.status == "coach_cancelled"

        let refundablePaymentStatus =
            reservation.paymentStatus == "paid" ||
            (
                reservation.paymentStatus == "refund_failed" &&
                reservation.refundStatus == "failed_to_create"
            )

        return cancellableStatus &&
        refundablePaymentStatus &&
        reservation.weatherCancellationStatus != "pending" &&
        !isPast(reservation)
    }

    private func refundActionTitle(_ reservation: Reservation) -> String {
        isRefundFailed(reservation)
            ? "全額返金を再試行"
            : "予約をキャンセル・全額返金"
    }

    private func isRefundFailed(_ reservation: Reservation) -> Bool {
        reservation.paymentStatus == "refund_failed" ||
        ["failed", "canceled", "failed_to_create"].contains(
            reservation.refundStatus
        )
    }

    private func isRefundProcessing(_ reservation: Reservation) -> Bool {
        reservation.paymentStatus == "refund_processing" ||
        ["creating", "pending", "requires_action"].contains(
            reservation.refundStatus
        )
    }

    @ViewBuilder
    private func statusBadge(_ reservation: Reservation) -> some View {
        if reservation.paymentStatus == "refunded" ||
            reservation.refundStatus == "succeeded" {

            let refundLabel =
                isStudentCancellation(reservation) &&
                reservation.cancellationRefundPercent == 50
                ? "50%返金済み"
                : "全額返金済み"

            statusChip(
                refundLabel,
                icon:
                    "arrow.uturn.backward.circle.fill",
                color: .purple
            )

        } else if reservation.paymentStatus == "refund_failed" ||
                    ["failed", "canceled", "failed_to_create"].contains(
                        reservation.refundStatus
                    ) {
            statusChip(
                "返金確認中",
                icon:
                    "exclamationmark.triangle.fill",
                color: .red
            )

        } else if reservation.weatherCancellationStatus == "pending" {
            statusChip(
                reservation.weatherCancellationRequesterRole == "coach"
                    ? "回答待ち"
                    : "要回答",
                icon: "cloud.rain.fill",
                color: .orange
            )

        } else if isRefundProcessing(reservation) {
            statusChip(
                "返金処理中",
                icon:
                    "arrow.triangle.2.circlepath",
                color: .orange
            )

        } else if isStudentCancellation(reservation) &&
                    reservation.cancellationRefundPercent == 0 {
            statusChip(
                "返金なし",
                icon: "minus.circle.fill",
                color: CoachReservationUI.textSecondary
            )

        } else {
            statusBadgeForReservationStatus(
                reservation.status
            )
        }
    }

    @ViewBuilder
    private func statusBadgeForReservationStatus(
        _ status: String
    ) -> some View {
        switch status {
        case "confirmed":
            statusChip(
                "承認済み",
                icon: "checkmark.circle.fill",
                color: .blue
            )

        case "paid":
            statusChip(
                "支払い済み",
                icon: "checkmark.seal.fill",
                color: CoachReservationUI.brandGreen
            )

        case "reserved":
            statusChip(
                "予約済み",
                icon: "calendar.circle.fill",
                color: .blue
            )

        case "completed":
            statusChip(
                "完了",
                icon: "flag.checkered",
                color: CoachReservationUI.textSecondary
            )

        case "cancelled", "canceled":
            statusChip(
                "キャンセル",
                icon: "minus.circle.fill",
                color: CoachReservationUI.textSecondary
            )

        case "coach_cancelled":
            statusChip(
                "コーチ都合",
                icon: "minus.circle.fill",
                color: .purple
            )

        case "weather_cancelled":
            statusChip(
                "雨天キャンセル",
                icon: "cloud.rain.fill",
                color: .blue
            )

        case "student_cancelled":
            statusChip(
                "生徒都合",
                icon: "minus.circle.fill",
                color: CoachReservationUI.textSecondary
            )

        case "rejected":
            statusChip(
                "却下済み",
                icon: "xmark.circle.fill",
                color: .red
            )

        default:
            statusChip(
                "承認待ち",
                icon: "clock.fill",
                color: .orange
            )
        }
    }

    private func statusChip(
        _ text: String,
        icon: String,
        color: Color
    ) -> some View {
        Label(
            text,
            systemImage: icon
        )
        .font(
            .system(
                size: 11,
                weight: .semibold
            )
        )
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
        .lineLimit(1)
    }

    private func statusDescription(_ reservation: Reservation) -> String {
        let studentCancelled = isStudentCancellation(reservation)

        if reservation.paymentStatus == "refunded" ||
            reservation.refundStatus == "succeeded" {

            if reservation.status == "weather_cancelled" ||
                reservation.cancellationSource == "weather" {
                return "雨天・施設都合キャンセル・全額返金済み"
            }

            if studentCancelled {
                if reservation.cancellationRefundPercent == 50 {
                    return "生徒都合キャンセル・50%返金済み"
                }

                return "生徒都合キャンセル・全額返金済み"
            }

            return "コーチ都合キャンセル・全額返金済み"
        }

        if reservation.paymentStatus == "refund_failed" ||
            ["failed", "canceled", "failed_to_create"].contains(
                reservation.refundStatus
            ) {
            return studentCancelled
                ? "生徒都合キャンセル・返金状況を確認中"
                : "返金状況を運営が確認します"
        }

        if isRefundProcessing(reservation) {
            if reservation.status == "weather_cancelled" ||
                reservation.cancellationSource == "weather" {
                return "雨天・施設都合キャンセル・全額返金処理中"
            }

            if studentCancelled {
                if reservation.cancellationRefundPercent == 50 {
                    return "生徒都合キャンセル・50%返金処理中"
                }

                return "生徒都合キャンセル・全額返金処理中"
            }

            return "コーチ都合キャンセル・全額返金処理中"
        }

        if reservation.weatherCancellationStatus == "pending" {
            return reservation.weatherCancellationRequesterRole == "coach"
                ? "雨天・施設都合キャンセル・生徒の回答待ち"
                : "生徒から雨天・施設都合キャンセル申請があります"
        }

        switch reservation.status {
        case "confirmed":
            return "生徒の支払い待ち"
        case "paid":
            return "支払いが完了しています"
        case "reserved":
            return "予約が確定しています"
        case "completed":
            return "レッスン完了"
        case "cancelled", "canceled":
            return "キャンセルされた予約"
        case "coach_cancelled":
            return "コーチ都合でキャンセルした予約"
        case "weather_cancelled":
            return "雨天・施設都合で双方合意キャンセル"

        case "student_cancelled":
            if reservation.cancellationRefundPercent == 0 {
                return "生徒都合キャンセル・返金なし"
            } else if reservation.cancellationRefundPercent == 50 {
                return "生徒都合キャンセル・50%返金"
            } else {
                return "生徒都合キャンセル・全額返金"
            }
        case "rejected":
            return "却下した予約"
        default:
            return "確認が必要な予約申請"
        }
    }

    private func isStudentCancellation(_ reservation: Reservation) -> Bool {
        reservation.status == "student_cancelled" ||
        reservation.cancellationSource == "student"
    }

    private func displayDate(_ value: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.calendar = Calendar(identifier: .gregorian)
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")

        let parsedDate = ["yyyy-MM-dd", "yyyy/MM/dd"]
            .compactMap { format -> Date? in
                inputFormatter.dateFormat = format
                return inputFormatter.date(from: value)
            }
            .first

        guard let parsedDate else {
            return value.replacingOccurrences(of: "-", with: "/")
        }

        let outputFormatter = DateFormatter()
        outputFormatter.calendar = Calendar(identifier: .gregorian)
        outputFormatter.locale = Locale(identifier: "ja_JP")
        outputFormatter.dateFormat = "M/d（E）"
        return outputFormatter.string(from: parsedDate)
    }

    private func combinedTimeRange(_ times: [String]) -> String {
        let sortedTimes = times.sorted()

        guard let first = sortedTimes.first,
              let last = sortedTimes.last else {
            return "時間未登録"
        }

        return "\(startTime(from: first))〜\(endTime(for: last))"
    }

    private func startTime(from time: String) -> String {
        time
            .replacingOccurrences(of: "~", with: "〜")
            .components(separatedBy: "〜")
            .first ?? time
    }

    private func endTime(for startTime: String) -> String {
        let normalizedTime = startTime.replacingOccurrences(of: "~", with: "〜")
        let parts = normalizedTime.components(separatedBy: "〜")

        if parts.count >= 2, let savedEndTime = parts.last {
            return savedEndTime
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"

        guard let startDate = formatter.date(from: normalizedTime),
              let endDate = Calendar.current.date(
                byAdding: .hour,
                value: 1,
                to: startDate
              ) else {
            return normalizedTime
        }

        return formatter.string(from: endDate)
    }
}

private struct StudentReservationAvatarView: View {

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
            CoachReservationUI.softGreen
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
            .foregroundStyle(
                CoachReservationUI.brandGreen
                    .opacity(0.55)
            )
    }
}


private struct CoachReservationDetailView: View {

    let reservation:
        CoachReservationListView.Reservation
    let studentName: String
    let studentImageURL: String
    let coachName: String

    private let functions =
        Functions.functions(
            region: "asia-northeast1"
        )

    @State private var canMessageStudent = false
    @State private var isCheckingChatAccess = false

    private var coachId: String {
        Auth.auth().currentUser?.uid ?? ""
    }

    private var resolvedCoachName: String {
        let trimmed =
            coachName
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        return trimmed.isEmpty
            ? "コーチ"
            : trimmed
    }

    private var resolvedStudentName: String {
        let trimmed =
            studentName
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        return trimmed.isEmpty
            ? "生徒"
            : trimmed
    }

    private var isPaidUpcomingReservation: Bool {
        let paid =
            reservation.status == "paid" ||
            reservation.status == "reserved" &&
                reservation.paymentStatus == "paid" ||
            [
                "paid",
                "partially_refunded",
                "refund_processing",
                "refund_failed"
            ]
            .contains(
                reservation.paymentStatus
            )

        guard paid else {
            return false
        }

        let cancelledStatuses = [
            "cancelled",
            "canceled",
            "coach_cancelled",
            "student_cancelled",
            "weather_cancelled",
            "rejected"
        ]

        guard
            !cancelledStatuses.contains(
                reservation.status
            )
        else {
            return false
        }

        guard let endDate = lessonEndDate else {
            return false
        }

        return endDate > Date()
    }

    private var lessonEndDate: Date? {
        guard
            let lastTime =
                reservation.times
                    .sorted()
                    .last
        else {
            return nil
        }

        let normalizedDate =
            reservation.date
                .replacingOccurrences(
                    of: "/",
                    with: "-"
                )

        let startTime =
            normalizedStartTime(
                from: lastTime
            )

        let formatter =
            DateFormatter()
        formatter.calendar =
            Calendar(
                identifier: .gregorian
            )
        formatter.locale =
            Locale(
                identifier: "en_US_POSIX"
            )
        formatter.timeZone =
            TimeZone(
                identifier: "Asia/Tokyo"
            ) ?? .current
        formatter.dateFormat =
            "yyyy-MM-dd HH:mm"

        guard
            let startDate =
                formatter.date(
                    from:
                        "\(normalizedDate) \(startTime)"
                )
        else {
            return nil
        }

        return Calendar.current.date(
            byAdding: .hour,
            value: 1,
            to: startDate
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {

                VStack(spacing: 14) {
                    NavigationLink {
                        StudentPublicProfileView(
                            studentId:
                                reservation.studentId,
                            initialDisplayName:
                                resolvedStudentName,
                            initialImageURL:
                                studentImageURL
                        )
                    } label: {
                        StudentReservationAvatarView(
                            imageURL:
                                studentImageURL,
                            size: 88
                        )
                    }
                    .buttonStyle(.plain)

                    Text(resolvedStudentName)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("生徒プロフィールを見るには画像をタップ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 16) {
                    detailRow(
                        title: "日付",
                        value:
                            reservation.date
                                .replacingOccurrences(
                                    of: "-",
                                    with: "/"
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
                            "¥\(reservation.totalPrice)"
                    )

                    if !reservation.court.isEmpty {
                        Divider()

                        detailRow(
                            title: "場所",
                            value:
                                reservation.court
                        )
                    }

                    Divider()

                    detailRow(
                        title: "状態",
                        value:
                            statusText
                    )
                }
                .padding()
                .background(
                    Color(.systemGray6)
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 18
                    )
                )

                if isPaidUpcomingReservation &&
                    canMessageStudent &&
                    !isCheckingChatAccess {
                    NavigationLink {
                        ChatView(
                            coachId: coachId,
                            coachName:
                                resolvedCoachName,
                            studentId:
                                reservation.studentId,
                            studentName:
                                resolvedStudentName,
                            currentRole: .coach
                        )
                    } label: {
                        Label(
                            "メッセージを送る",
                            systemImage:
                                "message.fill"
                        )
                        .font(.headline)
                        .frame(
                            maxWidth: .infinity
                        )
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(Color.green)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 14
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("予約詳細")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadChatAccessState()
        }
    }

    private var statusText: String {
        if reservation.paymentStatus == "refunded" ||
            reservation.refundStatus == "succeeded" {
            return "返金済み"
        }

        switch reservation.status {
        case "paid":
            return "支払い済み"
        case "reserved":
            return "予約確定"
        case "confirmed":
            return "支払い待ち"
        case "pending":
            return "承認待ち"
        case "completed":
            return "レッスン完了"
        case "rejected":
            return "却下済み"
        case "cancelled", "canceled":
            return "キャンセル"
        case "coach_cancelled":
            return "コーチ都合キャンセル"
        default:
            return reservation.status
        }
    }

    @MainActor
    private func loadChatAccessState() async {
        guard
            isPaidUpcomingReservation,
            !coachId.isEmpty,
            !reservation.studentId.isEmpty
        else {
            canMessageStudent = false
            isCheckingChatAccess = false
            return
        }

        isCheckingChatAccess = true
        canMessageStudent = false

        do {
            let result =
                try await functions
                    .httpsCallable(
                        "getChatMessagingStatus"
                    )
                    .call(
                        [
                            "studentId":
                                reservation.studentId,
                            "coachId":
                                coachId
                        ]
                    )

            guard
                let data =
                    result.data
                    as? [String: Any]
            else {
                canMessageStudent = false
                isCheckingChatAccess = false
                return
            }

            canMessageStudent =
                data["canSend"]
                as? Bool
                ?? false

            isCheckingChatAccess = false

        } catch {
            canMessageStudent = false
            isCheckingChatAccess = false

            print(
                "コーチ予約詳細チャット利用可否確認失敗:",
                error.localizedDescription
            )
        }
    }

    private func detailRow(
        title: String,
        value: String
    ) -> some View {
        HStack(
            alignment: .firstTextBaseline
        ) {
            Text(title)

            Spacer()

            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
    }

    private func combinedTimeRange(
        _ times: [String]
    ) -> String {
        let sorted =
            times.sorted()

        guard
            let first = sorted.first,
            let last = sorted.last
        else {
            return "時間未設定"
        }

        let start =
            normalizedStartTime(
                from: first
            )

        let end =
            endTime(
                for: last
            )

        return "\(start)〜\(end)"
    }

    private func normalizedStartTime(
        from value: String
    ) -> String {
        value
            .replacingOccurrences(
                of: "~",
                with: "〜"
            )
            .components(
                separatedBy: "〜"
            )
            .first?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            ?? value
    }

    private func endTime(
        for value: String
    ) -> String {
        let normalized =
            value.replacingOccurrences(
                of: "~",
                with: "〜"
            )

        if normalized.contains("〜") {
            return normalized
                .components(
                    separatedBy: "〜"
                )
                .last?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                ?? value
        }

        let formatter =
            DateFormatter()
        formatter.calendar =
            Calendar(
                identifier: .gregorian
            )
        formatter.locale =
            Locale(
                identifier: "en_US_POSIX"
            )
        formatter.timeZone =
            TimeZone(
                identifier: "Asia/Tokyo"
            ) ?? .current
        formatter.dateFormat = "HH:mm"

        guard
            let startDate =
                formatter.date(
                    from: value
                ),
            let endDate =
                Calendar.current.date(
                    byAdding: .hour,
                    value: 1,
                    to: startDate
                )
        else {
            return value
        }

        return formatter.string(
            from: endDate
        )
    }
}

#Preview {
    NavigationStack {
        CoachReservationListView()
    }
}
