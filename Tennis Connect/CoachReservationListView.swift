// 修正版：コーチの予約一覧を「対応待ち・今後の予約・履歴」に整理

import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

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

    private let db = Firestore.firestore()

    var body: some View {
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
                    reservationCard(reservation)
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(reservation.studentName)
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
                Label(displayDate(reservation.date), systemImage: "calendar")
                Label(combinedTimeRange(reservation.times), systemImage: "clock")
            }
            .font(.subheadline)

            HStack(spacing: 14) {
                Label(
                    "\(max(reservation.times.count, 1))時間",
                    systemImage: "hourglass"
                )

                if reservation.totalPrice > 0 {
                    Label("¥\(reservation.totalPrice)", systemImage: "yensign.circle")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !reservation.court.isEmpty {
                Label(reservation.court, systemImage: "location")
                    .font(.subheadline)
            }

            if reservation.status == "pending" {
                if isPast(reservation) {
                    Label(
                        "予約日時を過ぎています",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                HStack(spacing: 12) {
                    Button {
                        reservationToApprove = reservation
                        showApproveAlert = true
                    } label: {
                        Label("承認する", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(updatingReservationId != nil)

                    Button(role: .destructive) {
                        reservationToReject = reservation
                        showRejectAlert = true
                    } label: {
                        Label("却下する", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(updatingReservationId != nil)
                }
                .padding(.top, 4)
            }

            if canRequestRefund(reservation) {
                Button(role: .destructive) {
                    reservationToRefund = reservation
                    showRefundAlert = true
                } label: {
                    Label(
                        refundActionTitle(reservation),
                        systemImage: "arrow.uturn.backward.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(updatingReservationId != nil)
                .padding(.top, 4)
            } else if isRefundProcessing(reservation) {
                Label(
                    "返金処理中です",
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 4)
            }

            if updatingReservationId == reservation.id {
                HStack {
                    Spacer()
                    ProgressView("更新中…")
                    Spacer()
                }
                .font(.caption)
            }
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

    private func loadReservations() {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "予約一覧の確認にはログインが必要です"
            reservations = []
            return
        }

        isLoading = true
        errorMessage = ""

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
                                    ?? (data["cancellationRefundPercent"] as? Int)
                                    ?? 0,
                                totalPrice: data["totalPrice"] as? Int ?? 0,
                                createdAt: data["createdAt"] as? Timestamp
                            )
                        } ?? []

                    reservations = loadedReservations
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

            Label(
                refundLabel,
                systemImage: "arrow.uturn.backward.circle.fill"
            )
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.purple)

        } else if reservation.paymentStatus == "refund_failed" ||
                    ["failed", "canceled", "failed_to_create"].contains(
                        reservation.refundStatus
                    ) {
            Label("返金確認中", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.red)

        } else if isRefundProcessing(reservation) {
            Label("返金処理中", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.orange)

        } else if isStudentCancellation(reservation) &&
                    reservation.cancellationRefundPercent == 0 {
            Label("返金なし", systemImage: "minus.circle.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

        } else {
            statusBadgeForReservationStatus(reservation.status)
        }
    }

    @ViewBuilder
    private func statusBadgeForReservationStatus(_ status: String) -> some View {
        switch status {
        case "confirmed":
            Label("承認済み", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)

        case "paid":
            Label("支払い済み", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.green)

        case "reserved":
            Label("予約済み", systemImage: "calendar.circle.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)

        case "completed":
            Label("完了", systemImage: "flag.checkered")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

        case "cancelled", "canceled":
            Label("キャンセル", systemImage: "minus.circle.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

        case "coach_cancelled":
            Label("コーチ都合キャンセル", systemImage: "minus.circle.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.purple)

        case "student_cancelled":
            Label("生徒都合キャンセル", systemImage: "minus.circle.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

        case "rejected":
            Label("却下済み", systemImage: "xmark.circle.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.red)

        default:
            Label("承認待ち", systemImage: "clock.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.orange)
        }
    }

    private func statusDescription(_ reservation: Reservation) -> String {
        let studentCancelled = isStudentCancellation(reservation)

        if reservation.paymentStatus == "refunded" ||
            reservation.refundStatus == "succeeded" {

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
            if studentCancelled {
                if reservation.cancellationRefundPercent == 50 {
                    return "生徒都合キャンセル・50%返金処理中"
                }

                return "生徒都合キャンセル・全額返金処理中"
            }

            return "コーチ都合キャンセル・全額返金処理中"
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

#Preview {
    NavigationStack {
        CoachReservationListView()
    }
}
