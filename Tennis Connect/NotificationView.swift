import SwiftUI
import FirebaseAuth
import FirebaseFirestore

enum NotificationAudience: Equatable {
    case student
    case coach
}

struct NotificationView: View {

    private struct NotificationItem: Identifiable {
        let id: String
        let type: String
        let title: String
        let message: String
        let reservationId: String
        let coachId: String
        let date: String
        let times: [String]
        let isRead: Bool
        let createdAt: Timestamp?
    }

    private struct PaymentRoute {
        let reservationId: String
        let coach: Coach
        let date: Date
        let times: [String]
        let totalPrice: Int
    }

    let audience: NotificationAudience

    @State private var notifications: [NotificationItem] = []
    @State private var isLoading = false
    @State private var isOpeningDestination = false
    @State private var errorMessage = ""
    @State private var listener: ListenerRegistration?
    @State private var paymentRoute: PaymentRoute?
    @State private var showPayment = false
    @State private var showStudentReservations = false
    @State private var showCoachReservations = false

    private let db = Firestore.firestore()

    init(audience: NotificationAudience = .student) {
        self.audience = audience
    }

    var body: some View {
        Group {
            if isLoading && notifications.isEmpty {
                ProgressView("通知を読み込み中…")
            } else if notifications.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)

                    Text("通知はありません")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("予約の承認・却下・返金などのお知らせが表示されます")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                List(notifications) { notification in
                    Button {
                        openRelatedScreen(notification)
                    } label: {
                        notificationRow(notification)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        notification.isRead
                            ? Color.clear
                            : Color.blue.opacity(0.08)
                    )
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    startListening()
                }
            }
        }
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showPayment) {
            if let route = paymentRoute {
                PaymentView(
                    reservationId: route.reservationId,
                    coach: route.coach,
                    date: route.date,
                    times: route.times,
                    totalPrice: route.totalPrice
                )
            }
        }
        .navigationDestination(isPresented: $showStudentReservations) {
            ReservationListView()
        }
        .navigationDestination(isPresented: $showCoachReservations) {
            CoachReservationListView()
        }
        .toolbar {
            if notifications.contains(where: { !$0.isRead }) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("すべて既読") {
                        markAllAsRead()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isOpeningDestination {
                ProgressView("関連画面を開いています…")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
            } else if !errorMessage.isEmpty {
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
            startListening()
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
    }

    private func notificationRow(_ notification: NotificationItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: iconName(for: notification.type))
                .font(.title2)
                .foregroundStyle(iconColor(for: notification.type))
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(notification.title)
                        .font(.headline)

                    Spacer()

                    if !notification.isRead {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 9, height: 9)
                    }
                }

                Text(notification.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)

                if let createdAt = notification.createdAt {
                    Text(displayDate(createdAt.dateValue()))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func startListening() {
        listener?.remove()

        guard let uid = Auth.auth().currentUser?.uid else {
            notifications = []
            isLoading = false
            errorMessage = "通知の確認にはログインが必要です"
            return
        }

        isLoading = true
        errorMessage = ""

        listener = db.collection("notifications")
            .whereField("recipientId", isEqualTo: uid)
            .addSnapshotListener { snapshot, error in
                DispatchQueue.main.async {
                    isLoading = false

                    if let error = error {
                        errorMessage =
                            "通知を取得できませんでした: \(error.localizedDescription)"
                        return
                    }

                    var loadedNotifications: [NotificationItem] =
                        snapshot?.documents.map { document in
                            let data = document.data()

                            return NotificationItem(
                                id: document.documentID,
                                type: data["type"] as? String ?? "",
                                title: data["title"] as? String ?? "お知らせ",
                                message: data["message"] as? String ?? "",
                                reservationId: data["reservationId"] as? String ?? "",
                                coachId: data["coachId"] as? String ?? "",
                                date: data["date"] as? String ?? "",
                                times: data["times"] as? [String] ?? [],
                                isRead: data["isRead"] as? Bool ?? false,
                                createdAt: data["createdAt"] as? Timestamp
                            )
                        }
                        .filter { notification in
                            switch audience {
                            case .student:
                                return notification.type != "reservationRequested"
                            case .coach:
                                return notification.type == "reservationRequested"
                            }
                        } ?? []

                    loadedNotifications.sort {
                        let firstDate = $0.createdAt?.dateValue() ?? .distantPast
                        let secondDate = $1.createdAt?.dateValue() ?? .distantPast
                        return firstDate > secondDate
                    }

                    notifications = loadedNotifications
                }
            }
    }

    private func markAsRead(_ notification: NotificationItem) {
        guard !notification.isRead else {
            return
        }

        db.collection("notifications")
            .document(notification.id)
            .updateData(["isRead": true]) { error in
                if let error = error {
                    DispatchQueue.main.async {
                        errorMessage =
                            "通知を既読にできませんでした: \(error.localizedDescription)"
                    }
                }
            }
    }

    private func openRelatedScreen(_ notification: NotificationItem) {
        markAsRead(notification)
        errorMessage = ""

        switch notification.type {
        case "reservationApproved":
            openPayment(for: notification)

        case "reservationRejected":
            showStudentReservations = true

        case "coachCancellationRefundStarted",
             "coachCancellationRefunded",
             "coachCancellationRefundFailed":
            showStudentReservations = true

        case "reservationRequested":
            showCoachReservations = true

        default:
            break
        }
    }

    private func openPayment(for notification: NotificationItem) {
        guard !notification.reservationId.isEmpty else {
            errorMessage = "予約情報を確認できませんでした"
            return
        }

        isOpeningDestination = true

        db.collection("reservations")
            .document(notification.reservationId)
            .getDocument { snapshot, error in
                DispatchQueue.main.async {
                    isOpeningDestination = false

                    if let error = error {
                        errorMessage =
                            "予約情報を取得できませんでした: \(error.localizedDescription)"
                        return
                    }

                    guard let data = snapshot?.data() else {
                        errorMessage = "予約情報が見つかりませんでした"
                        return
                    }

                    let status = data["status"] as? String ?? ""

                    if status == "paid" {
                        showStudentReservations = true
                        return
                    }

                    guard status == "confirmed" else {
                        errorMessage = "この予約は現在、支払いへ進めない状態です"
                        return
                    }

                    let savedTimes = data["times"] as? [String] ?? []
                    let legacyTime = data["time"] as? String ?? ""
                    let times = savedTimes.isEmpty
                        ? (legacyTime.isEmpty ? notification.times : [legacyTime])
                        : savedTimes.sorted()

                    let pricePerHour = data["pricePerHour"] as? Int ?? 0
                    let totalPrice = data["totalPrice"] as? Int
                        ?? pricePerHour * times.count
                    let coachId = data["coachId"] as? String
                        ?? notification.coachId
                    let coachName = data["coachName"] as? String
                        ?? "コーチ名未登録"
                    let dateString = data["date"] as? String
                        ?? notification.date

                    let coach = Coach(
                        id: coachId,
                        name: coachName,
                        price: pricePerHour,
                        area: "",
                        imageURL: "",
                        availableTimes: [],
                        ageGroup: "",
                        careers: ["経歴未登録"],
                        tennisExperience: "未登録",
                        coachingExperience: "未登録",
                        introduction: ""
                    )

                    paymentRoute = PaymentRoute(
                        reservationId: notification.reservationId,
                        coach: coach,
                        date: reservationDate(dateString),
                        times: times,
                        totalPrice: totalPrice
                    )
                    showPayment = true
                }
            }
    }

    private func markAllAsRead() {
        let unreadNotifications = notifications.filter { !$0.isRead }

        guard !unreadNotifications.isEmpty else {
            return
        }

        let batch = db.batch()

        for notification in unreadNotifications {
            let reference = db.collection("notifications")
                .document(notification.id)
            batch.updateData(["isRead": true], forDocument: reference)
        }

        batch.commit { error in
            if let error = error {
                DispatchQueue.main.async {
                    errorMessage =
                        "通知を既読にできませんでした: \(error.localizedDescription)"
                }
            }
        }
    }

    private func iconName(for type: String) -> String {
        switch type {
        case "reservationApproved":
            return "checkmark.circle.fill"
        case "reservationRejected":
            return "xmark.circle.fill"
        case "reservationRequested":
            return "calendar.badge.plus"
        case "coachCancellationRefundStarted":
            return "arrow.uturn.backward.circle.fill"
        case "coachCancellationRefunded":
            return "checkmark.seal.fill"
        case "coachCancellationRefundFailed":
            return "exclamationmark.triangle.fill"
        default:
            return "bell.fill"
        }
    }

    private func iconColor(for type: String) -> Color {
        switch type {
        case "reservationApproved":
            return .green
        case "reservationRejected":
            return .red
        case "reservationRequested":
            return .orange
        case "coachCancellationRefundStarted":
            return .orange
        case "coachCancellationRefunded":
            return .green
        case "coachCancellationRefundFailed":
            return .red
        default:
            return .blue
        }
    }

    private func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }

    private func reservationDate(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in ["yyyy-MM-dd", "yyyy/MM/dd"] {
            formatter.dateFormat = format

            if let date = formatter.date(from: value) {
                return date
            }
        }

        return Date()
    }
}

#Preview {
    NavigationStack {
        NotificationView()
    }
}
