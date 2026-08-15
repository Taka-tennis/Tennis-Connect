import SwiftUI

struct BookingCompleteView: View {
    @State private var showChat = false
    @Environment(\.returnHomeAction) private var returnHome

    let coach: Coach
    let date: Date
    let times: [String]
    let totalPrice: Int

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 90))
                .foregroundStyle(.green)

            Text("予約が完了しました！")
                .font(.largeTitle)
                .bold()

            Text("お支払いが完了しました。")
                .foregroundStyle(.secondary)

            VStack(spacing: 18) {
                detailRow(title: "コーチ", value: coach.name)
                Divider()
                detailRow(title: "日付", value: displayDate(date))
                Divider()
                detailRow(title: "時間", value: combinedTimeRange(times))
                Divider()
                detailRow(title: "レッスン時間", value: "\(times.count)時間")
                Divider()
                detailRow(title: "料金", value: "¥\(totalPrice)")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(18)

            Text("予約内容はマイページから確認できます。")
                .foregroundStyle(.secondary)

            Spacer()

            VStack(spacing: 15) {
                Button {
                    showChat = true
                } label: {
                    Text("チャットを開く")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                }

                Button {
                    print("支払い完了画面のホームボタンが押されました")

                    NotificationCenter.default.post(
                        name: .returnToStudentHome,
                        object: nil
                    )
                } label: {
                    Text("ホームへ戻る")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(15)
                }
            }
        }
        .padding()
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $showChat) {
            ChatView(coach: coach)
        }
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
        guard let first = times.sorted().first,
              let last = times.sorted().last else {
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
        BookingCompleteView(
            coach: sampleCoaches[0],
            date: Date(),
            times: ["09:00", "10:00"],
            totalPrice: sampleCoaches[0].price * 2
        )
    }
}
