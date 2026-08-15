import SwiftUI
import FirebaseFirestore

struct ReservationDetailView: View {

    let reservation: ReservationItem
    let db = Firestore.firestore()
    
    @Environment(\.dismiss) private var dismiss

    @State private var showCancelAlert = false

    var body: some View {

        ScrollView {

            VStack(spacing: 24) {

                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 70))
                    .foregroundStyle(.green)

                Text("予約詳細")
                    .font(.largeTitle)
                    .bold()

                VStack(spacing: 16) {

                    row(title: "コーチ", value: reservation.coachName)

                    Divider()

                    row(title: "日付", value: reservation.date)

                    Divider()

                    row(title: "時間", value: reservation.time)

                    Divider()

                    row(title: "料金", value: "¥3,000")
                    Divider()

                    row(title: "ステータス", value: "予約済み")

                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(18)

                Button {

                } label: {

                    Text("チャットを開く")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(15)

                }

                Button {
                    showCancelAlert = true
                } label: {

                    Text("予約をキャンセル")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                        .alert("予約をキャンセルしますか？", isPresented: $showCancelAlert) {

                            Button("いいえ", role: .cancel) { }

                            Button("はい", role: .destructive) {
                                cancelReservation()
                            }

                        } message: {

                            Text("この操作は元に戻せません。")

                        }
                }

            }
            .padding()

        }

    }

   
    func cancelReservation() {
        
        print("coachId = \(reservation.coachId)")
        print("date = \(reservation.date)")
        print("time = \(reservation.time)")
        
        let availabilityRef = db.collection("coachAvailability")
            .document("sampleCoach")
            .collection("dates")
            .document(reservation.date)
        
        availabilityRef.getDocument { snapshot, error in

            guard let data = snapshot?.data(),
                  var times = data["times"] as? [String] else {
                return
            }

            times.append(reservation.time)
            times.sort()

            availabilityRef.updateData([
                "times": times
            ]) { error in

                if let error = error {
                    print("空き時間更新失敗: \(error.localizedDescription)")
                    return
                }

                db.collection("reservations")
                    .document(reservation.id)
                    .delete { error in

                        if let error = error {
                            print("削除失敗: \(error.localizedDescription)")
                        } else {
                            print("予約削除成功")
                            dismiss()
                        }
                    }
            }
        }

    }
    func row(title: String, value: String) -> some View {

        HStack {

            Text(title)

            Spacer()

            Text(value)
                .bold()

        }

    }

}

#Preview {
    ReservationDetailView(
        reservation: ReservationItem(
            id: "1",
            coachId: "coach1",
            coachName: "山田コーチ",
            date: "2026-07-29",
            time: "13:00",
            status: "reserved"
        )
    )
}
