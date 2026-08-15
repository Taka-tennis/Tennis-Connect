import SwiftUI

struct CoachDashboardView: View {

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(spacing: 20) {

                    HeroCard()

                    DashboardCard(
                        title: "空き日程管理",
                        subtitle: "来週は3日未登録",
                        systemImage: "calendar"
                    ) {
                        CoachAvailabilityView()
                    }

                    DashboardCard(
                        title: "予約一覧",
                        subtitle: "今日・今後の予約を見る",
                        systemImage: "list.bullet.rectangle"
                    ) {
                        CoachReservationListView()
                    }

                    DashboardCard(
                        title: "チャット",
                        subtitle: "未読2件",
                        systemImage: "message"
                    ) {
                        Text("チャット")
                    }

                    DashboardCard(
                        title: "レビュー",
                        subtitle: "新着レビュー1件",
                        systemImage: "star.fill"
                    ) {
                        Text("レビュー")
                    }

                    DashboardCard(
                        title: "プロフィール編集",
                        subtitle: "プロフィールを編集",
                        systemImage: "person"
                    ) {
                        Text("プロフィール編集")
                    }

                }
                .padding()

            }
            .navigationTitle("ホーム")

        }
    }
}

#Preview {
    CoachDashboardView()
}
