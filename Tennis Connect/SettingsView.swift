import SwiftUI
import FirebaseAuth

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
                    SettingsInfoView(
                        title: "お問い合わせ",
                        message: "お問い合わせ窓口は正式リリース前に設定します。"
                    )
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
