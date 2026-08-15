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

            ChatListView()
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

    private let db = Firestore.firestore()
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("🎾 コーチホーム")
                    .font(.largeTitle)
                    .fontWeight(.bold)

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
        }
        .onDisappear {
            reservationListener?.remove()
            reservationListener = nil
            messageListener?.remove()
            messageListener = nil
        }
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

                    if status == "paid" {
                        let totalPrice = data["totalPrice"] as? Int ?? 0

                        if let paidAt = data["paidAt"] as? Timestamp,
                           calendar.isDate(
                                paidAt.dateValue(),
                                equalTo: now,
                                toGranularity: .month
                           ) {
                            newMonthlySales += totalPrice
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
        let totalPrice: Int
        let paidAt: Timestamp?
    }

    @State private var sales: [SaleItem] = []
    @State private var isLoading = false
    @State private var errorMessage = ""

    private let db = Firestore.firestore()

    private var totalSales: Int {
        sales.reduce(0) { $0 + $1.totalPrice }
    }

    private var monthlySales: Int {
        let calendar = Calendar.current
        let now = Date()

        return sales.reduce(0) { total, sale in
            guard let paidAt = sale.paidAt?.dateValue(),
                  calendar.isDate(
                    paidAt,
                    equalTo: now,
                    toGranularity: .month
                  ) else {
                return total
            }

            return total + sale.totalPrice
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    SalesSummaryCard(
                        title: "今月の売上",
                        value: monthlySales
                    )

                    SalesSummaryCard(
                        title: "累計売上",
                        value: totalSales
                    )
                }

                if isLoading {
                    ProgressView("売上を読み込み中…")
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
                    VStack(spacing: 0) {
                        ForEach(sales) { sale in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sale.studentName)
                                        .fontWeight(.semibold)

                                    Text(sale.date.replacingOccurrences(of: "-", with: "/"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text("¥\(sale.totalPrice)")
                                    .fontWeight(.bold)
                                    .foregroundStyle(.green)
                            }
                            .padding()

                            if sale.id != sales.last?.id {
                                Divider()
                            }
                        }
                    }
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
        }
        .navigationTitle("売上管理")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadSales()
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
                            "売上を取得できませんでした: \(error.localizedDescription)"
                        return
                    }

                    var loadedSales: [SaleItem] =
                        snapshot?.documents.compactMap { document -> SaleItem? in
                            let data = document.data()

                            guard data["status"] as? String == "paid" else {
                                return nil
                            }

                            return SaleItem(
                                id: document.documentID,
                                studentName: data["studentName"] as? String ?? "生徒",
                                date: data["date"] as? String ?? "",
                                totalPrice: data["totalPrice"] as? Int ?? 0,
                                paidAt: data["paidAt"] as? Timestamp
                            )
                        } ?? []

                    loadedSales.sort {
                        let first = $0.paidAt?.dateValue() ?? .distantPast
                        let second = $1.paidAt?.dateValue() ?? .distantPast
                        return first > second
                    }

                    sales = loadedSales
                }
            }
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

            Text("¥\(value)")
                .font(.title3)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
