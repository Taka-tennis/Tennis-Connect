import SwiftUI

struct BasicInfoSectionView: View {

    @Binding var name: String
    @Binding var area: String
    @Binding var career: String
    @Binding var price: String
    @Binding var ageGroup: String

    var body: some View {

        Section("基本情報") {

            TextField("名前", text: $name)

            Picker("年代", selection: $ageGroup) {
                Text("20代").tag("20代")
                Text("30代").tag("30代")
                Text("40代").tag("40代")
                Text("50代").tag("50代")
                Text("60代以上").tag("60代以上")
            }

            TextField("活動エリア", text: $area)

            TextField("経歴", text: $career)

            TextField("料金", text: $price)
                .keyboardType(.numberPad)
        }
    }
}
