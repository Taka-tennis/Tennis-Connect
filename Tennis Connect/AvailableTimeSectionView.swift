import SwiftUI
import Foundation

struct AvailableTimeSectionView: View {

    let timeSlots: [String]

    @Binding var selectedLessonTimes: [String]
    @Binding var availableTimes: String

    @State private var showAvailabilityPicker = false

    private var hourlyTimeSlots: [String] {

        let filteredTimes = timeSlots.filter {
            $0.hasSuffix(":00")
        }

        if filteredTimes.isEmpty {
            return (9...21).map {
                String(format: "%02d:00", $0)
            }
        }

        return filteredTimes
    }

    private var groupedDates: [String] {

        let dates = selectedLessonTimes.map {
            datePart(from: $0)
        }

        return Array(Set(dates)).sorted()
    }

    var body: some View {

        Section("空き時間") {

            Button {
                showAvailabilityPicker = true
            } label: {

                HStack {

                    Image(systemName: "calendar.badge.plus")
                        .foregroundColor(.green)

                    Text("空き日時を追加")

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(.plain)

            if selectedLessonTimes.isEmpty {

                Text("空き日時が登録されていません")
                    .foregroundColor(.gray)

            } else {

                ForEach(groupedDates, id: \.self) { date in

                    DisclosureGroup {

                        ForEach(
                            lessonTimes(for: date),
                            id: \.self
                        ) { lessonTime in

                            HStack {

                                Image(systemName: "clock")
                                    .foregroundColor(.green)

                                Text(timePart(from: lessonTime))

                                Spacer()

                                Button {
                                    selectedLessonTimes.removeAll {
                                        $0 == lessonTime
                                    }
                                    updateAvailableTimes()
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.leading, 8)
                        }

                    } label: {

                        HStack {

                            Image(systemName: "calendar")
                                .foregroundColor(.green)

                            Text(date)
                                .font(.headline)

                            Spacer()

                            Text(
                                "\(lessonTimes(for: date).count)枠"
                            )
                            .font(.caption)
                            .foregroundColor(.gray)
                        }
                    }
                    .tint(.green)
                }
            }
        }
        .sheet(isPresented: $showAvailabilityPicker) {

            AvailabilityPickerFlowView(
                timeSlots: hourlyTimeSlots
            ) { date, selectedTimes in

                addAvailability(
                    date: date,
                    selectedTimes: selectedTimes
                )
            }
        }
    }

    private func lessonTimes(
        for date: String
    ) -> [String] {

        selectedLessonTimes
            .filter {
                datePart(from: $0) == date
            }
            .sorted()
    }

    private func datePart(
        from lessonTime: String
    ) -> String {

        guard let spaceIndex =
                lessonTime.firstIndex(of: " ") else {
            return lessonTime
        }

        return String(
            lessonTime[..<spaceIndex]
        )
    }

    private func timePart(
        from lessonTime: String
    ) -> String {

        guard let spaceIndex =
                lessonTime.firstIndex(of: " ") else {
            return lessonTime
        }

        let timeStartIndex =
            lessonTime.index(after: spaceIndex)

        return String(
            lessonTime[timeStartIndex...]
        )
    }

    private func addAvailability(
        date: Date,
        selectedTimes: Set<String>
    ) {

        for time in selectedTimes {

            guard let lessonTime = makeLessonTime(
                date: date,
                time: time
            ) else {
                continue
            }

            if !selectedLessonTimes.contains(lessonTime) {
                selectedLessonTimes.append(lessonTime)
            }
        }

        selectedLessonTimes.sort()
        updateAvailableTimes()
    }

    private func makeLessonTime(
        date: Date,
        time: String
    ) -> String? {

        let timeFormatter = DateFormatter()
        timeFormatter.locale =
            Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"

        guard
            let startDate = timeFormatter.date(from: time),
            let endDate = Calendar.current.date(
                byAdding: .hour,
                value: 1,
                to: startDate
            )
        else {
            return nil
        }

        let endTime =
            timeFormatter.string(from: endDate)

        let dateFormatter = DateFormatter()
        dateFormatter.locale =
            Locale(identifier: "ja_JP")
        dateFormatter.dateFormat = "yyyy/MM/dd"

        let dateText =
            dateFormatter.string(from: date)

        return "\(dateText) \(time)〜\(endTime)"
    }

    private func updateAvailableTimes() {

        availableTimes =
            selectedLessonTimes.joined(separator: ",")
    }
}


struct AvailabilityPickerFlowView: View {

    let timeSlots: [String]
    let onConfirm: (Date, Set<String>) -> Void

    @State private var selectedDate =
        Calendar.current.startOfDay(for: Date())

    @State private var selectedTimes: Set<String> = []

    @Environment(\.dismiss) private var dismiss

    var body: some View {

        NavigationStack {

            VStack(spacing: 20) {

                Text("日付を選択してください")
                    .font(.headline)

                Text(formattedDate(selectedDate))
                    .font(.title2)
                    .bold()
                    .foregroundColor(.green)

                DatePicker(
                    "",
                    selection: $selectedDate,
                    in: Calendar.current.startOfDay(for: Date())...,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(
                    \.locale,
                    Locale(identifier: "ja_JP")
                )

                Spacer()

                NavigationLink {

                    AvailabilityTimePickerView(
                        date: selectedDate,
                        timeSlots: timeSlots,
                        selectedTimes: $selectedTimes
                    ) {
                        onConfirm(
                            selectedDate,
                            selectedTimes
                        )
                        dismiss()
                    }

                } label: {

                    Text("この日付の時間を選ぶ")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
            }
            .padding()
            .navigationTitle("日付を選ぶ")
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {

                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"

        return formatter.string(from: date)
    }
}


struct AvailabilityTimePickerView: View {

    let date: Date
    let timeSlots: [String]

    @Binding var selectedTimes: Set<String>

    let onConfirm: () -> Void

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {

        VStack(spacing: 16) {

            Text(formattedDate(date))
                .font(.title3)
                .bold()

            ScrollView {

                LazyVGrid(
                    columns: columns,
                    spacing: 12
                ) {

                    ForEach(timeSlots, id: \.self) { time in

                        Button {

                            if selectedTimes.contains(time) {
                                selectedTimes.remove(time)
                            } else {
                                selectedTimes.insert(time)
                            }

                        } label: {

                            Text(
                                "\(time)〜\(endTime(from: time))"
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                selectedTimes.contains(time)
                                ? Color.green
                                : Color(.systemGray6)
                            )
                            .foregroundColor(
                                selectedTimes.contains(time)
                                ? .white
                                : .primary
                            )
                            .cornerRadius(12)
                        }
                    }
                }
                .padding()
            }

            Button {
                onConfirm()
            } label: {

                Text("選択した時間を確定")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        selectedTimes.isEmpty
                        ? Color.gray
                        : Color.green
                    )
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .disabled(selectedTimes.isEmpty)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationTitle("時間を選ぶ")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func formattedDate(_ date: Date) -> String {

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"

        return formatter.string(from: date)
    }

    private func endTime(from startTime: String) -> String {

        let formatter = DateFormatter()
        formatter.locale =
            Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"

        guard
            let startDate = formatter.date(from: startTime),
            let endDate = Calendar.current.date(
                byAdding: .hour,
                value: 1,
                to: startDate
            )
        else {
            return ""
        }

        return formatter.string(from: endDate)
    }
}
