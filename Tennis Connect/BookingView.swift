import SwiftUI
import FirebaseFirestore
import FirebaseAuth

private enum BookingUI {
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

struct BookingView: View {
    @State private var lessonDate = Date()
    @State private var selectedTimes: Set<String> = []
    @State private var showConfirm = false
    @State private var showLogin = false
    @State private var availableTimes: [String] = []
    @State private var selectionMessage = ""
    @State private var loadErrorMessage = ""
    @State private var isLoadingAvailability = false

    let coach: Coach

    private let db = Firestore.firestore()

    private let timeColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var sortedSelectedTimes: [String] {
        selectedTimes.sorted()
    }

    private var totalPrice: Int {
        coach.price * selectedTimes.count
    }

    private var trimmedCoachArea: String {
        coach.area.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private var primaryCareer: String {
        let value =
            coach.careers.first?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            ?? ""

        if value.isEmpty ||
            value == "経歴未登録" {
            return ""
        }

        return value
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BookingUI.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: 16
                    ) {
                        coachSummaryCard

                        dateSelectionCard

                        availabilityCard

                        if !selectedTimes.isEmpty {
                            bookingSummaryCard
                        }

                        Color.clear
                            .frame(height: 92)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }
                .scrollIndicators(.hidden)
            }
            .tint(BookingUI.brandGreen)
            .navigationTitle("レッスン予約")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                bookingActionArea
            }
            .navigationDestination(
                isPresented: $showConfirm
            ) {
                BookingConfirmView(
                    coach: coach,
                    date: lessonDate,
                    times: sortedSelectedTimes
                )
            }
            .sheet(isPresented: $showLogin) {
                LoginView {
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + 0.3
                    ) {
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

    private var coachSummaryCard: some View {
        HStack(spacing: 14) {
            coachAvatar

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Text(coach.name)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        BookingUI.textPrimary
                    )
                    .lineLimit(1)

                if !trimmedCoachArea.isEmpty {
                    Label(
                        trimmedCoachArea,
                        systemImage:
                            "mappin.and.ellipse"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        BookingUI.textSecondary
                    )
                    .lineLimit(1)
                }

                if !primaryCareer.isEmpty {
                    Text(primaryCareer)
                        .font(.caption)
                        .foregroundStyle(
                            BookingUI.textSecondary
                        )
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    Label(
                        "1時間",
                        systemImage: "clock"
                    )
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        BookingUI.textPrimary
                    )

                    Rectangle()
                        .fill(
                            BookingUI.border
                        )
                        .frame(
                            width: 1,
                            height: 18
                        )

                    Label(
                        "¥\(coach.price.formatted())",
                        systemImage:
                            "yensign.circle.fill"
                    )
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        BookingUI.brandGreen
                    )
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                BookingUI.border,
                lineWidth: 1
            )
        }
    }

    @ViewBuilder
    private var coachAvatar: some View {
        AsyncImage(
            url: URL(
                string: coach.imageURL
            )
        ) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()

            case .failure:
                coachAvatarPlaceholder

            case .empty:
                if coach.imageURL.isEmpty {
                    coachAvatarPlaceholder
                } else {
                    ZStack {
                        Circle()
                            .fill(
                                BookingUI.softGreen
                            )

                        ProgressView()
                            .tint(
                                BookingUI.brandGreen
                            )
                    }
                }

            @unknown default:
                coachAvatarPlaceholder
            }
        }
        .frame(
            width: 72,
            height: 72
        )
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(
                    BookingUI.border,
                    lineWidth: 1
                )
        }
        .accessibilityHidden(true)
    }

    private var coachAvatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(
                    BookingUI.softGreen
                )

            Image(
                systemName:
                    "person.fill"
            )
            .font(.system(size: 28))
            .foregroundStyle(
                BookingUI.brandGreen
            )
        }
    }

    private var dateSelectionCard: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            sectionHeader(
                title: "日付を選択",
                subtitle:
                    "空き時間を確認したい日を選んでください",
                systemImage: "calendar"
            )

            DatePicker(
                "",
                selection: $lessonDate,
                in:
                    Calendar.current
                        .startOfDay(
                            for: Date()
                        )...,
                displayedComponents: [.date]
            )
            .labelsHidden()
            .datePickerStyle(.graphical)
            .environment(
                \.locale,
                Locale(identifier: "ja_JP")
            )
            .tint(
                BookingUI.brandGreen
            )
        }
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                BookingUI.border,
                lineWidth: 1
            )
        }
    }

    private var availabilityCard: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            sectionHeader(
                title: "空き時間",
                subtitle:
                    "連続した時間を複数選択できます",
                systemImage: "clock"
            )

            if isLoadingAvailability {
                HStack(spacing: 10) {
                    Spacer()

                    ProgressView()
                        .tint(
                            BookingUI.brandGreen
                        )

                    Text("空き時間を確認中…")
                        .font(.subheadline)
                        .foregroundStyle(
                            BookingUI.textSecondary
                        )

                    Spacer()
                }
                .padding(.vertical, 18)

            } else if availableTimes.isEmpty {
                VStack(spacing: 8) {
                    Image(
                        systemName:
                            "calendar.badge.minus"
                    )
                    .font(.system(size: 24))
                    .foregroundStyle(
                        BookingUI.textSecondary
                    )

                    Text(
                        "この日の空き時間はありません"
                    )
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        BookingUI.textPrimary
                    )

                    Text(
                        "別の日付を選択してください"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        BookingUI.textSecondary
                    )
                }
                .frame(
                    maxWidth: .infinity
                )
                .padding(.vertical, 18)

            } else {
                LazyVGrid(
                    columns: timeColumns,
                    spacing: 10
                ) {
                    ForEach(
                        availableTimes,
                        id: \.self
                    ) { time in
                        timeButton(time)
                    }
                }
            }

            if !selectionMessage.isEmpty {
                Label(
                    selectionMessage,
                    systemImage:
                        "exclamationmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }

            if !loadErrorMessage.isEmpty {
                Label(
                    loadErrorMessage,
                    systemImage:
                        "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                BookingUI.border,
                lineWidth: 1
            )
        }
    }

    private func timeButton(
        _ time: String
    ) -> some View {
        let isSelected =
            selectedTimes.contains(time)

        return Button {
            toggleTime(time)
        } label: {
            HStack(spacing: 7) {
                Text(timeRange(from: time))
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                if isSelected {
                    Image(
                        systemName:
                            "checkmark.circle.fill"
                    )
                    .font(.system(size: 15))
                }
            }
            .frame(
                maxWidth: .infinity
            )
            .frame(height: 44)
            .foregroundStyle(
                isSelected
                    ? Color.white
                    : BookingUI.textPrimary
            )
            .background(
                isSelected
                    ? BookingUI.brandGreen
                    : BookingUI.softGreen
                        .opacity(0.65)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 13,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 13,
                    style: .continuous
                )
                .stroke(
                    isSelected
                        ? BookingUI.brandGreen
                        : BookingUI.brandGreen
                            .opacity(0.10),
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var bookingSummaryCard: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            HStack(spacing: 8) {
                Image(
                    systemName:
                        "doc.text"
                )
                .font(
                    .system(
                        size: 15,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    BookingUI.brandGreen
                )

                Text("予約内容の確認")
                    .font(.headline)
                    .foregroundStyle(
                        BookingUI.textPrimary
                    )
            }

            summaryRow(
                title: "選択時間",
                value:
                    combinedTimeRange(
                        sortedSelectedTimes
                    )
            )

            Divider()

            summaryRow(
                title: "レッスン時間",
                value:
                    "\(selectedTimes.count)時間"
            )

            Divider()

            HStack(
                alignment: .firstTextBaseline
            ) {
                Text("合計料金")
                    .font(.headline)
                    .foregroundStyle(
                        BookingUI.textPrimary
                    )

                Spacer()

                Text(
                    "¥\(totalPrice.formatted())"
                )
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(
                    BookingUI.brandGreen
                )
            }
        }
        .padding(16)
        .background(
            BookingUI.softGreen.opacity(0.58)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                BookingUI.brandGreen.opacity(0.12),
                lineWidth: 1
            )
        }
    }

    private func summaryRow(
        title: String,
        value: String
    ) -> some View {
        HStack(
            alignment: .firstTextBaseline
        ) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(
                    BookingUI.textSecondary
                )

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(
                    BookingUI.textPrimary
                )
                .multilineTextAlignment(
                    .trailing
                )
        }
    }

    private var bookingActionArea: some View {
        VStack(spacing: 7) {
            Button {
                continueToConfirmation()
            } label: {
                HStack(spacing: 8) {
                    Spacer()

                    Text("予約内容を確認する")
                        .fontWeight(.semibold)

                    Image(
                        systemName:
                            "chevron.right"
                    )
                    .font(
                        .system(
                            size: 13,
                            weight: .bold
                        )
                    )

                    Spacer()
                }
                .frame(height: 52)
                .foregroundStyle(.white)
                .background(
                    selectedTimes.isEmpty
                        ? Color.gray
                        : BookingUI.brandGreen
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(
                selectedTimes.isEmpty
            )

            Text(
                selectedTimes.isEmpty
                    ? "空き時間を選択してください"
                    : "次の画面で予約内容を最終確認します"
            )
            .font(.caption2)
            .foregroundStyle(
                BookingUI.textSecondary
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private func sectionHeader(
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            BookingUI.softGreen
                        )
                        .frame(
                            width: 34,
                            height: 34
                        )

                    Image(
                        systemName:
                            systemImage
                    )
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        BookingUI.brandGreen
                    )
                }

                Text(title)
                    .font(.headline)
                    .foregroundStyle(
                        BookingUI.textPrimary
                    )
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(
                    BookingUI.textSecondary
                )
                .padding(.leading, 42)
        }
    }

    private func continueToConfirmation() {
        let dateKey =
            firestoreDate(
                from: lessonDate
            )

        let hasExpiredSelection =
            sortedSelectedTimes.contains {
                !isFutureTimeSlot(
                    $0,
                    dateKey: dateKey
                )
            }

        if hasExpiredSelection {
            selectionMessage =
                "開始時刻を過ぎた時間は予約できません。空き時間を選び直してください。"
            loadAvailableTimes()
            return
        }

        if Auth.auth().currentUser == nil {
            showLogin = true
        } else {
            showConfirm = true
        }
    }

    private func toggleTime(
        _ time: String
    ) {
        var candidate =
            selectedTimes

        if candidate.contains(time) {
            candidate.remove(time)
        } else {
            candidate.insert(time)
        }

        guard
            isConsecutive(
                candidate.sorted()
            )
        else {
            selectionMessage =
                "同じ予約では、連続した時間だけ選択できます"
            return
        }

        selectedTimes = candidate
        selectionMessage = ""
    }

    private func isConsecutive(
        _ times: [String]
    ) -> Bool {
        guard times.count > 1 else {
            return true
        }

        let formatter =
            timeFormatter()

        for index in 1..<times.count {
            guard
                let previous =
                    formatter.date(
                        from:
                            normalizedStartTime(
                                times[index - 1]
                            )
                    ),
                let current =
                    formatter.date(
                        from:
                            normalizedStartTime(
                                times[index]
                            )
                    )
            else {
                return false
            }

            if current.timeIntervalSince(
                previous
            ) != 60 * 60 {
                return false
            }
        }

        return true
    }

    private func loadAvailableTimes() {
        selectedTimes = []
        selectionMessage = ""
        loadErrorMessage = ""
        isLoadingAvailability = true

        let formattedDate =
            firestoreDate(
                from: lessonDate
            )

        let dateRef = db
            .collection(
                "coachAvailability"
            )
            .document(coach.id)
            .collection("dates")
            .document(formattedDate)

        dateRef.getDocument {
            snapshot,
            error in

            if let error {
                DispatchQueue.main.async {
                    guard
                        firestoreDate(
                            from: lessonDate
                        ) == formattedDate
                    else {
                        return
                    }

                    isLoadingAvailability =
                        false
                    loadErrorMessage =
                        "空き時間を取得できませんでした: " +
                        error.localizedDescription
                }
                return
            }

            if snapshot?.exists == true {
                let times =
                    snapshot?
                        .data()?["times"]
                    as? [String]
                    ?? []

                finishLoading(
                    times: times,
                    formattedDate:
                        formattedDate
                )

            } else {
                loadLegacyAvailableTimes(
                    formattedDate:
                        formattedDate
                )
            }
        }
    }

    private func loadLegacyAvailableTimes(
        formattedDate: String
    ) {
        db.collection("coaches")
            .document(coach.id)
            .getDocument {
                snapshot,
                error in

                if let error {
                    print(
                        "旧空き時間取得エラー:",
                        error.localizedDescription
                    )
                }

                let entries =
                    snapshot?
                        .data()?[
                            "availableTimes"
                        ]
                    as? [String]
                    ?? []

                let times =
                    legacyStartTimes(
                        entries: entries,
                        formattedDate:
                            formattedDate
                    )

                // 旧availableTimesは表示互換のため読み取るだけ。
                // coachAvailabilityへの書き込みはCloud Functions側で行う。
                finishLoading(
                    times: times,
                    formattedDate:
                        formattedDate
                )
            }
    }

    private func legacyStartTimes(
        entries: [String],
        formattedDate: String
    ) -> [String] {
        let displayDate =
            formattedDate
                .replacingOccurrences(
                    of: "-",
                    with: "/"
                )

        return entries
            .compactMap { entry in
                let normalized =
                    entry
                        .replacingOccurrences(
                            of: "~",
                            with: "〜"
                        )

                let prefixes = [
                    "\(displayDate) ",
                    "\(formattedDate) "
                ]

                guard
                    let prefix =
                        prefixes.first(
                            where: {
                                normalized
                                    .hasPrefix($0)
                            }
                        )
                else {
                    return nil
                }

                let range =
                    normalized
                        .dropFirst(
                            prefix.count
                        )

                let start =
                    String(range)
                        .components(
                            separatedBy: "〜"
                        )
                        .first?
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                    ?? ""

                return start.isEmpty
                    ? nil
                    : start
            }
            .sorted()
    }

    private func finishLoading(
        times: [String],
        formattedDate: String
    ) {
        DispatchQueue.main.async {
            // 日付を素早く切り替えた場合に、
            // 古い通信結果で現在の日付を上書きしない。
            guard
                firestoreDate(
                    from: lessonDate
                ) == formattedDate
            else {
                return
            }

            availableTimes =
                Array(Set(times))
                    .filter {
                        isFutureTimeSlot(
                            $0,
                            dateKey:
                                formattedDate
                        )
                    }
                    .sorted()

            isLoadingAvailability = false
            loadErrorMessage = ""
        }
    }

    private func isFutureTimeSlot(
        _ value: String,
        dateKey: String
    ) -> Bool {
        let startTime =
            normalizedStartTime(value)

        guard !startTime.isEmpty else {
            return false
        }

        let formatter =
            DateFormatter()
        formatter.calendar =
            Calendar(
                identifier: .gregorian
            )
        formatter.locale =
            Locale(
                identifier: "en_US_POSIX"
            )
        formatter.timeZone =
            TimeZone(
                identifier: "Asia/Tokyo"
            ) ?? .current
        formatter.dateFormat =
            "yyyy-MM-dd HH:mm"

        guard
            let slotDate =
                formatter.date(
                    from:
                        "\(dateKey) \(startTime)"
                )
        else {
            return false
        }

        return slotDate > Date()
    }

    private func normalizedStartTime(
        _ value: String
    ) -> String {
        value
            .replacingOccurrences(
                of: "~",
                with: "〜"
            )
            .components(
                separatedBy: "〜"
            )
            .first?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        ?? ""
    }

    private func firestoreDate(
        from date: Date
    ) -> String {
        let formatter =
            DateFormatter()
        formatter.calendar =
            Calendar(
                identifier: .gregorian
            )
        formatter.locale =
            Locale(
                identifier: "en_US_POSIX"
            )
        formatter.timeZone =
            TimeZone(
                identifier: "Asia/Tokyo"
            ) ?? .current
        formatter.dateFormat =
            "yyyy-MM-dd"

        return formatter.string(
            from: date
        )
    }

    private func timeRange(
        from startTime: String
    ) -> String {
        if startTime.contains("〜") ||
            startTime.contains("~") {
            return startTime
                .replacingOccurrences(
                    of: "~",
                    with: "〜"
                )
        }

        guard
            let startDate =
                timeFormatter()
                    .date(
                        from: startTime
                    ),
            let endDate =
                Calendar.current.date(
                    byAdding: .hour,
                    value: 1,
                    to: startDate
                )
        else {
            return startTime
        }

        return
            "\(startTime)〜\(timeFormatter().string(from: endDate))"
    }

    private func combinedTimeRange(
        _ times: [String]
    ) -> String {
        guard
            let first = times.first,
            let last = times.last
        else {
            return ""
        }

        let firstStart =
            normalizedStartTime(first)
        let lastRange =
            timeRange(from: last)
        let end =
            lastRange
                .components(
                    separatedBy: "〜"
                )
                .last
            ?? last

        return "\(firstStart)〜\(end)"
    }

    private func timeFormatter()
        -> DateFormatter {
        let formatter =
            DateFormatter()
        formatter.calendar =
            Calendar(
                identifier: .gregorian
            )
        formatter.locale =
            Locale(
                identifier: "en_US_POSIX"
            )
        formatter.timeZone =
            TimeZone(
                identifier: "Asia/Tokyo"
            ) ?? .current
        formatter.dateFormat =
            "HH:mm"

        return formatter
    }
}

#Preview {
    BookingView(
        coach: sampleCoaches[0]
    )
}
