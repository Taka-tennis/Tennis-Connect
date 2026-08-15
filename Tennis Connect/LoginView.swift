import SwiftUI
import FirebaseAuth

struct LoginView: View {

    private let onAuthenticationSuccess: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""

    @State private var errorMessage = ""
    @State private var showRegister = false
    @State private var isLoggingIn = false

    init(
        onAuthenticationSuccess: (() -> Void)? = nil
    ) {
        self.onAuthenticationSuccess = onAuthenticationSuccess
    }

    var body: some View {

        NavigationStack {

            VStack(spacing: 20) {

                Text("Tennis Connect")
                    .font(.largeTitle)
                    .bold()

                TextField("メールアドレス", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)

                SecureField("パスワード", text: $password)
                    .textFieldStyle(.roundedBorder)

                Button("ログイン") {

                    guard !email.isEmpty,
                          !password.isEmpty else {
                        errorMessage =
                            "メールアドレスとパスワードを入力してください"
                        return
                    }

                    isLoggingIn = true
                    errorMessage = ""

                    Auth.auth().signIn(
                        withEmail: email,
                        password: password
                    ) { result, error in

                        if let error = error {

                            isLoggingIn = false
                            errorMessage = error.localizedDescription
                            print("ログイン失敗: \(error.localizedDescription)")

                        } else {

                            print("ログイン成功")
                            print("UID: \(result?.user.uid ?? "")")

                            isLoggingIn = false
                            onAuthenticationSuccess?()
                            dismiss()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
                .disabled(isLoggingIn)

                if isLoggingIn {
                    ProgressView("ログイン中…")
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Spacer()
                Button("新規会員登録はこちら") {
                    showRegister = true
                }
                .padding(.top)
            }
            .padding()
            .navigationDestination(isPresented: $showRegister) {
                RegisterView {
                    onAuthenticationSuccess?()
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    LoginView()
}
