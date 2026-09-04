// 修正版：本日レッスン可能コーチをコーチ側のON/OFFと連動し、日付検索も安全化

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

private struct CoachSortMetadata {
    let rating: Double
    let reviewCount: Int
    let createdAt: Date?
}

private enum CoachSearchSortOption: String, CaseIterable, Identifiable {
    case recommended
    case priceLow
    case priceHigh
    case ratingHigh
    case newest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended:
            return "おすすめ順"
        case .priceLow:
            return "料金が安い順"
        case .priceHigh:
            return "料金が高い順"
        case .ratingHigh:
            return "評価が高い順"
        case .newest:
            return "新着順"
        }
    }

    var systemImage: String {
        switch self {
        case .recommended:
            return "sparkles"
        case .priceLow:
            return "arrow.down"
        case .priceHigh:
            return "arrow.up"
        case .ratingHigh:
            return "star.fill"
        case .newest:
            return "clock.badge.checkmark"
        }
    }
}

private enum CoachAgeFilterOption: String, CaseIterable, Identifiable {
    case all
    case teens
    case twenties
    case thirties
    case forties
    case fifties
    case sixties
    case seventiesPlus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "すべて"
        case .teens:
            return "10代"
        case .twenties:
            return "20代"
        case .thirties:
            return "30代"
        case .forties:
            return "40代"
        case .fifties:
            return "50代"
        case .sixties:
            return "60代"
        case .seventiesPlus:
            return "70代以上"
        }
    }

    var coachAgeGroup: String? {
        switch self {
        case .all:
            return nil
        default:
            return title
        }
    }
}

private enum CoachPriceFilterOption: String, CaseIterable, Identifiable {
    case noLimit
    case upTo3000
    case upTo5000
    case upTo10000
    case upTo20000

    var id: String { rawValue }

    var title: String {
        switch self {
        case .noLimit:
            return "上限なし"
        case .upTo3000:
            return "3,000円以下"
        case .upTo5000:
            return "5,000円以下"
        case .upTo10000:
            return "10,000円以下"
        case .upTo20000:
            return "20,000円以下"
        }
    }

    var maximumPrice: Int? {
        switch self {
        case .noLimit:
            return nil
        case .upTo3000:
            return 3000
        case .upTo5000:
            return 5000
        case .upTo10000:
            return 10000
        case .upTo20000:
            return 20000
        }
    }
}

private enum SameDaySortOption: String, CaseIterable, Identifiable {
    case earliest
    case recommended
    case priceLow
    case priceHigh
    case ratingHigh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .earliest:
            return "直近で予約できる順"
        case .recommended:
            return "おすすめ順"
        case .priceLow:
            return "料金が安い順"
        case .priceHigh:
            return "料金が高い順"
        case .ratingHigh:
            return "評価が高い順"
        }
    }

    var shortTitle: String {
        switch self {
        case .earliest:
            return "直近順"
        case .recommended:
            return "おすすめ"
        case .priceLow:
            return "安い順"
        case .priceHigh:
            return "高い順"
        case .ratingHigh:
            return "評価順"
        }
    }

    var systemImage: String {
        switch self {
        case .earliest:
            return "clock"
        case .recommended:
            return "sparkles"
        case .priceLow:
            return "arrow.down"
        case .priceHigh:
            return "arrow.up"
        case .ratingHigh:
            return "star.fill"
        }
    }
}

private func dailyRecommendationContext() -> String {
    let viewerId: String

    if let uid = Auth.auth().currentUser?.uid,
       !uid.isEmpty {
        viewerId = uid
    } else {
        let defaults = UserDefaults.standard
        let key = "tennisConnectAnonymousSortSeed"

        if let saved = defaults.string(forKey: key),
           !saved.isEmpty {
            viewerId = saved
        } else {
            let newValue = UUID().uuidString
            defaults.set(newValue, forKey: key)
            viewerId = newValue
        }
    }

    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone =
        TimeZone(identifier: "Asia/Tokyo") ?? .current
    formatter.dateFormat = "yyyy-MM-dd"

    return viewerId + "|" + formatter.string(from: Date())
}

private func stableRotationScore(
    coachId: String,
    context: String
) -> UInt64 {
    // SwiftのhashValueは起動ごとに変わるため使わない。
    // FNV-1aで、同じユーザー・同じ日なら同じ順番になる
    // 決定的なスコアを生成する。
    var hash: UInt64 = 1469598103934665603

    for byte in (context + "|" + coachId).utf8 {
        hash ^= UInt64(byte)
        hash &*= 1099511628211
    }

    return hash
}

private func recommendedComesFirst(
    _ lhs: Coach,
    _ rhs: Coach,
    context: String
) -> Bool {
    let left = stableRotationScore(
        coachId: lhs.id,
        context: context
    )
    let right = stableRotationScore(
        coachId: rhs.id,
        context: context
    )

    if left != right {
        return left < right
    }

    return lhs.id < rhs.id
}

private func ratingComesFirst(
    _ lhs: Coach,
    _ rhs: Coach,
    metadata: [String: CoachSortMetadata],
    context: String
) -> Bool {
    let left = metadata[lhs.id]
    let right = metadata[rhs.id]

    let leftHasReviews = (left?.reviewCount ?? 0) > 0
    let rightHasReviews = (right?.reviewCount ?? 0) > 0

    // 新規コーチは rating=5.0 / reviewCount=0 なので、
    // 「評価順」でレビュー済みコーチより上に固定されないようにする。
    if leftHasReviews != rightHasReviews {
        return leftHasReviews
    }

    let leftRating = left?.rating ?? 0
    let rightRating = right?.rating ?? 0

    if leftRating != rightRating {
        return leftRating > rightRating
    }

    let leftCount = left?.reviewCount ?? 0
    let rightCount = right?.reviewCount ?? 0

    if leftCount != rightCount {
        return leftCount > rightCount
    }

    return recommendedComesFirst(
        lhs,
        rhs,
        context: context
    )
}

struct HomeView: View {
    let db = Firestore.firestore()
    let unreadNotificationCount: Int

    @State private var coaches: [Coach] = []
    @State private var sameDayCoaches: [Coach] = []
    @State private var isLoadingSameDayCoaches = false
    @State private var sameDayErrorMessage = ""
    @State private var isLoggedIn = false
    @State private var showLogin = false

    @State private var selectedSameDayCoach: Coach?
    @State private var showSameDayCoachDetail = false

    // UIScreenの幅ではなく、このセクションが実際に使える横幅を測る。
    @State private var sameDaySectionWidth: CGFloat = 0

    // Coach本体のモデルは広げず、この画面内だけで
    // 並び替えに必要な評価・登録日時を保持する。
    @State private var coachSortMetadata:
        [String: CoachSortMetadata] = [:]

    // 「本日レッスン可能」は最短で予約できる時間順を
    // デフォルトにするため、各コーチの直近空き時刻を保持する。
    @State private var sameDayEarliestLessonDates:
        [String: Date] = [:]

    @State private var sameDaySortOption:
        SameDaySortOption = .earliest

    init(unreadNotificationCount: Int = 0) {
        self.unreadNotificationCount = unreadNotificationCount
    }

    private let columns = [
        GridItem(
            .flexible(minimum: 0, maximum: .infinity),
            spacing: 12
        ),
        GridItem(
            .flexible(minimum: 0, maximum: .infinity),
            spacing: 12
        )
    ]


    private var sameDayCardWidth: CGFloat {
        guard sameDaySectionWidth > 12 else {
            return 0
        }

        // 実際にこのセクションへ割り当てられた幅から、
        // カード間12ptを引いて完全に2等分する。
        return (sameDaySectionWidth - 12) / 2
    }

    private var displayedSameDayCoaches: [Coach] {
        let context = dailyRecommendationContext()

        return sameDayCoaches.sorted { lhs, rhs in
            switch sameDaySortOption {
            case .earliest:
                let leftDate = sameDayEarliestLessonDates[lhs.id]
                let rightDate = sameDayEarliestLessonDates[rhs.id]

                switch (leftDate, rightDate) {
                case let (left?, right?):
                    if left != right {
                        return left < right
                    }

                case (_?, nil):
                    return true

                case (nil, _?):
                    return false

                case (nil, nil):
                    break
                }

                return recommendedComesFirst(
                    lhs,
                    rhs,
                    context: context
                )

            case .recommended:
                return recommendedComesFirst(
                    lhs,
                    rhs,
                    context: context
                )

            case .priceLow:
                if lhs.price != rhs.price {
                    return lhs.price < rhs.price
                }

                return recommendedComesFirst(
                    lhs,
                    rhs,
                    context: context
                )

            case .priceHigh:
                if lhs.price != rhs.price {
                    return lhs.price > rhs.price
                }

                return recommendedComesFirst(
                    lhs,
                    rhs,
                    context: context
                )

            case .ratingHigh:
                return ratingComesFirst(
                    lhs,
                    rhs,
                    metadata: coachSortMetadata,
                    context: context
                )
            }
        }
    }

    private var homeSameDayCoaches: [Coach] {
        Array(displayedSameDayCoaches.prefix(4))
    }

    private var sameDayCoachRows: [[Coach]] {
        let displayed = homeSameDayCoaches

        return stride(
            from: 0,
            to: displayed.count,
            by: 2
        ).map { startIndex in
            let endIndex = min(
                startIndex + 2,
                displayed.count
            )

            return Array(
                displayed[startIndex..<endIndex]
            )
        }
    }

    func fetchCoaches() {
        Task {
            do {
                let blockedCoachIDs = try await loadBlockedCoachIDs()

                let snapshot = try await db
                    .collection("coaches")
                    .getDocuments()

                let visibleDocuments = snapshot.documents.filter {
                    !blockedCoachIDs.contains($0.documentID)
                }

                var fetchedCoaches: [Coach] = []
                var fetchedMetadata:
                    [String: CoachSortMetadata] = [:]

                for document in visibleDocuments {
                    let data = document.data()

                    let savedCareers =
                        (data["careers"] as? [String] ?? [])
                            .map {
                                $0.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                            }
                            .filter {
                                !$0.isEmpty &&
                                $0 != "経歴未登録"
                            }

                    let legacyCareer =
                        (data["career"] as? String ?? "")
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )

                    let careers: [String]

                    if !savedCareers.isEmpty {
                        careers = savedCareers
                    } else if !legacyCareer.isEmpty {
                        careers = legacyCareer
                            .components(separatedBy: .newlines)
                            .map {
                                $0.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                            }
                            .filter {
                                !$0.isEmpty
                            }
                    } else {
                        careers = ["経歴未登録"]
                    }

                    let tennisExperience =
                        (data["tennisExperience"] as? String ?? "")
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )

                    let coachingExperience =
                        (data["coachingExperience"] as? String ?? "")
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )

                    let introduction =
                        (data["introduction"] as? String ?? "")
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )

                    let coach = Coach(
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
                        ageGroup:
                            data["ageGroup"] as? String
                            ?? "年代未登録",
                        careers: careers,
                        tennisExperience:
                            tennisExperience.isEmpty
                                ? "未登録"
                                : tennisExperience,
                        coachingExperience:
                            coachingExperience.isEmpty
                                ? "未登録"
                                : coachingExperience,
                        introduction:
                            introduction.isEmpty
                                ? "自己紹介はまだありません。"
                                : introduction
                    )

                    fetchedCoaches.append(coach)

                    let rating =
                        (data["rating"] as? NSNumber)?
                            .doubleValue
                        ?? 0

                    let reviewCount =
                        (data["reviewCount"] as? NSNumber)?
                            .intValue
                        ?? 0

                    let createdAt =
                        (data["createdAt"] as? Timestamp)?
                            .dateValue()

                    fetchedMetadata[document.documentID] =
                        CoachSortMetadata(
                            rating: rating,
                            reviewCount: reviewCount,
                            createdAt: createdAt
                        )
                }

                await MainActor.run {
                    coaches = fetchedCoaches
                    coachSortMetadata = fetchedMetadata
                }

                loadSameDayCoaches(from: fetchedCoaches)

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
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.tcBrandGreen)
                        .frame(width: 38, height: 38)
                        .background(Color.tcSoftGreen)
                        .clipShape(Circle())
                }
                .accessibilityLabel("スタート画面へ戻る")

                HomeBrandTitle()

                Spacer(minLength: 4)

                if isLoggedIn {
                    NavigationLink {
                        NotificationView()
                    } label: {
                        Image(
                            systemName: unreadNotificationCount > 0
                                ? "bell.fill"
                                : "bell"
                        )
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.tcBrandGreen)
                        .frame(width: 38, height: 38)
                        .background(Color.tcSoftGreen)
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
                } else {
                    Button {
                        showLogin = true
                    } label: {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.tcBrandGreen)
                            .frame(width: 38, height: 38)
                            .background(Color.tcSoftGreen)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("ログイン")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .background(Color.tcBackground)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {

                    NavigationLink {
                        ReservationListView()
                    } label: {
                        HomeActionCard(
                            title: "予約一覧を見る",
                            subtitle: "予約状況とレッスン予定を確認",
                            systemImage: "calendar"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        StudentCoachSearchView(
                            coaches: coaches,
                            sortMetadata: coachSortMetadata
                        )
                    } label: {
                        HomeActionCard(
                            title: "コーチを探す",
                            subtitle: "地域・駅名・希望日から検索",
                            systemImage: "magnifyingglass"
                        )
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 14) {

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 9) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(Color.tcBrandGreen)

                                Text("本日レッスン可能コーチ")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.tcTextPrimary)

                                Spacer(minLength: 8)

                                if sameDayCoaches.count > 1 {
                                    Menu {
                                        ForEach(
                                            SameDaySortOption.allCases
                                        ) { option in
                                            Button {
                                                sameDaySortOption = option
                                            } label: {
                                                HStack {
                                                    Label(
                                                        option.title,
                                                        systemImage:
                                                            option.systemImage
                                                    )

                                                    if sameDaySortOption
                                                        == option {
                                                        Image(
                                                            systemName:
                                                                "checkmark"
                                                        )
                                                    }
                                                }
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 5) {
                                            Image(
                                                systemName:
                                                    "arrow.up.arrow.down"
                                            )
                                            .font(
                                                .system(
                                                    size: 11,
                                                    weight: .bold
                                                )
                                            )

                                            Text(
                                                sameDaySortOption
                                                    .shortTitle
                                            )
                                            .font(
                                                .system(
                                                    size: 12,
                                                    weight: .semibold
                                                )
                                            )
                                        }
                                        .foregroundStyle(
                                            Color.tcBrandGreen
                                        )
                                        .padding(.horizontal, 10)
                                        .frame(height: 32)
                                        .background(Color.tcSoftGreen)
                                        .clipShape(Capsule())
                                    }
                                }
                            }

                            Text("すぐに予約できるコーチをチェック")
                                .font(.caption)
                                .foregroundStyle(Color.tcTextSecondary)
                        }

                        if isLoadingSameDayCoaches {
                            HStack {
                                Spacer()

                                VStack(spacing: 10) {
                                    ProgressView()
                                        .tint(Color.tcBrandGreen)

                                    Text("本日受付中のコーチを確認中…")
                                        .font(.caption)
                                        .foregroundStyle(Color.tcTextSecondary)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 30)

                        } else if sameDayCoaches.isEmpty {
                            VStack(spacing: 12) {

                                ZStack {
                                    Circle()
                                        .fill(Color.tcSoftGreen)
                                        .frame(width: 64, height: 64)

                                    Image(systemName: "figure.tennis")
                                        .font(.system(size: 28))
                                        .foregroundStyle(Color.tcBrandGreen)
                                }

                                Text("現在、本日レッスン可能なコーチはいません")
                                    .font(.headline)
                                    .foregroundStyle(Color.tcTextPrimary)
                                    .multilineTextAlignment(.center)

                                Text("時間をおいてもう一度確認してみてください")
                                    .font(.caption)
                                    .foregroundStyle(Color.tcTextSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                            .padding(.horizontal, 18)
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
                                    Color.tcBorder,
                                    lineWidth: 1
                                )
                            }

                        } else {
                            LazyVStack(spacing: 16) {
                                ForEach(
                                    Array(
                                        sameDayCoachRows.enumerated()
                                    ),
                                    id: \.offset
                                ) { _, row in
                                    HStack(
                                        alignment: .top,
                                        spacing: 12
                                    ) {
                                        ForEach(row) { coach in
                                            Button {
                                                selectedSameDayCoach = coach
                                                showSameDayCoachDetail = true
                                            } label: {
                                                SameDayCoachCard(
                                                    coach: coach,
                                                    cardWidth:
                                                        sameDayCardWidth,
                                                    metadata:
                                                        coachSortMetadata[
                                                            coach.id
                                                        ],
                                                    earliestLessonDate:
                                                        sameDayEarliestLessonDates[
                                                            coach.id
                                                        ]
                                                )
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            .frame(
                                                width: sameDayCardWidth,
                                                alignment: .topLeading
                                            )
                                        }

                                        if row.count == 1 {
                                            Color.clear
                                                .frame(
                                                    width: sameDayCardWidth
                                                )
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                                }
                            }
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )

                            NavigationLink {
                                SameDayCoachListView(
                                    coaches: sameDayCoaches,
                                    sortMetadata: coachSortMetadata,
                                    earliestLessonDates:
                                        sameDayEarliestLessonDates,
                                    initialSortOption:
                                        sameDaySortOption
                                )
                            } label: {
                                HStack(spacing: 6) {
                                    Text("本日受付中のコーチをすべて見る")
                                        .font(
                                            .system(
                                                size: 14,
                                                weight: .semibold
                                            )
                                        )

                                    Image(systemName: "chevron.right")
                                        .font(
                                            .system(
                                                size: 11,
                                                weight: .bold
                                            )
                                        )
                                }
                                .foregroundStyle(
                                    Color.tcBrandGreen
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.white)
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 14,
                                        style: .continuous
                                    )
                                )
                                .overlay {
                                    RoundedRectangle(
                                        cornerRadius: 14,
                                        style: .continuous
                                    )
                                    .stroke(
                                        Color.tcBorder,
                                        lineWidth: 1
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }

                        if !sameDayErrorMessage.isEmpty {
                            Text(sameDayErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    sameDaySectionWidth =
                                        proxy.size.width
                                }
                                .onChange(
                                    of: proxy.size.width
                                ) { newWidth in
                                    sameDaySectionWidth =
                                        newWidth
                                }
                        }
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Color.tcBackground)
        }
        .background(Color.tcBackground.ignoresSafeArea())
        .onAppear {
            isLoggedIn = Auth.auth().currentUser != nil
            fetchCoaches()
        }
        .sheet(isPresented: $showLogin) {
            LoginView {
                isLoggedIn = true
            }
        }
        .navigationDestination(
            isPresented: $showSameDayCoachDetail
        ) {
            if let coach = selectedSameDayCoach {
                CoachDetailView(coach: coach)
            }
        }
    }

    private func loadBlockedCoachIDs() async throws -> Set<String> {
        guard let uid = Auth.auth().currentUser?.uid else {
            return []
        }

        let snapshot = try await db
            .collection("blocks")
            .whereField(
                "blockerId",
                isEqualTo: uid
            )
            .getDocuments()

        return Set(
            snapshot.documents.compactMap { document in
                let data = document.data()

                guard
                    data["blockedRole"] as? String == "coach",
                    let blockedUserId =
                        data["blockedUserId"] as? String,
                    !blockedUserId.isEmpty
                else {
                    return nil
                }

                return blockedUserId
            }
        )
    }

    private func loadSameDayCoaches(from coaches: [Coach]) {
        let dateKey = firestoreDate(Date())
        let now = Date()

        isLoadingSameDayCoaches = true
        sameDayErrorMessage = ""
        sameDayCoaches = []
        sameDayEarliestLessonDates = [:]

        Task {
            var availableCoaches: [Coach] = []
            var earliestDates: [String: Date] = [:]
            var didEncounterError = false

            for coach in coaches {
                do {
                    let snapshot = try await db
                        .collection("coachAvailability")
                        .document(coach.id)
                        .collection("dates")
                        .document(dateKey)
                        .getDocument()

                    let data = snapshot.data() ?? [:]
                    let isSameDayAvailable =
                        data["sameDayAvailable"] as? Bool ?? false
                    let times =
                        data["times"] as? [String] ?? []

                    guard isSameDayAvailable else {
                        continue
                    }

                    let futureDates = times.compactMap { time -> Date? in
                        guard let lessonDate = lessonDate(
                            dateKey: dateKey,
                            time: time
                        ),
                        lessonDate > now else {
                            return nil
                        }

                        return lessonDate
                    }

                    guard let earliestDate = futureDates.min() else {
                        continue
                    }

                    availableCoaches.append(coach)
                    earliestDates[coach.id] = earliestDate

                } catch {
                    didEncounterError = true
                    print(
                        "本日レッスン可能コーチ取得エラー " +
                        "\(coach.id): \(error.localizedDescription)"
                    )
                }
            }

            await MainActor.run {
                sameDayCoaches = availableCoaches
                sameDayEarliestLessonDates = earliestDates
                isLoadingSameDayCoaches = false

                sameDayErrorMessage = didEncounterError
                    ? "一部のコーチ情報を取得できませんでした。再度お試しください。"
                    : ""
            }
        }
    }

    private func firestoreDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func lessonDate(
        dateKey: String,
        time: String
    ) -> Date? {
        let normalizedTime =
            time.replacingOccurrences(of: "~", with: "〜")
                .components(separatedBy: "〜")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? time

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        return formatter.date(
            from: "\(dateKey) \(normalizedTime)"
        )
    }
}


private struct HomeBrandTitle: View {

    var body: some View {
        HStack(spacing: 9) {
            HomeLogoMark()
                .frame(width: 30, height: 30)

            Text("Tennis Connect")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.tcBrandGreen)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }
}

private struct HomeLogoMark: View {

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.tcBrandGreen, lineWidth: 1.8)

            Circle()
                .fill(Color.tcBrandGreen)
                .frame(width: 5, height: 5)
                .offset(y: -15)

            Circle()
                .fill(Color.tcBrandGreen)
                .frame(width: 5, height: 5)
                .offset(x: 15)

            Circle()
                .fill(Color.tcLime)
                .frame(width: 16, height: 16)
                .overlay {
                    HomeTennisBallSeams()
                        .stroke(
                            Color.white,
                            style: StrokeStyle(
                                lineWidth: 1.1,
                                lineCap: .round
                            )
                        )
                        .clipShape(Circle())
                }
        }
        .accessibilityHidden(true)
    }
}

private struct HomeTennisBallSeams: Shape {

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let w = rect.width
        let h = rect.height

        path.move(
            to: CGPoint(
                x: -w * 0.04,
                y: h * 0.24
            )
        )

        path.addCurve(
            to: CGPoint(
                x: w * 1.04,
                y: h * 0.24
            ),
            control1: CGPoint(
                x: w * 0.27,
                y: h * 0.39
            ),
            control2: CGPoint(
                x: w * 0.73,
                y: h * 0.39
            )
        )

        path.move(
            to: CGPoint(
                x: -w * 0.04,
                y: h * 0.76
            )
        )

        path.addCurve(
            to: CGPoint(
                x: w * 1.04,
                y: h * 0.76
            ),
            control1: CGPoint(
                x: w * 0.27,
                y: h * 0.61
            ),
            control2: CGPoint(
                x: w * 0.73,
                y: h * 0.61
            )
        )

        return path
    }
}

private struct HomeActionCard: View {

    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {

            ZStack {
                Circle()
                    .fill(Color.tcSoftGreen)
                    .frame(width: 44, height: 44)

                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.tcBrandGreen)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.tcTextPrimary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.tcTextSecondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.tcBrandGreen)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 74)
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
                Color.tcBorder,
                lineWidth: 1
            )
        }
        .shadow(
            color: Color.black.opacity(0.035),
            radius: 10,
            y: 4
        )
    }
}

private struct StudentCoachSearchView: View {
    let coaches: [Coach]
    let sortMetadata: [String: CoachSortMetadata]

    @State private var searchText = ""
    @State private var sortOption:
        CoachSearchSortOption = .recommended

    @State private var selectedAgeFilter:
        CoachAgeFilterOption = .all
    @State private var selectedPriceFilter:
        CoachPriceFilterOption = .noLimit
    @State private var showFilterSheet = false

    @State private var isDateFilterEnabled = false
    @State private var selectedDate =
        Calendar.current.startOfDay(for: Date())
    @State private var availableCoachIDs: Set<String> = []
    @State private var isCheckingAvailability = false
    @State private var availabilityErrorMessage = ""

    // 「本日レッスン可能」と同じ方式で、
    // 検索結果エリアが実際に使える幅を測る。
    @State private var coachGridWidth: CGFloat = 0

    private let db = Firestore.firestore()

    private var coachGridCardWidth: CGFloat {
        guard coachGridWidth > 12 else {
            return 0
        }

        return (coachGridWidth - 12) / 2
    }

    private var activeFilterCount: Int {
        var count = 0

        if selectedAgeFilter != .all {
            count += 1
        }

        if selectedPriceFilter != .noLimit {
            count += 1
        }

        return count
    }

    private var hasActiveFilters: Bool {
        activeFilterCount > 0
    }

    private var filteredCoaches: [Coach] {
        let keyword = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let filtered = coaches.filter { coach in
            let matchesKeyword =
                keyword.isEmpty ||
                coach.name.localizedCaseInsensitiveContains(keyword) ||
                coach.area.localizedCaseInsensitiveContains(keyword) ||
                coach.careers
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(keyword)

            let matchesDate =
                !isDateFilterEnabled ||
                availableCoachIDs.contains(coach.id)

            let matchesAge: Bool

            if let requiredAge =
                selectedAgeFilter.coachAgeGroup {
                matchesAge =
                    coach.ageGroup == requiredAge
            } else {
                matchesAge = true
            }

            let matchesPrice: Bool

            if let maximumPrice =
                selectedPriceFilter.maximumPrice {
                matchesPrice =
                    coach.price <= maximumPrice
            } else {
                matchesPrice = true
            }

            return matchesKeyword &&
                matchesDate &&
                matchesAge &&
                matchesPrice
        }

        let context = dailyRecommendationContext()

        return filtered.sorted { lhs, rhs in
            switch sortOption {
            case .recommended:
                return recommendedComesFirst(
                    lhs,
                    rhs,
                    context: context
                )

            case .priceLow:
                if lhs.price != rhs.price {
                    return lhs.price < rhs.price
                }

                return recommendedComesFirst(
                    lhs,
                    rhs,
                    context: context
                )

            case .priceHigh:
                if lhs.price != rhs.price {
                    return lhs.price > rhs.price
                }

                return recommendedComesFirst(
                    lhs,
                    rhs,
                    context: context
                )

            case .ratingHigh:
                return ratingComesFirst(
                    lhs,
                    rhs,
                    metadata: sortMetadata,
                    context: context
                )

            case .newest:
                let leftDate = sortMetadata[lhs.id]?.createdAt
                let rightDate = sortMetadata[rhs.id]?.createdAt

                switch (leftDate, rightDate) {
                case let (left?, right?):
                    if left != right {
                        return left > right
                    }

                case (_?, nil):
                    return true

                case (nil, _?):
                    return false

                case (nil, nil):
                    break
                }

                return recommendedComesFirst(
                    lhs,
                    rhs,
                    context: context
                )
            }
        }
    }

    private var coachRows: [[Coach]] {
        stride(
            from: 0,
            to: filteredCoaches.count,
            by: 2
        ).map { startIndex in
            let endIndex = min(
                startIndex + 2,
                filteredCoaches.count
            )

            return Array(
                filteredCoaches[startIndex..<endIndex]
            )
        }
    }

    private var resultTitle: String {
        if isDateFilterEnabled {
            return "\(displayDate(selectedDate))に予約可能なコーチ"
        }

        return searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
            ? "コーチ一覧"
            : "検索結果"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField(
                        "コーチ名・地域・駅名で検索",
                        text: $searchText
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("検索文字を消去")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Color.white)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                    .stroke(Color.tcBorder, lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(
                            "レッスン希望日",
                            systemImage: "calendar"
                        )
                        .font(.headline)

                        Spacer()

                        Toggle(
                            "",
                            isOn: $isDateFilterEnabled
                        )
                        .labelsHidden()
                        .tint(Color.tcBrandGreen)
                    }

                    if isDateFilterEnabled {
                        DatePicker(
                            "日付を選択",
                            selection: $selectedDate,
                            in: Calendar.current.startOfDay(for: Date())...,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .environment(
                            \.locale,
                            Locale(identifier: "ja_JP")
                        )

                        if isCheckingAvailability {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("空き日程を確認中…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text(
                                isToday(selectedDate)
                                    ? "本日は「本日レッスン可能」をONにしていて、これから空き枠があるコーチのみ表示します"
                                    : "\(displayDate(selectedDate))に空き枠があるコーチのみ表示します"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        if !availabilityErrorMessage.isEmpty {
                            Text(availabilityErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } else {
                        Text("ONにすると、希望日に空き枠があるコーチだけに絞り込めます")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color.white)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                    .stroke(Color.tcBorder, lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 10) {

                    HStack(alignment: .center, spacing: 10) {
                        Text(resultTitle)
                            .font(.title2)
                            .bold()
                            .foregroundStyle(Color.tcTextPrimary)

                        Spacer(minLength: 8)
                    }

                    HStack(spacing: 10) {

                        Button {
                            showFilterSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(
                                    systemName:
                                        "line.3.horizontal.decrease"
                                )
                                .font(
                                    .system(
                                        size: 12,
                                        weight: .bold
                                    )
                                )

                                Text("絞り込み")
                                    .font(
                                        .system(
                                            size: 13,
                                            weight: .semibold
                                        )
                                    )

                                if activeFilterCount > 0 {
                                    Text("\(activeFilterCount)")
                                        .font(
                                            .system(
                                                size: 10,
                                                weight: .bold
                                            )
                                        )
                                        .foregroundStyle(.white)
                                        .frame(
                                            minWidth: 18,
                                            minHeight: 18
                                        )
                                        .background(
                                            Color.tcBrandGreen
                                        )
                                        .clipShape(Circle())
                                }
                            }
                            .foregroundStyle(
                                hasActiveFilters
                                    ? Color.tcBrandGreen
                                    : Color.tcTextSecondary
                            )
                            .padding(.horizontal, 11)
                            .frame(height: 36)
                            .background(
                                hasActiveFilters
                                    ? Color.tcSoftGreen
                                    : Color.white
                            )
                            .clipShape(Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(
                                        hasActiveFilters
                                            ? Color.tcBrandGreen
                                                .opacity(0.35)
                                            : Color.tcBorder,
                                        lineWidth: 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 4)

                        Menu {
                            ForEach(
                                CoachSearchSortOption.allCases
                            ) { option in
                                Button {
                                    sortOption = option
                                } label: {
                                    HStack {
                                        Label(
                                            option.title,
                                            systemImage:
                                                option.systemImage
                                        )

                                        if sortOption == option {
                                            Image(
                                                systemName:
                                                    "checkmark"
                                            )
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(
                                    systemName:
                                        "arrow.up.arrow.down"
                                )
                                .font(
                                    .system(
                                        size: 12,
                                        weight: .bold
                                    )
                                )

                                Text(sortOption.title)
                                    .font(
                                        .system(
                                            size: 13,
                                            weight: .semibold
                                        )
                                    )
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Color.tcBrandGreen)
                            .padding(.horizontal, 11)
                            .frame(height: 36)
                            .background(Color.tcSoftGreen)
                            .clipShape(Capsule())
                        }
                    }

                    if hasActiveFilters {
                        HStack(spacing: 8) {

                            if selectedAgeFilter != .all {
                                FilterConditionChip(
                                    text:
                                        selectedAgeFilter.title
                                ) {
                                    selectedAgeFilter = .all
                                }
                            }

                            if selectedPriceFilter != .noLimit {
                                FilterConditionChip(
                                    text:
                                        selectedPriceFilter.title
                                ) {
                                    selectedPriceFilter = .noLimit
                                }
                            }

                            Spacer(minLength: 0)

                            Button("すべて解除") {
                                selectedAgeFilter = .all
                                selectedPriceFilter = .noLimit
                            }
                            .font(
                                .system(
                                    size: 12,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(Color.tcBrandGreen)
                        }
                    }
                }

                if isCheckingAvailability && isDateFilterEnabled {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)

                        Text("予約可能なコーチを確認しています")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 44)

                } else if filteredCoaches.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)

                        Text("条件に合うコーチが見つかりません")
                            .font(.headline)

                        Text(
                            hasActiveFilters
                                ? "年代や料金などの絞り込み条件を変えてお試しください"
                                : (
                                    isDateFilterEnabled
                                        ? "別の日付や検索条件でお試しください"
                                        : "検索条件を変えてお試しください"
                                )
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 44)

                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(
                            Array(coachRows.enumerated()),
                            id: \.offset
                        ) { _, row in
                            HStack(
                                alignment: .top,
                                spacing: 12
                            ) {
                                ForEach(row) { coach in
                                    NavigationLink {
                                        CoachDetailView(coach: coach)
                                    } label: {
                                        CoachGridCard(
                                            coach: coach,
                                            metadata:
                                                sortMetadata[coach.id],
                                            cardWidth:
                                                coachGridCardWidth
                                        )
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .frame(
                                        width: coachGridCardWidth,
                                        alignment: .topLeading
                                    )
                                }

                                if row.count == 1 {
                                    Color.clear
                                        .frame(
                                            width: coachGridCardWidth
                                        )
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    coachGridWidth =
                                        proxy.size.width
                                }
                                .onChange(
                                    of: proxy.size.width
                                ) { newWidth in
                                    coachGridWidth = newWidth
                                }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color.tcBackground)
        .navigationTitle("コーチを探す")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFilterSheet) {
            CoachSearchFilterSheet(
                selectedAgeFilter: $selectedAgeFilter,
                selectedPriceFilter: $selectedPriceFilter
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: isDateFilterEnabled) { isEnabled in
            if isEnabled {
                loadAvailableCoachesForSelectedDate()
            } else {
                availableCoachIDs = []
                availabilityErrorMessage = ""
                isCheckingAvailability = false
            }
        }
        .onChange(of: selectedDate) { _ in
            guard isDateFilterEnabled else {
                return
            }

            loadAvailableCoachesForSelectedDate()
        }
    }

    private func loadAvailableCoachesForSelectedDate() {
        let dateKey = firestoreDate(selectedDate)
        let targetIsToday = isToday(selectedDate)
        let now = Date()

        isCheckingAvailability = true
        availabilityErrorMessage = ""
        availableCoachIDs = []

        Task {
            var fetchedAvailableCoachIDs: Set<String> = []
            var didEncounterError = false

            for coach in coaches {
                do {
                    let snapshot = try await db
                        .collection("coachAvailability")
                        .document(coach.id)
                        .collection("dates")
                        .document(dateKey)
                        .getDocument()

                    let data = snapshot.data() ?? [:]
                    let times =
                        data["times"] as? [String] ?? []

                    guard !times.isEmpty else {
                        continue
                    }

                    if targetIsToday {
                        let isSameDayAvailable =
                            data["sameDayAvailable"] as? Bool ?? false

                        guard isSameDayAvailable else {
                            continue
                        }

                        let hasFutureTime = times.contains { time in
                            guard let lessonDate = lessonDate(
                                dateKey: dateKey,
                                time: time
                            ) else {
                                return false
                            }

                            return lessonDate > now
                        }

                        if hasFutureTime {
                            fetchedAvailableCoachIDs.insert(coach.id)
                        }

                    } else {
                        fetchedAvailableCoachIDs.insert(coach.id)
                    }

                } catch {
                    didEncounterError = true
                    print(
                        "空き日程取得エラー " +
                        "\(coach.id): \(error.localizedDescription)"
                    )
                }
            }

            await MainActor.run {
                guard isDateFilterEnabled,
                      firestoreDate(selectedDate) == dateKey else {
                    return
                }

                availableCoachIDs = fetchedAvailableCoachIDs
                isCheckingAvailability = false

                if didEncounterError {
                    availabilityErrorMessage =
                        "一部の空き日程を取得できませんでした。再度お試しください。"
                } else {
                    availabilityErrorMessage = ""
                }
            }
        }
    }

    private func firestoreDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func isToday(_ date: Date) -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.isDate(date, inSameDayAs: Date())
    }

    private func lessonDate(
        dateKey: String,
        time: String
    ) -> Date? {
        let normalizedTime =
            time.replacingOccurrences(of: "~", with: "〜")
                .components(separatedBy: "〜")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? time

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        return formatter.date(
            from: "\(dateKey) \(normalizedTime)"
        )
    }

    private func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        formatter.dateFormat = "yyyy/M/d"
        return formatter.string(from: date)
    }
}

private struct SameDayCoachListView: View {

    let coaches: [Coach]
    let sortMetadata: [String: CoachSortMetadata]
    let earliestLessonDates: [String: Date]

    @State private var sortOption:
        SameDaySortOption
    @State private var searchText = ""
    @State private var selectedAgeFilter:
        CoachAgeFilterOption = .all
    @State private var selectedPriceFilter:
        CoachPriceFilterOption = .noLimit
    @State private var showFilterSheet = false
    @State private var gridWidth: CGFloat = 0

    init(
        coaches: [Coach],
        sortMetadata: [String: CoachSortMetadata],
        earliestLessonDates: [String: Date],
        initialSortOption: SameDaySortOption
    ) {
        self.coaches = coaches
        self.sortMetadata = sortMetadata
        self.earliestLessonDates = earliestLessonDates
        _sortOption = State(
            initialValue: initialSortOption
        )
    }

    private var cardWidth: CGFloat {
        guard gridWidth > 12 else {
            return 0
        }

        return (gridWidth - 12) / 2
    }

    private var activeFilterCount: Int {
        var count = 0

        if selectedAgeFilter != .all {
            count += 1
        }

        if selectedPriceFilter != .noLimit {
            count += 1
        }

        return count
    }

    private var filteredAndSortedCoaches: [Coach] {
        let keyword = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let filtered = coaches.filter { coach in
            let matchesKeyword =
                keyword.isEmpty ||
                coach.name.localizedCaseInsensitiveContains(
                    keyword
                ) ||
                coach.area.localizedCaseInsensitiveContains(
                    keyword
                ) ||
                coach.careers
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(
                        keyword
                    )

            let matchesAge: Bool

            if let requiredAge =
                selectedAgeFilter.coachAgeGroup {
                matchesAge =
                    coach.ageGroup == requiredAge
            } else {
                matchesAge = true
            }

            let matchesPrice: Bool

            if let maximumPrice =
                selectedPriceFilter.maximumPrice {
                matchesPrice =
                    coach.price <= maximumPrice
            } else {
                matchesPrice = true
            }

            return matchesKeyword &&
                matchesAge &&
                matchesPrice
        }

        let context = dailyRecommendationContext()

        return filtered.sorted { lhs, rhs in
            switch sortOption {
            case .earliest:
                let leftDate =
                    earliestLessonDates[lhs.id]
                let rightDate =
                    earliestLessonDates[rhs.id]

                switch (leftDate, rightDate) {
                case let (left?, right?):
                    if left != right {
                        return left < right
                    }

                case (_?, nil):
                    return true

                case (nil, _?):
                    return false

                case (nil, nil):
                    break
                }

                return recommendedComesFirst(
                    lhs,
                    rhs,
                    context: context
                )

            case .recommended:
                return recommendedComesFirst(
                    lhs,
                    rhs,
                    context: context
                )

            case .priceLow:
                if lhs.price != rhs.price {
                    return lhs.price < rhs.price
                }

                return recommendedComesFirst(
                    lhs,
                    rhs,
                    context: context
                )

            case .priceHigh:
                if lhs.price != rhs.price {
                    return lhs.price > rhs.price
                }

                return recommendedComesFirst(
                    lhs,
                    rhs,
                    context: context
                )

            case .ratingHigh:
                return ratingComesFirst(
                    lhs,
                    rhs,
                    metadata: sortMetadata,
                    context: context
                )
            }
        }
    }

    private var rows: [[Coach]] {
        stride(
            from: 0,
            to: filteredAndSortedCoaches.count,
            by: 2
        ).map { startIndex in
            let endIndex = min(
                startIndex + 2,
                filteredAndSortedCoaches.count
            )

            return Array(
                filteredAndSortedCoaches[
                    startIndex..<endIndex
                ]
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(
                            Color.tcTextSecondary
                        )

                    TextField(
                        "コーチ名・地域・駅名で検索",
                        text: $searchText
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(
                                systemName:
                                    "xmark.circle.fill"
                            )
                            .foregroundStyle(
                                Color.tcTextSecondary
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "検索文字を消去"
                        )
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Color.white)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                    .stroke(
                        Color.tcBorder,
                        lineWidth: 1
                    )
                }

                HStack(spacing: 10) {

                    Button {
                        showFilterSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(
                                systemName:
                                    "line.3.horizontal.decrease"
                            )
                            .font(
                                .system(
                                    size: 12,
                                    weight: .bold
                                )
                            )

                            Text("絞り込み")
                                .font(
                                    .system(
                                        size: 13,
                                        weight: .semibold
                                    )
                                )

                            if activeFilterCount > 0 {
                                Text(
                                    "\(activeFilterCount)"
                                )
                                .font(
                                    .system(
                                        size: 10,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(.white)
                                .frame(
                                    minWidth: 18,
                                    minHeight: 18
                                )
                                .background(
                                    Color.tcBrandGreen
                                )
                                .clipShape(Circle())
                            }
                        }
                        .foregroundStyle(
                            activeFilterCount > 0
                                ? Color.tcBrandGreen
                                : Color.tcTextSecondary
                        )
                        .padding(.horizontal, 11)
                        .frame(height: 36)
                        .background(
                            activeFilterCount > 0
                                ? Color.tcSoftGreen
                                : Color.white
                        )
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(
                                    activeFilterCount > 0
                                        ? Color.tcBrandGreen
                                            .opacity(0.35)
                                        : Color.tcBorder,
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 4)

                    Menu {
                        ForEach(
                            SameDaySortOption.allCases
                        ) { option in
                            Button {
                                sortOption = option
                            } label: {
                                HStack {
                                    Label(
                                        option.title,
                                        systemImage:
                                            option.systemImage
                                    )

                                    if sortOption == option {
                                        Image(
                                            systemName:
                                                "checkmark"
                                        )
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(
                                systemName:
                                    "arrow.up.arrow.down"
                            )
                            .font(
                                .system(
                                    size: 12,
                                    weight: .bold
                                )
                            )

                            Text(sortOption.shortTitle)
                                .font(
                                    .system(
                                        size: 13,
                                        weight: .semibold
                                    )
                                )
                        }
                        .foregroundStyle(
                            Color.tcBrandGreen
                        )
                        .padding(.horizontal, 11)
                        .frame(height: 36)
                        .background(Color.tcSoftGreen)
                        .clipShape(Capsule())
                    }
                }

                if activeFilterCount > 0 {
                    HStack(spacing: 8) {

                        if selectedAgeFilter != .all {
                            FilterConditionChip(
                                text:
                                    selectedAgeFilter.title
                            ) {
                                selectedAgeFilter = .all
                            }
                        }

                        if selectedPriceFilter != .noLimit {
                            FilterConditionChip(
                                text:
                                    selectedPriceFilter.title
                            ) {
                                selectedPriceFilter =
                                    .noLimit
                            }
                        }

                        Spacer(minLength: 0)

                        Button("すべて解除") {
                            selectedAgeFilter = .all
                            selectedPriceFilter = .noLimit
                        }
                        .font(
                            .system(
                                size: 12,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            Color.tcBrandGreen
                        )
                    }
                }

                HStack {
                    Text("本日受付中")
                        .font(.title2)
                        .bold()
                        .foregroundStyle(
                            Color.tcTextPrimary
                        )

                    Spacer()

                    Text(
                        "\(filteredAndSortedCoaches.count)人"
                    )
                    .font(
                        .system(
                            size: 13,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        Color.tcTextSecondary
                    )
                }

                if filteredAndSortedCoaches.isEmpty {
                    VStack(spacing: 12) {

                        ZStack {
                            Circle()
                                .fill(Color.tcSoftGreen)
                                .frame(
                                    width: 64,
                                    height: 64
                                )

                            Image(
                                systemName: "figure.tennis"
                            )
                            .font(.system(size: 28))
                            .foregroundStyle(
                                Color.tcBrandGreen
                            )
                        }

                        Text("条件に合うコーチが見つかりません")
                            .font(.headline)
                            .foregroundStyle(
                                Color.tcTextPrimary
                            )

                        Text(
                            searchText
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                                .isEmpty
                                ? "年代や料金の条件を変えてお試しください"
                                : "検索ワードや絞り込み条件を変えてお試しください"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            Color.tcTextSecondary
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 44)

                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(
                            Array(rows.enumerated()),
                            id: \.offset
                        ) { _, row in
                            HStack(
                                alignment: .top,
                                spacing: 12
                            ) {
                                ForEach(row) { coach in
                                    NavigationLink {
                                        CoachDetailView(
                                            coach: coach
                                        )
                                    } label: {
                                        SameDayCoachCard(
                                            coach: coach,
                                            cardWidth: cardWidth,
                                            metadata:
                                                sortMetadata[
                                                    coach.id
                                                ],
                                            earliestLessonDate:
                                                earliestLessonDates[
                                                    coach.id
                                                ]
                                        )
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .frame(
                                        width: cardWidth,
                                        alignment: .topLeading
                                    )
                                }

                                if row.count == 1 {
                                    Color.clear
                                        .frame(
                                            width: cardWidth
                                        )
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    gridWidth =
                                        proxy.size.width
                                }
                                .onChange(
                                    of: proxy.size.width
                                ) { newWidth in
                                    gridWidth = newWidth
                                }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color.tcBackground)
        .navigationTitle("本日レッスン可能")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showFilterSheet) {
            CoachSearchFilterSheet(
                selectedAgeFilter:
                    $selectedAgeFilter,
                selectedPriceFilter:
                    $selectedPriceFilter
            )
            .presentationDetents(
                [.medium, .large]
            )
            .presentationDragIndicator(.visible)
        }
    }
}

private struct FilterConditionChip: View {

    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Text(text)
                .font(
                    .system(
                        size: 12,
                        weight: .semibold
                    )
                )

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(
                        .system(
                            size: 9,
                            weight: .bold
                        )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(text)を解除")
        }
        .foregroundStyle(Color.tcBrandGreen)
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 30)
        .background(Color.tcSoftGreen)
        .clipShape(Capsule())
    }
}

private struct CoachSearchFilterSheet: View {

    @Binding var selectedAgeFilter:
        CoachAgeFilterOption
    @Binding var selectedPriceFilter:
        CoachPriceFilterOption

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    filterSection(
                        title: "年代",
                        systemImage: "person",
                        options:
                            CoachAgeFilterOption.allCases,
                        selected: selectedAgeFilter
                    ) { option in
                        selectedAgeFilter = option
                    }

                    filterSection(
                        title: "料金",
                        systemImage: "yensign.circle",
                        options:
                            CoachPriceFilterOption.allCases,
                        selected: selectedPriceFilter
                    ) { option in
                        selectedPriceFilter = option
                    }

                    Button {
                        selectedAgeFilter = .all
                        selectedPriceFilter = .noLimit
                    } label: {
                        Text("条件をすべてクリア")
                            .font(
                                .system(
                                    size: 14,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(Color.tcBrandGreen)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.tcSoftGreen)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 14,
                                    style: .continuous
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .background(Color.tcBackground)
            .navigationTitle("絞り込み")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .topBarTrailing
                ) {
                    Button("完了") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tcBrandGreen)
                }
            }
        }
    }

    @ViewBuilder
    private func filterSection<Option>(
        title: String,
        systemImage: String,
        options: [Option],
        selected: Option,
        onSelect: @escaping (Option) -> Void
    ) -> some View
    where Option: Identifiable & Equatable,
          Option.ID: Hashable {

        VStack(alignment: .leading, spacing: 12) {

            Label(
                title,
                systemImage: systemImage
            )
            .font(.headline)
            .foregroundStyle(Color.tcTextPrimary)

            VStack(spacing: 0) {
                ForEach(options) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        HStack {
                            Text(optionTitle(option))
                                .foregroundStyle(
                                    Color.tcTextPrimary
                                )

                            Spacer()

                            if option == selected {
                                Image(
                                    systemName:
                                        "checkmark.circle.fill"
                                )
                                .foregroundStyle(
                                    Color.tcBrandGreen
                                )
                            } else {
                                Image(
                                    systemName: "circle"
                                )
                                .foregroundStyle(
                                    Color.tcBorder
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if option.id != options.last?.id {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(Color.white)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 16,
                    style: .continuous
                )
                .stroke(Color.tcBorder, lineWidth: 1)
            }
        }
    }

    private func optionTitle<Option>(
        _ option: Option
    ) -> String {
        if let age =
            option as? CoachAgeFilterOption {
            return age.title
        }

        if let price =
            option as? CoachPriceFilterOption {
            return price.title
        }

        return ""
    }
}

private struct SameDayCoachCard: View {

    let coach: Coach
    let cardWidth: CGFloat
    let metadata: CoachSortMetadata?
    let earliestLessonDate: Date?

    private var contentWidth: CGFloat {
        max(cardWidth - 20, 0)
    }

    private func earliestTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        formatter.dateFormat = "H:mm"
        return "最短 " + formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            AsyncImage(
                url: URL(string: coach.imageURL)
            ) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()

                case .failure:
                    ZStack {
                        Color.tcSoftGreen

                        Image(
                            systemName:
                                "person.crop.circle.fill"
                        )
                        .font(.system(size: 45))
                        .foregroundStyle(
                            Color.tcBrandGreen.opacity(0.55)
                        )
                    }

                case .empty:
                    ZStack {
                        Color.tcSoftGreen

                        ProgressView()
                            .tint(Color.tcBrandGreen)
                    }

                @unknown default:
                    ZStack {
                        Color.tcSoftGreen
                    }
                }
            }
            .frame(
                width: contentWidth,
                height: 130
            )
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 13,
                    style: .continuous
                )
            )
            .overlay(alignment: .bottomLeading) {
                Text("本日可")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.tcBrandGreen)
                    .clipShape(Capsule())
                    .padding(8)
            }

            Text(coach.name)
                .font(.headline)
                .foregroundStyle(Color.tcTextPrimary)
                .lineLimit(1)
                .frame(
                    width: contentWidth,
                    alignment: .leading
                )
                .frame(
                    width: contentWidth,
                    alignment: .leading
                )

            Text(
                coach.careers.first
                    ?? "経歴未登録"
            )
            .font(.caption)
            .foregroundStyle(Color.tcTextSecondary)
            .lineLimit(1)
            .frame(
                width: contentWidth,
                alignment: .leading
            )

            Label(
                coach.area,
                systemImage:
                    "mappin.and.ellipse"
            )
            .font(.caption)
            .foregroundStyle(Color.tcTextSecondary)
            .lineLimit(1)
            .frame(
                width: contentWidth,
                alignment: .leading
            )

            HStack(spacing: 8) {
                if let earliestLessonDate {
                    Label(
                        earliestTimeText(
                            earliestLessonDate
                        ),
                        systemImage: "clock"
                    )
                    .font(
                        .system(
                            size: 11,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(Color.tcBrandGreen)
                }

                if let metadata,
                   metadata.reviewCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)

                        Text(
                            String(
                                format: "%.1f",
                                metadata.rating
                            )
                        )
                        .font(
                            .system(
                                size: 11,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(Color.tcTextSecondary)
                    }
                }
            }
            .frame(
                width: contentWidth,
                alignment: .leading
            )

            Text(
                "¥\(coach.price) / 1時間"
            )
            .font(.subheadline)
            .fontWeight(.bold)
            .foregroundStyle(Color.tcBrandGreen)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(
                width: contentWidth,
                alignment: .leading
            )
        }
        .frame(
            width: contentWidth,
            alignment: .leading
        )
        .padding(10)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(
                Color.tcBorder,
                lineWidth: 1
            )
        }
        .shadow(
            color: Color.black.opacity(0.045),
            radius: 9,
            x: 0,
            y: 4
        )
    }
}

private struct CoachGridCard: View {
    let coach: Coach
    let metadata: CoachSortMetadata?
    let cardWidth: CGFloat

    private var contentWidth: CGFloat {
        max(cardWidth - 20, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            AsyncImage(url: URL(string: coach.imageURL)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()

                case .failure:
                    ZStack {
                        Color.tcSoftGreen

                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 45))
                            .foregroundStyle(
                                Color.tcBrandGreen.opacity(0.55)
                            )
                    }

                case .empty:
                    ZStack {
                        Color.tcSoftGreen

                        ProgressView()
                            .tint(Color.tcBrandGreen)
                    }

                @unknown default:
                    ZStack {
                        Color.tcSoftGreen
                    }
                }
            }
            .frame(
                width: contentWidth,
                height: 130
            )
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 13,
                    style: .continuous
                )
            )

            Text(coach.name)
                .font(.headline)
                .foregroundStyle(Color.tcTextPrimary)
                .lineLimit(1)

            Text(coach.careers.first ?? "経歴未登録")
                .font(.caption)
                .foregroundStyle(Color.tcTextSecondary)
                .lineLimit(1)
                .frame(
                    width: contentWidth,
                    alignment: .leading
                )

            Label(
                coach.area,
                systemImage: "mappin.and.ellipse"
            )
            .font(.caption)
            .foregroundStyle(Color.tcTextSecondary)
            .lineLimit(1)
            .frame(
                width: contentWidth,
                alignment: .leading
            )

            Group {
                if let metadata,
                   metadata.reviewCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)

                        Text(
                            String(
                                format: "%.1f",
                                metadata.rating
                            )
                        )
                        .font(
                            .system(
                                size: 12,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(Color.tcTextPrimary)

                        Text("(\(metadata.reviewCount))")
                            .font(.caption2)
                            .foregroundStyle(Color.tcTextSecondary)
                    }
                } else {
                    Text("レビューなし")
                        .font(.caption2)
                        .foregroundStyle(Color.tcTextSecondary)
                }
            }
            .frame(
                width: contentWidth,
                alignment: .leading
            )

            Text("¥\(coach.price) / 1時間")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(Color.tcBrandGreen)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(
                    width: contentWidth,
                    alignment: .leading
                )
        }
        .frame(
            width: contentWidth,
            alignment: .leading
        )
        .padding(10)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(Color.tcBorder, lineWidth: 1)
        }
        .shadow(
            color: Color.black.opacity(0.045),
            radius: 9,
            x: 0,
            y: 4
        )
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


private extension Color {

    static let tcBrandGreen = Color(
        red: 34 / 255,
        green: 168 / 255,
        blue: 102 / 255
    )

    static let tcLime = Color(
        red: 151 / 255,
        green: 207 / 255,
        blue: 63 / 255
    )

    static let tcSoftGreen = Color(
        red: 232 / 255,
        green: 245 / 255,
        blue: 236 / 255
    )

    static let tcBackground = Color(
        red: 250 / 255,
        green: 251 / 255,
        blue: 250 / 255
    )

    static let tcTextPrimary = Color(
        red: 34 / 255,
        green: 34 / 255,
        blue: 34 / 255
    )

    static let tcTextSecondary = Color(
        red: 101 / 255,
        green: 109 / 255,
        blue: 104 / 255
    )

    static let tcBorder = Color(
        red: 226 / 255,
        green: 232 / 255,
        blue: 228 / 255
    )
}

#Preview {
    HomeView()
}
