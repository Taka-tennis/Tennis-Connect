import SwiftUI
import FirebaseAuth
import FirebaseFirestore

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

    @State private var message = ""
    @State private var messages: [Message] = []
    @State private var studentDisplayName: String
    @State private var errorMessage = ""
    @State private var listener: ListenerRegistration?

    init(coach: Coach) {
        let currentStudentId = Auth.auth().currentUser?.uid ?? ""

        self.coachId = coach.id
        self.coachName = coach.name
        self.studentId = currentStudentId
        self.currentRole = .student
        self.initialStudentName = ""
        _studentDisplayName = State(initialValue: "")
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
        _studentDisplayName = State(initialValue: studentName)
    }

    private var currentSender: String {
        currentRole == .student ? "user" : "coach"
    }

    private var incomingSender: String {
        currentRole == .student ? "coach" : "user"
    }

    private var navigationTitle: String {
        switch currentRole {
        case .student:
            return coachName
        case .coach:
            let trimmed =
                studentDisplayName
                    .trimmingCharacters(in: .whitespacesAndNewlines)

            return trimmed.isEmpty ? "生徒" : trimmed
        }
    }

    private var conversationId: String {
        "\(studentId)__\(coachId)"
    }

    var body: some View {
        VStack(spacing: 0) {

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { msg in
                            HStack {
                                if msg.sender == currentSender {
                                    Spacer()

                                    Text(msg.text)
                                        .padding()
                                        .background(Color.green)
                                        .foregroundStyle(.white)
                                        .cornerRadius(12)
                                } else {
                                    Text(msg.text)
                                        .padding()
                                        .background(Color(.systemGray5))
                                        .cornerRadius(12)

                                    Spacer()
                                }
                            }
                            .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(
                                lastMessage.id,
                                anchor: .bottom
                            )
                        }
                    }
                }
            }

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }

            Divider()

            HStack {
                TextField("メッセージ", text: $message)
                    .textFieldStyle(.roundedBorder)

                Button("送信") {
                    saveMessage()
                }
                .disabled(
                    message
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        .isEmpty
                )
            }
            .padding()
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadStudentDisplayNameIfNeeded()
            startMessageListener()
        }
        .onDisappear {
            listener?.remove()
            listener = nil
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

        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "メッセージの送信にはログインが必要です"
            return
        }

        let isAuthorizedSender: Bool

        switch currentRole {
        case .student:
            isAuthorizedSender = uid == studentId
        case .coach:
            isAuthorizedSender = uid == coachId
        }

        guard isAuthorizedSender else {
            errorMessage = "このチャットからメッセージを送信できません"
            return
        }

        guard !studentId.isEmpty, !coachId.isEmpty else {
            errorMessage = "チャット相手を確認できませんでした"
            return
        }

        let savedStudentName =
            studentDisplayName
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        let data: [String: Any] = [
            "conversationId": conversationId,
            "coachId": coachId,
            "coachName": coachName,
            "studentId": studentId,
            "studentDisplayName":
                savedStudentName.isEmpty
                    ? "生徒"
                    : savedStudentName,
            "text": trimmedMessage,
            "sender": currentSender,
            "senderId": uid,
            "createdAt": Timestamp(date: Date()),
            "isRead": false
        ]

        db.collection("messages")
            .addDocument(data: data) { error in
                DispatchQueue.main.async {
                    if let error {
                        errorMessage =
                            "送信できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    message = ""
                    errorMessage = ""

                    NotificationCenter.default.post(
                        name: Notification.Name(
                            "ReloadChatList"
                        ),
                        object: nil
                    )
                }
            }
    }

    private func startMessageListener() {
        listener?.remove()
        listener = nil

        guard !studentId.isEmpty, !coachId.isEmpty else {
            messages = []
            errorMessage = "チャット相手を確認できませんでした"
            return
        }

        listener = db.collection("messages")
            .whereField(
                "studentId",
                isEqualTo: studentId
            )
            .whereField(
                "coachId",
                isEqualTo: coachId
            )
            .addSnapshotListener { snapshot, error in
                DispatchQueue.main.async {
                    if let error {
                        errorMessage =
                            "メッセージを取得できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    let documents =
                        snapshot?.documents ?? []

                    let loadedMessages =
                        documents.compactMap {
                            document -> Message? in

                            let data = document.data()

                            guard
                                let text =
                                    data["text"] as? String,
                                let sender =
                                    data["sender"] as? String,
                                let timestamp =
                                    data["createdAt"]
                                        as? Timestamp
                            else {
                                return nil
                            }

                            return Message(
                                id: document.documentID,
                                text: text,
                                sender: sender,
                                createdAt:
                                    timestamp.dateValue(),
                                isRead:
                                    data["isRead"]
                                        as? Bool ?? false
                            )
                        }
                        .sorted {
                            $0.createdAt < $1.createdAt
                        }

                    messages = loadedMessages
                    errorMessage = ""

                    markIncomingMessagesAsRead(
                        documents
                    )
                }
            }
    }

    private func markIncomingMessagesAsRead(
        _ documents: [QueryDocumentSnapshot]
    ) {
        guard let uid = Auth.auth().currentUser?.uid else {
            return
        }

        let canMarkAsRead: Bool

        switch currentRole {
        case .student:
            canMarkAsRead = uid == studentId
        case .coach:
            canMarkAsRead = uid == coachId
        }

        guard canMarkAsRead else {
            return
        }

        let unreadDocuments =
            documents.filter { document in
                let data = document.data()

                let sender =
                    data["sender"] as? String ?? ""
                let isRead =
                    data["isRead"] as? Bool ?? false

                return sender == incomingSender &&
                    !isRead
            }

        guard !unreadDocuments.isEmpty else {
            return
        }

        let batch = db.batch()

        for document in unreadDocuments {
            batch.updateData(
                ["isRead": true],
                forDocument: document.reference
            )
        }

        batch.commit { error in
            if let error {
                DispatchQueue.main.async {
                    errorMessage =
                        "既読状態を更新できませんでした: " +
                        error.localizedDescription
                }
            }
        }
    }

    private func loadStudentDisplayNameIfNeeded() {
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
            studentDisplayName = initialName
            return
        }

        guard !studentId.isEmpty else {
            return
        }

        db.collection("students")
            .document(studentId)
            .getDocument { snapshot, _ in
                let savedName =
                    (snapshot?.data()?["displayName"]
                        as? String)?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ) ?? ""

                DispatchQueue.main.async {
                    if !savedName.isEmpty {
                        studentDisplayName = savedName
                    }
                }
            }
    }
}

#Preview {
    ChatView(coach: sampleCoaches[0])
}
