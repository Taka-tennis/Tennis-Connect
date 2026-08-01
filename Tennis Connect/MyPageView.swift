import SwiftUI

struct MyPageView: View {

    var body: some View {

        NavigationStack {

            List {

                Section {

                    VStack(spacing: 16) {

                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 90))
                            .foregroundStyle(.green)

                        Text("たかひろ")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("テニスを楽しもう！")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 24) {

                            VStack {
                                Text("12")
                                    .font(.title2)
                                    .bold()

                                Text("予約")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            VStack {
                                Text("8")
                                    .font(.title2)
                                    .bold()

                                Text("レビュー")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            VStack {
                                Text("❤️")
                                    .font(.title2)

                                Text("お気に入り")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                        }

                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)

                }

                Section("メニュー") {

                    NavigationLink {

                        ReservationListView()

                    } label: {

                        Label("予約一覧", systemImage: "calendar")

                    }

                    NavigationLink {

                        FavoriteView()

                    } label: {

                        Label("お気に入り", systemImage: "heart")

                    }

                    NavigationLink {

                        Text("通知")

                    } label: {

                        Label("通知", systemImage: "bell")

                    }

                    NavigationLink {

                        Text("設定")

                    } label: {

                        Label("設定", systemImage: "gear")

                    }

                }

                Section {

                    Button(role: .destructive) {

                    } label: {

                        Text("ログアウト")

                    }

                }

            }
            .navigationTitle("マイページ")

        }

    }

}

#Preview {
    MyPageView()
}
