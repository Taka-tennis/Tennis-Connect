import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct FavoriteView: View {

    private struct FavoriteCoach: Identifiable {
        let coach: Coach
        let createdAt: Date

        var id: String {
            coach.id
        }
    }

    private let db = Firestore.firestore()

    @State private var favoriteCoaches: [FavoriteCoach] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var listener: ListenerRegistration?
    @State private var isLoggedIn = false
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoggedIn {
                    if isLoading && favoriteCoaches.isEmpty {
                        ProgressView("お気に入りを読み込み中…")
                    } else if !errorMessage.isEmpty &&
                                favoriteCoaches.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 40))
                                .foregroundStyle(.orange)

                            Text("お気に入りを取得できませんでした")
                                .font(.headline)

                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button("再読み込み") {
                                startFavoriteListener()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                        .padding()
                    } else if favoriteCoaches.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "heart")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)

                            Text("お気に入りはまだありません")
                                .font(.headline)

                            Text("コーチ詳細の♡を押すと、ここに追加されます")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    } else {
                        List(favoriteCoaches) { item in
                            NavigationLink {
                                CoachDetailView(coach: item.coach)
                            } label: {
                                FavoriteCoachRow(coach: item.coach)
                            }
                        }
                        .listStyle(.plain)
                    }
                } else {
                    loggedOutView
                }
            }
            .navigationTitle("お気に入り")
            .onAppear {
                isLoggedIn = Auth.auth().currentUser != nil

                if isLoggedIn {
                    startFavoriteListener()
                } else {
                    favoriteCoaches = []
                    errorMessage = ""
                    isLoading = false
                }
            }
            .onDisappear {
                listener?.remove()
                listener = nil
            }
            .sheet(isPresented: $showLogin) {
                LoginView {
                    isLoggedIn = true
                    startFavoriteListener()
                }
            }
        }
    }

    private var loggedOutView: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "heart.circle")
                .font(.system(size: 58))
                .foregroundStyle(.secondary)

            Text("お気に入りを見るにはログインが必要です")
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text("ログインすると、保存したコーチをいつでも確認できます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showLogin = true
            } label: {
                Label(
                    "ログイン・新規会員登録",
                    systemImage: "person.crop.circle.badge.plus"
                )
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.top, 6)

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private func startFavoriteListener() {
        listener?.remove()
        listener = nil

        guard let studentId = Auth.auth().currentUser?.uid else {
            isLoggedIn = false
            favoriteCoaches = []
            errorMessage = ""
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = ""

        listener = db.collection("favorites")
            .whereField("studentId", isEqualTo: studentId)
            .addSnapshotListener { snapshot, error in
                if let error {
                    DispatchQueue.main.async {
                        isLoading = false
                        errorMessage = error.localizedDescription
                    }
                    return
                }

                let favoriteDocuments = snapshot?.documents ?? []

                if favoriteDocuments.isEmpty {
                    DispatchQueue.main.async {
                        favoriteCoaches = []
                        isLoading = false
                        errorMessage = ""
                    }
                    return
                }

                loadCoaches(from: favoriteDocuments)
            }
    }

    private func loadCoaches(
        from favoriteDocuments: [QueryDocumentSnapshot]
    ) {
        let group = DispatchGroup()

        var loadedItems: [FavoriteCoach] = []

        for favoriteDocument in favoriteDocuments {
            let favoriteData = favoriteDocument.data()
            let coachId = favoriteData["coachId"] as? String ?? ""

            guard !coachId.isEmpty else {
                continue
            }

            let createdAt =
                (favoriteData["createdAt"] as? Timestamp)?
                .dateValue() ?? .distantPast

            group.enter()

            db.collection("coaches")
                .document(coachId)
                .getDocument { coachSnapshot, _ in
                    defer {
                        group.leave()
                    }

                    guard let coachData = coachSnapshot?.data() else {
                        return
                    }

                    let coach = Coach(
                        id: coachId,
                        name:
                            coachData["name"] as? String
                            ?? "名前未登録",
                        price:
                            coachData["price"] as? Int
                            ?? 0,
                        area:
                            coachData["area"] as? String
                            ?? "エリア未登録",
                        imageURL:
                            coachData["imageURL"] as? String
                            ?? "",
                        availableTimes: [],
                        ageGroup:
                            coachData["ageGroup"] as? String
                            ?? "年代未登録",
                        careers:
                            coachData["careers"] as? [String]
                            ?? ["経歴未登録"],
                        tennisExperience:
                            coachData["tennisExperience"] as? String
                            ?? "未登録",
                        coachingExperience:
                            coachData["coachingExperience"] as? String
                            ?? "未登録",
                        introduction:
                            coachData["introduction"] as? String
                            ?? "自己紹介はまだありません。"
                    )

                    DispatchQueue.main.async {
                        loadedItems.append(
                            FavoriteCoach(
                                coach: coach,
                                createdAt: createdAt
                            )
                        )
                    }
                }
        }

        group.notify(queue: .main) {
            favoriteCoaches =
                loadedItems.sorted {
                    $0.createdAt > $1.createdAt
                }

            isLoading = false
            errorMessage = ""
        }
    }
}

private struct FavoriteCoachRow: View {

    let coach: Coach

    var body: some View {
        HStack(spacing: 14) {
            coachImage

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Text(coach.name)
                    .font(.headline)

                Text(coach.area)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("¥\(coach.price) / 1時間")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }

            Spacer()

            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var coachImage: some View {
        if coach.imageURL.isEmpty {
            Image(systemName: "person.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 58, height: 58)
                .foregroundStyle(.gray)
        } else {
            AsyncImage(
                url: URL(string: coach.imageURL)
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()

                case .failure:
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.gray)

                case .empty:
                    ProgressView()

                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(Circle())
        }
    }
}

#Preview {
    FavoriteView()
}
