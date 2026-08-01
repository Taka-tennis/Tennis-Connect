import SwiftUI
import FirebaseFirestore

struct PaymentView: View {

    let coach: Coach
    let date: Date
    let time: String

    @State private var paymentMethod = "Apple Pay"
    @State private var showComplete = false

    let db = Firestore.firestore()

    var body: some View {

        VStack(spacing: 25) {

            Text("💳 支払い")
                .font(.largeTitle)
                .bold()

            VStack(alignment: .leading, spacing: 16) {

                Text("予約内容")
                    .font(.headline)

                Divider()

                HStack {
                    Text("コーチ")
                    Spacer()
                    Text(coach.name)
                }

                HStack {
                    Text("日付")
                    Spacer()
                    Text(date.formatted(date: .long, time: .omitted))
                }

                HStack {
                    Text("時間")
                    Spacer()
                    Text(time)
                }

            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(16)

            VStack(alignment: .leading) {

                Text("支払い方法")
                    .font(.headline)

                Picker("", selection: $paymentMethod) {

                    Text("Apple Pay")
                        .tag("Apple Pay")

                    Text("クレジットカード")
                        .tag("クレジットカード")

                }
                .pickerStyle(.inline)

            }

            Spacer()

            Text("合計")
                .font(.headline)

            Text("¥\(coach.price)")
                .font(.largeTitle)
                .bold()

            Button {
                saveReservation()
            } label: {

                Text("支払いを完了する")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(15)

            }

        }
        .padding()
        .navigationDestination(isPresented: $showComplete) {
            BookingCompleteView(
                coach: coach,
                date: date,
                time: time
                
            )
        }

    }
    func saveReservation() {

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        db.collection("reservations").addDocument(data: [

            "coachName": coach.name,
            "date": formatter.string(from: date),
            "time": time,
            "price": coach.price,
            "paymentMethod": paymentMethod,
            "createdAt": Timestamp()

        ]) { error in

            if let error = error {
                print("保存失敗: \(error.localizedDescription)")
            } else {
                print("予約保存成功")
                showComplete = true
            }

        }

    }
}
