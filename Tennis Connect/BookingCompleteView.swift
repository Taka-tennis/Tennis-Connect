import SwiftUI

struct BookingCompleteView: View {
    
    @State private var showChat = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) var presentationMode

    let coach: Coach
    let date: Date
    let time: String

    var body: some View {

        VStack(spacing: 30) {

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 90))
                .foregroundStyle(.green)

            Text("予約が完了しました！")
                .font(.largeTitle)
                .bold()

            Text("ご予約ありがとうございます。")
                .foregroundStyle(.secondary)

            VStack(spacing: 18) {

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
                    Text(date.formatted(date: .long, time: .omitted))
                        .bold()
                }

                Divider()

                HStack {
                    Text("時間")
                    Spacer()
                    Text(time)
                        .bold()
                }

                Divider()

                HStack {
                    Text("料金")
                    Spacer()
                    Text("¥\(coach.price)")
                        .bold()
                        .foregroundStyle(.green)
                }

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
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Text("ホームへ戻る")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.black)
                        .cornerRadius(15)
                }
            }
        }
        .padding()
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $showChat) {
            ChatView(coach: coach)
        }    }
}

#Preview {
    BookingCompleteView(
        coach: sampleCoaches[0],
        date: Date(),
        time: "09:00"
    )
}
