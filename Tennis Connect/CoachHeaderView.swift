import SwiftUI

struct CoachHeaderView: View {

    let coach: Coach

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

            HStack(spacing: 4) {

                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)

                Text("4.9")
                    .fontWeight(.bold)

                Text("(128件)")
                    .foregroundStyle(.secondary)

            }

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
