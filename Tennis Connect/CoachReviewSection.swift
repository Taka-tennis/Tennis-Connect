import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

struct CoachReviewSection: View {

    let coachId: String
    let coachName: String

    @State private var recentReviews: [CoachReviewItem] = []
    @State private var ratingAverage = 0.0
    @State private var ratingCount = 0
    @State private var isLoading = false
    @State private var errorMessage = ""

    @State private var canCreateReview = false
    @State private var canEditReview = false
    @State private var eligibleReservationId = ""
    @State private var existingReviewId = ""
    @State private var existingRating = 0
    @State private var existingComment = ""
    @State private var isCheckingReviewAction = false
    @State private var reviewActionError = ""

    private let db = Firestore.firestore()
    private let functions = Functions.functions(
        region: "asia-northeast1"
    )

    init(
        coachId: String,
        coachName: String = "コーチ"
    ) {
        self.coachId = coachId
        self.coachName = coachName
    }

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    private var shouldCheckReviewAction: Bool {
        guard let currentUserId,
              !currentUserId.isEmpty,
              currentUserId != coachId else {
            return false
        }

        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {

            HStack {
                Image(systemName: "star.bubble.fill")
                    .foregroundStyle(.green)

                Text("レビュー")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if ratingCount > 0 {
                    Text(String(format: "%.1f", ratingAverage))
                        .font(.headline)
                } else {
                    Text("評価なし")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if ratingCount > 0 {
                HStack(spacing: 5) {
                    StarDisplayView(
                        rating: Int(ratingAverage.rounded()),
                        size: .body
                    )

                    Text("\(ratingCount)件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if shouldCheckReviewAction {
                reviewActionContent
            }

            Divider()

            reviewContent

            if ratingCount > recentReviews.count,
               !recentReviews.isEmpty {
                NavigationLink {
                    CoachReviewListView(coachId: coachId)
                } label: {
                    Text("すべてのレビューを見る")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.green)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onAppear {
            loadReviews()
            loadReviewActionStatus()
        }
    }

    @ViewBuilder
    private var reviewActionContent: some View {
        if isCheckingReviewAction {
            HStack(spacing: 9) {
                ProgressView()
                    .tint(.green)

                Text("レビュー投稿状況を確認中…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)

        } else if !reviewActionError.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.secondary)

                Text("レビュー投稿状況を確認できませんでした")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("再確認") {
                    loadReviewActionStatus()
                }
                .font(.caption)
                .fontWeight(.semibold)
                .buttonStyle(.plain)
                .foregroundStyle(.green)
            }
            .padding(.vertical, 4)

        } else if canEditReview,
                  !existingReviewId.isEmpty,
                  (1...5).contains(existingRating),
                  !existingComment.isEmpty {
            NavigationLink {
                ReviewSubmissionView(
                    reviewId: existingReviewId,
                    coachName: coachName,
                    existingRating: existingRating,
                    existingComment: existingComment
                ) {
                    refreshAfterReviewChange()
                }
            } label: {
                reviewActionButtonLabel(
                    title: "あなたのレビューを編集",
                    subtitle: "星の数やコメントを変更できます",
                    systemImage: "square.and.pencil"
                )
            }
            .buttonStyle(.plain)

        } else if canCreateReview,
                  !eligibleReservationId.isEmpty {
            NavigationLink {
                ReviewSubmissionView(
                    reservationId: eligibleReservationId,
                    coachName: coachName
                ) {
                    refreshAfterReviewChange()
                }
            } label: {
                reviewActionButtonLabel(
                    title: "このコーチのレビューを書く",
                    subtitle: "受講したレッスンについて感想を投稿できます",
                    systemImage: "star.bubble"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func reviewActionButtonLabel(
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 42, height: 42)

                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.green)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.green.opacity(0.18), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var reviewContent: some View {
        if isLoading {
            HStack {
                Spacer()
                ProgressView("レビューを読み込み中…")
                Spacer()
            }
            .padding(.vertical, 18)
        } else if !errorMessage.isEmpty {
            VStack(spacing: 12) {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)

                Button("再読み込み") {
                    loadReviews()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if recentReviews.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "star.bubble")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)

                Text("まだレビューはありません")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("レッスンを受けた生徒のレビューがここに表示されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else {
            ForEach(Array(recentReviews.enumerated()), id: \.element.id) {
                index,
                review in

                CoachReviewCardView(review: review)

                if index < recentReviews.count - 1 {
                    Divider()
                }
            }
        }
    }

    private func refreshAfterReviewChange() {
        loadReviews()
        loadReviewActionStatus()
    }

    private func loadReviewActionStatus() {
        resetReviewActionState()

        guard shouldCheckReviewAction else {
            return
        }

        guard !coachId.isEmpty else {
            reviewActionError = "コーチ情報を確認できませんでした"
            return
        }

        isCheckingReviewAction = true
        reviewActionError = ""

        functions
            .httpsCallable("getCoachReviewStatus")
            .call(["coachId": coachId]) { result, error in
                DispatchQueue.main.async {
                    isCheckingReviewAction = false

                    if let error {
                        reviewActionError = error.localizedDescription
                        return
                    }

                    guard let data = result?.data as? [String: Any] else {
                        reviewActionError = "レビュー状況の確認結果を読み取れませんでした"
                        return
                    }

                    let fetchedCanCreate =
                        boolValue(data["canCreate"])
                    let fetchedCanEdit =
                        boolValue(data["canEdit"])
                    let fetchedReservationId =
                        stringValue(data["eligibleReservationId"])
                    let fetchedReviewId =
                        stringValue(data["existingReviewId"])
                    let fetchedRating =
                        intValue(data["existingRating"])
                    let fetchedComment =
                        stringValue(data["existingComment"])

                    if fetchedCanEdit {
                        guard !fetchedReviewId.isEmpty,
                              (1...5).contains(fetchedRating),
                              !fetchedComment.isEmpty else {
                            reviewActionError =
                                "レビュー情報を確認できませんでした"
                            return
                        }
                    }

                    if fetchedCanCreate &&
                        fetchedReservationId.isEmpty {
                        reviewActionError =
                            "受講済みレッスンを確認できませんでした"
                        return
                    }

                    canCreateReview = fetchedCanCreate
                    canEditReview = fetchedCanEdit
                    eligibleReservationId = fetchedReservationId
                    existingReviewId = fetchedReviewId
                    existingRating = fetchedRating
                    existingComment = fetchedComment
                    reviewActionError = ""
                }
            }
    }

    private func resetReviewActionState() {
        canCreateReview = false
        canEditReview = false
        eligibleReservationId = ""
        existingReviewId = ""
        existingRating = 0
        existingComment = ""
        isCheckingReviewAction = false
        reviewActionError = ""
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool {
            return value
        }

        if let value = value as? NSNumber {
            return value.boolValue
        }

        return false
    }

    private func intValue(_ value: Any?) -> Int {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        return 0
    }

    private func stringValue(_ value: Any?) -> String {
        (value as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadReviews() {
        guard !coachId.isEmpty else {
            recentReviews = []
            ratingAverage = 0
            ratingCount = 0
            errorMessage = "コーチ情報を確認できませんでした"
            return
        }

        isLoading = true
        errorMessage = ""

        let group = DispatchGroup()

        var loadedAverage = 0.0
        var loadedCount = 0
        var loadedReviews: [CoachReviewItem] = []
        var firstError: Error?

        group.enter()

        db.collection("coaches")
            .document(coachId)
            .getDocument { snapshot, error in

                defer {
                    group.leave()
                }

                if let error = error {
                    firstError = error
                    return
                }

                let data = snapshot?.data() ?? [:]

                let count =
                    (data["ratingCount"] as? NSNumber)?.intValue ??
                    (data["reviewCount"] as? NSNumber)?.intValue ??
                    0

                loadedCount = count

                if count > 0 {
                    loadedAverage =
                        (data["ratingAverage"] as? NSNumber)?.doubleValue ??
                        (data["rating"] as? NSNumber)?.doubleValue ??
                        0
                } else {
                    loadedAverage = 0
                }
            }

        group.enter()

        db.collection("reviews")
            .whereField("coachId", isEqualTo: coachId)
            .order(by: "createdAt", descending: true)
            .limit(to: 3)
            .getDocuments { snapshot, error in

                defer {
                    group.leave()
                }

                if let error = error {
                    if firstError == nil {
                        firstError = error
                    }
                    return
                }

                loadedReviews = snapshot?.documents.compactMap {
                    CoachReviewItem(document: $0)
                } ?? []
            }

        group.notify(queue: .main) {
            isLoading = false

            if let firstError = firstError {
                errorMessage =
                    "レビューを取得できませんでした: " +
                    firstError.localizedDescription
                return
            }

            ratingAverage = loadedAverage
            ratingCount = loadedCount
            recentReviews = loadedReviews
        }
    }
}

private struct CoachReviewListView: View {

    let coachId: String

    @State private var reviews: [CoachReviewItem] = []
    @State private var lastDocument: DocumentSnapshot?
    @State private var isInitialLoading = false
    @State private var isLoadingMore = false
    @State private var hasMore = true
    @State private var errorMessage = ""

    private let db = Firestore.firestore()
    private let pageSize = 20

    var body: some View {
        Group {
            if isInitialLoading && reviews.isEmpty {
                ProgressView("レビューを読み込み中…")
            } else if reviews.isEmpty && errorMessage.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "star.bubble")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)

                    Text("レビューはありません")
                        .font(.headline)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(reviews.enumerated()), id: \.element.id) {
                            index,
                            review in

                            CoachReviewCardView(review: review)
                                .padding(.vertical, 16)

                            if index < reviews.count - 1 {
                                Divider()
                            }

                            if review.id == reviews.last?.id,
                               hasMore {
                                Color.clear
                                    .frame(height: 1)
                                    .onAppear {
                                        loadNextPage()
                                    }
                            }
                        }

                        if isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding()
                                Spacer()
                            }
                        }

                        if !errorMessage.isEmpty {
                            VStack(spacing: 10) {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.center)

                                Button("再読み込み") {
                                    loadNextPage()
                                }
                                .buttonStyle(.bordered)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .navigationTitle("レビュー一覧")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if reviews.isEmpty && !isInitialLoading {
                loadFirstPage()
            }
        }
    }

    private func loadFirstPage() {
        reviews = []
        lastDocument = nil
        hasMore = true
        errorMessage = ""
        isInitialLoading = true

        fetchPage(isFirstPage: true)
    }

    private func loadNextPage() {
        guard hasMore,
              !isInitialLoading,
              !isLoadingMore else {
            return
        }

        errorMessage = ""
        isLoadingMore = true

        fetchPage(isFirstPage: false)
    }

    private func fetchPage(isFirstPage: Bool) {
        guard !coachId.isEmpty else {
            isInitialLoading = false
            isLoadingMore = false
            hasMore = false
            errorMessage = "コーチ情報を確認できませんでした"
            return
        }

        var query: Query = db.collection("reviews")
            .whereField("coachId", isEqualTo: coachId)
            .order(by: "createdAt", descending: true)
            .limit(to: pageSize)

        if !isFirstPage,
           let lastDocument {
            query = query.start(afterDocument: lastDocument)
        }

        query.getDocuments { snapshot, error in
            DispatchQueue.main.async {
                isInitialLoading = false
                isLoadingMore = false

                if let error = error {
                    errorMessage =
                        "レビューを取得できませんでした: " +
                        error.localizedDescription
                    return
                }

                let documents = snapshot?.documents ?? []

                let newReviews = documents.compactMap {
                    CoachReviewItem(document: $0)
                }

                if isFirstPage {
                    reviews = newReviews
                } else {
                    let existingIds = Set(reviews.map(\.id))
                    reviews.append(
                        contentsOf: newReviews.filter {
                            !existingIds.contains($0.id)
                        }
                    )
                }

                lastDocument = documents.last
                hasMore = documents.count == pageSize
                errorMessage = ""
            }
        }
    }
}

private struct CoachReviewCardView: View {

    let review: CoachReviewItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.green)

                Text(review.studentDisplayName)
                    .fontWeight(.semibold)

                Spacer()

                Text(review.displayDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            StarDisplayView(
                rating: review.rating,
                size: .caption
            )

            Text(review.comment)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(review.studentDisplayName)、5段階中\(review.rating)、\(review.comment)"
        )
    }
}

private struct StarDisplayView: View {

    let rating: Int
    let size: Font

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { number in
                Image(
                    systemName: number <= rating
                    ? "star.fill"
                    : "star"
                )
                .font(size)
                .foregroundStyle(.yellow)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct CoachReviewItem: Identifiable {

    let id: String
    let rating: Int
    let comment: String
    let studentDisplayName: String
    let createdAt: Date

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()

        guard let rating =
                (data["rating"] as? NSNumber)?.intValue,
              (1...5).contains(rating) else {
            return nil
        }

        let comment =
            (data["comment"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !comment.isEmpty else {
            return nil
        }

        self.id = document.documentID
        self.rating = rating
        self.comment = comment

        let savedName =
            (data["studentDisplayName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        self.studentDisplayName =
            savedName.isEmpty
            ? "匿名ユーザー"
            : savedName

        self.createdAt =
            (data["createdAt"] as? Timestamp)?.dateValue() ??
            .distantPast
    }

    var displayDate: String {
        guard createdAt != .distantPast else {
            return "投稿日不明"
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy/M/d"

        return formatter.string(from: createdAt)
    }
}

#Preview {
    NavigationStack {
        CoachReviewSection(
            coachId: "sampleCoach"
        )
        .padding()
    }
}
