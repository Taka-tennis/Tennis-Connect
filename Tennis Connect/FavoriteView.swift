import SwiftUI
import FirebaseAuth
import FirebaseFirestore

private enum FavoriteUI {
    static let brandGreen = Color(
        red: 42 / 255,
        green: 174 / 255,
        blue: 102 / 255
    )

    static let softGreen = Color(
        red: 232 / 255,
        green: 245 / 255,
        blue: 236 / 255
    )

    static let background = Color(
        red: 248 / 255,
        green: 250 / 255,
        blue: 249 / 255
    )

    static let textPrimary = Color(
        red: 34 / 255,
        green: 34 / 255,
        blue: 34 / 255
    )

    static let textSecondary = Color(
        red: 102 / 255,
        green: 110 / 255,
        blue: 105 / 255
    )

    static let border = Color.black.opacity(0.08)
}

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
                    ZStack {
                        FavoriteUI.background
                            .ignoresSafeArea()

                        Group {
                            if isLoading &&
                                favoriteCoaches.isEmpty {
                                loadingView

                            } else if
                                !errorMessage.isEmpty &&
                                favoriteCoaches.isEmpty {
                                errorStateView

                            } else if
                                favoriteCoaches.isEmpty {
                                emptyStateView

                            } else {
                                favoriteList
                            }
                        }
                    }
                } else {
                    loggedOutView
                }
            }
            .tint(FavoriteUI.brandGreen)
            .navigationTitle("お気に入り")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                isLoggedIn =
                    Auth.auth().currentUser != nil

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
            .sheet(
                isPresented: $showLogin
            ) {
                LoginView {
                    isLoggedIn = true
                    startFavoriteListener()
                }
            }
        }
    }

    private var favoriteList: some View {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: 12
            ) {
                headerSection

                ForEach(
                    favoriteCoaches
                ) { item in
                    NavigationLink {
                        CoachDetailView(
                            coach: item.coach
                        )
                    } label: {
                        FavoriteCoachCard(
                            coach: item.coach
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
    }

    private var headerSection: some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            Text("お気に入りのコーチ")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(
                    FavoriteUI.textPrimary
                )

            Text(
                "保存したコーチをいつでも確認できます"
            )
            .font(.subheadline)
            .foregroundStyle(
                FavoriteUI.textSecondary
            )
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .padding(.bottom, 4)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(
                    FavoriteUI.brandGreen
                )

            Text("お気に入りを読み込み中…")
                .font(.subheadline)
                .foregroundStyle(
                    FavoriteUI.textSecondary
                )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    private var errorStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        Color.orange.opacity(0.10)
                    )
                    .frame(
                        width: 82,
                        height: 82
                    )

                Image(
                    systemName:
                        "exclamationmark.triangle.fill"
                )
                .font(.system(size: 34))
                .foregroundStyle(.orange)
            }

            Text(
                "お気に入りを取得できませんでした"
            )
            .font(.title3)
            .fontWeight(.bold)
            .foregroundStyle(
                FavoriteUI.textPrimary
            )
            .multilineTextAlignment(.center)

            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(
                    FavoriteUI.textSecondary
                )
                .multilineTextAlignment(.center)

            Button {
                startFavoriteListener()
            } label: {
                Label(
                    "再読み込み",
                    systemImage:
                        "arrow.clockwise"
                )
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .foregroundStyle(.white)
                .background(
                    FavoriteUI.brandGreen
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        FavoriteUI.softGreen
                    )
                    .frame(
                        width: 88,
                        height: 88
                    )

                Image(
                    systemName: "heart"
                )
                .font(.system(size: 36))
                .foregroundStyle(
                    FavoriteUI.brandGreen
                )
            }

            Text(
                "お気に入りはまだありません"
            )
            .font(.title3)
            .fontWeight(.bold)
            .foregroundStyle(
                FavoriteUI.textPrimary
            )

            Text(
                "コーチ詳細の♡を押すと、ここに追加されます"
            )
            .font(.subheadline)
            .foregroundStyle(
                FavoriteUI.textSecondary
            )
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    private var loggedOutView: some View {
        ZStack {
            FavoriteUI.background
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(
                            FavoriteUI.softGreen
                        )
                        .frame(
                            width: 92,
                            height: 92
                        )

                    Image(
                        systemName:
                            "heart.circle"
                    )
                    .font(.system(size: 42))
                    .foregroundStyle(
                        FavoriteUI.brandGreen
                    )
                }

                Text(
                    "お気に入りを見るにはログインが必要です"
                )
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(
                    FavoriteUI.textPrimary
                )
                .multilineTextAlignment(.center)

                Text(
                    "ログインすると、保存したコーチをいつでも確認できます。"
                )
                .font(.subheadline)
                .foregroundStyle(
                    FavoriteUI.textSecondary
                )
                .multilineTextAlignment(.center)

                Button {
                    showLogin = true
                } label: {
                    Label(
                        "ログイン・新規会員登録",
                        systemImage:
                            "person.crop.circle.badge.plus"
                    )
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundStyle(.white)
                    .background(
                        FavoriteUI.brandGreen
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 15,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 6)

                Spacer()
            }
            .padding(.horizontal, 28)
        }
    }

    private func startFavoriteListener() {
        listener?.remove()
        listener = nil

        guard
            let studentId =
                Auth.auth().currentUser?.uid
        else {
            isLoggedIn = false
            favoriteCoaches = []
            errorMessage = ""
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = ""

        listener = db
            .collection("favorites")
            .whereField(
                "studentId",
                isEqualTo: studentId
            )
            .addSnapshotListener {
                snapshot,
                error in

                if let error {
                    DispatchQueue.main.async {
                        isLoading = false
                        errorMessage =
                            error.localizedDescription
                    }
                    return
                }

                let favoriteDocuments =
                    snapshot?.documents
                    ?? []

                if favoriteDocuments.isEmpty {
                    DispatchQueue.main.async {
                        favoriteCoaches = []
                        isLoading = false
                        errorMessage = ""
                    }
                    return
                }

                loadCoaches(
                    from:
                        favoriteDocuments
                )
            }
    }

    private func loadCoaches(
        from favoriteDocuments:
            [QueryDocumentSnapshot]
    ) {
        let group = DispatchGroup()

        var loadedItems:
            [FavoriteCoach] = []

        for favoriteDocument
            in favoriteDocuments {

            let favoriteData =
                favoriteDocument.data()

            let coachId =
                favoriteData["coachId"]
                as? String
                ?? ""

            guard !coachId.isEmpty else {
                continue
            }

            let createdAt =
                (
                    favoriteData["createdAt"]
                    as? Timestamp
                )?
                .dateValue()
                ?? .distantPast

            group.enter()

            db.collection("coaches")
                .document(coachId)
                .getDocument {
                    coachSnapshot,
                    _ in

                    defer {
                        group.leave()
                    }

                    guard
                        let coachData =
                            coachSnapshot?
                                .data()
                    else {
                        return
                    }

                    let coach = Coach(
                        id: coachId,
                        name:
                            coachData["name"]
                            as? String
                            ?? "名前未登録",
                        price:
                            coachData["price"]
                            as? Int
                            ?? 0,
                        area:
                            coachData["area"]
                            as? String
                            ?? "エリア未登録",
                        imageURL:
                            coachData["imageURL"]
                            as? String
                            ?? "",
                        availableTimes: [],
                        ageGroup:
                            coachData["ageGroup"]
                            as? String
                            ?? "年代未登録",
                        careers:
                            coachData["careers"]
                            as? [String]
                            ?? ["経歴未登録"],
                        tennisExperience:
                            coachData[
                                "tennisExperience"
                            ]
                            as? String
                            ?? "未登録",
                        coachingExperience:
                            coachData[
                                "coachingExperience"
                            ]
                            as? String
                            ?? "未登録",
                        introduction:
                            coachData["introduction"]
                            as? String
                            ?? "自己紹介はまだありません。"
                    )

                    DispatchQueue.main.async {
                        loadedItems.append(
                            FavoriteCoach(
                                coach: coach,
                                createdAt:
                                    createdAt
                            )
                        )
                    }
                }
        }

        group.notify(queue: .main) {
            favoriteCoaches =
                loadedItems.sorted {
                    $0.createdAt >
                    $1.createdAt
                }

            isLoading = false
            errorMessage = ""
        }
    }
}

private struct FavoriteCoachCard: View {

    let coach: Coach

    var body: some View {
        HStack(
            alignment: .center,
            spacing: 14
        ) {
            coachImage

            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                Text(coach.name)
                    .font(.headline)
                    .foregroundStyle(
                        FavoriteUI.textPrimary
                    )
                    .lineLimit(1)

                Label(
                    coach.area,
                    systemImage:
                        "mappin.and.ellipse"
                )
                .font(.caption)
                .foregroundStyle(
                    FavoriteUI.textSecondary
                )
                .lineLimit(1)

                HStack(spacing: 8) {
                    Text(
                        "¥\(coach.price.formatted())"
                    )
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        FavoriteUI.brandGreen
                    )

                    Text("/ 1時間")
                        .font(.caption)
                        .foregroundStyle(
                            FavoriteUI.textSecondary
                        )
                }

                if !coach.ageGroup.isEmpty &&
                    coach.ageGroup !=
                    "年代未登録" {
                    Text(coach.ageGroup)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            FavoriteUI.brandGreen
                        )
                        .padding(
                            .horizontal,
                            8
                        )
                        .frame(height: 23)
                        .background(
                            FavoriteUI.softGreen
                        )
                        .clipShape(Capsule())
                }
            }

            Spacer()

            VStack(spacing: 14) {
                Image(
                    systemName:
                        "heart.fill"
                )
                .font(
                    .system(
                        size: 17,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    FavoriteUI.brandGreen
                )

                Image(
                    systemName:
                        "chevron.right"
                )
                .font(
                    .system(
                        size: 11,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    FavoriteUI.textSecondary
                )
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                FavoriteUI.border,
                lineWidth: 1
            )
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var coachImage: some View {
        if coach.imageURL.isEmpty {
            placeholderImage
        } else {
            AsyncImage(
                url:
                    URL(
                        string:
                            coach.imageURL
                    )
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()

                case .failure:
                    placeholderImage

                case .empty:
                    ZStack {
                        Circle()
                            .fill(
                                FavoriteUI.softGreen
                            )

                        ProgressView()
                            .tint(
                                FavoriteUI.brandGreen
                            )
                    }

                @unknown default:
                    placeholderImage
                }
            }
            .frame(
                width: 66,
                height: 66
            )
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(
                        FavoriteUI.border,
                        lineWidth: 1
                    )
            }
        }
    }

    private var placeholderImage: some View {
        ZStack {
            Circle()
                .fill(
                    FavoriteUI.softGreen
                )
                .frame(
                    width: 66,
                    height: 66
                )

            Image(
                systemName:
                    "person.fill"
            )
            .font(.system(size: 27))
            .foregroundStyle(
                FavoriteUI.brandGreen
            )
        }
    }
}
