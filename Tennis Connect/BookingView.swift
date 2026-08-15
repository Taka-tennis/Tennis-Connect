import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct BookingView: View {
    @State private var lessonDate = Date()
    @State private var selectedTimes: Set<String> = []
    @State private var showConfirm = false
    @State private var showLogin = false
    @State private var availableTimes: [String] = []
    @State private var selectionMessage = ""
    @State private var loadErrorMessage = ""

    let coach: Coach

    private let db = Firestore.firestore()

    private var sortedSelectedTimes: [String] {
        selectedTimes.sorted()
    }

    private var totalPrice: Int {
        coach.price * selectedTimes.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 25) {
                    AsyncImage(url: URL(string: coach.imageURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .cornerRadius(15)

                    Text(coach.name)
                        .font(.largeTitle)
                        .bold()

                    Text(coach.careers.first ?? "経歴未登録")
                        .font(.headline)

                    Text(coach.area)

                    Text("1時間 ¥\(coach.price)")
                        .font(.title2)
                        .bold()

                    Text("🎾 レッスン予約")
                        .font(.largeTitle)
                        .bold()

                    DatePicker(
                        "日付",
                        selection: $lessonDate,
                        in: Calendar.current.startOfDay(for: Date())...,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .environment(\.locale, Locale(identifier: "ja_JP"))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("⏰ 空き時間")
                            .font(.title3)
                            .bold()

                        Text("連続した時間を複数選択できます")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if availableTimes.isEmpty {
                            Text("この日の空き時間はありません")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 12)
                        } else {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ],
                                spacing: 12
                            ) {
                                ForEach(availableTimes, id: \.self) { time in
                                    Button {
                                        toggleTime(time)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(timeRange(from: time))
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.8)

                                            if selectedTimes.contains(time) {
                                                Image(systemName: "checkmark.circle.fill")
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
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
                        }

                        if !selectionMessage.isEmpty {
                            Text(selectionMessage)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        if !loadErrorMessage.isEmpty {
                            Text(loadErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(18)
                    .shadow(color: .black.opacity(0.08), radius: 2)

                    if !selectedTimes.isEmpty {
                        VStack(spacing: 12) {
                            HStack {
                                Text("選択時間")
                                Spacer()
                                Text(combinedTimeRange(sortedSelectedTimes))
                                    .bold()
                            }

                            HStack {
                                Text("レッスン時間")
                                Spacer()
                                Text("\(selectedTimes.count)時間")
                                    .bold()
                            }

                            Divider()

                            HStack {
                                Text("合計料金")
                                    .font(.headline)
                                Spacer()
                                Text("¥\(totalPrice)")
                                    .font(.title2)
                                    .bold()
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(16)
                    }

                    Button {
                        continueToConfirmation()
                    } label: {
                        Text("予約内容を確認")
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

                    Spacer()
                }
                .padding()
                .navigationDestination(isPresented: $showConfirm) {
                    BookingConfirmView(
                        coach: coach,
                        date: lessonDate,
                        times: sortedSelectedTimes
                    )
                }
                .sheet(isPresented: $showLogin) {
                    LoginView {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showConfirm = true
                        }
                    }
                }
                .onAppear {
                    loadAvailableTimes()
                }
                .onChange(of: lessonDate) { _ in
                    loadAvailableTimes()
                }
            }
        }
    }

    private func continueToConfirmation() {
        if Auth.auth().currentUser == nil {
            showLogin = true
        } else {
            showConfirm = true
        }
    }

    private func toggleTime(_ time: String) {
        var candidate = selectedTimes

        if candidate.contains(time) {
            candidate.remove(time)
        } else {
            candidate.insert(time)
        }

        guard isConsecutive(candidate.sorted()) else {
            selectionMessage = "同じ予約では、連続した時間だけ選択できます"
            return
        }

        selectedTimes = candidate
        selectionMessage = ""
    }

    private func isConsecutive(_ times: [String]) -> Bool {
        guard times.count > 1 else {
            return true
        }

        let formatter = timeFormatter()

        for index in 1..<times.count {
            guard let previous = formatter.date(from: times[index - 1]),
                  let current = formatter.date(from: times[index]) else {
                return false
            }

            if current.timeIntervalSince(previous) != 60 * 60 {
                return false
            }
        }

        return true
    }

    private func loadAvailableTimes() {
        selectedTimes = []
        selectionMessage = ""
        loadErrorMessage = ""

        let formattedDate = firestoreDate(from: lessonDate)

        let dateRef = db.collection("coachAvailability")
            .document(coach.id)
            .collection("dates")
            .document(formattedDate)

        dateRef.getDocument { snapshot, error in
            if let error = error {
                DispatchQueue.main.async {
                    loadErrorMessage =
                        "空き時間を取得できませんでした: \(error.localizedDescription)"
                }
                return
            }

            if snapshot?.exists == true {
                let times = snapshot?.data()?["times"] as? [String] ?? []
                finishLoading(times: times)
            } else {
                loadLegacyAvailableTimes(
                    formattedDate: formattedDate,
                    dateRef: dateRef
                )
            }
        }
    }

    private func loadLegacyAvailableTimes(
        formattedDate: String,
        dateRef: DocumentReference
    ) {
        db.collection("coaches")
            .document(coach.id)
            .getDocument { snapshot, error in
                if let error = error {
                    print("旧空き時間取得エラー: \(error)")
                }

                let entries = snapshot?.data()?["availableTimes"] as? [String] ?? []
                let times = legacyStartTimes(
                    entries: entries,
                    formattedDate: formattedDate
                )

                if !times.isEmpty {
                    dateRef.setData(["times": times]) { error in
                        if let error = error {
                            print("空き時間移行エラー: \(error)")
                        }
                    }
                }

                finishLoading(times: times)
            }
    }

    private func legacyStartTimes(
        entries: [String],
        formattedDate: String
    ) -> [String] {
        let displayDate = formattedDate
            .replacingOccurrences(of: "-", with: "/")

        return entries.compactMap { entry in
            guard entry.hasPrefix("\(displayDate) "),
                  let spaceIndex = entry.firstIndex(of: " ") else {
                return nil
            }

            let rangeStart = entry.index(after: spaceIndex)
            let range = String(entry[rangeStart...])
                .replacingOccurrences(of: "~", with: "〜")

            return range.components(separatedBy: "〜").first
        }
        .filter { !$0.isEmpty }
        .sorted()
    }

    private func finishLoading(times: [String]) {
        DispatchQueue.main.async {
            availableTimes = Array(Set(times)).sorted()
        }
    }

    private func firestoreDate(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func timeRange(from startTime: String) -> String {
        if startTime.contains("〜") || startTime.contains("~") {
            return startTime.replacingOccurrences(of: "~", with: "〜")
        }

        guard let startDate = timeFormatter().date(from: startTime),
              let endDate = Calendar.current.date(
                byAdding: .hour,
                value: 1,
                to: startDate
              ) else {
            return startTime
        }

        return "\(startTime)〜\(timeFormatter().string(from: endDate))"
    }

    private func combinedTimeRange(_ times: [String]) -> String {
        guard let first = times.first,
              let last = times.last else {
            return ""
        }

        let lastRange = timeRange(from: last)
        let end = lastRange.components(separatedBy: "〜").last ?? last
        return "\(first)〜\(end)"
    }

    private func timeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }
}

#Preview {
    BookingView(coach: sampleCoaches[0])
}
