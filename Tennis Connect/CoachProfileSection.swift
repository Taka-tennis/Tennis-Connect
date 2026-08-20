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
                value: displayValue(coach.ageGroup)
            )

            profileRow(
                icon: "tennis.racket",
                title: "テニス歴",
                value: displayValue(
                    coach.tennisExperience
                )
            )

            profileRow(
                icon: "figure.tennis",
                title: "指導歴",
                value: displayValue(
                    coach.coachingExperience
                )
            )

            Divider()

            VStack(alignment: .leading, spacing: 12) {

                Label(
                    "経歴",
                    systemImage: "trophy.fill"
                )
                .font(.headline)
                .foregroundStyle(.primary)

                ForEach(
                    Array(displayedCareers.enumerated()),
                    id: \.offset
                ) { _, career in
                    HStack(
                        alignment: .top,
                        spacing: 10
                    ) {
                        Image(
                            systemName:
                                career == "未登録"
                                    ? "minus.circle"
                                    : "checkmark.circle.fill"
                        )
                        .foregroundColor(
                            career == "未登録"
                                ? Color.secondary
                                : Color.green
                        )
                        .padding(.top, 2)

                        Text(career)
                            .foregroundColor(
                                career == "未登録"
                                    ? Color.secondary
                                    : Color.primary
                            )
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )

                        Spacer()
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {

                Text("自己紹介")
                    .font(.headline)

                Text(
                    introductionText
                )
                .foregroundStyle(.secondary)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
                .lineSpacing(5)
            }
        }
        .padding(20)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(Color(.systemGray6))
        .clipShape(
            RoundedRectangle(cornerRadius: 20)
        )
    }

    private var displayedCareers: [String] {
        let cleaned = coach.careers
            .map {
                $0.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
            .filter {
                !$0.isEmpty &&
                $0 != "経歴未登録"
            }

        return cleaned.isEmpty
            ? ["未登録"]
            : cleaned
    }

    private var introductionText: String {
        let value =
            coach.introduction.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        return value.isEmpty
            ? "自己紹介はまだありません。"
            : value
    }

    private func displayValue(
        _ value: String
    ) -> String {
        let trimmed =
            value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if trimmed.isEmpty ||
            trimmed == "年代未登録" ||
            trimmed == "未登録" {
            return "未登録"
        }

        return trimmed
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
