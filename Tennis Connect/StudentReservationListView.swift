import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct StudentReservationListView: View {

    struct Reservation: Identifiable {
        let id: String
        let coachName: String
        let date: String
        let time: String
        let court: String
        let status: String
    }

    @State private var reservations: [Reservation] = []
    
    func loadReservations() {

        guard let studentId = Auth.auth().currentUser?.uid else {
            print("ログインユーザーが見つかりません")
            return
        }
        print("ログイン中のUID: \(studentId)")

        db.collection("reservations")
            .whereField("studentId", isEqualTo: studentId)
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in

                if let error = error {
                    print("予約取得エラー: \(error.localizedDescription)")
                    return
                }

                guard let documents = snapshot?.documents else {
                    print("予約データがありません")
                    return
                }

                reservations = documents.map { doc in

                    let data = doc.data()

                    return Reservation(
                        id: doc.documentID,
                        coachName: data["coachName"] as? String ?? "コーチ",
                        date: data["date"] as? String ?? "",
                        time: data["time"] as? String ?? "",
                        court: data["court"] as? String ?? "未設定",
                        status: data["status"] as? String ?? "pending"
                    )
                }

                print("自分の予約件数: \(reservations.count)")
            }
    }

    let db = Firestore.firestore()

    var body: some View {

        List(reservations) { reservation in

            VStack(alignment: .leading, spacing: 8) {

                Text(reservation.coachName)
                    .font(.headline)

                Label(reservation.date, systemImage: "calendar")

                Label(reservation.time, systemImage: "clock")

                Label(reservation.court, systemImage: "location")

                if reservation.status == "pending" {

                    Text("🟠 承認待ち")
                        .foregroundColor(.orange)

                } else if reservation.status == "confirmed" {

                    Text("🟢 予約確定")
                        .foregroundColor(.green)

                } else {

                    Text("🔴 却下")
                        .foregroundColor(.red)
                }
            }
            .padding(.vertical,6)
        }
        .navigationTitle("予約一覧")
        .onAppear {
            loadReservations()
        }
    }
}
