import SwiftUI
import FirebaseFirestore

struct Message: Identifiable {

    let id: String
    let text: String
    let sender: String
    let createdAt: Date

    var isRead: Bool

    var isMe: Bool {
        sender == "user"
    }
}

struct ChatView: View {

    let coach: Coach
    let db = Firestore.firestore()

    @State private var message = ""

    @State private var messages: [Message] = []

    func saveMessage() {

        db.collection("messages").addDocument(data: [
            "coachId": coach.id,
            "coachName": coach.name,
            "text": message,
            "sender": "user",
            "createdAt": Timestamp(),
            "isRead": true
        ]) { error in

            if let error = error {

                print("保存失敗: \(error.localizedDescription)")

            } else {

                print("保存成功")

            }

        }

    }
    func loadMessages() {
        
        print("loadMessages: \(coach.name)")

        db.collection("messages")
            .whereField("coachName", isEqualTo: coach.name)
            .order(by: "createdAt")
            .addSnapshotListener { snapshot, error in

                guard let documents = snapshot?.documents else {
                    return
                }

                messages = documents.compactMap { document in

                    let data = document.data()

                    guard
                        let text = data["text"] as? String,
                        let sender = data["sender"] as? String,
                        let timestamp = data["createdAt"] as? Timestamp
                    else {
                        return nil
                    }

                    let isRead = data["isRead"] as? Bool ?? false
                    
                    print("sender =", sender)

                    return Message(
                        id: document.documentID,
                        text: text,
                        sender: sender,
                        createdAt: timestamp.dateValue(),
                        isRead: isRead
                    )
                }
                print("件数: \(messages.count)")
                for msg in messages {
                    print(msg.text)
                }
            }
    }
    
    func markAsRead() {

        db.collection("messages")
            .whereField("coachName", isEqualTo: coach.name)
            .whereField("sender", isEqualTo: "coach")
            .whereField("isRead", isEqualTo: false)
            .getDocuments { snapshot, error in

                guard let documents = snapshot?.documents else { return }
                print("更新対象:", documents.count)
                
                for document in documents {
                    print(document.documentID)

                    document.reference.updateData([
                        "isRead": true
                    ])
                }
            }
    }
    
    var body: some View {

        VStack {

            ScrollViewReader { proxy in
                
                ScrollView {
                    
                    LazyVStack(alignment: .leading, spacing: 12) {
                        
                        ForEach(messages) { msg in
                            
                            HStack {
                                
                                if msg.isMe {
                                    
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
                .onChange(of: messages.count) {_ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            Divider()

            HStack {

                TextField("メッセージ", text: $message)
                    .textFieldStyle(.roundedBorder)

                Button("送信") {

                    guard !message.isEmpty else { return }

                
                    saveMessage()
                    
                    message = ""
                }

            }
            .padding()
        }
        .navigationTitle(coach.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadMessages()

            db.collection("messages")
                .whereField("coachName", isEqualTo: coach.name)
                .whereField("sender", isEqualTo: "coach")
                .getDocuments { snapshot, error in

                    snapshot?.documents.forEach { document in
                        document.reference.updateData([
                            "isRead": true
                        ])
                    }

                }
        
            markAsRead()
        }
    }
}

#Preview {
    ChatView(coach: sampleCoaches[0])
}
