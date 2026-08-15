import SwiftUI
import FirebaseFirestore

struct CoachScheduleSection: View {

    let coach: Coach

    @State private var schedule: [String: [String]] = [:]
    @State private var isLoading = false

    private let db = Firestore.firestore()

    private var sortedDates: [String] {
        schedule.keys.sorted()
    }

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

            Text("日付をタップすると空き時間が表示されます")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if isLoading {

                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 16)

            } else if sortedDates.isEmpty {

                Text("現在、予約できる空き日程はありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .center
                    )
                    .padding(.vertical, 16)

            } else {

                ForEach(sortedDates, id: \.self) { date in

                    DisclosureGroup {

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ],
                            spacing: 12
                        ) {
                            ForEach(
                                schedule[date] ?? [],
                                id: \.self
                            ) { time in
                                timeCard(time: time)
                            }
                        }
                        .padding(.top, 12)

                    } label: {

                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(.green)

                            Text(displayDate(from: date))
                                .font(.headline)

                            Spacer()

                            Text("\(schedule[date]?.count ?? 0)枠")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.green)
                    .padding(14)
                    .background(Color.white)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 14)
                    )
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onAppear {
            loadSchedule()
        }
    }

    private func loadSchedule() {

        isLoading = true

        db.collection("coachAvailability")
            .document(coach.id)
            .collection("dates")
            .getDocuments { snapshot, error in

                if let error = error {
                    print("空き日程取得エラー: \(error)")
                }

                let documents = snapshot?.documents ?? []
                let existingDates = Set(
                    documents.map { $0.documentID }
                )

                var loadedSchedule: [String: [String]] = [:]

                for document in documents {

                    let date = document.documentID
                    let times = document.data()["times"]
                        as? [String] ?? []

                    if date >= todayKey && !times.isEmpty {
                        loadedSchedule[date] = times.sorted()
                    }
                }

                loadLegacySchedule(
                    existingSchedule: loadedSchedule,
                    existingDates: existingDates
                )
            }
    }

    private func loadLegacySchedule(
        existingSchedule: [String: [String]],
        existingDates: Set<String>
    ) {

        db.collection("coaches")
            .document(coach.id)
            .getDocument { snapshot, error in

                if let error = error {
                    print("旧空き日程取得エラー: \(error)")
                }

                let entries = snapshot?.data()?["availableTimes"]
                    as? [String] ?? []

                let legacySchedule = makeLegacySchedule(
                    entries: entries
                )

                var mergedSchedule = existingSchedule

                for (date, times) in legacySchedule {

                    guard !existingDates.contains(date) else {
                        continue
                    }

                    mergedSchedule[date] = times

                    db.collection("coachAvailability")
                        .document(coach.id)
                        .collection("dates")
                        .document(date)
                        .setData(["times": times]) { error in

                            if let error = error {
                                print("空き日程移行エラー: \(error)")
                            }
                        }
                }

                finishLoading(schedule: mergedSchedule)
            }
    }

    private func makeLegacySchedule(
        entries: [String]
    ) -> [String: [String]] {

        var result: [String: [String]] = [:]

        for entry in entries {

            let parts = entry.split(
                separator: " ",
                maxSplits: 1
            )

            guard parts.count == 2 else {
                continue
            }

            let date = String(parts[0])
                .replacingOccurrences(of: "/", with: "-")

            guard date >= todayKey else {
                continue
            }

            let timeRange = String(parts[1])
                .replacingOccurrences(of: "~", with: "〜")

            guard let startTime = timeRange
                .components(separatedBy: "〜")
                .first,
                  !startTime.isEmpty else {
                continue
            }

            if !(result[date] ?? []).contains(startTime) {
                result[date, default: []].append(startTime)
            }
        }

        for date in Array(result.keys) {
            result[date]?.sort()
        }

        return result
    }

    private func finishLoading(
        schedule: [String: [String]]
    ) {

        DispatchQueue.main.async {
            self.schedule = schedule
            isLoading = false
        }
    }

    private var todayKey: String {

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        return formatter.string(
            from: Calendar.current.startOfDay(for: Date())
        )
    }

    private func displayDate(from date: String) -> String {
        date.replacingOccurrences(of: "-", with: "/")
    }

    private func timeCard(time: String) -> some View {

        HStack {

            VStack(alignment: .leading, spacing: 4) {
                Text(timeRange(from: time))
                    .font(.headline)

                Text("予約可能")
                    .font(.caption)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.green.opacity(0.10))
        .foregroundStyle(.primary)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func timeRange(from startTime: String) -> String {

        if startTime.contains("〜") || startTime.contains("~") {
            return startTime
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"

        guard
            let startDate = formatter.date(from: startTime),
            let endDate = Calendar.current.date(
                byAdding: .hour,
                value: 1,
                to: startDate
            )
        else {
            return startTime
        }

        return "\(startTime)〜\(formatter.string(from: endDate))"
    }
}

#Preview {
    CoachScheduleSection(
        coach: sampleCoaches[0]
    )
    .padding()
}
