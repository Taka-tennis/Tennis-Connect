import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

private enum CoachAvailabilityUI {
    static let brandGreen = Color(
        red: 42 / 255,
        green: 174 / 255,
        blue: 102 / 255
    )

    static let softGreen = Color(
        red: 232 / 255,
        green: 245 / 255,
        blue: 236 / 255
    )

    static let background = Color(
        red: 248 / 255,
        green: 250 / 255,
        blue: 249 / 255
    )

    static let textPrimary = Color(
        red: 34 / 255,
        green: 34 / 255,
        blue: 34 / 255
    )

    static let textSecondary = Color(
        red: 102 / 255,
        green: 110 / 255,
        blue: 105 / 255
    )

    static let border = Color.black.opacity(0.08)
}

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
    private let functions = Functions.functions(
        region: "asia-northeast1"
    )

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
        "approved",
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
        ZStack {
            CoachAvailabilityUI.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    VStack(alignment: .leading, spacing: 5) {
                        Text("空き日程管理")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(
                                CoachAvailabilityUI.textPrimary
                            )

                        Text("受付できる日時をまとめて設定できます")
                            .font(.subheadline)
                            .foregroundStyle(
                                CoachAvailabilityUI.textSecondary
                            )
                    }

                    sameDayStatusCard

                    dateSelectionCard

                    availabilityTimeCard

                    saveCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .tint(CoachAvailabilityUI.brandGreen)
        .navigationTitle("空き日程")
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

    private var sameDayStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {

            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            isSameDayAvailable
                                ? CoachAvailabilityUI.softGreen
                                : Color(.systemGray6)
                        )
                        .frame(width: 42, height: 42)

                    Image(
                        systemName:
                            isSameDayAvailable
                                ? "bolt.fill"
                                : "bolt"
                    )
                    .font(
                        .system(
                            size: 17,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        isSameDayAvailable
                            ? CoachAvailabilityUI.brandGreen
                            : CoachAvailabilityUI.textSecondary
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("本日のレッスン受付")
                        .font(.headline)
                        .foregroundStyle(
                            CoachAvailabilityUI.textPrimary
                        )

                    if isLoadingSameDayStatus {
                        Text("本日の受付状況を確認中…")
                            .font(.caption)
                            .foregroundStyle(
                                CoachAvailabilityUI.textSecondary
                            )
                    } else {
                        Text(
                            "現在の予約可能な空き枠：\(todayAvailableTimeCount)件"
                        )
                        .font(.caption)
                        .foregroundStyle(
                            CoachAvailabilityUI.textSecondary
                        )
                    }
                }

                Spacer()

                if !isLoadingSameDayStatus {
                    Text(
                        isSameDayAvailable
                            ? "受付中"
                            : "停止中"
                    )
                    .font(
                        .system(
                            size: 12,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        isSameDayAvailable
                            ? CoachAvailabilityUI.brandGreen
                            : CoachAvailabilityUI.textSecondary
                    )
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        isSameDayAvailable
                            ? CoachAvailabilityUI.softGreen
                            : Color(.systemGray6)
                    )
                    .clipShape(Capsule())
                }
            }

            if isLoadingSameDayStatus {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(height: 46)
            } else {
                Button {
                    toggleSameDayAvailability()
                } label: {
                    HStack(spacing: 8) {
                        Spacer()

                        if isUpdatingSameDayStatus {
                            ProgressView()
                        } else {
                            Image(
                                systemName:
                                    isSameDayAvailable
                                        ? "stop.circle"
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
                    .frame(height: 46)
                    .foregroundStyle(
                        isSameDayAvailable
                            ? Color.red
                            : Color.white
                    )
                    .background(
                        isSameDayAvailable
                            ? Color.white
                            : CoachAvailabilityUI.brandGreen
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                        .stroke(
                            isSameDayAvailable
                                ? Color.red.opacity(0.45)
                                : Color.clear,
                            lineWidth: 1
                        )
                    }
                }
                .buttonStyle(.plain)
                .disabled(
                    isUpdatingSameDayStatus ||
                    (!isSameDayAvailable &&
                     todayAvailableTimeCount == 0)
                )
                .opacity(
                    isUpdatingSameDayStatus ||
                    (!isSameDayAvailable &&
                     todayAvailableTimeCount == 0)
                        ? 0.55
                        : 1
                )

                if todayAvailableTimeCount == 0 &&
                    !isSameDayAvailable {
                    Text(
                        "本日の空き時間を1枠以上登録すると受付をONにできます。"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        CoachAvailabilityUI.textSecondary
                    )
                } else {
                    Text(
                        "ONにした日だけ「本日レッスン可能コーチ」に掲載されます。日付が変わると自動的にOFF扱いになります。"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        CoachAvailabilityUI.textSecondary
                    )
                }
            }

            if !sameDayErrorMessage.isEmpty {
                Text(sameDayErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                isSameDayAvailable
                    ? CoachAvailabilityUI.brandGreen.opacity(0.22)
                    : CoachAvailabilityUI.border,
                lineWidth: 1
            )
        }
    }

    private var dateSelectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(
                        .system(
                            size: 16,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        CoachAvailabilityUI.brandGreen
                    )

                Text("日付を選択")
                    .font(.headline)
                    .foregroundStyle(
                        CoachAvailabilityUI.textPrimary
                    )
            }

            DatePicker(
                "",
                selection: $selectedDate,
                in: Calendar.current.startOfDay(for: Date())...,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.graphical)
            .environment(
                \.locale,
                Locale(identifier: "ja_JP")
            )
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                CoachAvailabilityUI.border,
                lineWidth: 1
            )
        }
    }

    private var availabilityTimeCard: some View {
        VStack(alignment: .leading, spacing: 14) {

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(displayDate)の空き時間")
                        .font(.headline)
                        .foregroundStyle(
                            CoachAvailabilityUI.textPrimary
                        )

                    Text("タップして受付可能な時間を選択")
                        .font(.caption)
                        .foregroundStyle(
                            CoachAvailabilityUI.textSecondary
                        )
                }

                Spacer()

                if dirtyDateKeys.contains(formattedDate) {
                    Label(
                        "未保存",
                        systemImage: "pencil"
                    )
                    .font(
                        .system(
                            size: 11,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(
                        Color.orange.opacity(0.10)
                    )
                    .clipShape(Capsule())
                }
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("読み込み中…")
                    Spacer()
                }
                .frame(minHeight: 120)

            } else {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .flexible(),
                            spacing: 10
                        ),
                        GridItem(
                            .flexible(),
                            spacing: 10
                        )
                    ],
                    spacing: 10
                ) {
                    ForEach(timeSlots, id: \.self) { time in
                        let isBlocked =
                            blockedTimes.contains(time)
                        let isSelected =
                            selectedTimes.contains(time)

                        Button {
                            toggleTime(time)
                        } label: {
                            VStack(
                                alignment: .leading,
                                spacing: 8
                            ) {
                                HStack {
                                    Image(
                                        systemName:
                                            isBlocked
                                                ? "lock.fill"
                                                : isSelected
                                                    ? "checkmark.circle.fill"
                                                    : "plus.circle"
                                    )
                                    .font(
                                        .system(
                                            size: 14,
                                            weight: .semibold
                                        )
                                    )
                                    .foregroundStyle(
                                        isBlocked
                                            ? CoachAvailabilityUI.textSecondary
                                            : isSelected
                                                ? CoachAvailabilityUI.brandGreen
                                                : CoachAvailabilityUI.textSecondary
                                    )

                                    Spacer()

                                    if isBlocked {
                                        Text("予約あり")
                                            .font(
                                                .system(
                                                    size: 10,
                                                    weight: .semibold
                                                )
                                            )
                                            .foregroundStyle(
                                                CoachAvailabilityUI.textSecondary
                                            )
                                    }
                                }

                                Text(
                                    "\(time)〜\(endTime(for: time))"
                                )
                                .font(
                                    .system(
                                        size: 14,
                                        weight: .semibold
                                    )
                                )
                                .foregroundStyle(
                                    isBlocked
                                        ? CoachAvailabilityUI.textSecondary
                                        : CoachAvailabilityUI.textPrimary
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            }
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 72,
                                alignment: .leading
                            )
                            .padding(12)
                            .background(
                                isBlocked
                                    ? Color(.systemGray6)
                                    : isSelected
                                        ? CoachAvailabilityUI.softGreen
                                        : Color.white
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 14,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 14,
                                    style: .continuous
                                )
                                .stroke(
                                    isSelected
                                        ? CoachAvailabilityUI.brandGreen.opacity(0.45)
                                        : CoachAvailabilityUI.border,
                                    lineWidth: 1
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isBlocked)
                        .opacity(isBlocked ? 0.65 : 1)
                    }
                }
            }

            if selectedTimes.isEmpty &&
                blockedTimes.isEmpty &&
                !isLoading {
                Text("この日の空き時間は登録されていません")
                    .font(.caption)
                    .foregroundStyle(
                        CoachAvailabilityUI.textSecondary
                    )
            }

            if !blockedTimes.isEmpty && !isLoading {
                HStack(
                    alignment: .top,
                    spacing: 7
                ) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(
                            CoachAvailabilityUI.textSecondary
                        )

                    Text(
                        "予約申請中・承認済み・支払い済みの時間は変更できません"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        CoachAvailabilityUI.textSecondary
                    )
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                CoachAvailabilityUI.border,
                lineWidth: 1
            )
        }
    }

    private var saveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                saveAvailability()
            } label: {
                HStack {
                    Spacer()

                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else if dirtyDateKeys.isEmpty {
                        Text("変更はありません")
                            .fontWeight(.semibold)
                    } else {
                        Text(
                            "\(dirtyDateKeys.count)日分の変更を保存"
                        )
                        .fontWeight(.semibold)
                    }

                    Spacer()
                }
                .frame(height: 48)
                .foregroundStyle(.white)
                .background(
                    dirtyDateKeys.isEmpty
                        ? Color.gray
                        : CoachAvailabilityUI.brandGreen
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(
                isLoading ||
                isSaving ||
                dirtyDateKeys.isEmpty
            )
            .opacity(
                dirtyDateKeys.isEmpty ? 0.55 : 1
            )

            Text(
                "日付を移動しても未保存の選択内容は保持されます。複数日を編集して、最後にまとめて保存できます。"
            )
            .font(.caption)
            .foregroundStyle(
                CoachAvailabilityUI.textSecondary
            )

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                CoachAvailabilityUI.border,
                lineWidth: 1
            )
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

                await MainActor.run {
                    todayAvailableTimeCount = actualAvailableTimes.count
                    isSameDayAvailable =
                        savedSameDayAvailable &&
                        !actualAvailableTimes.isEmpty
                    isLoadingSameDayStatus = false
                    sameDayErrorMessage = ""
                }

                // Firestore上でONのままでも、予約や時刻経過によって
                // 実際の空き枠が0件になっていた場合は、Cloud Functions経由で
                // サーバー側の状態もOFFへ同期する。
                if savedSameDayAvailable && actualAvailableTimes.isEmpty {
                    functions
                        .httpsCallable("setCoachSameDayAvailability")
                        .call(["enabled": false]) { _, error in
                            guard let error else {
                                return
                            }

                            DispatchQueue.main.async {
                                sameDayErrorMessage =
                                    "本日の受付状態を同期できませんでした: " +
                                    error.localizedDescription
                            }
                        }
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
        guard Auth.auth().currentUser != nil else {
            sameDayErrorMessage = "本日の受付設定にはログインが必要です"
            return
        }

        guard !isUpdatingSameDayStatus else {
            return
        }

        let nextEnabled = !isSameDayAvailable

        isUpdatingSameDayStatus = true
        sameDayErrorMessage = ""

        functions
            .httpsCallable("setCoachSameDayAvailability")
            .call(["enabled": nextEnabled]) { result, error in
                DispatchQueue.main.async {
                    isUpdatingSameDayStatus = false

                    if let error {
                        sameDayErrorMessage =
                            nextEnabled
                            ? "本日の受付を開始できませんでした: " +
                                error.localizedDescription
                            : "本日の受付を終了できませんでした: " +
                                error.localizedDescription
                        return
                    }

                    guard
                        let data = result?.data as? [String: Any],
                        let serverEnabled = data["enabled"] as? Bool
                    else {
                        sameDayErrorMessage =
                            "本日の受付設定の結果を確認できませんでした。"
                        return
                    }

                    isSameDayAvailable = serverEnabled
                    sameDayErrorMessage = ""

                    if serverEnabled {
                        todayAvailableTimeCount = integerValue(
                            data["availableTimeCount"]
                        )
                        sameDayAlertMessage =
                            "本日の受付をONにしました。「本日レッスン可能コーチ」への掲載対象になります。"
                    } else {
                        sameDayAlertMessage =
                            "「本日レッスン可能コーチ」への掲載を終了しました。"
                    }

                    showSameDayAlert = true
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
        guard Auth.auth().currentUser != nil else {
            errorMessage = "空き日程の保存にはログインが必要です"
            return
        }

        let dateKeysToSave =
            dirtyDateKeys.sorted()

        guard !dateKeysToSave.isEmpty else {
            return
        }

        // Cloud Functions側でも同じ上限を検証する。
        guard dateKeysToSave.count <= 400 else {
            errorMessage =
                "一度に保存できる変更日数を超えています。400日以下に分けて保存してください。"
            return
        }

        let changes: [[String: Any]] = dateKeysToSave.map { dateKey in
            [
                "date": dateKey,
                "times": (draftTimesByDate[dateKey] ?? []).sorted()
            ]
        }

        errorMessage = ""
        isSaving = true

        functions
            .httpsCallable("saveCoachAvailability")
            .call(["changes": changes]) { result, error in
                DispatchQueue.main.async {
                    if let error {
                        isSaving = false
                        errorMessage =
                            "保存できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    guard
                        let data = result?.data as? [String: Any],
                        let savedDictionary = dictionaryValue(
                            data["saved"]
                        )
                    else {
                        isSaving = false
                        errorMessage =
                            "保存結果を確認できませんでした。もう一度画面を開き直して確認してください。"
                        return
                    }

                    let blockedDictionary =
                        dictionaryValue(data["blocked"]) ?? [:]

                    var sanitizedDrafts:
                        [String: Set<String>] = [:]
                    var serverBlockedTimes:
                        [String: Set<String>] = [:]

                    for dateKey in dateKeysToSave {
                        guard savedDictionary.keys.contains(dateKey) else {
                            isSaving = false
                            errorMessage =
                                "保存結果の一部を確認できませんでした。もう一度画面を開き直して確認してください。"
                            return
                        }

                        sanitizedDrafts[dateKey] =
                            stringSet(savedDictionary[dateKey])

                        serverBlockedTimes[dateKey] =
                            stringSet(blockedDictionary[dateKey])
                    }

                    // サーバー側で最新予約を確認した結果を、そのまま画面へ反映する。
                    // 予約済み枠がクライアントの古い下書きに含まれていても、
                    // Cloud Functions側で除外された値だけを採用する。
                    for (dateKey, safeTimes) in sanitizedDrafts {
                        draftTimesByDate[dateKey] = safeTimes
                    }

                    dirtyDateKeys.subtract(
                        Set(dateKeysToSave)
                    )

                    if let currentSavedTimes =
                        sanitizedDrafts[formattedDate] {
                        let currentBlockedTimes =
                            serverBlockedTimes[formattedDate] ?? []

                        blockedTimes = currentBlockedTimes
                        selectedTimes = currentSavedTimes
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
            }
    }

    private func dictionaryValue(
        _ value: Any?
    ) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }

        if let dictionary = value as? NSDictionary {
            var result: [String: Any] = [:]

            for (key, item) in dictionary {
                guard let key = key as? String else {
                    continue
                }

                result[key] = item
            }

            return result
        }

        return nil
    }

    private func stringSet(
        _ value: Any?
    ) -> Set<String> {
        if let values = value as? [String] {
            return Set(values)
        }

        if let values = value as? [Any] {
            return Set(
                values.compactMap { $0 as? String }
            )
        }

        return []
    }

    private func integerValue(
        _ value: Any?
    ) -> Int {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        return 0
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
