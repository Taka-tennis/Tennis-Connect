import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {

        TabView(selection: $selectedTab) {

            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("ホーム", systemImage: "house.fill")
            }
            .tag(0)

            ChatListView()
                .tabItem {
                    Label("チャット", systemImage: "message.fill")
                }
                .tag(1)

            FavoriteView()
                .tabItem {
                    Label("お気に入り", systemImage: "heart.fill")
                }
                .tag(2)

            MyPageView()
                .tabItem {
                    Label("マイページ", systemImage: "person.fill")
                }
                .tag(3)

        }

    }
}

#Preview {
    MainTabView()
}
