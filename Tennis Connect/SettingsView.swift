import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SettingsView: View {

    private var loginEmail: String {
        Auth.auth().currentUser?.email ?? "未設定"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        List {
            Section("アカウント") {
                HStack {
                    Label("メールアドレス", systemImage: "envelope")
                    Spacer()
                    Text(loginEmail)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("通知") {
                NavigationLink {
                    SettingsInfoView(
                        title: "通知設定",
                        message: "アプリ内通知は利用できます。プッシュ通知の細かな設定は、正式リリースに向けて追加予定です。"
                    )
                } label: {
                    Label("通知設定", systemImage: "bell")
                }
            }

            Section("サポート・ポリシー") {
                NavigationLink {
                    SettingsInfoView(
                        title: "利用規約",
                        message: "正式な利用規約は公開前に設定します。"
                    )
                } label: {
                    Label("利用規約", systemImage: "doc.text")
                }

                NavigationLink {
                    SettingsInfoView(
                        title: "プライバシーポリシー",
                        message: "正式なプライバシーポリシーは公開前に設定します。"
                    )
                } label: {
                    Label("プライバシーポリシー", systemImage: "hand.raised")
                }

                NavigationLink {
                    SettingsInfoView(
                        title: "キャンセルポリシー",
                        message: "正式なキャンセル・返金ルールは公開前に設定します。"
                    )
                } label: {
                    Label("キャンセルポリシー", systemImage: "arrow.uturn.backward.circle")
                }

                NavigationLink {
                    InquiryView()
                } label: {
                    Label("お問い合わせ", systemImage: "questionmark.circle")
                }
            }

            Section("アプリ情報") {
                HStack {
                    Label("バージョン", systemImage: "info.circle")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
    }
}


private struct InquiryView: View {

    private enum InquiryCategory: String, CaseIterable, Identifiable {
        case reservation = "予約について"
        case payment = "支払い・返金について"
        case coach = "コーチについて"
        case account = "アカウントについて"
        case other = "その他"

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: InquiryCategory = .reservation
    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage = ""
    @State private var showSentAlert = false

    private let db = Firestore.firestore()

    private var loginEmail: String {
        Auth.auth().currentUser?.email ?? "未設定"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        Form {
            Section("お問い合わせ種別") {
                Picker("種別", selection: $selectedCategory) {
                    ForEach(InquiryCategory.allCases) { category in
                        Text(category.rawValue)
                            .tag(category)
                    }
                }
            }

            Section("返信先") {
                HStack {
                    Text("メールアドレス")

                    Spacer()

                    Text(loginEmail)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                Text("登録中のメールアドレスを返信先として保存します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("お問い合わせ内容") {
                TextEditor(text: $message)
                    .frame(minHeight: 180)

                HStack {
                    Spacer()

                    Text("\(message.count) / 1000")
                        .font(.caption)
                        .foregroundStyle(
                            message.count > 1000
                                ? .red
                                : .secondary
                        )
                }
            }

            if !errorMessage.isEmpty {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    submitInquiry()
                } label: {
                    HStack {
                        Spacer()

                        if isSending {
                            ProgressView()
                        } else {
                            Label(
                                "送信する",
                                systemImage: "paperplane.fill"
                            )
                            .fontWeight(.semibold)
                        }

                        Spacer()
                    }
                }
                .disabled(
                    isSending ||
                    message.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty ||
                    message.count > 1000
                )
            } footer: {
                Text("送信した内容はTennis Connect運営へのお問い合わせとして保存されます。")
            }
        }
        .navigationTitle("お問い合わせ")
        .navigationBarTitleDisplayMode(.inline)
        .alert("送信しました", isPresented: $showSentAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("お問い合わせを受け付けました。")
        }
    }

    private func submitInquiry() {
        guard let user = Auth.auth().currentUser else {
            errorMessage = "お問い合わせの送信にはログインが必要です。"
            return
        }

        let trimmedMessage = message.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !trimmedMessage.isEmpty else {
            errorMessage = "お問い合わせ内容を入力してください。"
            return
        }

        guard trimmedMessage.count <= 1000 else {
            errorMessage = "お問い合わせ内容は1000文字以内で入力してください。"
            return
        }

        isSending = true
        errorMessage = ""

        db.collection("inquiries")
            .addDocument(
                data: [
                    "userId": user.uid,
                    "email": user.email ?? "",
                    "category": selectedCategory.rawValue,
                    "message": trimmedMessage,
                    "status": "open",
                    "appVersion": appVersion,
                    "createdAt": FieldValue.serverTimestamp()
                ]
            ) { error in
                DispatchQueue.main.async {
                    isSending = false

                    if let error {
                        errorMessage =
                            "送信できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    message = ""
                    showSentAlert = true
                }
            }
    }
}


private struct SettingsInfoView: View {

    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text(title)
                .font(.title2)
                .fontWeight(.bold)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
