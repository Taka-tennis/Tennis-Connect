import SwiftUI
import FirebaseFirestore

struct Reservation: Identifiable {
    let id: String
    let coachName: String
    let date: String
    let time: String
    let price: Int
}

struct ReservationListView: View {

    @State private var reservations: [Reservation] = []

    let db = Firestore.firestore()

    var body: some View {

        NavigationStack {

            List(reservations) { reservation in

                NavigationLink {
                    ReservationDetailView(reservation: reservation)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        
                        Text("🎾 \(reservation.coachName)")
                            .font(.headline)
                        
                        Text("📅 \(reservation.date)")
                        
                        Text("🕐 \(reservation.time)")
                        
                        Text("💰 ¥\(reservation.price)")
                            .foregroundStyle(.green)
                        
                    }
                    .padding(.vertical,8)
                }
            }
            .navigationTitle("予約一覧")
            .onAppear {
                fetchReservations()
            }

        }

    }

    func fetchReservations() {

        db.collection("reservations")
            .getDocuments { snapshot, error in

                guard let documents = snapshot?.documents else {
                    return
                }

                reservations = documents.map { document in

                    let data = document.data()

                    return Reservation(
                        id: document.documentID,
                        coachName: data["coachName"] as? String ?? "",
                        date: data["date"] as? String ?? "",
                        time: data["time"] as? String ?? "",
                        price: data["price"] as? Int ?? 0
                    )

                }

            }

    }

}

#Preview {
    ReservationListView()
}
