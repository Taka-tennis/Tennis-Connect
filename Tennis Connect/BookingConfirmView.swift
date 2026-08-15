// 修正版：予約申請と同時にコーチへ通知を保存します
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct BookingConfirmView: View {
    @State private var isSubmitting = false
    @State private var isSubmitted = false
    @State private var errorMessage = ""

    let coach: Coach
    let date: Date
    let times: [String]

    private let db = Firestore.firestore()

    private var sortedTimes: [String] {
        times.sorted()
    }

    private var totalPrice: Int {
        coach.price * times.count
    }

    var body: some View {
        Group {
            if isSubmitted {
                BookingRequestCompleteView(
                    coach: coach,
                    date: date,
                    times: sortedTimes,
                    totalPrice: totalPrice
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
                    HStack {
                        Text("コーチ")
                        Spacer()
                        Text(coach.name)
                            .bold()
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
                    .background(isSubmitting ? Color.gray : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
                .disabled(isSubmitting || times.isEmpty)
            }
            .padding()
        }
    }

    private func submitReservationRequest() {
        guard let studentId = Auth.auth().currentUser?.uid else {
            errorMessage = "予約申請にはログインが必要です"
            return
        }

        guard !sortedTimes.isEmpty else {
            errorMessage = "予約時間を選択してください"
            return
        }

        errorMessage = ""
        isSubmitting = true

        let dateKey = firestoreDate(date)
        let availabilityRef = db.collection("coachAvailability")
            .document(coach.id)
            .collection("dates")
            .document(dateKey)

        availabilityRef.getDocument { snapshot, error in
            if let error = error {
                finishWithError(
                    "空き時間を確認できませんでした: \(error.localizedDescription)"
                )
                return
            }

            guard var availableTimes = snapshot?.data()?["times"] as? [String] else {
                finishWithError("選択した日の空き時間が見つかりませんでした")
                return
            }

            let unavailableTimes = sortedTimes.filter {
                !availableTimes.contains($0)
            }

            guard unavailableTimes.isEmpty else {
                finishWithError(
                    "選択した時間の一部が予約済みになりました。前の画面に戻って選び直してください。"
                )
                return
            }

            availableTimes.removeAll { sortedTimes.contains($0) }

            let reservationRef = db.collection("reservations").document()
            let batch = db.batch()

            batch.setData(
                [
                    "coachId": coach.id,
                    "studentId": studentId,
                    "coachName": coach.name,
                    "date": dateKey,
                    "time": sortedTimes.first ?? "",
                    "times": sortedTimes,
                    "durationHours": sortedTimes.count,
                    "pricePerHour": coach.price,
                    "totalPrice": totalPrice,
                    "status": "pending",
                    "createdAt": Timestamp()
                ],
                forDocument: reservationRef
            )

            batch.updateData(
                ["times": availableTimes.sorted()],
                forDocument: availabilityRef
            )

            let notificationRef = db.collection("notifications").document()

            batch.setData(
                [
                    "recipientId": coach.id,
                    "coachId": coach.id,
                    "studentId": studentId,
                    "reservationId": reservationRef.documentID,
                    "type": "reservationRequested",
                    "title": "新しい予約申請が届きました",
                    "message": "\(displayDate(date)) \(combinedTimeRange(sortedTimes))の予約申請が届きました。内容を確認してください。",
                    "date": dateKey,
                    "times": sortedTimes,
                    "isRead": false,
                    "createdAt": Timestamp()
                ],
                forDocument: notificationRef
            )

            batch.commit { error in
                if let error = error {
                    finishWithError(
                        "予約を申請できませんでした: \(error.localizedDescription)"
                    )
                    return
                }

                DispatchQueue.main.async {
                    isSubmitting = false
                    isSubmitted = true
                }
            }
        }
    }

    private func finishWithError(_ message: String) {
        DispatchQueue.main.async {
            isSubmitting = false
            errorMessage = message
        }
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
                detailRow(title: "コーチ", value: coach.name)
                Divider()
                detailRow(title: "日付", value: displayDate(date))
                Divider()
                detailRow(title: "時間", value: combinedTimeRange(times))
                Divider()
                detailRow(title: "料金", value: "¥\(totalPrice)")
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

#Preview {
    NavigationStack {
        BookingConfirmView(
            coach: sampleCoaches[0],
            date: Date(),
            times: ["09:00", "10:00"]
        )
    }
}
