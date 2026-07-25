import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {

            HomeView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("ホーム")
                }

            SearchView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("探す")
                }

            RecruitView()
                .tabItem {
                    Image(systemName: "plus.circle.fill")
                    Text("募集")
                }

            MessageView()
                .tabItem {
                    Image(systemName: "message.fill")
                    Text("メッセージ")
                }

            ProfileView()
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("マイページ")
                }
        }
    }
}

#Preview {
    ContentView()
}
