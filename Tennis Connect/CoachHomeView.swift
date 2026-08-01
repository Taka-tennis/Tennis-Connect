import SwiftUI

struct CoachHomeView: View {

    var body: some View {

        NavigationStack {

            VStack(spacing: 25) {

                Text("🎾 コーチホーム")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                NavigationLink {
                    CoachRegisterView()
                } label: {

                    Label("プロフィールを編集", systemImage: "person")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(15)

                }

                Button {

                } label: {

                    Label("予約一覧", systemImage: "calendar")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(15)

                }

                Button {

                } label: {

                    Label("売上管理", systemImage: "yensign.circle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(15)

                }

                Spacer()

            }
            .padding()
            .navigationTitle("コーチ")
        }

    }
}

#Preview {
    CoachHomeView()
}
