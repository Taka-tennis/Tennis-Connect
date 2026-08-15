import SwiftUI
import FirebaseFirestore

struct ChatListView: View {

    let db = Firestore.firestore()

    @State private var lastMessages: [String: String] = [:]
    @State private var lastTimes: [String: Date] = [:]
    @State private var unreadCounts: [String: Int] = [:]

    func loadLastMessages() {

        for coach in sampleCoaches {

            print("検索中:", coach.name)
            
            db.collection("messages")
                .whereField("coachName", isEqualTo: coach.name)
                .order(by: "createdAt", descending: true)
                .limit(to: 1)
                .addSnapshotListener { snapshot, error in
                    
                    print(snapshot?.documents.count ?? 0)

                    guard
                        let document = snapshot?.documents.first,
                        let text = document.data()["text"] as? String,
                        let timestamp = document.data()["createdAt"] as? Timestamp
                    else {
                        DispatchQueue.main.async {
                            lastMessages[coach.name] = "メッセージはありません"
                            unreadCounts[coach.name] = 0
                        }
                        return
                    }

                    let sender = document.data()["sender"] as? String ?? ""

                    let isRead: Bool

                    if sender == "user" {
                        isRead = true
                    } else {
                        isRead = document.data()["isRead"] as? Bool ?? false
                    }
                    let isMe = document.data()["isMe"] as? Bool ?? false
                    
                    print("取得成功")
                    print(coach.name)
                    print(text)
                    print("isRead:", isRead)
                    
                    DispatchQueue.main.async {
                        lastMessages[coach.name] = text
                        lastTimes[coach.name] = timestamp.dateValue()
                        if isMe {
                            unreadCounts[coach.name] = 0
                        } else {
                            unreadCounts[coach.name] = isRead ? 0 : 1
                        }
                        print("====")
                        print(coach.name)
                        print(isRead)
                        print(unreadCounts[coach.name] ?? -1)
                    }
                }
        }
    }
    
    var body: some View {

        NavigationStack {

            List(sampleCoaches) { coach in

                NavigationLink {

                    ChatView(coach: coach)

                } label: {

                    HStack(spacing: 12) {

                        if coach.imageURL.isEmpty {

                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 55, height: 55)
                                .foregroundStyle(.gray)

                        } else {

                            AsyncImage(url: URL(string: coach.imageURL)) { phase in
                                switch phase {

                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()

                                case .failure:
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .scaledToFill()
                                        .foregroundStyle(.gray)

                                case .empty:
                                    ProgressView()

                                @unknown default:
                                    EmptyView()
                                }
                            }
                            .frame(width: 55, height: 55)
                            .clipShape(Circle())
                        }

                        VStack(alignment: .leading, spacing: 4) {

                            Text(coach.name)
                                .font(.headline)

                            Text(lastMessages[coach.name] ?? "メッセージはありません")
                                .foregroundStyle(.gray)
                                .font(.subheadline)
                        }

                        VStack(alignment: .trailing, spacing: 6) {

                            Text(
                                lastTimes[coach.name]?
                                    .formatted(date: .omitted, time: .shortened)
                                ?? "--:--"
                            )
                            .font(.caption)
                            .foregroundStyle(.gray)

                            if unreadCounts[coach.name] ?? 0 > 0 {

                                Circle()
                                    .fill(.red)
                                    .frame(width: 10, height: 10)

                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("チャット")
            .onAppear {
                print("ChatListView表示")
                loadLastMessages()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: Notification.Name("ReloadChatList"))
            ) { _ in
                loadLastMessages()
            }
            }
        }
    }


#Preview {
    ChatListView()
}
