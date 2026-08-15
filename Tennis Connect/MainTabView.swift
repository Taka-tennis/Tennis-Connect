// 修正版：通知タブを削除し、HomeViewの画面内ヘッダーへ未読件数を渡す

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
    @State private var notificationListener: ListenerRegistration?

    private let db = Firestore.firestore()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(
                    unreadNotificationCount: unreadNotificationCount
                )
            }
            .id(homeNavigationId)
            .tabItem {
                Label("ホーム", systemImage: "house.fill")
            }
            .tag(0)

            ReservationListView()
                .tabItem {
                    Label("予約", systemImage: "calendar")
                }
                .tag(1)

            ChatListView()
                .tabItem {
                    Label("チャット", systemImage: "message.fill")
                }
                .tag(2)

            FavoriteView()
                .tabItem {
                    Label("お気に入り", systemImage: "heart.fill")
                }
                .tag(3)

            MyPageView()
                .tabItem {
                    Label("マイページ", systemImage: "person.fill")
            }
            .tag(4)
        }
        .environment(\.returnHomeAction, {
            returnToHome()
        })
        .onReceive(
            NotificationCenter.default.publisher(
                for: .returnToStudentHome
            )
        ) { _ in
            returnToHome()
        }
        .onAppear {
            startNotificationListener()
        }
        .onDisappear {
            notificationListener?.remove()
            notificationListener = nil
        }
    }

    private func returnToHome() {
        selectedTab = 0
        homeNavigationId = UUID()
    }

    private func startNotificationListener() {
        notificationListener?.remove()

        guard let uid = Auth.auth().currentUser?.uid else {
            unreadNotificationCount = 0
            return
        }

        notificationListener = db.collection("notifications")
            .whereField("recipientId", isEqualTo: uid)
            .addSnapshotListener { snapshot, _ in
                let unreadCount = snapshot?.documents.filter { document in
                    let data = document.data()
                    let isStudentNotification =
                        data["type"] as? String != "reservationRequested"
                    let isUnread = data["isRead"] as? Bool != true
                    return isStudentNotification && isUnread
                }.count ?? 0

                DispatchQueue.main.async {
                    unreadNotificationCount = unreadCount
                }
            }
    }
}

#Preview {
    MainTabView()
}
