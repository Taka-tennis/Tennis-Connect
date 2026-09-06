import SwiftUI
import FirebaseAuth
import FirebaseFirestore

enum NotificationAudience: Equatable {
    case student
    case coach
}

enum NotificationRouting {

    private static let coachTypes: Set<String> = [
        "reservationRequested",
        "reservationWithdrawn",
        "studentCancellation"
    ]

    static func belongs(
        type: String,
        to audience: NotificationAudience
    ) -> Bool {

        // 雨天キャンセル系は送信先がtype名に明示されているため、
        // 今後種類が増えてもToCoach / ToStudentで安全に振り分ける。
        if type.hasSuffix("ToCoach") {
            return audience == .coach
        }

        if type.hasSuffix("ToStudent") {
            return audience == .student
        }

        if coachTypes.contains(type) {
            return audience == .coach
        }

        // 現在、上記以外の通知は生徒向け。
        return audience == .student
    }

    static func unreadCount(
        in documents: [QueryDocumentSnapshot],
        audience: NotificationAudience
    ) -> Int {

        let relevantDocuments =
            documents.filter { document in
                let type =
                    document.data()["type"]
                    as? String
                    ?? ""

                return belongs(
                    type: type,
                    to: audience
                )
            }

        // 予約取り下げ後は、同じ予約の古い
        // 「新しい予約申請」を通知一覧でも非表示にしている。
        // ベルの未読件数も同じ挙動へ揃える。
        let withdrawnReservationIds: Set<String>

        if audience == .coach {
            withdrawnReservationIds = Set(
                relevantDocuments.compactMap {
                    document in

                    let data =
                        document.data()

                    guard
                        data["type"] as? String
                            == "reservationWithdrawn"
                    else {
                        return nil
                    }

                    let reservationId =
                        data["reservationId"]
                        as? String
                        ?? ""

                    return reservationId.isEmpty
                        ? nil
                        : reservationId
                }
            )
        } else {
            withdrawnReservationIds = []
        }

        return relevantDocuments.filter {
            document in

            let data =
                document.data()

            let isUnread =
                data["isRead"]
                as? Bool
                != true

            guard isUnread else {
                return false
            }

            if audience == .coach,
               data["type"] as? String
                    == "reservationRequested" {

                let reservationId =
                    data["reservationId"]
                    as? String
                    ?? ""

                if !reservationId.isEmpty &&
                    withdrawnReservationIds.contains(
                        reservationId
                    ) {
                    return false
                }
            }

            return true
        }
        .count
    }
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
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection

                    if isLoading && notifications.isEmpty {
                        loadingState
                    } else if notifications.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(notifications) { notification in
                                notificationCard(notification)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .refreshable {
                startListening()
            }
        }
        .navigationTitle("")
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
                    Button {
                        markAllAsRead()
                    } label: {
                        Text("すべて既読")
                            .font(.subheadline.weight(.semibold))
                    }
                    .tint(.green)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isOpeningDestination {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.green)

                    Text("関連画面を開いています…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            } else if !errorMessage.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(
                        systemName: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)

                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
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

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("通知")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(
                audience == .coach
                    ? "予約申請やキャンセルなどのお知らせを確認できます"
                    : "予約の承認・キャンセル・返金などのお知らせを確認できます"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingState: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.green)

            Text("通知を読み込み中…")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(18)
        .background(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .fill(
                Color(.secondarySystemGroupedBackground)
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                Color.primary.opacity(0.06),
                lineWidth: 1
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.10))
                    .frame(width: 76, height: 76)

                Image(systemName: "bell.slash.fill")
                    .font(
                        .system(
                            size: 30,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.green)
            }

            Text("通知はありません")
                .font(.title3)
                .fontWeight(.semibold)

            Text(
                audience == .coach
                    ? "新しい予約申請やキャンセルなどのお知らせがここに表示されます"
                    : "予約の承認・キャンセル・返金などのお知らせがここに表示されます"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .fill(
                Color(.secondarySystemGroupedBackground)
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                Color.primary.opacity(0.06),
                lineWidth: 1
            )
        }
    }

    private func notificationCard(
        _ notification: NotificationItem
    ) -> some View {

        Button {
            openRelatedScreen(notification)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                    .fill(
                        iconColor(
                            for: notification.type
                        )
                        .opacity(0.12)
                    )
                    .frame(
                        width: 46,
                        height: 46
                    )

                    Image(
                        systemName:
                            iconName(
                                for: notification.type
                            )
                    )
                    .font(
                        .system(
                            size: 20,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        iconColor(
                            for: notification.type
                        )
                    )
                }

                VStack(
                    alignment: .leading,
                    spacing: 7
                ) {
                    HStack(
                        alignment: .firstTextBaseline,
                        spacing: 8
                    ) {
                        Text(notification.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 8)

                        if !notification.isRead {
                            Circle()
                                .fill(Color.green)
                                .frame(
                                    width: 9,
                                    height: 9
                                )
                                .accessibilityLabel("未読")
                        }
                    }

                    Text(notification.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )

                    if let createdAt =
                        notification.createdAt {

                        HStack(spacing: 5) {
                            Image(systemName: "clock")
                                .font(.caption2)

                            Text(
                                displayDate(
                                    createdAt.dateValue()
                                )
                            )
                            .font(.caption2)
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .padding(16)
            .background(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .fill(
                    notification.isRead
                        ? Color(
                            .secondarySystemGroupedBackground
                        )
                        : Color.green.opacity(0.06)
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .stroke(
                    notification.isRead
                        ? Color.primary.opacity(0.06)
                        : Color.green.opacity(0.20),
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
    }

    private func startListening() {
        listener?.remove()

        guard let uid =
            Auth.auth().currentUser?.uid
        else {
            notifications = []
            isLoading = false
            errorMessage =
                "通知の確認にはログインが必要です"
            return
        }

        isLoading = true
        errorMessage = ""

        listener =
            db.collection("notifications")
            .whereField(
                "recipientId",
                isEqualTo: uid
            )
            .addSnapshotListener {
                snapshot,
                error in

                DispatchQueue.main.async {
                    isLoading = false

                    if let error = error {
                        errorMessage =
                            "通知を取得できませんでした: \(error.localizedDescription)"
                        return
                    }

                    var loadedNotifications:
                        [NotificationItem] =
                        snapshot?
                        .documents
                        .map { document in
                            let data =
                                document.data()

                            return NotificationItem(
                                id:
                                    document.documentID,
                                type:
                                    data["type"]
                                    as? String
                                    ?? "",
                                title:
                                    data["title"]
                                    as? String
                                    ?? "お知らせ",
                                message:
                                    data["message"]
                                    as? String
                                    ?? "",
                                reservationId:
                                    data["reservationId"]
                                    as? String
                                    ?? "",
                                coachId:
                                    data["coachId"]
                                    as? String
                                    ?? "",
                                date:
                                    data["date"]
                                    as? String
                                    ?? "",
                                times:
                                    data["times"]
                                    as? [String]
                                    ?? [],
                                isRead:
                                    data["isRead"]
                                    as? Bool
                                    ?? false,
                                createdAt:
                                    data["createdAt"]
                                    as? Timestamp
                            )
                        }
                        .filter { notification in
                            shouldShowNotification(
                                notification
                            )
                        }
                        ?? []

                    let withdrawnReservationIds =
                        Set(
                            loadedNotifications
                                .filter {
                                    $0.type
                                        == "reservationWithdrawn"
                                        &&
                                        !$0.reservationId
                                        .isEmpty
                                }
                                .map(\.reservationId)
                        )

                    if !withdrawnReservationIds
                        .isEmpty {

                        loadedNotifications
                            .removeAll {
                                $0.type
                                    == "reservationRequested"
                                    &&
                                    withdrawnReservationIds
                                    .contains(
                                        $0.reservationId
                                    )
                            }
                    }

                    loadedNotifications.sort {
                        let firstDate =
                            $0.createdAt?
                            .dateValue()
                            ?? .distantPast

                        let secondDate =
                            $1.createdAt?
                            .dateValue()
                            ?? .distantPast

                        return firstDate
                            > secondDate
                    }

                    notifications =
                        loadedNotifications
                }
            }
    }

    private func shouldShowNotification(
        _ notification: NotificationItem
    ) -> Bool {

        NotificationRouting.belongs(
            type: notification.type,
            to: audience
        )
    }

    private func markAsRead(
        _ notification: NotificationItem
    ) {
        guard !notification.isRead else {
            return
        }

        db.collection("notifications")
            .document(notification.id)
            .updateData(
                ["isRead": true]
            ) { error in

                if let error = error {
                    DispatchQueue.main.async {
                        errorMessage =
                            "通知を既読にできませんでした: \(error.localizedDescription)"
                    }
                }
            }
    }

    private func openRelatedScreen(
        _ notification: NotificationItem
    ) {
        markAsRead(notification)
        errorMessage = ""

        switch notification.type {

        case "reservationApproved":
            openPayment(
                for: notification
            )

        case "reservationRejected":
            showStudentReservations = true

        case "coachCancellationRefundStarted",
             "coachCancellationRefunded",
             "coachCancellationRefundFailed":

            showStudentReservations = true

        case "reservationRequested",
             "reservationWithdrawn",
             "studentCancellation":

            showCoachReservations = true

        case "studentCancellationRefunded",
             "studentCancellationRefundFailed",
             "weatherCancellationRequestToStudent",
             "weatherCancellationWithdrawnToStudent",
             "weatherCancellationRejectedToStudent",
             "weatherCancellationApprovedToStudent",
             "weatherCancellationRefundedToStudent",
             "weatherCancellationRefundFailedToStudent":

            showStudentReservations = true

        case "weatherCancellationRequestToCoach",
             "weatherCancellationWithdrawnToCoach",
             "weatherCancellationRejectedToCoach",
             "weatherCancellationApprovedToCoach",
             "weatherCancellationRefundedToCoach",
             "weatherCancellationRefundFailedToCoach":

            showCoachReservations = true

        default:
            break
        }
    }

    private func openPayment(
        for notification: NotificationItem
    ) {
        guard
            !notification.reservationId.isEmpty
        else {
            errorMessage =
                "予約情報を確認できませんでした"
            return
        }

        isOpeningDestination = true

        db.collection("reservations")
            .document(
                notification.reservationId
            )
            .getDocument {
                snapshot,
                error in

                DispatchQueue.main.async {
                    isOpeningDestination = false

                    if let error = error {
                        errorMessage =
                            "予約情報を取得できませんでした: \(error.localizedDescription)"
                        return
                    }

                    guard
                        let data =
                            snapshot?.data()
                    else {
                        errorMessage =
                            "予約情報が見つかりませんでした"
                        return
                    }

                    let status =
                        data["status"]
                        as? String
                        ?? ""

                    if status == "paid" {
                        showStudentReservations =
                            true
                        return
                    }

                    guard
                        status == "confirmed"
                    else {
                        errorMessage =
                            "この予約は現在、支払いへ進めない状態です"
                        return
                    }

                    let savedTimes =
                        data["times"]
                        as? [String]
                        ?? []

                    let legacyTime =
                        data["time"]
                        as? String
                        ?? ""

                    let times =
                        savedTimes.isEmpty
                        ? (
                            legacyTime.isEmpty
                            ? notification.times
                            : [legacyTime]
                        )
                        : savedTimes.sorted()

                    let pricePerHour =
                        data["pricePerHour"]
                        as? Int
                        ?? 0

                    let totalPrice =
                        data["totalPrice"]
                        as? Int
                        ??
                        pricePerHour
                        * times.count

                    let coachId =
                        data["coachId"]
                        as? String
                        ?? notification.coachId

                    let coachName =
                        data["coachName"]
                        as? String
                        ?? "コーチ名未登録"

                    let dateString =
                        data["date"]
                        as? String
                        ?? notification.date

                    let coach = Coach(
                        id: coachId,
                        name: coachName,
                        price: pricePerHour,
                        area: "",
                        imageURL: "",
                        availableTimes: [],
                        ageGroup: "",
                        careers: [
                            "経歴未登録"
                        ],
                        tennisExperience:
                            "未登録",
                        coachingExperience:
                            "未登録",
                        introduction: ""
                    )

                    paymentRoute =
                        PaymentRoute(
                            reservationId:
                                notification
                                .reservationId,
                            coach: coach,
                            date:
                                reservationDate(
                                    dateString
                                ),
                            times: times,
                            totalPrice:
                                totalPrice
                        )

                    showPayment = true
                }
            }
    }

    private func markAllAsRead() {
        let unreadNotifications =
            notifications.filter {
                !$0.isRead
            }

        guard
            !unreadNotifications.isEmpty
        else {
            return
        }

        let batch = db.batch()

        for notification
            in unreadNotifications {

            let reference =
                db.collection("notifications")
                .document(
                    notification.id
                )

            batch.updateData(
                ["isRead": true],
                forDocument: reference
            )
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

    private func iconName(
        for type: String
    ) -> String {

        switch type {

        case "reservationApproved":
            return "checkmark.circle.fill"

        case "reservationRejected":
            return "xmark.circle.fill"

        case "reservationRequested":
            return "calendar.badge.plus"

        case "reservationWithdrawn":
            return "calendar.badge.minus"

        case "studentCancellation":
            return "calendar.badge.minus"

        case "studentCancellationRefunded":
            return "checkmark.seal.fill"

        case "studentCancellationRefundFailed":
            return "exclamationmark.triangle.fill"

        case "coachCancellationRefundStarted":
            return "arrow.uturn.backward.circle.fill"

        case "coachCancellationRefunded":
            return "checkmark.seal.fill"

        case "coachCancellationRefundFailed":
            return "exclamationmark.triangle.fill"

        case "weatherCancellationRequestToStudent",
             "weatherCancellationRequestToCoach":

            return "cloud.rain.fill"

        case "weatherCancellationWithdrawnToStudent",
             "weatherCancellationWithdrawnToCoach":

            return "arrow.uturn.backward.circle.fill"

        case "weatherCancellationRejectedToStudent",
             "weatherCancellationRejectedToCoach":

            return "xmark.circle.fill"

        case "weatherCancellationApprovedToStudent",
             "weatherCancellationApprovedToCoach":

            return "checkmark.circle.fill"

        case "weatherCancellationRefundedToStudent",
             "weatherCancellationRefundedToCoach":

            return "checkmark.seal.fill"

        case "weatherCancellationRefundFailedToStudent",
             "weatherCancellationRefundFailedToCoach":

            return "exclamationmark.triangle.fill"

        default:
            return "bell.fill"
        }
    }

    private func iconColor(
        for type: String
    ) -> Color {

        switch type {

        case "reservationApproved":
            return .green

        case "reservationRejected":
            return .red

        case "reservationRequested":
            return .orange

        case "reservationWithdrawn":
            return .secondary

        case "studentCancellation":
            return .red

        case "studentCancellationRefunded":
            return .green

        case "studentCancellationRefundFailed":
            return .red

        case "coachCancellationRefundStarted":
            return .orange

        case "coachCancellationRefunded":
            return .green

        case "coachCancellationRefundFailed":
            return .red

        case "weatherCancellationRequestToStudent",
             "weatherCancellationRequestToCoach":

            return .blue

        case "weatherCancellationWithdrawnToStudent",
             "weatherCancellationWithdrawnToCoach":

            return .secondary

        case "weatherCancellationRejectedToStudent",
             "weatherCancellationRejectedToCoach":

            return .red

        case "weatherCancellationApprovedToStudent",
             "weatherCancellationApprovedToCoach":

            return .green

        case "weatherCancellationRefundedToStudent",
             "weatherCancellationRefundedToCoach":

            return .green

        case "weatherCancellationRefundFailedToStudent",
             "weatherCancellationRefundFailedToCoach":

            return .red

        default:
            return .blue
        }
    }

    private func displayDate(
        _ date: Date
    ) -> String {

        let formatter =
            DateFormatter()

        formatter.locale =
            Locale(
                identifier: "ja_JP"
            )

        formatter.dateFormat =
            "yyyy/MM/dd HH:mm"

        return formatter.string(
            from: date
        )
    }

    private func reservationDate(
        _ value: String
    ) -> Date {

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

        for format
            in [
                "yyyy-MM-dd",
                "yyyy/MM/dd"
            ] {

            formatter.dateFormat =
                format

            if let date =
                formatter.date(
                    from: value
                ) {
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
