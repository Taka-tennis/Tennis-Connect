// 修正版：画面内ヘッダーの左に戻るボタン、右に通知ベルを表示

import SwiftUI
import FirebaseFirestore

struct HomeView: View {
    let db = Firestore.firestore()
    let unreadNotificationCount: Int

    @State private var coaches: [Coach] = []
    @State private var searchText = ""

    init(unreadNotificationCount: Int = 0) {
        self.unreadNotificationCount = unreadNotificationCount
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    func fetchCoaches() {
        Task {
            do {
                let snapshot = try await db.collection("coaches").getDocuments()

                let fetchedCoaches = snapshot.documents.map { document in
                    let data = document.data()

                    return Coach(
                        id: document.documentID,
                        name: data["name"] as? String ?? "名前未登録",
                        price: data["price"] as? Int ?? 0,
                        area: data["area"] as? String ?? "エリア未登録",
                        imageURL: data["imageURL"] as? String ?? "",
                        availableTimes: [
                            ("09:00", true),
                            ("10:00", true),
                            ("11:00", false),
                            ("13:00", true),
                            ("15:00", true),
                            ("16:00", false)
                        ],
                        ageGroup: data["ageGroup"] as? String ?? "年代未登録",
                        careers: data["careers"] as? [String] ?? ["経歴未登録"],
                        tennisExperience: data["tennisExperience"] as? String ?? "未登録",
                        coachingExperience: data["coachingExperience"] as? String ?? "未登録",
                        introduction: data["introduction"] as? String ?? "自己紹介はまだありません。"
                    )
                }

                await MainActor.run {
                    coaches = fetchedCoaches
                }

            } catch {
                print("コーチ取得エラー: \(error.localizedDescription)")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    NotificationCenter.default.post(
                        name: .returnToStartScreen,
                        object: nil
                    )
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
                .accessibilityLabel("スタート画面へ戻る")

                Text("🎾 Tennis Connect")
                    .font(.title)
                    .bold()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 4)

                NavigationLink {
                    NotificationView()
                } label: {
                    Image(
                        systemName: unreadNotificationCount > 0
                            ? "bell.fill"
                            : "bell"
                    )
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
                    .overlay(alignment: .topTrailing) {
                        if unreadNotificationCount > 0 {
                            Text(
                                unreadNotificationCount > 99
                                    ? "99+"
                                    : "\(unreadNotificationCount)"
                            )
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 5, y: -5)
                        }
                    }
                }
                .accessibilityLabel(
                    unreadNotificationCount > 0
                        ? "未読通知が\(unreadNotificationCount)件あります"
                        : "通知"
                )
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 6)

            ScrollView {

                VStack(alignment: .leading, spacing: 20) {

                    NavigationLink {
                        ReservationListView()
                    } label: {
                        HStack {
                            Image(systemName: "calendar")
                            Text("予約一覧を見る")

                            Spacer()

                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    TextField(
                        "コーチ・地域・駅名で検索",
                        text: $searchText
                    )
                        .padding()
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(12)

                    VStack(alignment: .leading) {

                        Text("🔥 今日レッスンできます")
                            .font(.title2)
                            .bold()

                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(coaches) { coach in
                                NavigationLink {
                                    CoachDetailView(coach: coach)
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {

                                        AsyncImage(url: URL(string: coach.imageURL)) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image
                                                    .resizable()
                                                    .scaledToFill()

                                            case .failure:
                                                ZStack {
                                                    Color.gray.opacity(0.15)

                                                    Image(systemName: "person.crop.circle.fill")
                                                        .font(.system(size: 45))
                                                        .foregroundColor(.gray)
                                                }

                                            case .empty:
                                                ZStack {
                                                    Color.gray.opacity(0.15)
                                                    ProgressView()
                                                }

                                            @unknown default:
                                                EmptyView()
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 130)
                                        .clipped()
                                        .cornerRadius(12)

                                        Text(coach.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)

                                        Text(coach.careers.first ?? "経歴未登録")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)

                                        Label(coach.area, systemImage: "mappin.and.ellipse")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)

                                        Text("¥\(coach.price) / 1時間")
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(.blue)
                                    }
                                    .padding(10)
                                    .background(Color.white)
                                    .cornerRadius(14)
                                    .shadow(
                                        color: Color.black.opacity(0.08),
                                        radius: 5,
                                        x: 0,
                                        y: 2
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                }
                .padding()
            }
        }
        .onAppear {
            fetchCoaches()
        }
    }
}

struct LessonCard: View {
    let imageURL: String
    let name: String
    let time: String
    let place: String
    let price: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            AsyncImage(url: URL(string: imageURL)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ProgressView()
            }
            .frame(height: 180)
            .clipped()
            .cornerRadius(12)

            Text(name)
                .font(.headline)

            Text(time)
            Text(place)

            Text(price)
                .bold()



        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
}

#Preview {
    HomeView()
}
