import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

struct ChatListView: View {

    let role: ChatParticipantRole

    private struct StudentConversation: Identifiable {
        let id: String
        let coachName: String
        let coachImageURL: String
        let lastMessage: String
        let lastTime: Date
        let unreadCount: Int
    }

    private struct CoachConversation: Identifiable {
        let id: String
        let coachName: String
        let studentName: String
        let studentImageURL: String
        let lastMessage: String
        let lastTime: Date
        let unreadCount: Int
    }

    private let db = Firestore.firestore()

    @State private var studentConversations: [StudentConversation] = []
    @State private var coachConversations: [CoachConversation] = []
    @State private var messageListener: ListenerRegistration?
    @State private var errorMessage = ""
    @State private var isLoggedIn = false
    @State private var showLogin = false

    init(role: ChatParticipantRole = .student) {
        self.role = role
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoggedIn {
                    switch role {
                    case .student:
                        studentChatList

                    case .coach:
                        coachChatList
                    }
                } else {
                    loggedOutView
                }
            }
            .navigationTitle("チャット")
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
                    startMessageListener()
                } else {
                    resetChatState()
                    errorMessage = ""
                }
            }
            .onDisappear {
                messageListener?.remove()
                messageListener = nil
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: Notification.Name("ReloadChatList")
                )
            ) { _ in
                guard Auth.auth().currentUser != nil else {
                    isLoggedIn = false
                    resetChatState()
                    errorMessage = ""
                    return
                }

                isLoggedIn = true
                startMessageListener()
            }
            .sheet(isPresented: $showLogin) {
                LoginView {
                    isLoggedIn = true
                    startMessageListener()
                }
            }
        }
    }

    private var loggedOutView: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "message.badge")
                .font(.system(size: 58))
                .foregroundStyle(.secondary)

            Text("チャットを利用するにはログインが必要です")
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(
                role == .student
                    ? "ログインすると、コーチとのメッセージを確認できます。"
                    : "ログインすると、生徒とのメッセージを確認できます。"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Button {
                showLogin = true
            } label: {
                Label(
                    "ログイン・新規会員登録",
                    systemImage: "person.crop.circle.badge.plus"
                )
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

    private var studentChatList: some View {
        Group {
            if studentConversations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "message")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)

                    Text("チャットはまだありません")
                        .font(.headline)

                    Text(
                        "コーチとのメッセージが始まると、ここに表示されます"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                List(studentConversations) { conversation in
                    NavigationLink {
                        ChatView(
                            coachId: conversation.id,
                            coachName: conversation.coachName,
                            studentId:
                                Auth.auth().currentUser?.uid ?? "",
                            studentName: "",
                            currentRole: .student
                        )
                    } label: {
                        HStack(spacing: 12) {
                            ChatParticipantAvatarView(
                                imageURL:
                                    conversation.coachImageURL,
                                size: 55
                            )

                            VStack(
                                alignment: .leading,
                                spacing: 4
                            ) {
                                Text(conversation.coachName)
                                    .font(.headline)

                                Text(conversation.lastMessage)
                                    .foregroundStyle(.gray)
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }

                            Spacer()

                            VStack(
                                alignment: .trailing,
                                spacing: 6
                            ) {
                                Text(
                                    conversation.lastTime
                                        .formatted(
                                            date: .omitted,
                                            time: .shortened
                                        )
                                )
                                .font(.caption)
                                .foregroundStyle(.gray)

                                unreadBadge(
                                    count: conversation.unreadCount
                                )
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private var coachChatList: some View {
        Group {
            if coachConversations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "message")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)

                    Text("チャットはまだありません")
                        .font(.headline)

                    Text(
                        "生徒からメッセージが届くと、ここに表示されます"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                List(coachConversations) { conversation in
                    NavigationLink {
                        ChatView(
                            coachId:
                                Auth.auth().currentUser?.uid ?? "",
                            coachName: conversation.coachName,
                            studentId: conversation.id,
                            studentName: conversation.studentName,
                            currentRole: .coach
                        )
                    } label: {
                        HStack(spacing: 12) {
                            ChatParticipantAvatarView(
                                imageURL:
                                    conversation.studentImageURL,
                                size: 55
                            )

                            VStack(
                                alignment: .leading,
                                spacing: 4
                            ) {
                                Text(conversation.studentName)
                                    .font(.headline)

                                Text(conversation.lastMessage)
                                    .foregroundStyle(.gray)
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }

                            Spacer()

                            VStack(
                                alignment: .trailing,
                                spacing: 6
                            ) {
                                Text(
                                    conversation.lastTime
                                        .formatted(
                                            date: .omitted,
                                            time: .shortened
                                        )
                                )
                                .font(.caption)
                                .foregroundStyle(.gray)

                                unreadBadge(
                                    count:
                                        conversation.unreadCount
                                )
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func unreadBadge(
        count: Int
    ) -> some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(Color.red)
                .clipShape(Capsule())
        }
    }

    private func startMessageListener() {
        messageListener?.remove()
        messageListener = nil

        guard let uid = Auth.auth().currentUser?.uid else {
            isLoggedIn = false
            resetChatState()
            errorMessage = ""
            return
        }

        let participantField: String

        switch role {
        case .student:
            participantField = "studentId"

        case .coach:
            participantField = "coachId"
        }

        messageListener = db.collection("messages")
            .whereField(
                participantField,
                isEqualTo: uid
            )
            .addSnapshotListener { snapshot, error in
                DispatchQueue.main.async {
                    if let error {
                        errorMessage =
                            "チャットを取得できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    let documents =
                        snapshot?.documents ?? []

                    switch role {
                    case .student:
                        updateStudentChatList(
                            documents: documents
                        )

                    case .coach:
                        updateCoachChatList(
                            documents: documents
                        )
                    }

                    errorMessage = ""
                }
            }
    }

    private func updateStudentChatList(
        documents: [QueryDocumentSnapshot]
    ) {
        let validDocuments =
            documents.filter {
                let coachId =
                    $0.data()["coachId"] as? String ?? ""

                return !coachId.isEmpty
            }

        let grouped =
            Dictionary(
                grouping: validDocuments
            ) { document in
                document.data()["coachId"] as? String ?? ""
            }

        let conversations =
            grouped.compactMap {
                coachId,
                coachDocuments
                    -> StudentConversation? in

                let sortedDocuments =
                    coachDocuments.sorted {
                        messageDate($0) < messageDate($1)
                    }

                guard let latest =
                        sortedDocuments.last else {
                    return nil
                }

                let latestData = latest.data()

                let coachName =
                    (
                        latestData["coachName"] as? String
                    )?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ) ?? ""

                let unreadCount =
                    coachDocuments.filter {
                        let data = $0.data()

                        let sender =
                            data["sender"] as? String ?? ""
                        let isRead =
                            data["isRead"] as? Bool ?? false

                        return sender == "coach" &&
                            !isRead
                    }
                    .count

                return StudentConversation(
                    id: coachId,
                    coachName:
                        coachName.isEmpty
                            ? "コーチ"
                            : coachName,
                    coachImageURL: "",
                    lastMessage:
                        latestData["text"] as? String
                        ?? "",
                    lastTime:
                        messageDate(latest),
                    unreadCount: unreadCount
                )
            }
            .sorted {
                $0.lastTime > $1.lastTime
            }

        studentConversations = conversations
        coachConversations = []

        loadCoachImagesForStudentChat(
            coachIds: conversations.map(\.id)
        )
    }

    private func updateCoachChatList(
        documents: [QueryDocumentSnapshot]
    ) {
        let validDocuments =
            documents.filter {
                let studentId =
                    $0.data()["studentId"] as? String ?? ""

                return !studentId.isEmpty
            }

        let grouped =
            Dictionary(
                grouping: validDocuments
            ) { document in
                document.data()["studentId"] as? String ?? ""
            }

        let conversations =
            grouped.compactMap {
                studentId,
                studentDocuments
                    -> CoachConversation? in

                let sortedDocuments =
                    studentDocuments.sorted {
                        messageDate($0) < messageDate($1)
                    }

                guard let latest =
                        sortedDocuments.last else {
                    return nil
                }

                let latestData = latest.data()

                let savedStudentName =
                    (
                        latestData[
                            "studentDisplayName"
                        ] as? String
                    )?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ) ?? ""

                let unreadCount =
                    studentDocuments.filter {
                        let data = $0.data()

                        let sender =
                            data["sender"] as? String
                            ?? ""
                        let isRead =
                            data["isRead"] as? Bool
                            ?? false

                        return sender == "user" &&
                            !isRead
                    }
                    .count

                return CoachConversation(
                    id: studentId,
                    coachName:
                        latestData["coachName"]
                            as? String
                        ?? "コーチ",
                    studentName:
                        savedStudentName.isEmpty
                            ? "生徒"
                            : savedStudentName,
                    studentImageURL: "",
                    lastMessage:
                        latestData["text"] as? String
                        ?? "",
                    lastTime:
                        messageDate(latest),
                    unreadCount: unreadCount
                )
            }
            .sorted {
                $0.lastTime > $1.lastTime
            }

        coachConversations = conversations
        studentConversations = []

        loadStudentProfilesForCoachChat()
    }

    private func loadCoachImagesForStudentChat(
        coachIds: [String]
    ) {
        let uniqueCoachIds = Set(
            coachIds.filter { !$0.isEmpty }
        )

        guard !uniqueCoachIds.isEmpty else {
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var imageURLs: [String: String] = [:]

        for coachId in uniqueCoachIds {
            group.enter()

            db.collection("coaches")
                .document(coachId)
                .getDocument { snapshot, _ in
                    let imageURL =
                        snapshot?.data()?["imageURL"]
                        as? String ?? ""

                    lock.lock()
                    imageURLs[coachId] = imageURL
                    lock.unlock()

                    group.leave()
                }
        }

        group.notify(queue: .main) {
            studentConversations =
                studentConversations.map {
                    conversation in

                    StudentConversation(
                        id: conversation.id,
                        coachName:
                            conversation.coachName,
                        coachImageURL:
                            imageURLs[
                                conversation.id
                            ] ?? "",
                        lastMessage:
                            conversation.lastMessage,
                        lastTime:
                            conversation.lastTime,
                        unreadCount:
                            conversation.unreadCount
                    )
                }
        }
    }

    private func loadStudentProfilesForCoachChat() {
        let functions = Functions.functions(
            region: "asia-northeast1"
        )

        functions
            .httpsCallable(
                "getCoachChatStudentProfiles"
            )
            .call([:]) { result, error in
                DispatchQueue.main.async {
                    if let error {
                        print(
                            "チャット相手のプロフィールを取得できませんでした:",
                            error.localizedDescription
                        )
                        return
                    }

                    guard
                        let data =
                            result?.data
                            as? [String: Any],
                        let rawProfiles =
                            data["profiles"]
                            as? [String: Any]
                    else {
                        return
                    }

                    coachConversations =
                        coachConversations.map {
                            conversation in

                            let rawProfile =
                                rawProfiles[
                                    conversation.id
                                ]
                                as? [String: Any]

                            let displayName =
                                (
                                    rawProfile?[
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
                                rawProfile?[
                                    "imageURL"
                                ]
                                as? String
                                ?? ""

                            return CoachConversation(
                                id: conversation.id,
                                coachName:
                                    conversation.coachName,
                                studentName:
                                    displayName.isEmpty
                                        ? conversation.studentName
                                        : displayName,
                                studentImageURL:
                                    imageURL,
                                lastMessage:
                                    conversation.lastMessage,
                                lastTime:
                                    conversation.lastTime,
                                unreadCount:
                                    conversation.unreadCount
                            )
                        }
                }
            }
    }

    private func messageDate(
        _ document: QueryDocumentSnapshot
    ) -> Date {
        (
            document.data()["createdAt"]
                as? Timestamp
        )?
        .dateValue()
        ?? .distantPast
    }

    private func resetChatState() {
        studentConversations = []
        coachConversations = []
    }
}

private struct ChatParticipantAvatarView: View {

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
            Color(.systemGray5)
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
            .foregroundStyle(.secondary)
    }
}

#Preview {
    ChatListView()
}
