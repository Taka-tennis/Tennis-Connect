import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct RegisterButtonSectionView: View {

    @Binding var name: String
    @Binding var area: String
    @Binding var career: String
    @Binding var price: String
    @Binding var imageURL: String
    @Binding var introduction: String
    @Binding var specialty: String
    @Binding var availableTimes: String
    @Binding var ageGroup: String
    @Binding var showSuccessAlert: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var registrationError = ""

    let db = Firestore.firestore()

    var body: some View {

        Section {

            Button("登録する") {
                registerCoach()
            }

            if !registrationError.isEmpty {
                Text(registrationError)
                    .font(.caption)
                    .foregroundColor(.red)
            }

        }
        .alert("登録完了", isPresented: $showSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("コーチを登録しました！")
        }
    }

    private func registerCoach() {

        guard let uid = Auth.auth().currentUser?.uid else {
            registrationError = "コーチ登録にはログインが必要です"
            return
        }

        registrationError = ""

        let coachRef = db.collection("coaches").document(uid)
        let batch = db.batch()

        batch.setData(
            [
                "coachId": coachRef.documentID,
                "ownerId": uid,
                "name": name,
                "area": area,
                "career": career,
                "price": Int(price) ?? 0,
                "imageURL": imageURL,
                "introduction": introduction,
                "specialty": specialty,
                "rating": 5.0,
                "reviewCount": 0,
                "availableTimes": availabilityEntries,
                "ageGroup": ageGroup
            ],
            forDocument: coachRef
        )

        for (date, times) in groupedAvailability {

            let dateRef = db.collection("coachAvailability")
                .document(coachRef.documentID)
                .collection("dates")
                .document(date)

            batch.setData(
                ["times": times.sorted()],
                forDocument: dateRef
            )
        }

        batch.commit { error in

            if let error = error {
                print("登録失敗: \(error)")
                registrationError =
                    "登録に失敗しました: \(error.localizedDescription)"
                return
            }

            print("登録完了: \(coachRef.documentID)")
            showSuccessAlert = true
        }
    }

    private var availabilityEntries: [String] {

        availableTimes
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var groupedAvailability: [String: [String]] {

        var grouped: [String: [String]] = [:]

        for entry in availabilityEntries {

            let parts = entry.split(
                separator: " ",
                maxSplits: 1
            )

            guard parts.count == 2 else {
                continue
            }

            let date = String(parts[0])
                .replacingOccurrences(of: "/", with: "-")

            let timeRange = String(parts[1])
                .replacingOccurrences(of: "~", with: "〜")

            guard let startTime = timeRange
                .components(separatedBy: "〜")
                .first,
                  !startTime.isEmpty else {
                continue
            }

            if !(grouped[date] ?? []).contains(startTime) {
                grouped[date, default: []].append(startTime)
            }
        }

        return grouped
    }
}

#Preview {
    Text("Preview")
}
