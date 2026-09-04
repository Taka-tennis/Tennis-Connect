// 修正版：コーチ画面を5タブ化し、ホームをダッシュボードに変更

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

private enum CoachUI {
    static let brandGreen = Color(
        red: 42 / 255,
        green: 174 / 255,
        blue: 102 / 255
    )

    static let lime = Color(
        red: 151 / 255,
        green: 207 / 255,
        blue: 63 / 255
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

private struct CoachBrandMark: View {

    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    CoachUI.brandGreen,
                    lineWidth: max(1.5, size * 0.07)
                )
                .frame(width: size, height: size)

            Circle()
                .fill(CoachUI.brandGreen)
                .frame(
                    width: size * 0.16,
                    height: size * 0.16
                )
                .offset(y: -size * 0.5)

            Circle()
                .fill(CoachUI.brandGreen)
                .frame(
                    width: size * 0.16,
                    height: size * 0.16
                )
                .offset(x: size * 0.5)

            Circle()
                .fill(CoachUI.lime)
                .frame(
                    width: size * 0.48,
                    height: size * 0.48
                )
                .overlay {
                    CoachMiniTennisSeams()
                        .stroke(
                            .white,
                            style: StrokeStyle(
                                lineWidth: max(1.1, size * 0.055),
                                lineCap: .round
                            )
                        )
                        .clipShape(Circle())
                }
        }
        .frame(
            width: size * 1.18,
            height: size * 1.18
        )
        .accessibilityHidden(true)
    }
}

private struct CoachMiniTennisSeams: Shape {

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let w = rect.width
        let h = rect.height

        path.move(
            to: CGPoint(
                x: -w * 0.04,
                y: h * 0.25
            )
        )

        path.addCurve(
            to: CGPoint(
                x: w * 1.04,
                y: h * 0.25
            ),
            control1: CGPoint(
                x: w * 0.27,
                y: h * 0.38
            ),
            control2: CGPoint(
                x: w * 0.73,
                y: h * 0.38
            )
        )

        path.move(
            to: CGPoint(
                x: -w * 0.04,
                y: h * 0.75
            )
        )

        path.addCurve(
            to: CGPoint(
                x: w * 1.04,
                y: h * 0.75
            ),
            control1: CGPoint(
                x: w * 0.27,
                y: h * 0.62
            ),
            control2: CGPoint(
                x: w * 0.73,
                y: h * 0.62
            )
        )

        return path
    }
}

struct CoachHomeView: View {

    @State private var selectedTab = 0

    @State private var unreadNotificationCount = 0
    @State private var unreadChatCount = 0

    @State private var notificationListener: ListenerRegistration?
    @State private var messageListener: ListenerRegistration?

    private let db = Firestore.firestore()

    var body: some View {
        TabView(selection: $selectedTab) {
            CoachTabDashboardView(
                selectedTab: $selectedTab,
                unreadChatCount: unreadChatCount
            )
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
                .badge(unreadChatCount)
                .tag(3)

            CoachMyPageView()
                .tabItem {
                    Label("マイページ", systemImage: "person.fill")
                }
                .tag(4)
        }
        .tint(CoachUI.brandGreen)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if selectedTab == 0 {
                    HStack(spacing: 8) {
                        CoachBrandMark(size: 24)

                        Text("Tennis Connect")
                            .font(
                                .system(
                                    size: 18,
                                    weight: .bold,
                                    design: .rounded
                                )
                            )
                            .foregroundStyle(
                                CoachUI.brandGreen
                            )
                    }
                } else {
                    Text(tabTitle)
                        .font(
                            .system(
                                size: 17,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            CoachUI.textPrimary
                        )
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    NotificationView(audience: .coach)
                } label: {
                    Image(
                        systemName: unreadNotificationCount > 0
                            ? "bell.fill"
                            : "bell"
                    )
                    .font(
                        .system(
                            size: 16,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        CoachUI.brandGreen
                    )
                    .frame(width: 34, height: 34)
                    .background(CoachUI.softGreen)
                    .clipShape(Circle())
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
                            .offset(x: 5, y: -5)
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
            startUnreadMessageListener()
        }
        .onDisappear {
            notificationListener?.remove()
            notificationListener = nil

            messageListener?.remove()
            messageListener = nil
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

        notificationListener =
            db.collection("notifications")
                .whereField(
                    "recipientId",
                    isEqualTo: uid
                )
                .addSnapshotListener {
                    snapshot,
                    error in

                    if let error {
                        print(
                            "コーチ未読通知取得エラー:",
                            error.localizedDescription
                        )
                        return
                    }

                    let unreadCount =
                        NotificationRouting.unreadCount(
                            in:
                                snapshot?.documents
                                ?? [],
                            audience: .coach
                        )

                    DispatchQueue.main.async {
                        unreadNotificationCount =
                            unreadCount
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
            .addSnapshotListener { snapshot, error in
                if let error {
                    print(
                        "コーチ未読チャット取得エラー:",
                        error.localizedDescription
                    )
                    return
                }

                let unreadCount =
                    snapshot?.documents.filter { document in
                        let data = document.data()

                        let isUnread =
                            data["isRead"] as? Bool != true

                        let sender: String

                        if let savedSender =
                            data["sender"] as? String {
                            sender = savedSender
                        } else if let isStudentMessage =
                                    data["isMe"] as? Bool {
                            // 以前のメッセージ形式にも対応。
                            sender =
                                isStudentMessage
                                    ? "user"
                                    : "coach"
                        } else {
                            sender = ""
                        }

                        return
                            sender == "user" &&
                            isUnread
                    }
                    .count
                    ?? 0

                DispatchQueue.main.async {
                    unreadChatCount = unreadCount
                }
            }
    }
}

private struct CoachTabDashboardView: View {

    @Binding var selectedTab: Int
    let unreadChatCount: Int

    @State private var pendingCount = 0
    @State private var todayLessonCount = 0
    @State private var monthlySales = 0
    @State private var nextLesson = "予定はありません"
    @State private var reservationListener: ListenerRegistration?

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
        ZStack {
            CoachUI.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {

                    VStack(alignment: .leading, spacing: 5) {
                        Text("コーチダッシュボード")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(
                                CoachUI.textPrimary
                            )

                        Text("今日の予定と売上をまとめて確認できます")
                            .font(.subheadline)
                            .foregroundStyle(
                                CoachUI.textSecondary
                            )
                    }

                    sameDayAvailabilityCard

                    VStack(alignment: .leading, spacing: 12) {
                        Text("今日の状況")
                            .font(.headline)
                            .foregroundStyle(
                                CoachUI.textPrimary
                            )

                        LazyVGrid(
                            columns: columns,
                            spacing: 12
                        ) {
                            Button {
                                selectedTab = 1
                            } label: {
                                DashboardSummaryCard(
                                    title: "承認待ち",
                                    value: "\(pendingCount)件",
                                    icon: "clock",
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
                                    color: CoachUI.brandGreen
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                selectedTab = 3
                            } label: {
                                DashboardSummaryCard(
                                    title: "未読チャット",
                                    value: "\(unreadChatCount)件",
                                    icon: "message",
                                    color: CoachUI.brandGreen
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                CoachSalesView()
                            } label: {
                                DashboardSummaryCard(
                                    title: "今月の売上",
                                    value:
                                        "¥\(monthlySales.formatted())",
                                    icon: "chart.bar",
                                    color: CoachUI.brandGreen
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("クイックアクション")
                            .font(.headline)
                            .foregroundStyle(
                                CoachUI.textPrimary
                            )

                        LazyVGrid(
                            columns: columns,
                            spacing: 12
                        ) {
                            Button {
                                selectedTab = 1
                            } label: {
                                DashboardActionCard(
                                    title: "予約一覧",
                                    detail:
                                        pendingCount > 0
                                            ? "対応待ち \(pendingCount)件"
                                            : "予約を確認",
                                    icon: "calendar"
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                selectedTab = 2
                            } label: {
                                DashboardActionCard(
                                    title: "空き日程",
                                    detail: "受付枠を設定",
                                    icon: "calendar.badge.plus"
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                selectedTab = 4
                            } label: {
                                DashboardActionCard(
                                    title: "プロフィール",
                                    detail: "情報を確認・編集",
                                    icon: "person"
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                CoachSalesView()
                            } label: {
                                DashboardActionCard(
                                    title: "売上確認",
                                    detail: "売上・返金を確認",
                                    icon: "chart.bar"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(
                                systemName:
                                    "calendar.badge.clock"
                            )
                            .font(
                                .system(
                                    size: 16,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                CoachUI.brandGreen
                            )

                            Text("次のレッスン")
                                .font(.headline)
                                .foregroundStyle(
                                    CoachUI.textPrimary
                                )
                        }

                        Text(nextLesson)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(
                                CoachUI.textPrimary
                            )

                        Text("予定の詳細は予約一覧から確認できます")
                            .font(.caption)
                            .foregroundStyle(
                                CoachUI.textSecondary
                            )
                    }
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
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
                            CoachUI.border,
                            lineWidth: 1
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            startReservationListener()
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
        }
    }

    private var sameDayAvailabilityCard: some View {
        VStack(alignment: .leading, spacing: 14) {

            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            isSameDayAvailable
                                ? CoachUI.softGreen
                                : Color(.systemGray6)
                        )
                        .frame(width: 42, height: 42)

                    Image(
                        systemName:
                            isSameDayAvailable
                                ? "bolt.fill"
                                : "bolt"
                    )
                    .font(
                        .system(
                            size: 17,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        isSameDayAvailable
                            ? CoachUI.brandGreen
                            : CoachUI.textSecondary
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("本日のレッスン受付")
                        .font(.headline)
                        .foregroundStyle(
                            CoachUI.textPrimary
                        )

                    if isLoadingSameDayStatus {
                        Text("本日の空き枠を確認中…")
                            .font(.caption)
                            .foregroundStyle(
                                CoachUI.textSecondary
                            )
                    } else {
                        Text(
                            "予約可能な空き枠：\(todayAvailableTimeCount)件"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            CoachUI.textSecondary
                        )
                    }
                }

                Spacer()

                Text(
                    isSameDayAvailable
                        ? "受付中"
                        : "停止中"
                )
                .font(
                    .system(
                        size: 12,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    isSameDayAvailable
                        ? CoachUI.brandGreen
                        : CoachUI.textSecondary
                )
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    isSameDayAvailable
                        ? CoachUI.softGreen
                        : Color(.systemGray6)
                )
                .clipShape(Capsule())
            }

            Button {
                toggleSameDayAvailability()
            } label: {
                HStack(spacing: 8) {
                    Spacer()

                    if isUpdatingSameDayStatus {
                        ProgressView()
                    } else {
                        Image(
                            systemName:
                                isSameDayAvailable
                                    ? "stop.circle"
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
                .frame(height: 46)
                .foregroundStyle(
                    isSameDayAvailable
                        ? Color.red
                        : Color.white
                )
                .background(
                    isSameDayAvailable
                        ? Color.white
                        : CoachUI.brandGreen
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                    .stroke(
                        isSameDayAvailable
                            ? Color.red.opacity(0.45)
                            : Color.clear,
                        lineWidth: 1
                    )
                }
            }
            .buttonStyle(.plain)
            .disabled(
                isLoadingSameDayStatus ||
                isUpdatingSameDayStatus ||
                (!isSameDayAvailable &&
                    todayAvailableTimeCount == 0)
            )
            .opacity(
                isLoadingSameDayStatus ||
                isUpdatingSameDayStatus ||
                (!isSameDayAvailable &&
                    todayAvailableTimeCount == 0)
                    ? 0.55
                    : 1
            )

            if todayAvailableTimeCount == 0 &&
                !isLoadingSameDayStatus {
                Button {
                    selectedTab = 2
                } label: {
                    HStack(spacing: 7) {
                        Image(
                            systemName:
                                "calendar.badge.plus"
                        )

                        Text("本日の空き時間を設定する")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundStyle(
                        CoachUI.brandGreen
                    )
                }
                .buttonStyle(.plain)
            }

            if !sameDayErrorMessage.isEmpty {
                Text(sameDayErrorMessage)
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
                isSameDayAvailable
                    ? CoachUI.brandGreen.opacity(0.22)
                    : CoachUI.border,
                lineWidth: 1
            )
        }
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
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.10))
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(
                            .system(
                                size: 15,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(color)
                }

                Spacer()
            }

            Text(value)
                .font(
                    .system(
                        size: 22,
                        weight: .bold,
                        design: .rounded
                    )
                )
                .foregroundStyle(CoachUI.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(title)
                .font(
                    .system(
                        size: 12,
                        weight: .medium
                    )
                )
                .foregroundStyle(CoachUI.textSecondary)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 112,
            alignment: .leading
        )
        .padding(14)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
            .stroke(CoachUI.border, lineWidth: 1)
        }
    }
}

private struct DashboardActionCard: View {
    let title: String
    let detail: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                ZStack {
                    Circle()
                        .fill(CoachUI.softGreen)
                        .frame(width: 38, height: 38)

                    Image(systemName: icon)
                        .font(
                            .system(
                                size: 16,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            CoachUI.brandGreen
                        )
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(
                        .system(
                            size: 11,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        CoachUI.brandGreen
                    )
            }

            Text(title)
                .font(
                    .system(
                        size: 15,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    CoachUI.textPrimary
                )

            Text(detail)
                .font(.caption)
                .foregroundStyle(
                    CoachUI.textSecondary
                )
                .lineLimit(1)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 108,
            alignment: .leading
        )
        .padding(14)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
            .stroke(CoachUI.border, lineWidth: 1)
        }
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

            Section("売上・入金") {
                NavigationLink {
                    CoachSalesView()
                } label: {
                    Label("売上管理", systemImage: "yensign.circle")
                }

                NavigationLink {
                    CoachConnectSetupView()
                } label: {
                    Label(
                        "売上受取設定",
                        systemImage: "building.columns.circle"
                    )
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

private struct CoachConnectSetupView: View {

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var accountCreated = false
    @State private var detailsSubmitted = false
    @State private var payoutsEnabled = false
    @State private var transfersStatus = "inactive"
    @State private var readyForPayouts = false
    @State private var disabledReason = ""
    @State private var currentlyDueCount = 0
    @State private var pastDueCount = 0

    @State private var isLoading = false
    @State private var isOpeningOnboarding = false
    @State private var errorMessage = ""

    @State private var walletPendingAmount = 0
    @State private var walletAvailableAmount = 0
    @State private var walletTotalCoachEarnings = 0
    @State private var walletTotalPlatformFee = 0
    @State private var walletPendingCount = 0
    @State private var walletAvailableCount = 0
    @State private var walletNextAvailableAtMillis: Double?
    @State private var isLoadingWallet = false
    @State private var walletErrorMessage = ""
    @State private var walletProcessingAmount = 0
    @State private var walletPaidOutAmount = 0

    @State private var isRequestingPayout = false
    @State private var showPayoutConfirmation = false
    @State private var showPayoutResult = false
    @State private var payoutResultMessage = ""

    private let functions = Functions.functions(
        region: "asia-northeast1"
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                statusCard

                if readyForPayouts {
                    walletSummaryCard
                }

                VStack(alignment: .leading, spacing: 0) {
                    connectStatusRow(
                        title: "本人確認情報",
                        isComplete: detailsSubmitted
                    )

                    Divider()
                        .padding(.leading, 44)

                    connectStatusRow(
                        title: "銀行口座への出金",
                        isComplete: payoutsEnabled
                    )

                    Divider()
                        .padding(.leading, 44)

                    connectStatusRow(
                        title: "売上受取機能",
                        isComplete: transfersStatus == "active"
                    )
                }
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                if currentlyDueCount > 0 || pastDueCount > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            "追加の確認が必要です",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.headline)
                        .foregroundStyle(.orange)

                        Text(
                            "Stripeで確認が必要な項目があります。" +
                            "下のボタンから設定を続けてください。"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        if pastDueCount > 0 {
                            Text("期限超過の確認項目：\(pastDueCount)件")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                if !disabledReason.isEmpty {
                    Text("Stripe確認状況：\(disabledReason)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                Button {
                    openStripeOnboarding()
                } label: {
                    HStack {
                        Spacer()

                        if isOpeningOnboarding {
                            ProgressView()
                        } else {
                            Label(
                                onboardingButtonTitle,
                                systemImage: readyForPayouts
                                    ? "checkmark.seal.fill"
                                    : "building.columns.fill"
                            )
                            .fontWeight(.semibold)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(readyForPayouts ? .green : .blue)
                .disabled(
                    isLoading ||
                    isOpeningOnboarding ||
                    readyForPayouts
                )

                Button {
                    refreshConnectAndWallet()
                } label: {
                    HStack {
                        Spacer()
                        Label(
                            "設定状況を更新",
                            systemImage: "arrow.clockwise"
                        )
                        Spacer()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(
                    isLoading ||
                    isLoadingWallet ||
                    isOpeningOnboarding
                )

                if !walletErrorMessage.isEmpty {
                    Text(walletErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                Text(
                    "本人確認や銀行口座情報の登録はStripeの安全な画面で行います。" +
                    "Tennis Connectが銀行口座番号や本人確認書類を保存することはありません。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .navigationTitle("売上受取設定")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading && !accountCreated {
                ProgressView("設定状況を確認中…")
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .onAppear {
            refreshConnectAndWallet()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                refreshConnectAndWallet()
            }
        }
        .alert(
            "銀行口座へ出金しますか？",
            isPresented: $showPayoutConfirmation
        ) {
            Button("キャンセル", role: .cancel) { }

            Button("出金する") {
                requestCoachPayout()
            }
        } message: {
            Text(
                "¥\(walletAvailableAmount.formatted())を" +
                "登録済みの銀行口座へ出金します。"
            )
        }
        .alert(
            "出金手続き",
            isPresented: $showPayoutResult
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(payoutResultMessage)
        }
    }

    private var walletSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(
                    "売上残高",
                    systemImage: "wallet.pass.fill"
                )
                .font(.headline)

                Spacer()

                if isLoadingWallet {
                    ProgressView()
                }
            }

            HStack(spacing: 12) {
                walletAmountCard(
                    title: "売上予定",
                    amount: walletPendingAmount,
                    detail: walletPendingCount > 0
                        ? "\(walletPendingCount)件"
                        : "対象なし",
                    color: .orange
                )

                walletAmountCard(
                    title: "出金可能",
                    amount: walletAvailableAmount,
                    detail: walletAvailableCount > 0
                        ? "\(walletAvailableCount)件"
                        : "対象なし",
                    color: .green
                )
            }

            if let nextAvailableDate = walletNextAvailableDate {
                Label(
                    "次回出金可能：\(walletDateText(nextAvailableDate))",
                    systemImage: "clock.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text("累計コーチ受取額")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("¥\(walletTotalCoachEarnings.formatted())")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            HStack {
                Text("Tennis Connect手数料")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("¥\(walletTotalPlatformFee.formatted())")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            if walletProcessingAmount > 0 {
                HStack {
                    Label(
                        "出金処理中",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.orange)

                    Spacer()

                    Text("¥\(walletProcessingAmount.formatted())")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                }
            }

            if walletPaidOutAmount > 0 {
                HStack {
                    Label(
                        "出金済み",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.green)

                    Spacer()

                    Text("¥\(walletPaidOutAmount.formatted())")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
            }

            Button {
                showPayoutConfirmation = true
            } label: {
                HStack {
                    Spacer()

                    if isRequestingPayout {
                        ProgressView()
                    } else {
                        Label(
                            walletAvailableAmount > 0
                                ? "銀行口座へ出金する"
                                : "出金可能な売上はありません",
                            systemImage: "banknote.fill"
                        )
                        .fontWeight(.semibold)
                    }

                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(
                walletAvailableAmount <= 0 ||
                !readyForPayouts ||
                isRequestingPayout ||
                isLoadingWallet
            )

            Text(
                "手数料は10%です。コーチ受取額は返金後の決済額の90%で、" +
                "レッスン終了24時間後に出金可能になります。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func walletAmountCard(
        title: String,
        amount: Int,
        detail: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("¥\(amount.formatted())")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var walletNextAvailableDate: Date? {
        guard let milliseconds = walletNextAvailableAtMillis else {
            return nil
        }

        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    private func walletDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        formatter.dateFormat = "M/d（E）HH:mm"
        return formatter.string(from: date)
    }

    private var statusCard: some View {
        VStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.system(size: 52))
                .foregroundStyle(statusColor)

            Text(statusTitle)
                .font(.title3)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal)
        .background(statusColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var statusIcon: String {
        if readyForPayouts {
            return "checkmark.seal.fill"
        }

        if accountCreated {
            return "clock.badge.exclamationmark.fill"
        }

        return "building.columns.circle.fill"
    }

    private var statusColor: Color {
        if readyForPayouts {
            return .green
        }

        if accountCreated {
            return .orange
        }

        return .blue
    }

    private var statusTitle: String {
        if readyForPayouts {
            return "売上を受け取れる状態です"
        }

        if accountCreated {
            return "売上受取設定を完了してください"
        }

        return "売上を受け取る設定を始めましょう"
    }

    private var statusMessage: String {
        if readyForPayouts {
            return "Stripe Connectの本人確認と出金設定が完了しています。"
        }

        if accountCreated {
            return "Stripeの画面で本人確認と銀行口座登録を続けてください。"
        }

        return "コーチの売上を銀行口座へ受け取るために、Stripe Connectの設定が必要です。"
    }

    private var onboardingButtonTitle: String {
        if readyForPayouts {
            return "設定完了"
        }

        if accountCreated {
            return "本人確認・口座登録を続ける"
        }

        return "売上受取設定を始める"
    }

    private func connectStatusRow(
        title: String,
        isComplete: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(
                systemName: isComplete
                    ? "checkmark.circle.fill"
                    : "circle"
            )
            .foregroundStyle(isComplete ? .green : .secondary)
            .font(.title3)

            Text(title)
                .font(.subheadline)

            Spacer()

            Text(isComplete ? "完了" : "未完了")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(isComplete ? .green : .secondary)
        }
        .padding()
    }

    private func refreshConnectAndWallet() {
        loadConnectStatus()
        loadWalletSummary()
    }

    private func loadWalletSummary() {
        guard Auth.auth().currentUser != nil else {
            walletErrorMessage =
                "売上残高の確認にはログインが必要です。"
            return
        }

        guard !isLoadingWallet else {
            return
        }

        isLoadingWallet = true
        walletErrorMessage = ""

        functions
            .httpsCallable("getCoachWalletSummary")
            .call([:]) { result, error in
                DispatchQueue.main.async {
                    isLoadingWallet = false

                    if let error {
                        walletErrorMessage =
                            "売上残高を確認できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    guard let data =
                            result?.data as? [String: Any] else {
                        walletErrorMessage =
                            "売上残高の情報を読み取れませんでした。"
                        return
                    }

                    walletPendingAmount =
                        intValue(data["pendingAmount"])
                    walletAvailableAmount =
                        intValue(data["availableAmount"])
                    walletTotalCoachEarnings =
                        intValue(data["totalCoachEarnings"])
                    walletTotalPlatformFee =
                        intValue(data["totalPlatformFee"])
                    walletProcessingAmount =
                        intValue(data["processingAmount"])
                    walletPaidOutAmount =
                        intValue(data["paidOutAmount"])
                    walletPendingCount =
                        intValue(data["pendingCount"])
                    walletAvailableCount =
                        intValue(data["availableCount"])

                    if let number =
                        data["nextAvailableAtMillis"] as? NSNumber {
                        walletNextAvailableAtMillis =
                            number.doubleValue
                    } else if let value =
                                data["nextAvailableAtMillis"] as? Double {
                        walletNextAvailableAtMillis = value
                    } else {
                        walletNextAvailableAtMillis = nil
                    }

                    walletErrorMessage = ""
                }
            }
    }

    private func requestCoachPayout() {
        guard Auth.auth().currentUser != nil else {
            walletErrorMessage =
                "出金にはログインが必要です。"
            return
        }

        guard walletAvailableAmount > 0 else {
            walletErrorMessage =
                "現在、出金可能な売上はありません。"
            return
        }

        isRequestingPayout = true
        walletErrorMessage = ""

        functions
            .httpsCallable("requestCoachPayout")
            .call([:]) { result, error in
                DispatchQueue.main.async {
                    isRequestingPayout = false

                    if let error {
                        walletErrorMessage =
                            "出金できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    let data =
                        result?.data as? [String: Any] ?? [:]
                    let amount =
                        intValue(data["amount"])
                    let serverMessage =
                        data["message"] as? String ??
                        "銀行口座への出金手続きを開始しました。"

                    payoutResultMessage =
                        amount > 0
                            ? "¥\(amount.formatted())\n\(serverMessage)"
                            : serverMessage
                    showPayoutResult = true

                    loadWalletSummary()
                }
            }
    }

    private func loadConnectStatus() {
        guard Auth.auth().currentUser != nil else {
            errorMessage = "売上受取設定にはログインが必要です。"
            return
        }

        guard !isLoading else {
            return
        }

        isLoading = true
        errorMessage = ""

        functions
            .httpsCallable("getCoachConnectStatus")
            .call([:]) { result, error in
                DispatchQueue.main.async {
                    isLoading = false

                    if let error {
                        errorMessage =
                            "設定状況を確認できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    guard let data =
                            result?.data as? [String: Any] else {
                        errorMessage =
                            "Stripe Connectの状態を読み取れませんでした。"
                        return
                    }

                    applyConnectStatus(data)
                }
            }
    }

    private func openStripeOnboarding() {
        guard Auth.auth().currentUser != nil else {
            errorMessage = "売上受取設定にはログインが必要です。"
            return
        }

        isOpeningOnboarding = true
        errorMessage = ""

        functions
            .httpsCallable("createCoachConnectOnboardingLink")
            .call([:]) { result, error in
                DispatchQueue.main.async {
                    isOpeningOnboarding = false

                    if let error {
                        errorMessage =
                            "本人確認ページを開けませんでした: " +
                            error.localizedDescription
                        return
                    }

                    guard
                        let data = result?.data as? [String: Any],
                        let urlString = data["onboardingUrl"] as? String,
                        let url = URL(string: urlString)
                    else {
                        errorMessage =
                            "本人確認ページのURLを取得できませんでした。"
                        return
                    }

                    applyConnectStatus(data)
                    openURL(url)
                }
            }
    }

    private func applyConnectStatus(
        _ data: [String: Any]
    ) {
        accountCreated =
            boolValue(data["accountCreated"]) ||
            data["onboardingUrl"] != nil
        detailsSubmitted = boolValue(data["detailsSubmitted"])
        payoutsEnabled = boolValue(data["payoutsEnabled"])
        transfersStatus =
            data["transfersStatus"] as? String ?? "inactive"
        readyForPayouts = boolValue(data["readyForPayouts"])
        disabledReason =
            data["disabledReason"] as? String ?? ""
        currentlyDueCount = intValue(data["currentlyDueCount"])
        pastDueCount = intValue(data["pastDueCount"])
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool {
            return bool
        }

        if let number = value as? NSNumber {
            return number.boolValue
        }

        return false
    }

    private func intValue(_ value: Any?) -> Int {
        if let int = value as? Int {
            return int
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        return 0
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
