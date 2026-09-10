import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct RegisterView: View {

    private let onAuthenticationSuccess: (() -> Void)?

    @State private var displayName = ""
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

            VStack(spacing: 20) {

                Text("新規会員登録")
                    .font(.largeTitle)
                    .bold()

                TextField("表示名", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)

                TextField("メールアドレス", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("パスワード", text: $password)
                    .textFieldStyle(.roundedBorder)

                SecureField("パスワード（確認）", text: $passwordConfirm)
                    .textFieldStyle(.roundedBorder)

                Button("登録する") {

                    let trimmedDisplayName =
                        displayName.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )

                    let trimmedEmail =
                        email.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )

                    guard !trimmedDisplayName.isEmpty else {
                        message = "表示名を入力してください"
                        return
                    }

                    guard trimmedDisplayName.count <= 20 else {
                        message = "表示名は20文字以内で入力してください"
                        return
                    }

                    guard !trimmedEmail.isEmpty,
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
                        withEmail: trimmedEmail,
                        password: password
                    ) { result, error in

                        if let error = error {
                            isRegistering = false
                            message = error.localizedDescription
                            return
                        }

                        print("登録成功")
                        print("UID: \(result?.user.uid ?? "")")

                        guard let user = result?.user else {
                            isRegistering = false
                            message = "会員情報を取得できませんでした"
                            return
                        }

                        let authenticatedEmail =
                            user.email?
                                .trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                            ?? trimmedEmail

                        Firestore.firestore()
                            .collection("students")
                            .document(user.uid)
                            .setData([
                                "displayName": trimmedDisplayName,
                                "email": authenticatedEmail,
                                "createdAt":
                                    FieldValue.serverTimestamp()
                            ]) { error in

                                if let error = error {
                                    print(
                                        "Firestore保存失敗: \(error.localizedDescription)"
                                    )
                                    message =
                                        "会員情報の保存に失敗しました"
                                    isRegistering = false
                                    return
                                }

                                print("Firestore保存成功")
                                isRegistering = false
                                onAuthenticationSuccess?()
                            }
                    }

                }
                .frame(maxWidth: .infinity)
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
