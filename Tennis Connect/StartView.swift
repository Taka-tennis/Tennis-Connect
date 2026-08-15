// 修正版: ホーム左上の戻るボタンからスタート画面へ戻る通知を受信します
// Xcode内の既存の StartView.swift を、このファイルの内容で全置換してください
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

struct StartView: View {

    @State private var showCoachLogin = false
    @State private var showCoachHome = false
    @State private var showCoachRegister = false
    @State private var showStudentHome = false
    @State private var studentHomeId = UUID()
    @State private var shouldRouteAfterAuthentication = false
    @State private var isCheckingCoach = false
    @State private var coachErrorMessage = ""

    private let db = Firestore.firestore()

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

                Button {
                    showStudentHome = true
                } label: {
                    Text("レッスンを受ける")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                }

                Button {
                    handleCoachEntry()
                } label: {
                    Text("コーチはこちら")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(15)
                }
                .disabled(isCheckingCoach)

                Button {
                    handleCoachEntry()
                } label: {
                    Text("コーチ登録はこちら")
                        .underline()
                }
                .disabled(isCheckingCoach)

                if isCheckingCoach {
                    ProgressView("確認中…")
                }

                if !coachErrorMessage.isEmpty {
                    Text(coachErrorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .navigationBarHidden(true)
            .navigationDestination(
                isPresented: $showStudentHome
            ) {
                MainTabView()
                    .id(studentHomeId)
                    .navigationBarBackButtonHidden(true)
            }
            .navigationDestination(
                isPresented: $showCoachHome
            ) {
                CoachHomeView()
            }
            .navigationDestination(
                isPresented: $showCoachRegister
            ) {
                CoachRegisterView()
            }
            .sheet(
                isPresented: $showCoachLogin,
                onDismiss: {
                    if shouldRouteAfterAuthentication {
                        shouldRouteAfterAuthentication = false
                        routeAuthenticatedCoach()
                    }
                }
            ) {
                LoginView {
                    shouldRouteAfterAuthentication = true
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .returnToStudentHome
                )
            ) { _ in
                print("StartViewでホーム通知を受信しました")

                // 現在の予約・支払い画面を含む生徒側の画面を
                // いったんすべて閉じてから、ホームを開き直す。
                showStudentHome = false

                DispatchQueue.main.async {
                    studentHomeId = UUID()
                    showStudentHome = true
                    print("生徒ホームを開き直しました")
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .returnToStartScreen
                )
            ) { _ in
                print("スタート画面へ戻ります")
                studentHomeId = UUID()
                showStudentHome = false
            }
        }
    }

    private func handleCoachEntry() {

        coachErrorMessage = ""

        guard Auth.auth().currentUser != nil else {
            shouldRouteAfterAuthentication = false
            showCoachLogin = true
            return
        }

        routeAuthenticatedCoach()
    }

    private func routeAuthenticatedCoach() {

        guard let uid = Auth.auth().currentUser?.uid else {
            showCoachLogin = true
            return
        }

        isCheckingCoach = true
        coachErrorMessage = ""

        db.collection("coaches")
            .document(uid)
            .getDocument { snapshot, error in

                DispatchQueue.main.async {

                    isCheckingCoach = false

                    if let error = error {
                        coachErrorMessage =
                            "コーチ情報を確認できませんでした: \(error.localizedDescription)"
                        return
                    }

                    if snapshot?.exists == true {
                        showCoachHome = true
                    } else {
                        showCoachRegister = true
                    }
                }
            }
    }
}

#Preview {
    StartView()
}
