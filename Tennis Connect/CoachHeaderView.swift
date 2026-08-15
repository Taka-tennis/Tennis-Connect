import SwiftUI
import FirebaseFirestore

struct CoachHeaderView: View {

    let coach: Coach

    @State private var ratingAverage = 0.0
    @State private var ratingCount = 0
    @State private var isLoadingRating = false
    @State private var ratingLoadFailed = false

    private let db = Firestore.firestore()

    var body: some View {

        VStack(spacing: 24) {

            // MARK: - プロフィール画像

            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .foregroundStyle(.green)

            // MARK: - 名前

            Text(coach.name)
                .font(.system(size: 30, weight: .bold))

            // MARK: - 評価

            ratingView

            // MARK: - 情報カード

            VStack(spacing: 16) {

                infoRow(
                    icon: "trophy.fill",
                    title: coach.careers.first ?? "経歴未登録"
                )

                infoRow(
                    icon: "person.fill",
                    title: coach.ageGroup
                )

                infoRow(
                    icon: "mappin.and.ellipse",
                    title: coach.area
                )

                infoRow(
                    icon: "yensign.circle.fill",
                    title: "¥\(coach.price) / 1時間"
                )
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 18))

        }
        .padding()
        .onAppear {
            loadRating()
        }

    }

    // MARK: - 評価表示

    @ViewBuilder
    private var ratingView: some View {

        if isLoadingRating {

            ProgressView()
                .controlSize(.small)

        } else if ratingLoadFailed {

            Text("評価情報を取得できません")
                .font(.subheadline)
                .foregroundStyle(.secondary)

        } else if ratingCount > 0 {

            HStack(spacing: 4) {

                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)

                Text(String(format: "%.1f", ratingAverage))
                    .fontWeight(.bold)

                Text("(\(ratingCount)件)")
                    .foregroundStyle(.secondary)

            }

        } else {

            HStack(spacing: 4) {

                Image(systemName: "star")
                    .foregroundStyle(.secondary)

                Text("評価なし")
                    .foregroundStyle(.secondary)

            }

        }

    }

    // MARK: - 評価取得

    private func loadRating() {

        guard !coach.id.isEmpty else {
            ratingAverage = 0
            ratingCount = 0
            ratingLoadFailed = true
            return
        }

        isLoadingRating = true
        ratingLoadFailed = false

        db.collection("coaches")
            .document(coach.id)
            .getDocument { snapshot, error in

                DispatchQueue.main.async {

                    isLoadingRating = false

                    if error != nil {
                        ratingAverage = 0
                        ratingCount = 0
                        ratingLoadFailed = true
                        return
                    }

                    let data = snapshot?.data() ?? [:]

                    let count =
                        (data["ratingCount"] as? NSNumber)?.intValue ??
                        (data["reviewCount"] as? NSNumber)?.intValue ??
                        0

                    ratingCount = count

                    if count > 0 {
                        ratingAverage =
                            (data["ratingAverage"] as? NSNumber)?.doubleValue ??
                            (data["rating"] as? NSNumber)?.doubleValue ??
                            0
                    } else {
                        ratingAverage = 0
                    }

                }

            }

    }

    // MARK: - 共通Row

    func infoRow(icon: String, title: String) -> some View {

        HStack {

            Image(systemName: icon)
                .frame(width: 25)
                .foregroundStyle(.green)

            Text(title)

            Spacer()

        }

    }

}

#Preview {

    CoachHeaderView(
        coach: sampleCoaches[0]
    )

}
