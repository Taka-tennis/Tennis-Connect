import SwiftUI
import FirebaseFirestore

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

    let db = Firestore.firestore()

    var body: some View {

        Section {

            Button("登録する") {

                db.collection("coaches").addDocument(data: [
                    "name": name,
                    "area": area,
                    "career": career,
                    "price": Int(price) ?? 0,
                    "imageURL": imageURL,
                    "introduction": introduction,
                    "specialty": specialty,
                    "rating": 5.0,
                    "reviewCount": 0,
                    "availableTimes": availableTimes.components(separatedBy: ","),
                    "ageGroup": ageGroup
                ]) { error in

                    if let error = error {
                        print("登録失敗: \(error)")
                        return
                    }

                    print("登録完了")
                    showSuccessAlert = true
                }

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
}

#Preview {
    Text("Preview")
}