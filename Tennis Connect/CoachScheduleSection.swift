import SwiftUI

struct CoachScheduleSection: View {

    let coach: Coach

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {

            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.green)

                Text("空き時間")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()
            }

            Text("予約したい時間を選んでください")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: 12
            ) {
                ForEach(coach.availableTimes, id: \.0) { time in
                    timeCard(
                        time: time.0,
                        isAvailable: time.1
                    )
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func timeCard(
        time: String,
        isAvailable: Bool
    ) -> some View {

        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(time)
                    .font(.headline)

                Text(isAvailable ? "予約可能" : "予約済み")
                    .font(.caption)
            }

            Spacer()

            Image(
                systemName: isAvailable
                ? "checkmark.circle.fill"
                : "xmark.circle.fill"
            )
            .foregroundStyle(
                isAvailable
                ? .green
                : .secondary
            )
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            isAvailable
            ? Color.green.opacity(0.10)
            : Color.gray.opacity(0.12)
        )
        .foregroundStyle(
            isAvailable
            ? .primary
            : .secondary
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    CoachScheduleSection(
        coach: sampleCoaches[0]
    )
    .padding()
}
