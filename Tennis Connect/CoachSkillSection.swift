import SwiftUI

struct CoachSkillSection: View {

    private let skills = [
        Skill(name: "サーブ", rating: 5),
        Skill(name: "ストローク", rating: 5),
        Skill(name: "ボレー", rating: 4),
        Skill(name: "ダブルス", rating: 4)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {

            HStack(spacing: 8) {
                Image(systemName: "figure.tennis")
                    .foregroundStyle(.green)

                Text("得意分野")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            ForEach(skills) { skill in
                skillRow(skill)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func skillRow(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 8) {

            HStack {
                Text(skill.name)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(skill.rating).0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 5) {
                ForEach(1...5, id: \.self) { number in
                    Image(
                        systemName: number <= skill.rating
                        ? "circle.fill"
                        : "circle"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        number <= skill.rating
                        ? .green
                        : .gray.opacity(0.4)
                    )
                }
            }
        }
    }
}

private struct Skill: Identifiable {
    let id = UUID()
    let name: String
    let rating: Int
}

#Preview {
    CoachSkillSection()
        .padding()
}
