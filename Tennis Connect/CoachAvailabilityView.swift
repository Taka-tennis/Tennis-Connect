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
    @State private var saveAlertMessage = ""

    // 日付ごとの未保存の選択内容。
    // 日付を移動してもここに保持し、最後にまとめて保存する。
    @State private var draftTimesByDate: [String: Set<String>] = [:]

    // 実際にユーザーが変更した日だけを保存対象にする。
    @State private var dirtyDateKeys: Set<String> = []

    @State private var isSameDayAvailable = false
    @State private var todayAvailableTimeCount = 0
    @State private var isLoadingSameDayStatus = false
    @State private var isUpdatingSameDayStatus = false
    @State private var sameDayErrorMessage = ""
    @State private var showSameDayAlert = false
    @State private var sameDayAlertMessage = ""

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
        firestoreDate(selectedDate)
    }

    private var todayKey: String {
        firestoreDate(Date())
    }

    private var displayDate: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: selectedDate)
    }

    var body: some View {
        Form {

            Section("本日のレッスン受付") {
                if isLoadingSameDayStatus {
                    HStack {
                        Spacer()
                        ProgressView("本日の受付状況を確認中…")
                        Spacer()
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(
                            systemName: isSameDayAvailable
                                ? "bolt.circle.fill"
                                : "bolt.circle"
                        )
                        .foregroundStyle(
                            isSameDayAvailable ? .green : .secondary
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(
                                isSameDayAvailable
                                    ? "本日レッスン可能として掲載中"
                                    : "本日の受付はOFFです"
                            )
                            .fontWeight(.semibold)

                            Text("現在の予約可能な空き枠：\(todayAvailableTimeCount)件")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        toggleSameDayAvailability()
                    } label: {
                        HStack {
                            Spacer()

                            if isUpdatingSameDayStatus {
                                ProgressView()
                            } else {
                                Image(
                                    systemName: isSameDayAvailable
                                        ? "stop.circle.fill"
                                        : "bolt.fill"
                                )

                                Text(
                                    isSameDayAvailable
                                        ? "本日の受付を終了する"
                                        : "本日レッスン可能にする"
                                )
                                .fontWeight(.semibold)
                            }

                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isSameDayAvailable ? .red : .green)
                    .disabled(
                        isUpdatingSameDayStatus ||
                        (!isSameDayAvailable && todayAvailableTimeCount == 0)
                    )

                    if todayAvailableTimeCount == 0 && !isSameDayAvailable {
                        Text("本日の空き時間を1枠以上登録すると受付をONにできます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(
                            "ONにした日だけ「本日レッスン可能コーチ」に掲載されます。日付が変わると自動的にOFF扱いになります。"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if !sameDayErrorMessage.isEmpty {
                    Text(sameDayErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

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
                if dirtyDateKeys.contains(formattedDate) {
                    Label(
                        "この日には未保存の変更があります",
                        systemImage: "pencil.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

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
                        } else if dirtyDateKeys.isEmpty {
                            Text("変更はありません")
                                .fontWeight(.semibold)
                        } else {
                            Text("\(dirtyDateKeys.count)日分の変更を保存")
                                .fontWeight(.semibold)
                        }

                        Spacer()
                    }
                }
                .disabled(
                    isLoading ||
                    isSaving ||
                    dirtyDateKeys.isEmpty
                )
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Text(
                    "日付を移動しても未保存の選択内容は保持されます。複数日を編集して、最後にまとめて保存できます。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

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
            loadSameDayAvailabilityState()
        }
        .onChange(of: selectedDate) { _ in
            loadAvailability()
        }
        .alert("保存完了", isPresented: $showSaveAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveAlertMessage)
        }
        .alert("本日の受付", isPresented: $showSameDayAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(sameDayAlertMessage)
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

        let dateKey = formattedDate

        // 日付を移動しても選択内容が消えないよう、
        // 変更のたびにその日の下書きを更新する。
        draftTimesByDate[dateKey] = selectedTimes
        dirtyDateKeys.insert(dateKey)
    }

    private func loadAvailability() {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "空き日程の確認にはログインが必要です"
            selectedTimes = []
            blockedTimes = []
            return
        }

        let requestedDateKey = formattedDate

        errorMessage = ""
        blockedTimes = []

        // すでにこの画面内で編集した日なら、Firestore読込中も
        // 下書きを先に表示して選択内容を消さない。
        if let draft = draftTimesByDate[requestedDateKey] {
            selectedTimes = draft
        } else {
            selectedTimes = []
        }

        isLoading = true

        let availabilityRef = db.collection("coachAvailability")
            .document(uid)
            .collection("dates")
            .document(requestedDateKey)

        availabilityRef.getDocument { availabilitySnapshot, availabilityError in
            if let availabilityError {
                DispatchQueue.main.async {
                    // すでに別の日へ移動していたら、
                    // 古い通信結果で現在画面を上書きしない。
                    guard formattedDate == requestedDateKey else {
                        return
                    }

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
                        guard formattedDate == requestedDateKey else {
                            return
                        }

                        isLoading = false

                        if let reservationError {
                            errorMessage =
                                "予約状況を取得できませんでした: " +
                                reservationError.localizedDescription
                            blockedTimes = []
                            return
                        }

                        let reservedTimes = blockedTimes(
                            for: requestedDateKey,
                            documents: reservationSnapshot?.documents ?? []
                        )

                        blockedTimes = reservedTimes

                        let safeSavedTimes =
                            Set(savedTimes)
                                .subtracting(reservedTimes)

                        // ユーザーがまだこの日を変更していなければ、
                        // Firestoreの最新値を下書きの初期値にする。
                        // 変更済みなら下書きを絶対に上書きしない。
                        if !dirtyDateKeys.contains(requestedDateKey) {
                            draftTimesByDate[requestedDateKey] =
                                safeSavedTimes
                        }

                        let draftTimes =
                            draftTimesByDate[requestedDateKey]
                            ?? safeSavedTimes

                        // 編集中に新しい予約が入っていた場合にも、
                        // 予約済み時間は選択状態から外す。
                        let safeDraftTimes =
                            draftTimes.subtracting(reservedTimes)

                        draftTimesByDate[requestedDateKey] =
                            safeDraftTimes
                        selectedTimes = safeDraftTimes
                        errorMessage = ""
                    }
                }
        }
    }

    private func loadSameDayAvailabilityState() {
        guard let uid = Auth.auth().currentUser?.uid else {
            sameDayErrorMessage = "本日の受付状況の確認にはログインが必要です"
            isSameDayAvailable = false
            todayAvailableTimeCount = 0
            return
        }

        isLoadingSameDayStatus = true
        sameDayErrorMessage = ""

        let dateKey = todayKey

        Task {
            do {
                let todayRef = db
                    .collection("coachAvailability")
                    .document(uid)
                    .collection("dates")
                    .document(dateKey)

                let todaySnapshot = try await todayRef.getDocument()

                let savedTimes =
                    todaySnapshot.data()?["times"] as? [String] ?? []

                let savedSameDayAvailable =
                    todaySnapshot.data()?["sameDayAvailable"] as? Bool ?? false

                let reservationSnapshot = try await db
                    .collection("reservations")
                    .whereField("coachId", isEqualTo: uid)
                    .getDocuments()

                let reservedTimes = blockedTimes(
                    for: dateKey,
                    documents: reservationSnapshot.documents
                )

                let actualAvailableTimes =
                    Set(savedTimes)
                        .subtracting(reservedTimes)
                        .filter { isFutureTimeSlot($0, dateKey: dateKey) }

                if savedSameDayAvailable && actualAvailableTimes.isEmpty {
                    try? await todayRef.setData(
                        ["sameDayAvailable": false],
                        merge: true
                    )
                }

                await MainActor.run {
                    todayAvailableTimeCount = actualAvailableTimes.count
                    isSameDayAvailable =
                        savedSameDayAvailable &&
                        !actualAvailableTimes.isEmpty
                    isLoadingSameDayStatus = false
                    sameDayErrorMessage = ""
                }

            } catch {
                await MainActor.run {
                    isLoadingSameDayStatus = false
                    isSameDayAvailable = false
                    todayAvailableTimeCount = 0
                    sameDayErrorMessage =
                        "本日の受付状況を取得できませんでした: " +
                        error.localizedDescription
                }
            }
        }
    }

    private func toggleSameDayAvailability() {
        guard let uid = Auth.auth().currentUser?.uid else {
            sameDayErrorMessage = "本日の受付設定にはログインが必要です"
            return
        }

        isUpdatingSameDayStatus = true
        sameDayErrorMessage = ""

        let dateKey = todayKey
        let todayRef = db
            .collection("coachAvailability")
            .document(uid)
            .collection("dates")
            .document(dateKey)

        if isSameDayAvailable {
            todayRef.setData(
                ["sameDayAvailable": false],
                merge: true
            ) { error in
                DispatchQueue.main.async {
                    isUpdatingSameDayStatus = false

                    if let error {
                        sameDayErrorMessage =
                            "本日の受付を終了できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    isSameDayAvailable = false
                    sameDayAlertMessage =
                        "「本日レッスン可能コーチ」への掲載を終了しました。"
                    showSameDayAlert = true
                }
            }

            return
        }

        Task {
            do {
                let todaySnapshot = try await todayRef.getDocument()

                let savedTimes =
                    todaySnapshot.data()?["times"] as? [String] ?? []

                let reservationSnapshot = try await db
                    .collection("reservations")
                    .whereField("coachId", isEqualTo: uid)
                    .getDocuments()

                let reservedTimes = blockedTimes(
                    for: dateKey,
                    documents: reservationSnapshot.documents
                )

                let actualAvailableTimes =
                    Set(savedTimes)
                        .subtracting(reservedTimes)
                        .filter { isFutureTimeSlot($0, dateKey: dateKey) }

                guard !actualAvailableTimes.isEmpty else {
                    await MainActor.run {
                        todayAvailableTimeCount = 0
                        isSameDayAvailable = false
                        isUpdatingSameDayStatus = false
                        sameDayErrorMessage =
                            "本日の予約可能な空き枠がありません。空き時間を登録してからONにしてください。"
                    }
                    return
                }

                try await todayRef.setData(
                    ["sameDayAvailable": true],
                    merge: true
                )

                await MainActor.run {
                    todayAvailableTimeCount = actualAvailableTimes.count
                    isSameDayAvailable = true
                    isUpdatingSameDayStatus = false
                    sameDayErrorMessage = ""
                    sameDayAlertMessage =
                        "本日の受付をONにしました。「本日レッスン可能コーチ」への掲載対象になります。"
                    showSameDayAlert = true
                }

            } catch {
                await MainActor.run {
                    isUpdatingSameDayStatus = false
                    sameDayErrorMessage =
                        "本日の受付設定を更新できませんでした: " +
                        error.localizedDescription
                }
            }
        }
    }

    private func blockedTimes(
        for dateKey: String,
        documents: [QueryDocumentSnapshot]
    ) -> Set<String> {
        var result: Set<String> = []

        for document in documents {
            let data = document.data()

            let reservationDate =
                (data["date"] as? String ?? "")
                    .replacingOccurrences(of: "/", with: "-")

            guard reservationDate == dateKey else {
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

        let dateKeysToSave =
            dirtyDateKeys.sorted()

        guard !dateKeysToSave.isEmpty else {
            return
        }

        // Firestoreの1バッチ上限に十分余裕を持たせる。
        // 通常利用では到達しないが、本番運用の安全策として制限する。
        guard dateKeysToSave.count <= 400 else {
            errorMessage =
                "一度に保存できる変更日数を超えています。400日以下に分けて保存してください。"
            return
        }

        errorMessage = ""
        isSaving = true

        Task {
            do {
                // 保存直前にも予約状況を再取得する。
                // 編集中に予約が入った場合でも予約枠を空き枠へ戻さない。
                let reservationSnapshot = try await db
                    .collection("reservations")
                    .whereField("coachId", isEqualTo: uid)
                    .getDocuments()

                let reservationDocuments =
                    reservationSnapshot.documents

                let batch = db.batch()

                var sanitizedDrafts:
                    [String: Set<String>] = [:]

                for dateKey in dateKeysToSave {
                    let latestBlockedTimes = blockedTimes(
                        for: dateKey,
                        documents: reservationDocuments
                    )

                    let draftTimes =
                        draftTimesByDate[dateKey] ?? []

                    let safeSelectedTimes =
                        draftTimes.subtracting(
                            latestBlockedTimes
                        )

                    sanitizedDrafts[dateKey] =
                        safeSelectedTimes

                    var updateData: [String: Any] = [
                        "times": safeSelectedTimes.sorted()
                    ]

                    // 今日の空き枠を0件にした場合だけ、
                    // 既存仕様どおり本日受付も自動OFFにする。
                    if dateKey == todayKey &&
                        safeSelectedTimes.isEmpty {
                        updateData["sameDayAvailable"] = false
                    }

                    let dateRef = db
                        .collection("coachAvailability")
                        .document(uid)
                        .collection("dates")
                        .document(dateKey)

                    batch.setData(
                        updateData,
                        forDocument: dateRef,
                        merge: true
                    )
                }

                // 変更した複数日を1回のバッチでまとめて保存する。
                try await batch.commit()

                await MainActor.run {
                    for (dateKey, safeTimes)
                        in sanitizedDrafts {
                        draftTimesByDate[dateKey] =
                            safeTimes
                    }

                    dirtyDateKeys.subtract(
                        Set(dateKeysToSave)
                    )

                    // 現在表示中の日も、保存直前の予約状況を反映する。
                    if let currentSavedTimes =
                        sanitizedDrafts[formattedDate] {
                        let currentBlockedTimes =
                            blockedTimes(
                                for: formattedDate,
                                documents:
                                    reservationDocuments
                            )

                        blockedTimes =
                            currentBlockedTimes

                        selectedTimes =
                            currentSavedTimes
                                .subtracting(
                                    currentBlockedTimes
                                )
                    }

                    isSaving = false
                    errorMessage = ""

                    if dateKeysToSave.count == 1,
                       let onlyDate = dateKeysToSave.first {
                        saveAlertMessage =
                            "\(displayDateString(from: onlyDate))の空き時間を保存しました"
                    } else {
                        saveAlertMessage =
                            "\(dateKeysToSave.count)日分の空き時間をまとめて保存しました"
                    }

                    showSaveAlert = true

                    if dateKeysToSave.contains(todayKey) {
                        loadSameDayAvailabilityState()
                    }
                }

            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage =
                        "保存できませんでした: " +
                        error.localizedDescription
                }
            }
        }
    }

    private func displayDateString(
        from dateKey: String
    ) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.calendar =
            Calendar(identifier: .gregorian)
        inputFormatter.locale =
            Locale(identifier: "en_US_POSIX")
        inputFormatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        inputFormatter.dateFormat = "yyyy-MM-dd"

        guard let date =
            inputFormatter.date(from: dateKey)
        else {
            return dateKey
        }

        let outputFormatter = DateFormatter()
        outputFormatter.calendar =
            Calendar(identifier: .gregorian)
        outputFormatter.locale =
            Locale(identifier: "ja_JP")
        outputFormatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        outputFormatter.dateFormat = "yyyy/MM/dd"

        return outputFormatter.string(from: date)
    }

    private func isFutureTimeSlot(
        _ value: String,
        dateKey: String
    ) -> Bool {
        guard let start = startTime(from: value) else {
            return false
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        guard let slotDate = formatter.date(
            from: "\(dateKey) \(start)"
        ) else {
            return false
        }

        return slotDate > Date()
    }

    private func firestoreDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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
