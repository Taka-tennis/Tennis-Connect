import SwiftUI

struct CoachProfileSection: View {

    let coach: Coach

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            Text("プロフィール")
                .font(.title2)
                .fontWeight(.bold)

            profileRow(
                icon: "person.fill",
                title: "年代",
                value: coach.ageGroup
            )

            profileRow(
                icon: "tennis.racket",
                title: "テニス歴",
                value: coach.tennisExperience
            )

            profileRow(
                icon: "figure.tennis",
                title: "指導歴",
                value: coach.coachingExperience
            )

            Divider()

            VStack(alignment: .leading, spacing: 12) {

                Label("経歴", systemImage: "trophy.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)

                ForEach(coach.careers, id: \.self) { career in
                    HStack(alignment: .top, spacing: 10) {

                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .padding(.top, 2)

                        Text(career)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer()
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {

                Text("自己紹介")
                    .font(.headline)

                Text(coach.introduction)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(5)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func profileRow(
        icon: String,
        title: String,
        value: String
    ) -> some View {

        HStack(spacing: 12) {

            Image(systemName: icon)
                .foregroundStyle(.green)
                .frame(width: 24)

            Text(title)
                .fontWeight(.semibold)

            Spacer()

            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    CoachProfileSection(
        coach: sampleCoaches[0]
    )
}
