import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

enum ChatParticipantRole {
    case student
    case coach
}

struct Message: Identifiable {

    let id: String
    let text: String
    let sender: String
    let createdAt: Date
    var isRead: Bool
}

struct ChatView: View {

    let coachId: String
    let coachName: String
    let studentId: String
    let currentRole: ChatParticipantRole

    private let initialStudentName: String
    private let db = Firestore.firestore()
    private let functions = Functions.functions(
        region: "asia-northeast1"
    )

    @State private var message = ""
    @State private var messages: [Message] = []
    @State private var studentDisplayName: String
    @State private var partnerImageURL: String
    @State private var errorMessage = ""
    @State private var isMessagingAllowed = false
    @State private var isCheckingMessagingStatus = false
    @State private var messagingRestrictionReason = "checking"
    @State private var listener: ListenerRegistration?

    init(coach: Coach) {
        let currentStudentId =
            Auth.auth().currentUser?.uid ?? ""

        self.coachId = coach.id
        self.coachName = coach.name
        self.studentId = currentStudentId
        self.currentRole = .student
        self.initialStudentName = ""

        _studentDisplayName =
            State(initialValue: "")
        _partnerImageURL =
            State(initialValue: coach.imageURL)
    }

    init(
        coachId: String,
        coachName: String,
        studentId: String,
        studentName: String,
        currentRole: ChatParticipantRole
    ) {
        self.coachId = coachId
        self.coachName = coachName
        self.studentId = studentId
        self.currentRole = currentRole
        self.initialStudentName = studentName

        _studentDisplayName =
            State(initialValue: studentName)
        _partnerImageURL =
            State(initialValue: "")
    }

    private var currentSender: String {
        currentRole == .student
            ? "user"
            : "coach"
    }

    private var incomingSender: String {
        currentRole == .student
            ? "coach"
            : "user"
    }

    private var navigationTitle: String {
        switch currentRole {
        case .student:
            return coachName

        case .coach:
            let trimmed =
                studentDisplayName
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

            return trimmed.isEmpty
                ? "生徒"
                : trimmed
        }
    }

    private var conversationId: String {
        "\(studentId)__\(coachId)"
    }

    var body: some View {
        VStack(spacing: 0) {

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(
                            Array(messages.enumerated()),
                            id: \.element.id
                        ) { index, msg in

                            if shouldShowDateSeparator(
                                at: index
                            ) {
                                dateSeparator(
                                    for: msg.createdAt
                                )
                            }

                            messageRow(msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .background(
                    Color(.systemGroupedBackground)
                )
                .onChange(
                    of: messages.count
                ) { _ in
                    scrollToLatestMessage(
                        using: proxy
                    )
                }
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(
                        Color(.systemBackground)
                    )
            }

            Divider()

            messageInputBar
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadParticipantProfiles()
            refreshMessagingStatus()
            startMessageListener()
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
    }

    @ViewBuilder
    private func messageRow(
        _ msg: Message
    ) -> some View {
        if msg.sender == currentSender {
            outgoingMessageRow(msg)
        } else {
            incomingMessageRow(msg)
        }
    }

    private func outgoingMessageRow(
        _ msg: Message
    ) -> some View {
        HStack(
            alignment: .bottom,
            spacing: 7
        ) {
            Spacer(minLength: 48)

            VStack(
                alignment: .trailing,
                spacing: 3
            ) {
                Text(msg.text)
                    .font(.body)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(
                        .leading
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                    .padding(
                        .horizontal,
                        14
                    )
                    .padding(
                        .vertical,
                        10
                    )
                    .frame(
                        maxWidth: 280,
                        alignment: .leading
                    )
                    .background {
                        ChatBubbleBackground(
                            isOutgoing: true,
                            color: .green,
                            borderColor: .clear
                        )
                    }

                HStack(spacing: 5) {
                    if msg.isRead {
                        Text("既読")
                    }

                    Text(
                        messageTime(
                            msg.createdAt
                        )
                    )
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.trailing, 2)
            }
        }
    }

    private func incomingMessageRow(
        _ msg: Message
    ) -> some View {
        HStack(
            alignment: .bottom,
            spacing: 9
        ) {
            NavigationLink {
                partnerProfileDestination
            } label: {
                ChatPartnerAvatarView(
                    imageURL: partnerImageURL,
                    size: 38
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "\(navigationTitle)さんのプロフィール"
            )

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(msg.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(
                        .leading
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
                    .padding(
                        .horizontal,
                        14
                    )
                    .padding(
                        .vertical,
                        10
                    )
                    .frame(
                        maxWidth: 270,
                        alignment: .leading
                    )
                    .background {
                        ChatBubbleBackground(
                            isOutgoing: false,
                            color: Color(.systemGray5),
                            borderColor:
                                Color(.systemGray3)
                                    .opacity(0.7)
                        )
                    }

                Text(
                    messageTime(
                        msg.createdAt
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            }

            Spacer(minLength: 35)
        }
    }

    @ViewBuilder
    private var partnerProfileDestination: some View {
        switch currentRole {
        case .student:
            CoachProfileDestinationView(
                coachId: coachId
            )

        case .coach:
            StudentPublicProfileView(
                studentId: studentId,
                initialDisplayName:
                    studentDisplayName,
                initialImageURL:
                    partnerImageURL
            )
        }
    }

    private var messageInputBar: some View {
        VStack(spacing: 8) {
            if !isMessagingAllowed {
                HStack(spacing: 7) {
                    Image(systemName: "lock.fill")
                        .font(.caption)

                    Text(messagingRestrictionText)
                        .font(.caption)
                        .multilineTextAlignment(.leading)

                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 7)
            }

            HStack(
                alignment: .bottom,
                spacing: 9
            ) {
                TextField(
                    "メッセージ",
                    text: $message,
                    axis: .vertical
                )
                .lineLimit(1...5)
                .padding(
                    .horizontal,
                    13
                )
                .padding(
                    .vertical,
                    9
                )
                .background(
                    Color(.systemGray6)
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )
                .disabled(
                    !isMessagingAllowed
                    || isCheckingMessagingStatus
                )

                Button {
                    saveMessage()
                } label: {
                    Group {
                        if isCheckingMessagingStatus {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(
                                systemName:
                                    "paperplane.fill"
                            )
                            .font(
                                .system(
                                    size: 18,
                                    weight: .semibold
                                )
                            )
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(
                        width: 38,
                        height: 38
                    )
                    .background(
                        canSendMessage
                            ? Color.green
                            : Color.gray
                    )
                    .clipShape(Circle())
                }
                .disabled(!canSendMessage)
                .accessibilityLabel(
                    "メッセージを送信"
                )
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 9)
        }
        .background(
            Color(.systemBackground)
        )
    }

    private var messagingRestrictionText: String {
        switch messagingRestrictionReason {
        case "blocked":
            if currentRole == .student {
                return "このコーチをブロックしているため、メッセージを送信できません。"
            }

            return "現在このチャットではメッセージを送信できません。"

        case "payment_required":
            if currentRole == .student {
                return "支払いが完了した予約があるコーチとだけメッセージできます。"
            }

            return "支払いが完了した予約がある生徒とだけメッセージできます。"

        case "checking":
            return "チャットの利用状態を確認しています。"

        default:
            return "現在このチャットではメッセージを送信できません。"
        }
    }

    private var canSendMessage: Bool {
        isMessagingAllowed
        && !isCheckingMessagingStatus
        && !message
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty
    }

    private func dateSeparator(
        for date: Date
    ) -> some View {
        HStack {
            Spacer()

            Text(
                messageDate(date)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(
                .horizontal,
                11
            )
            .padding(
                .vertical,
                5
            )
            .background(
                Color(.systemGray5)
            )
            .clipShape(Capsule())

            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func shouldShowDateSeparator(
        at index: Int
    ) -> Bool {
        guard
            messages.indices.contains(index)
        else {
            return false
        }

        if index == 0 {
            return true
        }

        let currentDate =
            messages[index].createdAt
        let previousDate =
            messages[index - 1].createdAt

        return !Calendar.current
            .isDate(
                currentDate,
                inSameDayAs: previousDate
            )
    }

    private func scrollToLatestMessage(
        using proxy: ScrollViewProxy
    ) {
        guard
            let lastMessage =
                messages.last
        else {
            return
        }

        DispatchQueue.main.async {
            withAnimation(
                .easeOut(
                    duration: 0.2
                )
            ) {
                proxy.scrollTo(
                    lastMessage.id,
                    anchor: .bottom
                )
            }
        }
    }

    private func saveMessage() {
        let trimmedMessage =
            message.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !trimmedMessage.isEmpty else {
            return
        }

        guard isMessagingAllowed else {
            errorMessage =
                messagingRestrictionText
            return
        }

        verifyMessagingStatusBeforeSending {
            sendMessageToFirestore(
                trimmedMessage
            )
        }
    }

    private func sendMessageToFirestore(
        _ trimmedMessage: String
    ) {
        guard
            let uid =
                Auth.auth().currentUser?.uid
        else {
            errorMessage =
                "メッセージの送信にはログインが必要です"
            return
        }

        let isAuthorizedSender: Bool

        switch currentRole {
        case .student:
            isAuthorizedSender =
                uid == studentId

        case .coach:
            isAuthorizedSender =
                uid == coachId
        }

        guard isAuthorizedSender else {
            errorMessage =
                "このチャットからメッセージを送信できません"
            return
        }

        guard
            !studentId.isEmpty,
            !coachId.isEmpty
        else {
            errorMessage =
                "チャット相手を確認できませんでした"
            return
        }

        let savedStudentName =
            studentDisplayName
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        let data: [String: Any] = [
            "conversationId":
                conversationId,
            "coachId":
                coachId,
            "coachName":
                coachName,
            "studentId":
                studentId,
            "studentDisplayName":
                savedStudentName.isEmpty
                    ? "生徒"
                    : savedStudentName,
            "text":
                trimmedMessage,
            "sender":
                currentSender,
            "senderId":
                uid,
            "createdAt":
                Timestamp(date: Date()),
            "isRead":
                false
        ]

        db.collection("messages")
            .addDocument(
                data: data
            ) { error in
                DispatchQueue.main.async {
                    if let error {
                        if (
                            error as NSError
                        ).code == 7 {
                            isMessagingAllowed =
                                false
                            errorMessage =
                                messagingRestrictionText
                        } else {
                            errorMessage =
                                "送信できませんでした: "
                                + error.localizedDescription
                        }
                        return
                    }

                    message = ""
                    errorMessage = ""

                    NotificationCenter.default.post(
                        name:
                            Notification.Name(
                                "ReloadChatList"
                            ),
                        object: nil
                    )
                }
            }
    }

    private func refreshMessagingStatus() {
        checkMessagingStatus { _ in }
    }

    private func verifyMessagingStatusBeforeSending(
        onAllowed: @escaping () -> Void
    ) {
        checkMessagingStatus { allowed in
            if allowed {
                onAllowed()
            } else {
                errorMessage =
                    messagingRestrictionText
            }
        }
    }

    private func checkMessagingStatus(
        completion:
            @escaping (Bool) -> Void
    ) {
        guard
            !studentId.isEmpty,
            !coachId.isEmpty
        else {
            isMessagingAllowed = false
            messagingRestrictionReason = "unknown"
            completion(false)
            return
        }

        isCheckingMessagingStatus = true

        functions
            .httpsCallable(
                "getChatMessagingStatus"
            )
            .call(
                [
                    "studentId": studentId,
                    "coachId": coachId
                ]
            ) { result, error in
                DispatchQueue.main.async {
                    isCheckingMessagingStatus =
                        false

                    if let error {
                        // 状態確認に失敗した場合は安全側に倒し、
                        // 送信を許可しない。
                        isMessagingAllowed =
                            false
                        messagingRestrictionReason =
                            "unknown"
                        errorMessage =
                            "チャットの利用状態を確認できませんでした: "
                            + error.localizedDescription
                        completion(false)
                        return
                    }

                    guard
                        let data =
                            result?.data
                            as? [String: Any]
                    else {
                        isMessagingAllowed =
                            false
                        completion(false)
                        return
                    }

                    let allowed =
                        data["canSend"]
                        as? Bool
                        ?? false

                    messagingRestrictionReason =
                        data["restrictionReason"]
                        as? String
                        ?? (
                            allowed
                                ? ""
                                : "unknown"
                        )

                    isMessagingAllowed =
                        allowed

                    if allowed {
                        errorMessage = ""
                    }

                    completion(allowed)
                }
            }
    }

    private func startMessageListener() {
        listener?.remove()
        listener = nil

        guard
            !studentId.isEmpty,
            !coachId.isEmpty
        else {
            messages = []
            errorMessage =
                "チャット相手を確認できませんでした"
            return
        }

        listener = db
            .collection("messages")
            .whereField(
                "studentId",
                isEqualTo: studentId
            )
            .whereField(
                "coachId",
                isEqualTo: coachId
            )
            .addSnapshotListener {
                snapshot,
                error in

                DispatchQueue.main.async {
                    if let error {
                        errorMessage =
                            "メッセージを取得できませんでした: "
                            + error.localizedDescription
                        return
                    }

                    let documents =
                        snapshot?.documents ?? []

                    let loadedMessages =
                        documents
                            .compactMap {
                                document
                                -> Message? in

                                let data =
                                    document.data()

                                guard
                                    let text =
                                        data[
                                            "text"
                                        ]
                                        as? String,
                                    let sender =
                                        data[
                                            "sender"
                                        ]
                                        as? String,
                                    let timestamp =
                                        data[
                                            "createdAt"
                                        ]
                                        as? Timestamp
                                else {
                                    return nil
                                }

                                return Message(
                                    id:
                                        document
                                            .documentID,
                                    text:
                                        text,
                                    sender:
                                        sender,
                                    createdAt:
                                        timestamp
                                            .dateValue(),
                                    isRead:
                                        data[
                                            "isRead"
                                        ]
                                        as? Bool
                                        ?? false
                                )
                            }
                            .sorted {
                                $0.createdAt
                                    < $1.createdAt
                            }

                    messages =
                        loadedMessages
                    errorMessage = ""

                    markIncomingMessagesAsRead(
                        documents
                    )
                }
            }
    }

    private func markIncomingMessagesAsRead(
        _ documents:
            [QueryDocumentSnapshot]
    ) {
        guard
            let uid =
                Auth.auth().currentUser?.uid
        else {
            return
        }

        let canMarkAsRead: Bool

        switch currentRole {
        case .student:
            canMarkAsRead =
                uid == studentId

        case .coach:
            canMarkAsRead =
                uid == coachId
        }

        guard canMarkAsRead else {
            return
        }

        let unreadDocuments =
            documents.filter {
                document in

                let data =
                    document.data()

                let sender =
                    data["sender"]
                    as? String ?? ""
                let isRead =
                    data["isRead"]
                    as? Bool ?? false

                return
                    sender
                        == incomingSender
                    && !isRead
            }

        guard
            !unreadDocuments.isEmpty
        else {
            return
        }

        let batch = db.batch()

        for document
            in unreadDocuments {
            batch.updateData(
                ["isRead": true],
                forDocument:
                    document.reference
            )
        }

        batch.commit { error in
            if let error {
                DispatchQueue.main.async {
                    errorMessage =
                        "既読状態を更新できませんでした: "
                        + error.localizedDescription
                }
            }
        }
    }

    private func loadParticipantProfiles() {
        switch currentRole {
        case .student:
            loadCurrentStudentDisplayNameIfNeeded()
            loadCoachImageIfNeeded()

        case .coach:
            loadStudentProfileForCoach()
        }
    }

    private func loadCurrentStudentDisplayNameIfNeeded() {
        let currentName =
            studentDisplayName
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        if !currentName.isEmpty {
            return
        }

        let initialName =
            initialStudentName
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        if !initialName.isEmpty {
            studentDisplayName =
                initialName
            return
        }

        guard
            !studentId.isEmpty
        else {
            return
        }

        db.collection("students")
            .document(studentId)
            .getDocument {
                snapshot,
                _ in

                let savedName =
                    (
                        snapshot?
                            .data()?[
                                "displayName"
                            ]
                        as? String
                    )?
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    ?? ""

                DispatchQueue.main.async {
                    if !savedName.isEmpty {
                        studentDisplayName =
                            savedName
                    }
                }
            }
    }

    private func loadCoachImageIfNeeded() {
        if !partnerImageURL.isEmpty {
            return
        }

        guard
            !coachId.isEmpty
        else {
            return
        }

        db.collection("coaches")
            .document(coachId)
            .getDocument {
                snapshot,
                _ in

                let imageURL =
                    snapshot?
                        .data()?[
                            "imageURL"
                        ]
                    as? String
                    ?? ""

                DispatchQueue.main.async {
                    partnerImageURL =
                        imageURL
                }
            }
    }

    private func loadStudentProfileForCoach() {
        guard
            !studentId.isEmpty
        else {
            return
        }

        functions
            .httpsCallable(
                "getCoachChatStudentProfiles"
            )
            .call([:]) {
                result,
                error in

                DispatchQueue.main.async {
                    if let error {
                        print(
                            "チャット相手プロフィール取得失敗:",
                            error.localizedDescription
                        )
                        return
                    }

                    guard
                        let data =
                            result?.data
                            as? [String: Any],
                        let profiles =
                            data[
                                "profiles"
                            ]
                            as? [String: Any],
                        let profile =
                            profiles[
                                studentId
                            ]
                            as? [String: Any]
                    else {
                        return
                    }

                    let displayName =
                        (
                            profile[
                                "displayName"
                            ]
                            as? String
                            ?? ""
                        )
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )

                    let imageURL =
                        profile[
                            "imageURL"
                        ]
                        as? String
                        ?? ""

                    if !displayName.isEmpty {
                        studentDisplayName =
                            displayName
                    }

                    partnerImageURL =
                        imageURL
                }
            }
    }

    private func messageTime(
        _ date: Date
    ) -> String {
        let formatter =
            DateFormatter()
        formatter.locale =
            Locale(
                identifier: "ja_JP"
            )
        formatter.dateFormat =
            "HH:mm"

        return formatter.string(
            from: date
        )
    }

    private func messageDate(
        _ date: Date
    ) -> String {
        let formatter =
            DateFormatter()
        formatter.locale =
            Locale(
                identifier: "ja_JP"
            )
        formatter.dateFormat =
            "M/d (E)"

        return formatter.string(
            from: date
        )
    }
}

private struct ChatPartnerAvatarView: View {

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
            Color(.systemGray5)
        )
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(
                    Color(.separator)
                        .opacity(0.25),
                    lineWidth: 0.5
                )
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(
            systemName: "person.fill"
        )
        .resizable()
        .scaledToFit()
        .padding(size * 0.22)
        .foregroundStyle(.secondary)
    }
}

private struct ChatBubbleBackground: View {

    let isOutgoing: Bool
    let color: Color
    let borderColor: Color

    var body: some View {
        ZStack(
            alignment:
                isOutgoing
                    ? .bottomTrailing
                    : .bottomLeading
        ) {
            RoundedRectangle(
                cornerRadius: 17,
                style: .continuous
            )
            .fill(color)
            .overlay {
                RoundedRectangle(
                    cornerRadius: 17,
                    style: .continuous
                )
                .stroke(
                    borderColor,
                    lineWidth: 0.8
                )
            }

            Circle()
                .fill(color)
                .frame(
                    width: 14,
                    height: 14
                )
                .overlay {
                    Circle()
                        .stroke(
                            borderColor,
                            lineWidth: 0.8
                        )
                }
                .offset(
                    x:
                        isOutgoing
                            ? 4
                            : -4,
                    y: 2
                )
        }
    }
}

#Preview {
    ChatView(
        coach: sampleCoaches[0]
    )
}
