// 修正版：通知ベル + チャットタブ未読バッジ対応

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

extension Notification.Name {
    static let returnToStudentHome = Notification.Name(
        "returnToStudentHome"
    )

    static let returnToStartScreen = Notification.Name(
        "returnToStartScreen"
    )
}

private struct ReturnHomeActionKey: EnvironmentKey {
    static let defaultValue: () -> Void = {
        NotificationCenter.default.post(
            name: .returnToStudentHome,
            object: nil
        )
    }
}

extension EnvironmentValues {
    var returnHomeAction: () -> Void {
        get { self[ReturnHomeActionKey.self] }
        set { self[ReturnHomeActionKey.self] = newValue }
    }
}

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var homeNavigationId = UUID()

    @State private var unreadNotificationCount = 0
    @State private var unreadChatCount = 0

    @State private var notificationListener:
        ListenerRegistration?
    @State private var chatUnreadListener:
        ListenerRegistration?

    private let db = Firestore.firestore()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(
                    unreadNotificationCount:
                        unreadNotificationCount
                )
            }
            .id(homeNavigationId)
            .tabItem {
                Label(
                    "ホーム",
                    systemImage: "house.fill"
                )
            }
            .tag(0)

            ReservationListView()
                .tabItem {
                    Label(
                        "予約",
                        systemImage: "calendar"
                    )
                }
                .tag(1)

            ChatListView()
                .tabItem {
                    Label(
                        "チャット",
                        systemImage: "message.fill"
                    )
                }
                // 0件なら表示されず、未読がある時だけ
                // システム標準の赤いバッジが表示されます。
                .badge(unreadChatCount)
                .tag(2)

            FavoriteView()
                .tabItem {
                    Label(
                        "お気に入り",
                        systemImage: "heart.fill"
                    )
                }
                .tag(3)

            MyPageView()
                .tabItem {
                    Label(
                        "マイページ",
                        systemImage: "person.fill"
                    )
                }
                .tag(4)
        }
        .environment(
            \.returnHomeAction,
            {
                returnToHome()
            }
        )
        .onReceive(
            NotificationCenter.default.publisher(
                for: .returnToStudentHome
            )
        ) { _ in
            returnToHome()
        }
        .onAppear {
            startNotificationListener()
            startChatUnreadListener()
        }
        .onDisappear {
            notificationListener?.remove()
            notificationListener = nil

            chatUnreadListener?.remove()
            chatUnreadListener = nil
        }
    }

    private func returnToHome() {
        selectedTab = 0
        homeNavigationId = UUID()
    }

    private func startNotificationListener() {
        notificationListener?.remove()

        guard
            let uid = Auth.auth().currentUser?.uid
        else {
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
                            "未読通知取得エラー:",
                            error.localizedDescription
                        )
                        return
                    }

                    let unreadCount =
                        NotificationRouting.unreadCount(
                            in:
                                snapshot?.documents
                                ?? [],
                            audience: .student
                        )

                    DispatchQueue.main.async {
                        unreadNotificationCount =
                            unreadCount
                    }
                }
    }

    private func startChatUnreadListener() {
        chatUnreadListener?.remove()

        guard
            let uid = Auth.auth().currentUser?.uid
        else {
            unreadChatCount = 0
            return
        }

        // studentIdだけで取得し、sender/isReadはクライアント側で
        // 絞り込むことで複合インデックスを追加せずに監視します。
        chatUnreadListener =
            db.collection("messages")
                .whereField(
                    "studentId",
                    isEqualTo: uid
                )
                .addSnapshotListener {
                    snapshot,
                    error in

                    if let error {
                        print(
                            "チャット未読件数取得エラー:",
                            error.localizedDescription
                        )
                        return
                    }

                    let unreadCount =
                        snapshot?
                            .documents
                            .filter {
                                document in

                                let data =
                                    document.data()

                                let sender =
                                    data["sender"]
                                        as? String
                                        ?? ""

                                let isUnread =
                                    data["isRead"]
                                        as? Bool
                                        != true

                                // 生徒側タブでは、
                                // コーチから届いた未読だけを数えます。
                                return
                                    sender == "coach" &&
                                    isUnread
                            }
                            .count
                        ?? 0

                    DispatchQueue.main.async {
                        unreadChatCount =
                            unreadCount
                    }
                }
    }
}

#Preview {
    MainTabView()
}
