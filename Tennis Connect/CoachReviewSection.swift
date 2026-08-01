import SwiftUI

struct CoachReviewSection: View {

    private let reviews = [
        Review(
            rating: 5,
            comment: "説明がとても分かりやすく、苦手だったサーブが改善しました！",
            nickname: "Tennis好き太郎",
            tennisLevel: "中級",
            dateText: "2日前",
            helpfulCount: 18
        ),
        Review(
            rating: 5,
            comment: "初心者の私にも丁寧に教えてくれて、楽しく練習できました。",
            nickname: "Yuki",
            tennisLevel: "初級",
            dateText: "1週間前",
            helpfulCount: 11
        ),
        Review(
            rating: 4,
            comment: "試合で使える具体的なアドバイスをたくさんいただけました。",
            nickname: "T.K",
            tennisLevel: "上級",
            dateText: "3週間前",
            helpfulCount: 7
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {

            HStack {
                Image(systemName: "star.bubble.fill")
                    .foregroundStyle(.green)

                Text("レビュー")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Text("4.9")
                    .font(.headline)
            }

            HStack(spacing: 5) {
                ForEach(1...5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }

                Text("128件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(reviews) { review in
                reviewCard(review)

                if review.id != reviews.last?.id {
                    Divider()
                }
            }

            Button {
                print("レビュー一覧を開く")
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func reviewCard(_ review: Review) -> some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 3) {
                    Text(review.nickname)
                        .fontWeight(.semibold)

                    Label(review.tennisLevel, systemImage: "figure.tennis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(review.dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { number in
                    Image(
                        systemName: number <= review.rating
                        ? "star.fill"
                        : "star"
                    )
                    .font(.caption)
                    .foregroundStyle(.yellow)
                }
            }

            Text(review.comment)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)

            Button {
                print("参考になった")
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "hand.thumbsup")

                    Text("\(review.helpfulCount)人が参考になった")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct Review: Identifiable {
    let id = UUID()
    let rating: Int
    let comment: String
    let nickname: String
    let tennisLevel: String
    let dateText: String
    let helpfulCount: Int
}

#Preview {
    CoachReviewSection()
        .padding()
}
