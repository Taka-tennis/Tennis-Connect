import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct CoachAvailabilityView: View {

    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var selectedTimes: Set<String> = []
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
                        Button {
                            toggleTime(time)
                        } label: {
                            HStack {
                                Text("\(time)〜\(endTime(for: time))")
                                    .foregroundStyle(.primary)

                                Spacer()

                                Image(
                                    systemName: selectedTimes.contains(time)
                                    ? "checkmark.circle.fill"
                                    : "plus.circle.fill"
                                )
                                .foregroundStyle(
                                    selectedTimes.contains(time)
                                    ? .blue
                                    : .green
                                )
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if selectedTimes.isEmpty && !isLoading {
                    Text("この日の空き時間は登録されていません")
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
            return
        }

        errorMessage = ""
        selectedTimes = []
        isLoading = true

        db.collection("coachAvailability")
            .document(uid)
            .collection("dates")
            .document(formattedDate)
            .getDocument { snapshot, error in
                DispatchQueue.main.async {
                    isLoading = false

                    if let error = error {
                        errorMessage =
                            "空き時間を取得できませんでした: \(error.localizedDescription)"
                        return
                    }

                    let times = snapshot?.data()?["times"] as? [String] ?? []
                    selectedTimes = Set(times)
                }
            }
    }

    private func saveAvailability() {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "空き日程の保存にはログインが必要です"
            return
        }

        errorMessage = ""
        isSaving = true

        db.collection("coachAvailability")
            .document(uid)
            .collection("dates")
            .document(formattedDate)
            .setData(["times": selectedTimes.sorted()]) { error in
                DispatchQueue.main.async {
                    isSaving = false

                    if let error = error {
                        errorMessage =
                            "保存できませんでした: \(error.localizedDescription)"
                        return
                    }

                    showSaveAlert = true
                }
            }
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
