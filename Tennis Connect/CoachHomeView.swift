// 修正版：コーチ画面を5タブ化し、ホームをダッシュボードに変更

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct CoachHomeView: View {

    @State private var selectedTab = 0
    @State private var unreadNotificationCount = 0
    @State private var notificationListener: ListenerRegistration?

    private let db = Firestore.firestore()

    var body: some View {
        TabView(selection: $selectedTab) {
            CoachTabDashboardView(selectedTab: $selectedTab)
                .tabItem {
                    Label("ホーム", systemImage: "house.fill")
                }
                .tag(0)

            CoachReservationListView()
                .tabItem {
                    Label("予約", systemImage: "calendar.badge.clock")
                }
                .tag(1)

            CoachAvailabilityView()
                .tabItem {
                    Label("空き日程", systemImage: "calendar")
                }
                .tag(2)

            ChatListView(role: .coach)
                .tabItem {
                    Label("チャット", systemImage: "message.fill")
                }
                .tag(3)

            CoachMyPageView()
                .tabItem {
                    Label("マイページ", systemImage: "person.fill")
                }
                .tag(4)
        }
        .navigationTitle(tabTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    NotificationView(audience: .coach)
                } label: {
                    Image(
                        systemName: unreadNotificationCount > 0
                            ? "bell.fill"
                            : "bell"
                    )
                    .overlay(alignment: .topTrailing) {
                        if unreadNotificationCount > 0 {
                            Text(
                                unreadNotificationCount > 99
                                    ? "99+"
                                    : "\(unreadNotificationCount)"
                            )
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 8, y: -8)
                        }
                    }
                }
                .accessibilityLabel(
                    unreadNotificationCount > 0
                        ? "未読通知が\(unreadNotificationCount)件あります"
                        : "通知"
                )
            }
        }
        .onAppear {
            startNotificationListener()
        }
        .onDisappear {
            notificationListener?.remove()
            notificationListener = nil
        }
    }

    private var tabTitle: String {
        switch selectedTab {
        case 1:
            return "予約一覧"
        case 2:
            return "空き日程管理"
        case 3:
            return "チャット"
        case 4:
            return "マイページ"
        default:
            return "コーチ"
        }
    }

    private func startNotificationListener() {
        notificationListener?.remove()

        guard let uid = Auth.auth().currentUser?.uid else {
            unreadNotificationCount = 0
            return
        }

        notificationListener = db.collection("notifications")
            .whereField("recipientId", isEqualTo: uid)
            .addSnapshotListener { snapshot, _ in
                let unreadCount = snapshot?.documents.filter { document in
                    let data = document.data()
                    let isCoachNotification =
                        data["type"] as? String == "reservationRequested"
                    let isUnread = data["isRead"] as? Bool != true
                    return isCoachNotification && isUnread
                }.count ?? 0

                DispatchQueue.main.async {
                    unreadNotificationCount = unreadCount
                }
            }
    }
}

private struct CoachTabDashboardView: View {

    @Binding var selectedTab: Int

    @State private var pendingCount = 0
    @State private var todayLessonCount = 0
    @State private var monthlySales = 0
    @State private var nextLesson = "予定はありません"
    @State private var reservationListener: ListenerRegistration?
    @State private var unreadChatCount = 0
    @State private var messageListener: ListenerRegistration?

    @State private var isSameDayAvailable = false
    @State private var todayAvailableTimeCount = 0
    @State private var isLoadingSameDayStatus = false
    @State private var isUpdatingSameDayStatus = false
    @State private var sameDayErrorMessage = ""
    @State private var showSameDayAlert = false
    @State private var sameDayAlertMessage = ""

    private let db = Firestore.firestore()
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private let blockingReservationStatuses: Set<String> = [
        "pending",
        "confirmed",
        "paid",
        "reserved"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("🎾 コーチホーム")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                sameDayAvailabilityCard

                LazyVGrid(columns: columns, spacing: 12) {
                    Button {
                        selectedTab = 1
                    } label: {
                        DashboardSummaryCard(
                            title: "承認待ち",
                            value: "\(pendingCount)件",
                            icon: "clock.fill",
                            color: .orange
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedTab = 1
                    } label: {
                        DashboardSummaryCard(
                            title: "今日のレッスン",
                            value: "\(todayLessonCount)件",
                            icon: "figure.tennis",
                            color: .green
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        selectedTab = 3
                    } label: {
                        DashboardSummaryCard(
                            title: "未読チャット",
                            value: "\(unreadChatCount)件",
                            icon: "message.fill",
                            color: .blue
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        CoachSalesView()
                    } label: {
                        DashboardSummaryCard(
                            title: "今月の売上",
                            value: "¥\(monthlySales.formatted())",
                            icon: "yensign.circle.fill",
                            color: .orange
                        )
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("次のレッスン", systemImage: "calendar.badge.clock")
                        .font(.headline)

                    Text(nextLesson)
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.blue.opacity(0.08))
                .cornerRadius(16)

                Text("クイックメニュー")
                    .font(.headline)

                Button {
                    selectedTab = 1
                } label: {
                    DashboardActionRow(
                        title: "予約を確認する",
                        detail: pendingCount > 0
                            ? "対応待ちが\(pendingCount)件あります"
                            : "予約一覧を開く",
                        icon: "list.bullet.rectangle",
                        color: .green
                    )
                }
                .buttonStyle(.plain)

                Button {
                    selectedTab = 2
                } label: {
                    DashboardActionRow(
                        title: "空き日程を管理する",
                        detail: "空き時間の追加・変更",
                        icon: "calendar.badge.plus",
                        color: .blue
                    )
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .onAppear {
            startReservationListener()
            startUnreadMessageListener()
            loadSameDayAvailabilityState()
        }
        .onChange(of: selectedTab) { newValue in
            if newValue == 0 {
                loadSameDayAvailabilityState()
            }
        }
        .alert("本日の受付", isPresented: $showSameDayAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(sameDayAlertMessage)
        }
        .onDisappear {
            reservationListener?.remove()
            reservationListener = nil
            messageListener?.remove()
            messageListener = nil
        }
    }

    private var sameDayAvailabilityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(
                    systemName: isSameDayAvailable
                        ? "bolt.circle.fill"
                        : "bolt.circle"
                )
                .font(.title2)
                .foregroundStyle(
                    isSameDayAvailable ? .green : .secondary
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        isSameDayAvailable
                            ? "本日レッスン可能として掲載中"
                            : "本日のレッスン受付"
                    )
                    .font(.headline)

                    if isLoadingSameDayStatus {
                        Text("本日の空き枠を確認中…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("現在の予約可能な空き枠：\(todayAvailableTimeCount)件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            Button {
                toggleSameDayAvailability()
            } label: {
                HStack {
                    Spacer()

                    if isUpdatingSameDayStatus {
                        ProgressView()
                    } else {
                        Image(
                            systemName: isSameDayAvailable
                                ? "stop.circle.fill"
                                : "bolt.fill"
                        )

                        Text(
                            isSameDayAvailable
                                ? "本日の受付を終了する"
                                : "本日レッスン可能にする"
                        )
                        .fontWeight(.semibold)
                    }

                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(isSameDayAvailable ? .red : .green)
            .disabled(
                isLoadingSameDayStatus ||
                isUpdatingSameDayStatus ||
                (!isSameDayAvailable && todayAvailableTimeCount == 0)
            )

            if todayAvailableTimeCount == 0 &&
                !isLoadingSameDayStatus {
                Button {
                    selectedTab = 2
                } label: {
                    Label(
                        "本日の空き時間を設定する",
                        systemImage: "calendar.badge.plus"
                    )
                    .font(.subheadline)
                }
            }

            if !sameDayErrorMessage.isEmpty {
                Text(sameDayErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(
            isSameDayAvailable
                ? Color.green.opacity(0.10)
                : Color(.systemGray6)
        )
        .cornerRadius(16)
    }

    private func loadSameDayAvailabilityState() {
        guard let uid = Auth.auth().currentUser?.uid else {
            isSameDayAvailable = false
            todayAvailableTimeCount = 0
            sameDayErrorMessage = "ログインが必要です"
            return
        }

        isLoadingSameDayStatus = true
        sameDayErrorMessage = ""

        let dateKey = firestoreDate(Date())
        let todayRef = db
            .collection("coachAvailability")
            .document(uid)
            .collection("dates")
            .document(dateKey)

        Task {
            do {
                let todaySnapshot = try await todayRef.getDocument()

                let savedTimes =
                    todaySnapshot.data()?["times"] as? [String] ?? []

                let savedSameDayAvailable =
                    todaySnapshot.data()?["sameDayAvailable"] as? Bool ?? false

                let reservationSnapshot = try await db
                    .collection("reservations")
                    .whereField("coachId", isEqualTo: uid)
                    .getDocuments()

                let reservedTimes = blockedTimes(
                    for: dateKey,
                    documents: reservationSnapshot.documents
                )

                let actualAvailableTimes =
                    Set(savedTimes)
                        .subtracting(reservedTimes)
                        .filter { isFutureTimeSlot($0, dateKey: dateKey) }

                if savedSameDayAvailable && actualAvailableTimes.isEmpty {
                    try? await todayRef.setData(
                        ["sameDayAvailable": false],
                        merge: true
                    )
                }

                await MainActor.run {
                    todayAvailableTimeCount = actualAvailableTimes.count
                    isSameDayAvailable =
                        savedSameDayAvailable &&
                        !actualAvailableTimes.isEmpty
                    isLoadingSameDayStatus = false
                    sameDayErrorMessage = ""
                }

            } catch {
                await MainActor.run {
                    isLoadingSameDayStatus = false
                    isSameDayAvailable = false
                    todayAvailableTimeCount = 0
                    sameDayErrorMessage =
                        "本日の受付状況を取得できませんでした: " +
                        error.localizedDescription
                }
            }
        }
    }

    private func toggleSameDayAvailability() {
        guard let uid = Auth.auth().currentUser?.uid else {
            sameDayErrorMessage = "本日の受付設定にはログインが必要です"
            return
        }

        isUpdatingSameDayStatus = true
        sameDayErrorMessage = ""

        let dateKey = firestoreDate(Date())
        let todayRef = db
            .collection("coachAvailability")
            .document(uid)
            .collection("dates")
            .document(dateKey)

        if isSameDayAvailable {
            todayRef.setData(
                ["sameDayAvailable": false],
                merge: true
            ) { error in
                DispatchQueue.main.async {
                    isUpdatingSameDayStatus = false

                    if let error {
                        sameDayErrorMessage =
                            "本日の受付を終了できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    isSameDayAvailable = false
                    sameDayAlertMessage =
                        "「本日レッスン可能コーチ」への掲載を終了しました。"
                    showSameDayAlert = true
                }
            }

            return
        }

        Task {
            do {
                let todaySnapshot = try await todayRef.getDocument()

                let savedTimes =
                    todaySnapshot.data()?["times"] as? [String] ?? []

                let reservationSnapshot = try await db
                    .collection("reservations")
                    .whereField("coachId", isEqualTo: uid)
                    .getDocuments()

                let reservedTimes = blockedTimes(
                    for: dateKey,
                    documents: reservationSnapshot.documents
                )

                let actualAvailableTimes =
                    Set(savedTimes)
                        .subtracting(reservedTimes)
                        .filter { isFutureTimeSlot($0, dateKey: dateKey) }

                guard !actualAvailableTimes.isEmpty else {
                    await MainActor.run {
                        todayAvailableTimeCount = 0
                        isSameDayAvailable = false
                        isUpdatingSameDayStatus = false
                        sameDayErrorMessage =
                            "本日の予約可能な空き枠がありません。空き日程から本日の時間を登録してください。"
                    }
                    return
                }

                try await todayRef.setData(
                    ["sameDayAvailable": true],
                    merge: true
                )

                await MainActor.run {
                    todayAvailableTimeCount = actualAvailableTimes.count
                    isSameDayAvailable = true
                    isUpdatingSameDayStatus = false
                    sameDayErrorMessage = ""
                    sameDayAlertMessage =
                        "本日の受付をONにしました。「本日レッスン可能コーチ」への掲載対象になります。"
                    showSameDayAlert = true
                }

            } catch {
                await MainActor.run {
                    isUpdatingSameDayStatus = false
                    sameDayErrorMessage =
                        "本日の受付設定を更新できませんでした: " +
                        error.localizedDescription
                }
            }
        }
    }

    private func blockedTimes(
        for dateKey: String,
        documents: [QueryDocumentSnapshot]
    ) -> Set<String> {
        var result: Set<String> = []

        for document in documents {
            let data = document.data()

            let reservationDate =
                (data["date"] as? String ?? "")
                    .replacingOccurrences(of: "/", with: "-")

            guard reservationDate == dateKey else {
                continue
            }

            let status = data["status"] as? String ?? ""

            guard blockingReservationStatuses.contains(status) else {
                continue
            }

            let savedTimes = data["times"] as? [String] ?? []
            let legacyTime = data["time"] as? String ?? ""

            let reservationTimes =
                savedTimes.isEmpty
                    ? (legacyTime.isEmpty ? [] : [legacyTime])
                    : savedTimes

            for value in reservationTimes {
                if let start = startTime(from: value) {
                    result.insert(start)
                }
            }
        }

        return result
    }

    private func startTime(from value: String) -> String? {
        let normalized =
            value.replacingOccurrences(of: "~", with: "〜")

        let firstPart =
            normalized
                .components(separatedBy: "〜")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""

        return firstPart.isEmpty ? nil : firstPart
    }

    private func isFutureTimeSlot(
        _ value: String,
        dateKey: String
    ) -> Bool {
        guard let start = startTime(from: value) else {
            return false
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        guard let slotDate = formatter.date(
            from: "\(dateKey) \(start)"
        ) else {
            return false
        }

        return slotDate > Date()
    }

    private func startReservationListener() {
        reservationListener?.remove()

        guard let uid = Auth.auth().currentUser?.uid else {
            pendingCount = 0
            todayLessonCount = 0
            monthlySales = 0
            nextLesson = "ログインが必要です"
            return
        }

        reservationListener = db.collection("reservations")
            .whereField("coachId", isEqualTo: uid)
            .addSnapshotListener { snapshot, _ in
                let documents = snapshot?.documents ?? []
                let now = Date()
                let calendar = Calendar.current
                let todayKey = firestoreDate(now)

                var newPendingCount = 0
                var newTodayLessonCount = 0
                var newMonthlySales = 0
                var nextLessonDate: Date?

                for document in documents {
                    let data = document.data()
                    let status = data["status"] as? String ?? "pending"
                    let date = data["date"] as? String ?? ""
                    let savedTimes = data["times"] as? [String] ?? []
                    let legacyTime = data["time"] as? String ?? ""
                    let times = savedTimes.isEmpty
                        ? (legacyTime.isEmpty ? [] : [legacyTime])
                        : savedTimes.sorted()

                    if status == "pending" {
                        newPendingCount += 1
                    }

                    if date == todayKey &&
                        (status == "confirmed" || status == "paid") {
                        newTodayLessonCount += 1
                    }

                    let paymentStatus =
                        data["paymentStatus"] as? String ?? ""
                    let refundStatus =
                        data["refundStatus"] as? String ?? ""

                    let isSuccessfullyPaid =
                        paymentStatus == "paid" ||
                        (paymentStatus.isEmpty && status == "paid")

                    let isSuccessfullyRefunded =
                        paymentStatus == "refunded" ||
                        refundStatus == "succeeded"

                    if let paidAt = data["paidAt"] as? Timestamp,
                       calendar.isDate(
                            paidAt.dateValue(),
                            equalTo: now,
                            toGranularity: .month
                       ) {
                        let originalAmount =
                            data["amountPaid"] as? Int ??
                            data["totalPrice"] as? Int ??
                            0

                        if isSuccessfullyPaid {
                            newMonthlySales += originalAmount
                        } else if isSuccessfullyRefunded {
                            let refundAmount =
                                data["refundAmount"] as? Int ??
                                originalAmount

                            newMonthlySales += max(
                                0,
                                originalAmount - refundAmount
                            )
                        }
                    }

                    if status == "confirmed" || status == "paid",
                       let firstTime = times.first,
                       let lessonDate = lessonDate(
                            date: date,
                            time: firstTime
                       ),
                       lessonDate >= now,
                       lessonDate < (nextLessonDate ?? .distantFuture) {
                        nextLessonDate = lessonDate
                    }
                }

                DispatchQueue.main.async {
                    pendingCount = newPendingCount
                    todayLessonCount = newTodayLessonCount
                    monthlySales = newMonthlySales
                    nextLesson = nextLessonDate.map(displayLessonDate)
                        ?? "予定はありません"
                }
            }
    }

    private func startUnreadMessageListener() {
        messageListener?.remove()

        guard let uid = Auth.auth().currentUser?.uid else {
            unreadChatCount = 0
            return
        }

        messageListener = db.collection("messages")
            .whereField("coachId", isEqualTo: uid)
            .addSnapshotListener { snapshot, _ in
                let unreadCount = snapshot?.documents.filter { document in
                    let data = document.data()
                    let isUnread = data["isRead"] as? Bool != true

                    let sender: String

                    if let savedSender = data["sender"] as? String {
                        sender = savedSender
                    } else if let isStudentMessage = data["isMe"] as? Bool {
                        // 以前のメッセージ形式にも対応します。
                        sender = isStudentMessage ? "user" : "coach"
                    } else {
                        sender = ""
                    }

                    return sender == "user" && isUnread
                }.count ?? 0

                DispatchQueue.main.async {
                    unreadChatCount = unreadCount
                }
            }
    }

    private func firestoreDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func lessonDate(date: String, time: String) -> Date? {
        let startTime = time
            .replacingOccurrences(of: "~", with: "〜")
            .components(separatedBy: "〜")
            .first ?? time

        let normalizedDate = date.replacingOccurrences(of: "/", with: "-")
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(normalizedDate) \(startTime)")
    }

    private func displayLessonDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d（E） HH:mm"
        return formatter.string(from: date)
    }
}

private struct DashboardSummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

private struct DashboardActionRow: View {
    let title: String
    let detail: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(14)
    }
}

private struct CoachMyPageView: View {
    var body: some View {
        List {
            Section("プロフィール") {
                NavigationLink {
                    CoachRegisterView()
                } label: {
                    Label("プロフィールを編集", systemImage: "person.crop.circle")
                }
            }

            Section("管理") {
                NavigationLink {
                    CoachSalesView()
                } label: {
                    Label("売上管理", systemImage: "yensign.circle")
                }
            }

            Section("お知らせ") {
                Label(
                    "通知は右上のベルから確認できます",
                    systemImage: "bell"
                )
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CoachSalesView: View {

    private struct SaleItem: Identifiable {
        let id: String
        let studentName: String
        let date: String
        let originalAmount: Int
        let paymentStatus: String
        let refundStatus: String
        let refundAmount: Int
        let paidAt: Timestamp?

        var isRefunded: Bool {
            paymentStatus == "refunded" ||
            refundStatus == "succeeded"
        }

        var isRefundProcessing: Bool {
            paymentStatus == "refund_processing" ||
            ["creating", "pending", "requires_action"].contains(
                refundStatus
            )
        }

        var isRefundFailed: Bool {
            paymentStatus == "refund_failed" ||
            ["failed", "canceled", "failed_to_create"].contains(
                refundStatus
            )
        }

        var effectiveRefundAmount: Int {
            guard isRefunded else {
                return 0
            }

            return refundAmount > 0
                ? min(refundAmount, originalAmount)
                : originalAmount
        }

        var netAmount: Int {
            max(0, originalAmount - effectiveRefundAmount)
        }
    }

    @State private var sales: [SaleItem] = []
    @State private var selectedMonth = Date()
    @State private var isLoading = false
    @State private var errorMessage = ""

    private let db = Firestore.firestore()

    private var salesCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        return calendar
    }

    private var currentMonth: Date {
        startOfMonth(Date())
    }

    private var earliestMonth: Date {
        sales.compactMap(accountingDate)
            .min()
            .map(startOfMonth) ??
            currentMonth
    }

    private var totalNetSales: Int {
        sales.reduce(0) {
            $0 + $1.netAmount
        }
    }

    private var currentMonthNetSales: Int {
        netSales(for: currentMonth)
    }

    private var selectedMonthSales: [SaleItem] {
        let targetMonth = startOfMonth(selectedMonth)

        return sales.filter { sale in
            guard let date = accountingDate(for: sale) else {
                return false
            }

            return salesCalendar.isDate(
                date,
                equalTo: targetMonth,
                toGranularity: .month
            )
        }
    }

    private var selectedMonthNetSales: Int {
        selectedMonthSales.reduce(0) {
            $0 + $1.netAmount
        }
    }

    private var previousMonth: Date {
        salesCalendar.date(
            byAdding: .month,
            value: -1,
            to: startOfMonth(selectedMonth)
        ) ?? startOfMonth(selectedMonth)
    }

    private var previousMonthNetSales: Int {
        netSales(for: previousMonth)
    }

    private var monthDifference: Int {
        selectedMonthNetSales - previousMonthNetSales
    }

    private var canMoveToPreviousMonth: Bool {
        startOfMonth(selectedMonth) > earliestMonth
    }

    private var canMoveToNextMonth: Bool {
        startOfMonth(selectedMonth) < currentMonth
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                HStack(spacing: 12) {
                    SalesSummaryCard(
                        title: "今月の売上",
                        value: currentMonthNetSales
                    )

                    SalesSummaryCard(
                        title: "累計売上",
                        value: totalNetSales
                    )
                }

                Text(
                    "※ 売上は決済額から完了済みの返金額を差し引いた金額です。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if isLoading {
                    ProgressView("売上を読み込み中…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                } else if sales.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "yensign.circle")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)

                        Text("売上はまだありません")
                            .font(.headline)

                        Text("支払いが完了すると、ここに表示されます")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                } else {
                    Text("月別売上")
                        .font(.headline)

                    monthSelector

                    monthComparisonCard

                    Text("売上明細")
                        .font(.headline)

                    if selectedMonthSales.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "calendar.badge.minus")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)

                            Text(
                                "\(monthTitle(selectedMonth))の売上はありません"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(selectedMonthSales) { sale in
                                saleRow(sale)

                                if sale.id != selectedMonthSales.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                    }
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .navigationTitle("売上管理")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            loadSales()
        }
        .onAppear {
            loadSales()
        }
    }

    private var monthSelector: some View {
        HStack {
            Button {
                moveSelectedMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .fontWeight(.semibold)
                    .frame(width: 40, height: 40)
            }
            .disabled(!canMoveToPreviousMonth)

            Spacer()

            Text(monthTitle(selectedMonth))
                .font(.title3)
                .fontWeight(.bold)

            Spacer()

            Button {
                moveSelectedMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .fontWeight(.semibold)
                    .frame(width: 40, height: 40)
            }
            .disabled(!canMoveToNextMonth)
        }
        .padding(.horizontal, 6)
    }

    private var monthComparisonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(monthTitle(selectedMonth))の売上")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("¥\(selectedMonthNetSales.formatted())")
                        .font(.title2)
                        .fontWeight(.bold)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("前月")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("¥\(previousMonthNetSales.formatted())")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }

            Divider()

            HStack {
                Text("前月比")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(monthComparisonText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(monthComparisonColor)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }

    private var monthComparisonText: String {
        if monthDifference == 0 {
            return "±¥0"
        }

        let amountSign = monthDifference > 0 ? "+" : "-"
        let amount =
            "\(amountSign)¥\(abs(monthDifference).formatted())"

        guard previousMonthNetSales > 0 else {
            return amount
        }

        let percentage =
            Double(monthDifference) /
            Double(previousMonthNetSales) *
            100

        let percentSign = percentage > 0 ? "+" : ""
        let percentText = String(
            format: "%@%.1f%%",
            percentSign,
            percentage
        )

        return "\(amount)（\(percentText)）"
    }

    private var monthComparisonColor: Color {
        if monthDifference > 0 {
            return .green
        }

        if monthDifference < 0 {
            return .red
        }

        return .secondary
    }

    private func saleRow(
        _ sale: SaleItem
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {

            VStack(alignment: .leading, spacing: 5) {
                Text(sale.studentName)
                    .fontWeight(.semibold)

                Text(
                    sale.date.replacingOccurrences(
                        of: "-",
                        with: "/"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                saleStatusLabel(sale)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text("¥\(sale.originalAmount.formatted())")
                    .fontWeight(.bold)
                    .foregroundStyle(
                        sale.isRefunded
                            ? Color.gray
                            : Color.green
                    )

                if sale.isRefunded {
                    Text(
                        "実質 ¥\(sale.netAmount.formatted())"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    @ViewBuilder
    private func saleStatusLabel(
        _ sale: SaleItem
    ) -> some View {
        if sale.isRefunded {
            let refundText: String = {
                if sale.netAmount == 0 {
                    return "全額返金済み"
                }

                guard sale.originalAmount > 0 else {
                    return "一部返金済み"
                }

                let percentage = Int(
                    (
                        Double(sale.effectiveRefundAmount) /
                        Double(sale.originalAmount) *
                        100
                    ).rounded()
                )

                return "\(percentage)%返金済み"
            }()

            Label(
                refundText,
                systemImage: "arrow.uturn.backward.circle.fill"
            )
            .foregroundStyle(.purple)

        } else if sale.isRefundFailed {
            Label(
                "返金確認中",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.red)

        } else if sale.isRefundProcessing {
            Label(
                "返金処理中",
                systemImage: "arrow.triangle.2.circlepath"
            )
            .foregroundStyle(.orange)

        } else {
            Label(
                "支払い済み",
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
        }
    }

    private func loadSales() {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "売上の確認にはログインが必要です"
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
                            "売上を取得できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    var loadedSales: [SaleItem] =
                        snapshot?.documents.compactMap {
                            document -> SaleItem? in

                            let data = document.data()
                            let status =
                                data["status"] as? String ?? ""
                            let paymentStatus =
                                data["paymentStatus"] as? String ?? ""
                            let refundStatus =
                                data["refundStatus"] as? String ?? ""
                            let paidAt =
                                data["paidAt"] as? Timestamp

                            let hasPaymentRecord =
                                paidAt != nil ||
                                status == "paid" ||
                                [
                                    "paid",
                                    "refunded",
                                    "refund_processing",
                                    "refund_failed"
                                ].contains(paymentStatus)

                            guard hasPaymentRecord else {
                                return nil
                            }

                            let originalAmount =
                                data["amountPaid"] as? Int ??
                                data["totalPrice"] as? Int ??
                                0

                            guard originalAmount > 0 else {
                                return nil
                            }

                            return SaleItem(
                                id: document.documentID,
                                studentName:
                                    data["studentDisplayName"] as? String ??
                                    data["studentName"] as? String ??
                                    "生徒",
                                date:
                                    data["date"] as? String ?? "",
                                originalAmount: originalAmount,
                                paymentStatus: paymentStatus,
                                refundStatus: refundStatus,
                                refundAmount:
                                    data["refundAmount"] as? Int ?? 0,
                                paidAt: paidAt
                            )
                        } ?? []

                    loadedSales.sort {
                        let first =
                            accountingDate(for: $0) ?? .distantPast
                        let second =
                            accountingDate(for: $1) ?? .distantPast

                        return first > second
                    }

                    sales = loadedSales
                    selectedMonth = currentMonth
                    errorMessage = ""
                }
            }
    }

    private func netSales(
        for month: Date
    ) -> Int {
        sales.reduce(0) { total, sale in
            guard let date = accountingDate(for: sale),
                  salesCalendar.isDate(
                    date,
                    equalTo: month,
                    toGranularity: .month
                  ) else {
                return total
            }

            return total + sale.netAmount
        }
    }

    private func accountingDate(
        for sale: SaleItem
    ) -> Date? {
        if let paidAt = sale.paidAt {
            return paidAt.dateValue()
        }

        return reservationDate(sale.date)
    }

    private func reservationDate(
        _ value: String
    ) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = salesCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo")
        formatter.isLenient = false

        for format in ["yyyy-MM-dd", "yyyy/MM/dd"] {
            formatter.dateFormat = format

            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    private func startOfMonth(
        _ date: Date
    ) -> Date {
        let components = salesCalendar.dateComponents(
            [.year, .month],
            from: date
        )

        return salesCalendar.date(
            from: components
        ) ?? date
    }

    private func monthTitle(
        _ date: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = salesCalendar
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy年M月"

        return formatter.string(
            from: startOfMonth(date)
        )
    }

    private func moveSelectedMonth(
        by value: Int
    ) {
        guard let newMonth = salesCalendar.date(
            byAdding: .month,
            value: value,
            to: startOfMonth(selectedMonth)
        ) else {
            return
        }

        selectedMonth = newMonth
    }
}

private struct SalesSummaryCard: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("¥\(value.formatted())")
                .font(.title3)
                .fontWeight(.bold)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(14)
    }
}


#Preview {
    NavigationStack {
        CoachHomeView()
    }
}
