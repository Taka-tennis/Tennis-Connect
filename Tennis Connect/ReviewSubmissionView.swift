import SwiftUI
import FirebaseFunctions

struct ReviewSubmissionView: View {

    private enum ReviewMode {
        case create
        case edit
    }

    let reservationId: String
    let reviewId: String?
    let coachName: String
    let onSubmitted: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var rating: Int
    @State private var comment: String
    @State private var isSubmitting = false
    @State private var errorMessage = ""
    @State private var showSuccessAlert = false

    private let functions = Functions.functions(
        region: "asia-northeast1"
    )

    init(
        reservationId: String,
        coachName: String,
        onSubmitted: (() -> Void)? = nil
    ) {
        self.reservationId = reservationId
        self.reviewId = nil
        self.coachName = coachName
        self.onSubmitted = onSubmitted
        _rating = State(initialValue: 0)
        _comment = State(initialValue: "")
    }

    init(
        reviewId: String,
        coachName: String,
        existingRating: Int,
        existingComment: String,
        onSubmitted: (() -> Void)? = nil
    ) {
        self.reservationId = ""
        self.reviewId = reviewId
        self.coachName = coachName
        self.onSubmitted = onSubmitted
        _rating = State(initialValue: existingRating)
        _comment = State(initialValue: existingComment)
    }

    private var mode: ReviewMode {
        reviewId == nil ? .create : .edit
    }

    private var isEditing: Bool {
        mode == .edit
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        isEditing
                            ? "レビューを編集"
                            : "レッスンはいかがでしたか？"
                    )
                    .font(.title2)
                    .fontWeight(.bold)

                    Text(
                        isEditing
                            ? "\(coachName)へのレビュー内容を変更できます"
                            : "\(coachName)へのレビュー"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                ratingSection

                commentSection

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                }

                Button {
                    submit()
                } label: {
                    HStack {
                        Spacer()

                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Label(
                                isEditing
                                    ? "レビューを更新する"
                                    : "レビューを投稿する",
                                systemImage:
                                    isEditing
                                    ? "square.and.pencil"
                                    : "paperplane.fill"
                            )
                            .fontWeight(.semibold)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(
                        canSubmit
                        ? Color.green
                        : Color.gray
                    )
                    .foregroundStyle(.white)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit || isSubmitting)
            }
            .padding()
        }
        .navigationTitle(
            isEditing ? "レビュー編集" : "レビュー投稿"
        )
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isSubmitting)
        .alert(
            isEditing
                ? "レビューを更新しました"
                : "レビューを投稿しました",
            isPresented: $showSuccessAlert
        ) {
            Button("OK") {
                onSubmitted?()
                dismiss()
            }
        } message: {
            Text(
                isEditing
                    ? "変更内容を反映しました。"
                    : "ご協力ありがとうございます。"
            )
        }
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("評価")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { number in
                    Button {
                        rating = number
                        errorMessage = ""
                    } label: {
                        Image(
                            systemName: number <= rating
                            ? "star.fill"
                            : "star"
                        )
                        .font(.system(size: 34))
                        .foregroundStyle(.yellow)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(number)つ星")
                    .accessibilityValue(
                        rating == number
                        ? "選択中"
                        : ""
                    )
                }
            }

            Text(
                rating == 0
                ? "1〜5の星を選択してください"
                : "\(rating) / 5"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("コメント")
                    .font(.headline)

                Spacer()

                Text("\(comment.count) / 500")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $comment)
                .frame(minHeight: 160)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator))
                }
                .onChange(of: comment) { newValue in
                    if newValue.count > 500 {
                        comment = String(newValue.prefix(500))
                    }
                }

            Text(
                isEditing
                    ? "星の数とコメントは何度でも更新できます。"
                    : "レッスン内容やコーチの教え方についてご記入ください。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var trimmedComment: String {
        comment.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private var canSubmit: Bool {
        (1...5).contains(rating) &&
        !trimmedComment.isEmpty &&
        trimmedComment.count <= 500
    }

    private func submit() {
        switch mode {
        case .create:
            submitNewReview()

        case .edit:
            updateExistingReview()
        }
    }

    private func submitNewReview() {
        guard !reservationId.isEmpty else {
            errorMessage = "予約情報を確認できませんでした"
            return
        }

        guard validateInput() else {
            return
        }

        isSubmitting = true
        errorMessage = ""

        functions
            .httpsCallable("submitReview")
            .call(
                [
                    "reservationId": reservationId,
                    "rating": rating,
                    "comment": trimmedComment
                ]
            ) { _, error in
                DispatchQueue.main.async {
                    isSubmitting = false

                    if let error = error {
                        errorMessage = error.localizedDescription
                        return
                    }

                    showSuccessAlert = true
                }
            }
    }

    private func updateExistingReview() {
        guard let reviewId,
              !reviewId.isEmpty else {
            errorMessage = "レビュー情報を確認できませんでした"
            return
        }

        guard validateInput() else {
            return
        }

        isSubmitting = true
        errorMessage = ""

        functions
            .httpsCallable("updateReview")
            .call(
                [
                    "reviewId": reviewId,
                    "rating": rating,
                    "comment": trimmedComment
                ]
            ) { _, error in
                DispatchQueue.main.async {
                    isSubmitting = false

                    if let error = error {
                        errorMessage = error.localizedDescription
                        return
                    }

                    showSuccessAlert = true
                }
            }
    }

    private func validateInput() -> Bool {
        guard (1...5).contains(rating) else {
            errorMessage = "評価を1〜5で選択してください"
            return false
        }

        guard !trimmedComment.isEmpty else {
            errorMessage = "レビュー本文を入力してください"
            return false
        }

        guard trimmedComment.count <= 500 else {
            errorMessage = "レビュー本文は500文字以内で入力してください"
            return false
        }

        return true
    }
}

#Preview("新規投稿") {
    NavigationStack {
        ReviewSubmissionView(
            reservationId: "sampleReservation",
            coachName: "山田コーチ"
        )
    }
}

#Preview("編集") {
    NavigationStack {
        ReviewSubmissionView(
            reviewId: "sampleReview",
            coachName: "山田コーチ",
            existingRating: 4,
            existingComment: "とても分かりやすいレッスンでした。"
        )
    }
}
