import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

private enum BookingConfirmUI {
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

struct BookingConfirmView: View {
    @State private var isSubmitting = false
    @State private var isSubmitted = false
    @State private var errorMessage = ""
    @State private var courtName = ""
    @State private var courtAddress = ""

    private let courtNameMaxLength = 100
    private let courtAddressMaxLength = 200

    let coach: Coach
    let date: Date
    let times: [String]

    private let functions =
        Functions.functions(region: "asia-northeast1")

    private var sortedTimes: [String] {
        times.sorted()
    }

    private var totalPrice: Int {
        coach.price * times.count
    }

    private var normalizedCourtName: String {
        normalizedLocationValue(courtName)
    }

    private var normalizedCourtAddress: String {
        normalizedLocationValue(courtAddress)
    }

    private var locationIsValid: Bool {
        !normalizedCourtName.isEmpty &&
        !normalizedCourtAddress.isEmpty &&
        normalizedCourtName.count <= courtNameMaxLength &&
        normalizedCourtAddress.count <= courtAddressMaxLength
    }

    private var canSubmit: Bool {
        !isSubmitting &&
        !times.isEmpty &&
        locationIsValid
    }

    var body: some View {
        Group {
            if isSubmitted {
                BookingRequestCompleteView(
                    coach: coach,
                    date: date,
                    times: sortedTimes,
                    totalPrice: totalPrice,
                    courtName: normalizedCourtName,
                    courtAddress: normalizedCourtAddress
                )
            } else {
                confirmationContent
            }
        }
        .navigationBarBackButtonHidden(isSubmitted)
        .tint(BookingConfirmUI.brandGreen)
    }

    private var confirmationContent: some View {
        ZStack {
            BookingConfirmUI.background
                .ignoresSafeArea()

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 18
                ) {
                    headerSection

                    coachCard

                    lessonSummaryCard

                    locationCard

                    informationCard

                    if !errorMessage.isEmpty {
                        errorCard
                    }

                    Color.clear
                        .frame(height: 92)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("予約内容確認")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            submitArea
        }
    }

    private var headerSection: some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            Text("予約内容を確認")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(
                    BookingConfirmUI.textPrimary
                )

            Text("内容を確認して、コーチへ予約申請を送ります")
                .font(.subheadline)
                .foregroundStyle(
                    BookingConfirmUI.textSecondary
                )
        }
    }

    private var coachCard: some View {
        HStack(spacing: 14) {
            CoachAvatarView(
                imageURL: coach.imageURL,
                size: 62
            )

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Text(coach.name)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        BookingConfirmUI.textPrimary
                    )
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Image(
                        systemName:
                            "mappin.and.ellipse"
                    )
                    .font(.caption)

                    Text(
                        coach.area.isEmpty
                            ? "エリア未登録"
                            : coach.area
                    )
                    .font(.caption)
                }
                .foregroundStyle(
                    BookingConfirmUI.textSecondary
                )

                Text("このコーチに予約を申請します")
                    .font(.caption)
                    .foregroundStyle(
                        BookingConfirmUI.textSecondary
                    )
            }

            Spacer()
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
                BookingConfirmUI.border,
                lineWidth: 1
            )
        }
    }

    private var lessonSummaryCard: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            sectionTitle(
                "レッスン内容",
                systemImage: "calendar"
            )

            summaryRow(
                title: "日付",
                value: displayDate(date),
                icon: "calendar"
            )

            Divider()

            summaryRow(
                title: "時間",
                value: combinedTimeRange(
                    sortedTimes
                ),
                icon: "clock"
            )

            Divider()

            summaryRow(
                title: "レッスン時間",
                value: "\(times.count)時間",
                icon: "hourglass"
            )

            Divider()

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            BookingConfirmUI.softGreen
                        )
                        .frame(width: 34, height: 34)

                    Image(
                        systemName: "yensign"
                    )
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        BookingConfirmUI.brandGreen
                    )
                }

                Text("料金")
                    .foregroundStyle(
                        BookingConfirmUI.textSecondary
                    )

                Spacer()

                Text("¥\(totalPrice.formatted())")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        BookingConfirmUI.brandGreen
                    )
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
                BookingConfirmUI.border,
                lineWidth: 1
            )
        }
    }

    private var locationCard: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            sectionTitle(
                "レッスン場所",
                systemImage:
                    "mappin.and.ellipse"
            )

            Text(
                "コーチはこの場所を確認してから、予約を承認または却下します。"
            )
            .font(.caption)
            .foregroundStyle(
                BookingConfirmUI.textSecondary
            )

            inputField(
                title: "テニスコート名",
                placeholder:
                    "例：有明テニスの森公園",
                text: $courtName,
                count: normalizedCourtName.count,
                maxCount: courtNameMaxLength,
                axis: .horizontal
            )

            inputField(
                title: "所在地",
                placeholder:
                    "例：東京都江東区有明2-2-22",
                text: $courtAddress,
                count:
                    normalizedCourtAddress.count,
                maxCount:
                    courtAddressMaxLength,
                axis: .vertical
            )

            if normalizedCourtName.isEmpty ||
                normalizedCourtAddress.isEmpty {
                HStack(
                    alignment: .top,
                    spacing: 7
                ) {
                    Image(
                        systemName:
                            "exclamationmark.circle"
                    )

                    Text(
                        "テニスコート名と所在地はどちらも必須です"
                    )
                }
                .font(.caption)
                .foregroundStyle(.orange)
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
                BookingConfirmUI.border,
                lineWidth: 1
            )
        }
    }

    private var informationCard: some View {
        HStack(
            alignment: .top,
            spacing: 12
        ) {
            ZStack {
                Circle()
                    .fill(
                        BookingConfirmUI.softGreen
                    )
                    .frame(width: 38, height: 38)

                Image(systemName: "shield.checkered")
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        BookingConfirmUI.brandGreen
                    )
            }

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Text("この時点では支払いは発生しません")
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        BookingConfirmUI.textPrimary
                    )

                Text(
                    "申請後、コーチが内容とレッスン場所を確認します。承認された場合のみ、支払いへ進みます。"
                )
                .font(.caption)
                .foregroundStyle(
                    BookingConfirmUI.textSecondary
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }
        }
        .padding(16)
        .background(
            BookingConfirmUI.softGreen.opacity(0.55)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    private var errorCard: some View {
        HStack(
            alignment: .top,
            spacing: 8
        ) {
            Image(
                systemName:
                    "exclamationmark.triangle.fill"
            )

            Text(errorMessage)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
        }
        .font(.caption)
        .foregroundStyle(.red)
        .padding(14)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color.red.opacity(0.06)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }

    private var submitArea: some View {
        VStack(spacing: 8) {
            Button {
                submitReservationRequest()
            } label: {
                HStack(spacing: 8) {
                    Spacer()

                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(
                            systemName:
                                "paperplane.fill"
                        )

                        Text("この内容で予約申請する")
                            .fontWeight(.semibold)
                    }

                    Spacer()
                }
                .frame(height: 50)
                .foregroundStyle(.white)
                .background(
                    canSubmit
                        ? BookingConfirmUI.brandGreen
                        : Color.gray
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)

            Text(
                "コーチ承認後に支払い手続きへ進みます"
            )
            .font(.caption2)
            .foregroundStyle(
                BookingConfirmUI.textSecondary
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            .ultraThinMaterial
        )
    }

    private func sectionTitle(
        _ title: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(
                    .system(
                        size: 15,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    BookingConfirmUI.brandGreen
                )

            Text(title)
                .font(.headline)
                .foregroundStyle(
                    BookingConfirmUI.textPrimary
                )
        }
    }

    private func summaryRow(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        BookingConfirmUI.softGreen
                    )
                    .frame(width: 34, height: 34)

                Image(systemName: icon)
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        BookingConfirmUI.brandGreen
                    )
            }

            Text(title)
                .foregroundStyle(
                    BookingConfirmUI.textSecondary
                )

            Spacer()

            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(
                    BookingConfirmUI.textPrimary
                )
                .multilineTextAlignment(.trailing)
        }
    }

    private func inputField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        count: Int,
        maxCount: Int,
        axis: Axis
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 7
        ) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        BookingConfirmUI.textSecondary
                    )

                Spacer()

                Text("\(count)/\(maxCount)")
                    .font(.caption2)
                    .foregroundStyle(
                        count > maxCount
                            ? Color.red
                            : BookingConfirmUI.textSecondary
                    )
            }

            TextField(
                placeholder,
                text: text,
                axis: axis
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .lineLimit(
                axis == .vertical
                    ? 1...3
                    : 1...1
            )
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(
                BookingConfirmUI.background
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
                    count > maxCount
                        ? Color.red.opacity(0.5)
                        : BookingConfirmUI.border,
                    lineWidth: 1
                )
            }
        }
    }

    private func submitReservationRequest() {
        guard Auth.auth().currentUser != nil else {
            errorMessage = "予約申請にはログインが必要です"
            return
        }

        guard !sortedTimes.isEmpty else {
            errorMessage = "予約時間を選択してください"
            return
        }

        guard !normalizedCourtName.isEmpty else {
            errorMessage = "テニスコート名を入力してください"
            return
        }

        guard !normalizedCourtAddress.isEmpty else {
            errorMessage = "レッスン場所の所在地を入力してください"
            return
        }

        guard normalizedCourtName.count <= courtNameMaxLength else {
            errorMessage =
                "テニスコート名は\(courtNameMaxLength)文字以内で入力してください"
            return
        }

        guard normalizedCourtAddress.count <= courtAddressMaxLength else {
            errorMessage =
                "所在地は\(courtAddressMaxLength)文字以内で入力してください"
            return
        }

        errorMessage = ""
        isSubmitting = true

        let requestData: [String: Any] = [
            "coachId": coach.id,
            "date": firestoreDate(date),
            "times": sortedTimes,
            "courtName": normalizedCourtName,
            "courtAddress": normalizedCourtAddress
        ]

        functions
            .httpsCallable("submitReservationRequest")
            .call(requestData) { _, error in
                DispatchQueue.main.async {
                    isSubmitting = false

                    if let error = error {
                        errorMessage = reservationRequestErrorMessage(
                            from: error
                        )
                        return
                    }

                    isSubmitted = true
                }
            }
    }

    private func reservationRequestErrorMessage(
        from error: Error
    ) -> String {
        let nsError = error as NSError
        let message = nsError.localizedDescription

        if message.contains("予約済み") ||
            message.contains("空き時間") ||
            message.contains("テニスコート名") ||
            message.contains("所在地") ||
            message.contains("レッスン場所") {
            return message
        }

        if message.contains("ログイン") {
            return "ログイン状態を確認して、もう一度お試しください"
        }

        return "予約を申請できませんでした: \(message)"
    }

    private func finishWithError(_ message: String) {
        DispatchQueue.main.async {
            isSubmitting = false
            errorMessage = message
        }
    }

    private func normalizedLocationValue(
        _ value: String
    ) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }

    private func firestoreDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func combinedTimeRange(_ times: [String]) -> String {
        guard let first = times.first,
              let last = times.last else {
            return ""
        }

        return "\(first)〜\(endTime(for: last))"
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

private struct BookingRequestCompleteView: View {
    let coach: Coach
    let date: Date
    let times: [String]
    let totalPrice: Int
    let courtName: String
    let courtAddress: String

    var body: some View {
        ZStack {
            BookingConfirmUI.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 34)

                    ZStack {
                        Circle()
                            .fill(
                                BookingConfirmUI.softGreen
                            )
                            .frame(
                                width: 92,
                                height: 92
                            )

                        Image(
                            systemName:
                                "checkmark.circle.fill"
                        )
                        .font(.system(size: 54))
                        .foregroundStyle(
                            BookingConfirmUI.brandGreen
                        )
                    }

                    VStack(spacing: 7) {
                        Text("予約申請を送信しました")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(
                                BookingConfirmUI.textPrimary
                            )

                        Text(
                            "コーチの承認をお待ちください。\n承認後に支払いへ進めます。"
                        )
                        .font(.subheadline)
                        .foregroundStyle(
                            BookingConfirmUI.textSecondary
                        )
                        .multilineTextAlignment(.center)
                    }

                    coachSummaryCard

                    reservationSummaryCard

                    statusInformationCard

                    Button {
                        NotificationCenter.default.post(
                            name: .returnToStudentHome,
                            object: nil
                        )
                    } label: {
                        HStack {
                            Spacer()

                            Image(systemName: "house.fill")

                            Text("ホームへ戻る")
                                .fontWeight(.semibold)

                            Spacer()
                        }
                        .frame(height: 50)
                        .foregroundStyle(.white)
                        .background(
                            BookingConfirmUI.brandGreen
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 15,
                                style: .continuous
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
    }

    private var coachSummaryCard: some View {
        HStack(spacing: 14) {
            CoachAvatarView(
                imageURL: coach.imageURL,
                size: 58
            )

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text("担当コーチ")
                    .font(.caption)
                    .foregroundStyle(
                        BookingConfirmUI.textSecondary
                    )

                Text(coach.name)
                    .font(.headline)
                    .foregroundStyle(
                        BookingConfirmUI.textPrimary
                    )
            }

            Spacer()
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
                BookingConfirmUI.border,
                lineWidth: 1
            )
        }
    }

    private var reservationSummaryCard: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(
                        BookingConfirmUI.brandGreen
                    )

                Text("申請内容")
                    .font(.headline)
                    .foregroundStyle(
                        BookingConfirmUI.textPrimary
                    )
            }

            detailRow(
                title: "日付",
                value: displayDate(date)
            )
            Divider()

            detailRow(
                title: "時間",
                value: combinedTimeRange(times)
            )
            Divider()

            detailRow(
                title: "料金",
                value:
                    "¥\(totalPrice.formatted())"
            )
            Divider()

            multilineDetailRow(
                title: "テニスコート",
                value: courtName
            )
            Divider()

            multilineDetailRow(
                title: "所在地",
                value: courtAddress
            )
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
                BookingConfirmUI.border,
                lineWidth: 1
            )
        }
    }

    private var statusInformationCard: some View {
        HStack(
            alignment: .top,
            spacing: 12
        ) {
            ZStack {
                Circle()
                    .fill(
                        BookingConfirmUI.softGreen
                    )
                    .frame(width: 38, height: 38)

                Image(systemName: "clock")
                    .foregroundStyle(
                        BookingConfirmUI.brandGreen
                    )
            }

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text("現在は承認待ちです")
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        BookingConfirmUI.textPrimary
                    )

                Text(
                    "コーチが承認すると、予約一覧から支払い手続きへ進めるようになります。"
                )
                .font(.caption)
                .foregroundStyle(
                    BookingConfirmUI.textSecondary
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }
        }
        .padding(16)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            BookingConfirmUI.softGreen.opacity(0.55)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    private func detailRow(
        title: String,
        value: String
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(
                    BookingConfirmUI.textSecondary
                )

            Spacer()

            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(
                    BookingConfirmUI.textPrimary
                )
                .multilineTextAlignment(.trailing)
        }
    }

    private func multilineDetailRow(
        title: String,
        value: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            Text(title)
                .font(.caption)
                .foregroundStyle(
                    BookingConfirmUI.textSecondary
                )

            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(
                    BookingConfirmUI.textPrimary
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
        }
    }

    private func displayDate(
        _ date: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar =
            Calendar(identifier: .gregorian)
        formatter.locale =
            Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }

    private func combinedTimeRange(
        _ times: [String]
    ) -> String {
        guard let first = times.first,
              let last = times.last else {
            return ""
        }

        return "\(first)〜\(endTime(for: last))"
    }

    private func endTime(
        for startTime: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar =
            Calendar(identifier: .gregorian)
        formatter.locale =
            Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"

        guard let startDate =
                formatter.date(
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

        return formatter.string(from: endDate)
    }
}

private struct CoachAvatarView: View {

    let imageURL: String
    let size: CGFloat

    var body: some View {
        AsyncImage(
            url: URL(string: imageURL)
        ) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()

            case .failure:
                placeholder

            case .empty:
                if imageURL.isEmpty {
                    placeholder
                } else {
                    ProgressView()
                }

            @unknown default:
                placeholder
            }
        }
        .frame(
            width: size,
            height: size
        )
        .background(
            Color(.systemGray5)
        )
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(
                    Color(.separator).opacity(0.25),
                    lineWidth: 0.5
                )
        )
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .resizable()
            .scaledToFit()
            .padding(size * 0.22)
            .foregroundStyle(.secondary)
    }
}


