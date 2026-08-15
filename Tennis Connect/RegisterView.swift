import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct RegisterView: View {

    private let onAuthenticationSuccess: (() -> Void)?

    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirm = ""

    @State private var message = ""
    @State private var isRegistering = false

    init(
        onAuthenticationSuccess: (() -> Void)? = nil
    ) {
        self.onAuthenticationSuccess = onAuthenticationSuccess
    }

    var body: some View {

        NavigationStack {

            VStack(spacing:20) {

                Text("新規会員登録")
                    .font(.largeTitle)
                    .bold()

                TextField("メールアドレス", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)

                SecureField("パスワード", text: $password)
                    .textFieldStyle(.roundedBorder)

                SecureField("パスワード（確認）", text: $passwordConfirm)
                    .textFieldStyle(.roundedBorder)

                Button("登録する") {

                    guard !email.isEmpty,
                          !password.isEmpty else {
                        message =
                            "メールアドレスとパスワードを入力してください"
                        return
                    }

                    guard password == passwordConfirm else {
                        message = "パスワードが一致しません"
                        return
                    }

                    guard password.count >= 6 else {
                        message =
                            "パスワードは6文字以上で入力してください"
                        return
                    }

                    isRegistering = true
                    message = ""

                    Auth.auth().createUser(
                        withEmail: email,
                        password: password
                    ) { result, error in

                        if let error = error {
                            isRegistering = false
                            message = error.localizedDescription
                        } else {

                            print("登録成功")
                            print("UID: \(result?.user.uid ?? "")")
                            
                            guard let uid = result?.user.uid else {
                                isRegistering = false
                                message = "会員情報を取得できませんでした"
                                return
                            }

                            Firestore.firestore()
                                .collection("students")
                                .document(uid)
                                .setData([
                                    "email": email,
                                    "createdAt": Timestamp()
                                ]) { error in

                                    if let error = error {
                                        print("Firestore保存失敗: \(error.localizedDescription)")
                                    } else {
                                        print("Firestore保存成功")
                                    }

                                    isRegistering = false
                                    onAuthenticationSuccess?()
                                }
                        }

                    }

                }
                .frame(maxWidth:.infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)
                .disabled(isRegistering)

                if isRegistering {
                    ProgressView("登録中…")
                }

                Text(message)
                    .foregroundColor(.red)

            }
            .padding()
        }

    }

}
