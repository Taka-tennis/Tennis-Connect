import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct CoachAvailabilityView: View {

    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var selectedTimes: Set<String> = []
    @State private var blockedTimes: Set<String> = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var showSaveAlert = false

    private let db = Firestore.firestore()

    private let timeSlots = [
        "09:00", "10:00", "11:00",
        "12:00", "13:00", "14:00",
        "15:00", "16:00", "17:00",
        "18:00", "19:00", "20:00",
        "21:00"
    ]

    private let blockingReservationStatuses: Set<String> = [
        "pending",
        "confirmed",
        "paid",
        "reserved"
    ]

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: selectedDate)
    }

    private var displayDate: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: selectedDate)
    }

    var body: some View {
        Form {
            Section("日付") {
                DatePicker(
                    "日付を選択",
                    selection: $selectedDate,
                    in: Calendar.current.startOfDay(for: Date())...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .environment(\.locale, Locale(identifier: "ja_JP"))
            }

            Section("\(displayDate)の空き時間") {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("読み込み中…")
                        Spacer()
                    }
                } else {
                    ForEach(timeSlots, id: \.self) { time in
                        let isBlocked = blockedTimes.contains(time)
                        let isSelected = selectedTimes.contains(time)

                        Button {
                            toggleTime(time)
                        } label: {
                            HStack {
                                Text("\(time)〜\(endTime(for: time))")
                                    .foregroundStyle(
                                        isBlocked ? .secondary : .primary
                                    )

                                Spacer()

                                if isBlocked {
                                    HStack(spacing: 5) {
                                        Image(systemName: "lock.fill")
                                        Text("予約あり")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                } else {
                                    Image(
                                        systemName: isSelected
                                        ? "checkmark.circle.fill"
                                        : "plus.circle.fill"
                                    )
                                    .foregroundStyle(
                                        isSelected ? .blue : .green
                                    )
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isBlocked)
                        .opacity(isBlocked ? 0.55 : 1)
                    }
                }

                if selectedTimes.isEmpty &&
                    blockedTimes.isEmpty &&
                    !isLoading {
                    Text("この日の空き時間は登録されていません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !blockedTimes.isEmpty && !isLoading {
                    Text("予約申請中・承認済み・支払い済みの時間は変更できません")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    saveAvailability()
                } label: {
                    HStack {
                        Spacer()

                        if isSaving {
                            ProgressView()
                        } else {
                            Text("この日程を保存")
                                .fontWeight(.semibold)
                        }

                        Spacer()
                    }
                }
                .disabled(isLoading || isSaving)
                .buttonStyle(.borderedProminent)
                .tint(.green)

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("空き日程管理")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadAvailability()
        }
        .onChange(of: selectedDate) { _ in
            loadAvailability()
        }
        .alert("保存完了", isPresented: $showSaveAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(displayDate)の空き時間を保存しました")
        }
    }

    private func toggleTime(_ time: String) {
        guard !blockedTimes.contains(time) else {
            return
        }

        if selectedTimes.contains(time) {
            selectedTimes.remove(time)
        } else {
            selectedTimes.insert(time)
        }
    }

    private func loadAvailability() {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "空き日程の確認にはログインが必要です"
            selectedTimes = []
            blockedTimes = []
            return
        }

        errorMessage = ""
        selectedTimes = []
        blockedTimes = []
        isLoading = true

        let availabilityRef = db.collection("coachAvailability")
            .document(uid)
            .collection("dates")
            .document(formattedDate)

        availabilityRef.getDocument { availabilitySnapshot, availabilityError in
            if let availabilityError {
                DispatchQueue.main.async {
                    isLoading = false
                    errorMessage =
                        "空き時間を取得できませんでした: " +
                        availabilityError.localizedDescription
                }
                return
            }

            let savedTimes =
                availabilitySnapshot?.data()?["times"] as? [String] ?? []

            db.collection("reservations")
                .whereField("coachId", isEqualTo: uid)
                .getDocuments { reservationSnapshot, reservationError in
                    DispatchQueue.main.async {
                        isLoading = false

                        if let reservationError {
                            errorMessage =
                                "予約状況を取得できませんでした: " +
                                reservationError.localizedDescription
                            selectedTimes = []
                            blockedTimes = []
                            return
                        }

                        let reservedTimes = blockedTimesForSelectedDate(
                            reservationSnapshot?.documents ?? []
                        )

                        blockedTimes = reservedTimes

                        // 以前に誤って空き枠へ戻された予約済み時間があっても、
                        // 画面上では空き時間として選択しない。
                        selectedTimes =
                            Set(savedTimes)
                            .subtracting(reservedTimes)

                        errorMessage = ""
                    }
                }
        }
    }

    private func blockedTimesForSelectedDate(
        _ documents: [QueryDocumentSnapshot]
    ) -> Set<String> {
        var result: Set<String> = []

        for document in documents {
            let data = document.data()

            let reservationDate =
                (data["date"] as? String ?? "")
                .replacingOccurrences(of: "/", with: "-")

            guard reservationDate == formattedDate else {
                continue
            }

            let status = data["status"] as? String ?? ""

            guard blockingReservationStatuses.contains(status) else {
                continue
            }

            let savedTimes = data["times"] as? [String] ?? []
            let legacyTime = data["time"] as? String ?? ""

            let reservationTimes =
                savedTimes.isEmpty
                ? (legacyTime.isEmpty ? [] : [legacyTime])
                : savedTimes

            for value in reservationTimes {
                if let startTime = startTime(from: value) {
                    result.insert(startTime)
                }
            }
        }

        return result
    }

    private func saveAvailability() {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "空き日程の保存にはログインが必要です"
            return
        }

        errorMessage = ""
        isSaving = true

        // UIだけでなく保存時にも予約済み枠を必ず除外する。
        let safeSelectedTimes =
            selectedTimes.subtracting(blockedTimes)

        db.collection("coachAvailability")
            .document(uid)
            .collection("dates")
            .document(formattedDate)
            .setData(["times": safeSelectedTimes.sorted()]) { error in
                DispatchQueue.main.async {
                    isSaving = false

                    if let error {
                        errorMessage =
                            "保存できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    selectedTimes = safeSelectedTimes
                    showSaveAlert = true
                }
            }
    }

    private func startTime(from value: String) -> String? {
        let normalized =
            value.replacingOccurrences(of: "~", with: "〜")

        let firstPart =
            normalized
                .components(separatedBy: "〜")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""

        guard !firstPart.isEmpty else {
            return nil
        }

        return firstPart
    }

    private func endTime(for startTime: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"

        guard let startDate = formatter.date(from: startTime),
              let endDate = Calendar.current.date(
                byAdding: .hour,
                value: 1,
                to: startDate
              ) else {
            return startTime
        }

        return formatter.string(from: endDate)
    }
}

#Preview {
    NavigationStack {
        CoachAvailabilityView()
    }
}
