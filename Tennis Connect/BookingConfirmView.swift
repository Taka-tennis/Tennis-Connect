import SwiftUI

struct BookingConfirmView: View {
    
    @State private var showPayment = false

    let coach: Coach
    let date: Date
    let time: String

    var body: some View {

        VStack(spacing: 25) {

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 70))
                .foregroundStyle(.green)

            Text("予約内容確認")
                .font(.largeTitle)
                .bold()

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

            Spacer()

            Button {
                showPayment = true
            } label: {

                Text("支払いへ進む")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(15)

            }

        }
        .padding()
        .navigationDestination(isPresented: $showPayment) {
            PaymentView(
                coach: coach,
                date: date,
                time: time
            )
        }

    }
}
