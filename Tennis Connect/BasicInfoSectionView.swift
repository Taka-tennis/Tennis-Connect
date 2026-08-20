import SwiftUI

struct BasicInfoSectionView: View {

    @Binding var name: String
    @Binding var area: String
    @Binding var career: String
    @Binding var price: String
    @Binding var ageGroup: String
    @Binding var tennisExperience: String
    @Binding var coachingExperience: String

    var body: some View {
        Group {
            Section("基本情報") {
                TextField("名前", text: $name)

                Picker("年代", selection: $ageGroup) {
                    Text("20代").tag("20代")
                    Text("30代").tag("30代")
                    Text("40代").tag("40代")
                    Text("50代").tag("50代")
                    Text("60代以上").tag("60代以上")
                }

                TextField("活動エリア・最寄り駅", text: $area)

                TextField("料金", text: $price)
                    .keyboardType(.numberPad)
            }

            Section("経験・経歴") {
                TextField(
                    "テニス歴（例：15年）",
                    text: $tennisExperience
                )

                TextField(
                    "指導歴（例：5年）",
                    text: $coachingExperience
                )

                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        if career.isEmpty {
                            Text("経歴（複数ある場合は改行）")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $career)
                            .frame(minHeight: 110)
                            .scrollContentBackground(.hidden)
                    }

                    Text(
                        "大会実績・所属歴・指導実績などを、1項目ずつ改行して入力できます。"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}
