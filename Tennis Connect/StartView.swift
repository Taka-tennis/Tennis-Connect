import SwiftUI

struct StartView: View {
    var body: some View {
        NavigationStack {

            VStack(spacing: 30) {

                Spacer()

                Image(systemName: "tennis.racket")
                    .font(.system(size: 80))
                    .foregroundColor(.green)

                Text("Tennis Connect")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("コーチと生徒をつなぐアプリ")
                    .foregroundColor(.gray)

                Spacer()

                NavigationLink {
                    MainTabView()
                } label: {
                    Text("レッスンを受ける")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                }

                NavigationLink {
                    CoachHomeView()
                } label: {
                    Text("コーチはこちら")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                }

                NavigationLink {
                    CoachRegisterView()
                } label: {
                    Text("コーチ登録はこちら")
                        .underline()
                }

            }
            .padding()
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    StartView()
}
