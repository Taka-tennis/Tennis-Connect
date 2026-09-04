// 修正版：予約申請と同時にコーチへ通知を保存します
import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

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

    private let functions = Functions.functions(region: "asia-northeast1")

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
    }

    private var confirmationContent: some View {
        ScrollView {
            VStack(spacing: 25) {
                Spacer(minLength: 30)

                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 70))
                    .foregroundStyle(.blue)

                Text("予約内容確認")
                    .font(.largeTitle)
                    .bold()

                Text("まだ予約は完了していません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Text("コーチ")

                        Spacer()

                        CoachAvatarView(
                            imageURL: coach.imageURL,
                            size: 38
                        )

                        Text(coach.name)
                            .bold()
                            .multilineTextAlignment(.trailing)
                    }

                    Divider()

                    HStack {
                        Text("日付")
                        Spacer()
                        Text(displayDate(date))
                            .bold()
                    }

                    Divider()

                    HStack {
                        Text("時間")
                        Spacer()
                        Text(combinedTimeRange(sortedTimes))
                            .bold()
                    }

                    Divider()

                    HStack {
                        Text("レッスン時間")
                        Spacer()
                        Text("\(times.count)時間")
                            .bold()
                    }

                    Divider()

                    HStack {
                        Text("料金")
                        Spacer()
                        Text("¥\(totalPrice)")
                            .bold()
                            .foregroundStyle(.green)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(18)

                VStack(alignment: .leading, spacing: 14) {
                    Label(
                        "レッスン場所",
                        systemImage: "mappin.and.ellipse"
                    )
                    .font(.headline)

                    Text(
                        "コーチはこの場所を確認してから、予約を承認または却下します。"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("テニスコート名")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        TextField(
                            "例：有明テニスの森公園",
                            text: $courtName
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .frame(minHeight: 46)
                        .background(Color(.systemBackground))
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                            .stroke(
                                Color(.separator).opacity(0.22),
                                lineWidth: 1
                            )
                        }

                        Text(
                            "\(normalizedCourtName.count)/\(courtNameMaxLength)"
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            normalizedCourtName.count > courtNameMaxLength
                                ? Color.red
                                : Color.secondary
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("所在地")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        TextField(
                            "例：東京都江東区有明2-2-22",
                            text: $courtAddress,
                            axis: .vertical
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...3)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(Color(.systemBackground))
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                            .stroke(
                                Color(.separator).opacity(0.22),
                                lineWidth: 1
                            )
                        }

                        Text(
                            "\(normalizedCourtAddress.count)/\(courtAddressMaxLength)"
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            normalizedCourtAddress.count > courtAddressMaxLength
                                ? Color.red
                                : Color.secondary
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if normalizedCourtName.isEmpty ||
                        normalizedCourtAddress.isEmpty {
                        Text("※ テニスコート名と所在地はどちらも必須です")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(18)

                Text("申請後、コーチの承認を待ちます。支払いは承認後に行います。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    submitReservationRequest()
                } label: {
                    HStack {
                        Spacer()

                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("この内容で申請する")
                                .fontWeight(.semibold)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(canSubmit ? Color.green : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
                .disabled(!canSubmit)
            }
            .padding()
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
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "paperplane.circle.fill")
                .font(.system(size: 86))
                .foregroundStyle(.blue)

            Text("予約申請を送信しました")
                .font(.largeTitle)
                .bold()
                .multilineTextAlignment(.center)

            Text("コーチの承認をお待ちください。\n承認後に支払いへ進めます。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Text("コーチ")

                    Spacer()

                    CoachAvatarView(
                        imageURL: coach.imageURL,
                        size: 38
                    )

                    Text(coach.name)
                        .bold()
                        .multilineTextAlignment(.trailing)
                }

                Divider()
                detailRow(title: "日付", value: displayDate(date))
                Divider()
                detailRow(title: "時間", value: combinedTimeRange(times))
                Divider()
                detailRow(title: "料金", value: "¥\(totalPrice)")
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
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(18)

            Spacer()

            Button {
                print("ホームへ戻るボタンが押されました")
                NotificationCenter.default.post(
                    name: .returnToStudentHome,
                    object: nil
                )
            } label: {
                Text("ホームへ戻る")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(15)
            }
        }
        .padding()
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .bold()
        }
    }

    private func multilineDetailRow(
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .foregroundStyle(.secondary)

            Text(value)
                .bold()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd"
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


#Preview {
    NavigationStack {
        BookingConfirmView(
            coach: sampleCoaches[0],
            date: Date(),
            times: ["09:00", "10:00"]
        )
    }
}
