import SwiftUI
import FirebaseFirestore

struct ChatListView: View {

    let db = Firestore.firestore()

    @State private var lastMessages: [String: String] = [:]

    func loadLastMessages() {

        for coach in sampleCoaches {

            print("検索中:", coach.name)
            
            db.collection("messages")
                .whereField("coachName", isEqualTo: coach.name)
                .order(by: "createdAt", descending: true)
                .limit(to: 1)
                .getDocuments { snapshot, error in
                    
                    print(snapshot?.documents.count ?? 0)

                    guard let document = snapshot?.documents.first,
                          let text = document.data()["text"] as? String else {
                        return
                    }
                    
                    print("取得成功")
                    print(coach.name)
                    print(text)

                    DispatchQueue.main.async {
                        lastMessages[coach.name] = text
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

                        Circle()
                            .fill(Color.green)
                            .frame(width: 55, height: 55)

                        VStack(alignment: .leading, spacing: 4) {

                            Text(coach.name)
                                .font(.headline)

                            Text(lastMessages[coach.name] ?? "メッセージはありません")
                                .foregroundStyle(.gray)
                                .font(.subheadline)
                        }

                        Spacer()

                        Text("14:10")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("チャット")
            .onAppear {
                print("ChatListView表示")
                loadLastMessages()
            }
            }
        }
    }


#Preview {
    ChatListView()
}
