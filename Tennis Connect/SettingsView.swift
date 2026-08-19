import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

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
                    TermsOfServiceView()
                } label: {
                    Label("利用規約", systemImage: "doc.text")
                }

                NavigationLink {
                    PrivacyPolicyView()
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

            Section("アカウント管理") {
                NavigationLink {
                    AccountDeletionCheckView()
                } label: {
                    Label(
                        "アカウントを削除",
                        systemImage: "person.crop.circle.badge.minus"
                    )
                    .foregroundStyle(.red)
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



private struct AccountDeletionCheckView: View {

    @State private var isChecking = false
    @State private var isDeleting = false
    @State private var eligible: Bool?
    @State private var blockerMessages: [String] = []
    @State private var errorMessage = ""
    @State private var showDeleteConfirmation = false

    private let functions = Functions.functions(
        region: "asia-northeast1"
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.orange)

                Text("アカウント削除")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(
                    "アカウントを削除する前に、未処理の予約や返金が残っていないか確認します。"
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                if isChecking {
                    ProgressView("確認中…")
                        .padding(.vertical, 8)
                }

                if let eligible {
                    if eligible {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 42))
                                .foregroundStyle(.green)

                            Text("削除を進められる状態です")
                                .font(.headline)

                            Text(
                                "この確認ではまだアカウントやデータは削除されません。"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6))
                        .clipShape(
                            RoundedRectangle(cornerRadius: 16)
                        )
                    } else {
                        VStack(
                            alignment: .leading,
                            spacing: 12
                        ) {
                            Label(
                                "現在は削除できません",
                                systemImage: "xmark.circle.fill"
                            )
                            .font(.headline)
                            .foregroundStyle(.red)

                            ForEach(
                                Array(
                                    Set(blockerMessages)
                                ).sorted(),
                                id: \.self
                            ) { message in
                                Label(
                                    message,
                                    systemImage: "exclamationmark.circle"
                                )
                                .font(.subheadline)
                            }
                        }
                        .padding()
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .background(Color(.systemGray6))
                        .clipShape(
                            RoundedRectangle(cornerRadius: 16)
                        )
                    }
                }

                if eligible == true {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()

                            if isDeleting {
                                ProgressView()
                            } else {
                                Label(
                                    "アカウントを完全に削除",
                                    systemImage: "trash.fill"
                                )
                                .fontWeight(.semibold)
                            }

                            Spacer()
                        }
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isDeleting || isChecking)

                    Text(
                        "この操作は取り消せません。プロフィールなどのアカウントデータが削除されます。"
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    checkEligibility()
                } label: {
                    HStack {
                        Spacer()

                        if isChecking {
                            ProgressView()
                        } else {
                            Label(
                                "削除条件を確認する",
                                systemImage: "checklist"
                            )
                            .fontWeight(.semibold)
                        }

                        Spacer()
                    }
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isChecking)

                Text(
                    "支払い済みの今後の予約や返金処理中の予約などがある場合は、先にそれらの処理を完了する必要があります。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("アカウント削除")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "アカウントを完全に削除しますか？",
            isPresented: $showDeleteConfirmation
        ) {
            Button("キャンセル", role: .cancel) { }

            Button("削除する", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text(
                "この操作は取り消せません。削除条件をサーバー側でも再確認したうえで、アカウントを削除します。"
            )
        }
    }

    private func checkEligibility() {
        guard Auth.auth().currentUser != nil else {
            errorMessage =
                "アカウント削除の確認にはログインが必要です。"
            eligible = nil
            blockerMessages = []
            return
        }

        isChecking = true
        errorMessage = ""
        eligible = nil
        blockerMessages = []

        functions
            .httpsCallable("checkAccountDeletionEligibility")
            .call([:]) { result, error in
                DispatchQueue.main.async {
                    isChecking = false

                    if let error {
                        errorMessage =
                            "削除条件を確認できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    guard
                        let data = result?.data as? [String: Any],
                        let canDelete = data["eligible"] as? Bool
                    else {
                        errorMessage =
                            "削除条件の確認結果を読み取れませんでした。"
                        return
                    }

                    let blockers =
                        data["blockers"] as? [[String: Any]] ?? []

                    blockerMessages = blockers.compactMap {
                        $0["reason"] as? String
                    }

                    eligible = canDelete
                }
            }
    }

    private func deleteAccount() {
        guard Auth.auth().currentUser != nil else {
            errorMessage =
                "アカウント削除にはログインが必要です。"
            return
        }

        guard eligible == true else {
            errorMessage =
                "先に削除条件を確認してください。"
            return
        }

        isDeleting = true
        errorMessage = ""

        functions
            .httpsCallable("deleteAccount")
            .call(["confirm": true]) { _, error in
                DispatchQueue.main.async {
                    isDeleting = false

                    if let error {
                        errorMessage =
                            "アカウントを削除できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    do {
                        try Auth.auth().signOut()
                    } catch {
                        // サーバー側では削除済みのため、
                        // 画面遷移を優先します。
                    }

                    NotificationCenter.default.post(
                        name: .returnToStartScreen,
                        object: nil
                    )
                }
            }
    }
}


private struct TermsOfServiceView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Tennis Connect 利用規約")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(
                    "この利用規約（以下「本規約」といいます。）は、Tennis Connect運営（以下「運営者」といいます。）が提供するTennis Connect（以下「本サービス」といいます。）の利用条件を定めるものです。利用者は、本規約に同意のうえ本サービスを利用するものとします。"
                )
                .font(.body)

                termsSection(
                    title: "1. 適用",
                    text: """
                    本規約は、本サービスを利用するすべての利用者に適用されます。

                    本サービス内で個別のルール、ガイドライン、キャンセルポリシーその他の定めが表示されている場合、それらは本規約の一部を構成します。本規約と個別の定めが矛盾する場合は、個別の定めが優先して適用されます。
                    """
                )

                termsSection(
                    title: "2. 本サービスの内容",
                    text: """
                    本サービスは、テニスレッスンを希望する利用者と、レッスンを提供するコーチとの間で、コーチ情報の閲覧、予約、連絡、決済、レビューその他必要な機能を利用できる場を提供します。

                    運営者は、本サービス上の機能を通じてマッチングや取引を支援しますが、実際のレッスン内容、指導方法、実施場所その他コーチが提供する役務については、原則として当該コーチが責任を負います。
                    """
                )

                termsSection(
                    title: "3. アカウント登録・管理",
                    text: """
                    利用者は、登録にあたり正確かつ最新の情報を提供するものとします。

                    利用者は、自身のアカウントおよび認証情報を適切に管理し、第三者に不正に利用させてはなりません。

                    アカウントが不正利用された、またはそのおそれがあることを知った場合は、速やかに運営者へ連絡してください。
                    """
                )

                termsSection(
                    title: "4. 未成年者の利用",
                    text: """
                    未成年者が本サービスを利用する場合は、必要に応じて親権者その他の法定代理人の同意を得たうえで利用してください。
                    """
                )

                termsSection(
                    title: "5. コーチとしての利用",
                    text: """
                    コーチとして本サービスを利用する者は、プロフィール、経歴、料金、対応可能日時その他登録する情報について、虚偽または誤解を招く表示を行ってはなりません。

                    コーチは、自ら提供するレッスンについて、利用者の安全に十分配慮し、関係法令および本サービス上のルールを遵守するものとします。
                    """
                )

                termsSection(
                    title: "6. 予約・決済",
                    text: """
                    レッスンの予約は、本サービス上に表示される手順に従って行うものとします。

                    レッスン料金その他の支払額は、予約時に本サービス上に表示される内容に従います。

                    本サービスでは決済処理のためStripe等の外部決済サービスを利用する場合があります。決済の処理には、当該外部サービスの規約等が適用される場合があります。
                    """
                )

                termsSection(
                    title: "7. キャンセル・返金",
                    text: """
                    予約のキャンセル、返金その他予約後の取扱いについては、本サービス内に掲載するキャンセルポリシーに従います。

                    コーチ都合によるキャンセルその他返金の対象となる場合は、本サービス上で定める方法により返金処理を行います。
                    """
                )

                termsSection(
                    title: "8. チャット・プロフィール・レビュー等",
                    text: """
                    利用者は、チャット、プロフィール、レビューその他本サービス上に投稿または登録する内容について、自ら責任を負うものとします。

                    他者の権利を侵害する内容、虚偽の内容、誹謗中傷、脅迫、差別的表現、わいせつな内容、営業・勧誘を目的とする迷惑行為その他本規約に違反する内容を投稿してはなりません。

                    運営者は、本規約に違反する内容または本サービスの安全な運営上不適切と判断した内容について、必要に応じて非表示または削除等の措置を行う場合があります。
                    """
                )

                termsSection(
                    title: "9. 禁止事項",
                    text: """
                    利用者は、本サービスの利用にあたり、次の行為を行ってはなりません。

                    ・法令または公序良俗に違反する行為
                    ・他の利用者または第三者の権利、利益、プライバシーを侵害する行為
                    ・虚偽の情報を登録または投稿する行為
                    ・嫌がらせ、誹謗中傷、脅迫、差別その他他者に不利益を与える行為
                    ・本サービスを不正に操作し、または運営を妨害する行為
                    ・他人のアカウントを利用する行為
                    ・不正アクセス、リバースエンジニアリングその他本サービスの安全性を害する行為
                    ・本サービスの仕組みを不当に回避し、または不正な利益を得る行為
                    ・その他運営者が本サービスの運営上不適切と合理的に判断する行為
                    """
                )

                termsSection(
                    title: "10. 利用停止・投稿削除等",
                    text: """
                    運営者は、利用者が本規約に違反した場合、不正利用のおそれがある場合、他の利用者の安全を害するおそれがある場合その他本サービスの運営上必要と合理的に判断した場合、事前の通知なく、投稿の削除、機能の制限、アカウントの利用停止その他必要な措置を行う場合があります。
                    """
                )

                termsSection(
                    title: "11. アカウント削除",
                    text: """
                    利用者は、本サービス内の設定画面からアカウント削除を申し込むことができます。

                    未処理の予約、これから実施される支払い済み予約、返金処理中の予約その他処理を完了する必要がある事項が残っている場合、当該事項の処理が完了するまでアカウントを削除できない場合があります。

                    アカウント削除後のデータの取扱いについては、プライバシーポリシーに従います。
                    """
                )

                termsSection(
                    title: "12. 知的財産権",
                    text: """
                    本サービスに関するプログラム、デザイン、ロゴ、文章その他運営者が作成したコンテンツに関する権利は、運営者または正当な権利者に帰属します。

                    利用者が本サービスへ投稿した文章、画像その他のコンテンツについて、利用者は投稿に必要な権利を有していることを確認するものとします。
                    """
                )

                termsSection(
                    title: "13. サービスの変更・中断",
                    text: """
                    運営者は、保守、障害対応、セキュリティ上の必要、法令への対応その他合理的な理由がある場合、本サービスの全部または一部を変更、中断または終了することがあります。

                    重要な変更を行う場合は、可能な範囲で本サービス内その他適切な方法によりお知らせします。
                    """
                )

                termsSection(
                    title: "14. 責任",
                    text: """
                    運営者は、本サービスを安全かつ安定して提供できるよう努めますが、通信環境、端末、外部サービスその他運営者が合理的に管理できない事由により、本サービスが一時的に利用できない場合があります。

                    利用者間または利用者とコーチとの間で問題が生じた場合、運営者は必要に応じて事実確認その他合理的な範囲で対応します。

                    運営者の責めに帰すべき事由により利用者に損害が生じた場合の責任については、適用される法令に従うものとします。本規約は、法令上認められない範囲で運営者の責任を免除または制限するものではありません。
                    """
                )

                termsSection(
                    title: "15. 本規約の変更",
                    text: """
                    運営者は、法令の変更、本サービスの内容変更その他必要に応じて、本規約を変更することがあります。

                    重要な変更を行う場合は、本サービス内での表示その他適切な方法により利用者へお知らせします。
                    """
                )

                termsSection(
                    title: "16. 準拠法・裁判管轄",
                    text: """
                    本規約は日本法を準拠法とします。

                    本サービスに関して紛争が生じた場合は、まず当事者間で誠実に協議するものとし、解決しない場合の裁判管轄については、適用される法令に従います。
                    """
                )

                termsSection(
                    title: "17. お問い合わせ",
                    text: """
                    本規約に関するお問い合わせは、Tennis Connect内の「お問い合わせ」からご連絡ください。

                    運営者：Tennis Connect運営
                    連絡先メールアドレス：［正式なメールアドレスを公開前に記載］
                    制定日：［公開日を記載］
                    """
                )

                Text(
                    "※ 本内容は公開前の草案です。正式リリース前に、実際のサービス運用・料金・キャンセル条件・利用者間の契約関係等と一致しているかを確認し、必要に応じて専門家の確認を受けてください。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .padding()
        }
        .navigationTitle("利用規約")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func termsSection(
        title: String,
        text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


private struct PrivacyPolicyView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Tennis Connect プライバシーポリシー")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(
                    "Tennis Connect運営（以下「運営者」といいます。）は、Tennis Connect（以下「本サービス」といいます。）における利用者の情報を、以下のとおり取り扱います。"
                )
                .font(.body)

                policySection(
                    title: "1. 取得する情報",
                    text: """
                    本サービスでは、サービスの提供に必要な範囲で、メールアドレス、表示名、ユーザーID等のアカウント情報を取得します。

                    コーチとして本サービスを利用する場合、氏名または表示名、年代、活動地域、テニス歴、指導歴、経歴、自己紹介、得意分野、レッスン料金、対応可能日時、プロフィール画像その他プロフィールに入力された情報を取得する場合があります。

                    また、本サービスの利用に伴い、予約情報、レッスン料金、支払い・返金状況、お気に入り情報、レビューおよび評価、チャットの内容、お問い合わせ内容、通知に関する情報その他本サービスの利用履歴を取得する場合があります。

                    決済についてはStripeを利用し、決済処理に必要な情報はStripeを通じて処理されます。本サービスでは、決済金額、決済状況、返金状況、決済を識別するための情報等、サービス運営に必要な情報を取り扱う場合があります。
                    """
                )

                policySection(
                    title: "2. 利用目的",
                    text: """
                    取得した情報は、本サービスのアカウント管理、コーチプロフィールの表示、コーチと生徒のマッチング、予約の受付・承認・管理、決済および返金処理、チャット機能、レビュー・評価機能、お気に入り機能、通知機能、お問い合わせ対応、不正利用の防止、本サービスの安全性確保、障害対応およびサービス改善のために利用します。

                    取得した情報を、あらかじめ明示した利用目的と合理的な関連性を有する範囲を超えて利用する必要が生じた場合には、法令に従い必要な対応を行います。
                    """
                )

                policySection(
                    title: "3. 外部サービスの利用",
                    text: """
                    本サービスでは、サービス提供のために、Googleが提供するFirebaseおよびStripeが提供する決済関連サービス等の外部サービスを利用します。

                    これらの外部サービスにおいて、サービス提供、認証、データ保存、決済、不正利用防止、セキュリティ確保等のために、利用者に関する情報が処理される場合があります。

                    外部サービスにおける情報の取扱いについては、各サービス提供者が定めるプライバシーポリシーその他の規約が適用される場合があります。
                    """
                )

                policySection(
                    title: "4. 第三者提供および委託",
                    text: """
                    運営者は、法令に基づく場合その他法令上認められる場合を除き、利用者本人の同意なく個人データを第三者へ提供しません。

                    ただし、本サービスの提供に必要な範囲で、クラウドサービス、認証サービス、決済サービスその他の業務委託先に情報の取扱いを委託する場合があります。その場合、運営者は必要かつ適切な管理に努めます。
                    """
                )

                policySection(
                    title: "5. 情報の保存および削除",
                    text: """
                    運営者は、本サービスを提供するために必要な期間、または法令上保存が必要となる期間、利用者に関する情報を保存します。

                    利用者は、本サービス内の設定画面からアカウント削除を申し込むことができます。

                    アカウント削除が完了した場合、法令その他正当な理由により保存する必要がある情報を除き、アカウント情報、プロフィール情報その他当該アカウントに関連する個人データを削除します。

                    予約、支払いまたは返金等の未処理事項がある場合、安全に処理を完了するため、未処理事項の完了後にアカウント削除が可能となる場合があります。
                    """
                )

                policySection(
                    title: "6. 安全管理",
                    text: """
                    運営者は、個人情報への不正アクセス、漏えい、滅失、毀損その他の事故を防止するため、アクセス権限の管理、認証、データベースのアクセス制御その他合理的かつ適切な安全管理措置を講じるよう努めます。
                    """
                )

                policySection(
                    title: "7. 利用者による確認・訂正・削除等",
                    text: """
                    利用者は、本サービス上で変更可能なプロフィール情報等について、自ら確認または変更することができます。

                    保有する個人情報について、法令に基づく開示、訂正、利用停止または削除等の請求を希望する場合は、本サービスのお問い合わせ窓口からご連絡ください。
                    """
                )

                policySection(
                    title: "8. プライバシーポリシーの変更",
                    text: """
                    運営者は、法令の変更、本サービスの機能変更その他必要に応じて、本ポリシーを変更することがあります。

                    重要な変更を行う場合は、本サービス内での表示その他適切な方法により利用者へお知らせします。
                    """
                )

                policySection(
                    title: "9. お問い合わせ",
                    text: """
                    本ポリシーおよび個人情報の取扱いに関するお問い合わせは、Tennis Connect内の「お問い合わせ」からご連絡ください。

                    運営者：Tennis Connect運営
                    連絡先メールアドレス：［正式なメールアドレスを公開前に記載］
                    制定日：［公開日を記載］
                    """
                )

                Text(
                    "※ 本内容は公開前の草案です。正式リリース前に、実際の運用・収集データ・外部サービスの利用状況と一致しているか最終確認してください。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .padding()
        }
        .navigationTitle("プライバシーポリシー")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func policySection(
        title: String,
        text: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
