import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

private enum TennisConnectLegalInfo {
    static let operatorDisplayName = "Tennis Connect運営"

    // 公開前に必ず正式情報へ変更してください。
    static let contactEmail = "［公開前に正式なメールアドレスを記載］"
    static let effectiveDate = "［公開日を記載］"

    // 特定商取引法に基づく表記用。
    // 個人運営・法人運営の形態が確定したら正式情報へ変更してください。
    static let legalBusinessName = "［公開前に正式な事業者名を記載］"
    static let representativeName = "［公開前に代表者名を記載］"
    static let businessAddress = "［公開前に所在地を記載］"
    static let businessPhone = "［公開前に電話番号を記載］"

    static let platformFeePercent = 10
    static let coachSharePercent = 90
    static let payoutHoldHours = 24
}


struct SettingsView: View {

    private var loginEmail: String {
        Auth.auth().currentUser?.email ?? "未設定"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?[
            "CFBundleShortVersionString"
        ] as? String ?? "—"
    }

    var body: some View {
        List {
            Section("アカウント") {
                HStack {
                    Label(
                        "メールアドレス",
                        systemImage: "envelope"
                    )

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
                        message:
                            "アプリ内通知は利用できます。" +
                            "プッシュ通知の細かな設定は、" +
                            "正式リリースに向けて追加予定です。"
                    )
                } label: {
                    Label(
                        "通知設定",
                        systemImage: "bell"
                    )
                }
            }

            Section("サポート・ポリシー") {
                NavigationLink {
                    TermsOfServiceView()
                } label: {
                    Label(
                        "利用規約",
                        systemImage: "doc.text"
                    )
                }

                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    Label(
                        "プライバシーポリシー",
                        systemImage: "hand.raised"
                    )
                }

                NavigationLink {
                    CancellationPolicyView()
                } label: {
                    Label(
                        "キャンセル・返金ポリシー",
                        systemImage:
                            "arrow.uturn.backward.circle"
                    )
                }

                NavigationLink {
                    CoachPayoutPolicyView()
                } label: {
                    Label(
                        "コーチの売上・出金について",
                        systemImage: "banknote"
                    )
                }

                NavigationLink {
                    CommercialTransactionView()
                } label: {
                    Label(
                        "特定商取引法に基づく表記",
                        systemImage: "building.columns"
                    )
                }

                NavigationLink {
                    InquiryView()
                } label: {
                    Label(
                        "お問い合わせ",
                        systemImage: "questionmark.circle"
                    )
                }
            }

            Section("アカウント管理") {
                NavigationLink {
                    AccountDeletionCheckView()
                } label: {
                    Label(
                        "アカウントを削除",
                        systemImage:
                            "person.crop.circle.badge.minus"
                    )
                    .foregroundStyle(.red)
                }
            }

            Section("アプリ情報") {
                HStack {
                    Label(
                        "バージョン",
                        systemImage: "info.circle"
                    )

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


private struct CancellationPolicyView: View {

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 22
            ) {
                Text("キャンセル・返金ポリシー")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(
                    "Tennis Connectで確定したレッスンの" +
                    "キャンセルおよび返金は、" +
                    "以下のルールに基づいて処理します。"
                )
                .foregroundStyle(.secondary)

                policyCard(
                    title: "生徒都合のキャンセル",
                    systemImage: "person.fill",
                    rows: [
                        (
                            "開始まで24時間を超える",
                            "100%返金"
                        ),
                        (
                            "開始まで12時間を超え、24時間以下",
                            "50%返金"
                        ),
                        (
                            "開始まで12時間以下",
                            "返金なし"
                        )
                    ]
                )

                Text(
                    "※ 判定は予約されたレッスンの開始時刻を基準に行います。" +
                    "レッスン開始後は、生徒側から通常のキャンセル操作はできません。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                policyCard(
                    title: "コーチ都合のキャンセル",
                    systemImage:
                        "person.crop.circle.badge.xmark",
                    rows: [
                        (
                            "コーチ都合でキャンセル",
                            "原則100%返金"
                        )
                    ]
                )

                legalSection(
                    title: "返金処理について",
                    text: """
                    返金が発生する場合、Tennis ConnectはStripeを通じて返金処理を行います。

                    アプリ上でキャンセルが受け付けられた後も、カード会社等の処理状況によって、実際の利用明細への反映まで時間がかかる場合があります。

                    返金処理中または返金に失敗した場合は、アプリ内の表示やお問い合わせ窓口から状況をご確認ください。
                    """
                )

                legalSection(
                    title: "雨天・施設都合によるキャンセル",
                    text: """
                    屋外コートでの雨天、コート・施設の利用不可その他レッスンの実施が困難となる事情がある場合、生徒またはコーチは、原則としてレッスン開始24時間前から開始時刻までの間に「雨天・施設都合でキャンセル申請」を行うことができます。

                    申請しただけでは予約はキャンセルされず、返金も行われません。相手が申請に同意した場合に限り、双方合意によるキャンセルが成立します。

                    双方合意によるキャンセルが成立した場合、生徒へレッスン料金を100%返金し、当該予約に対応するコーチ売上は発生しません。予約されていた時間枠は、再び予約可能な空き枠へ戻ります。

                    相手が申請に同意しない場合、予約はキャンセルされず、そのまま継続します。

                    申請者は、相手が回答する前であれば申請を取り下げることができます。取り下げた場合も、予約はキャンセルされず、そのまま継続します。

                    Tennis Connect運営者は、通常、雨天の程度やコートの利用可否を個別に判定せず、当事者双方の合意をもってキャンセル成立を判断します。双方で解決できない事情がある場合は、本サービス内の「お問い合わせ」からご連絡ください。
                    """
                )

                Text(
                    "※ 通常キャンセルと雨天・施設都合キャンセルは別の手続きです。" +
                    "雨天・施設都合を理由とする全額返金は、相手の同意が成立した場合に限ります。" +
                    "本ポリシーの内容と、予約時またはキャンセル操作時に表示される条件が" +
                    "異なる場合は、実際の取引画面に表示された条件をご確認ください。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .padding()
        }
        .navigationTitle("キャンセル・返金")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func policyCard(
        title: String,
        systemImage: String,
        rows: [(String, String)]
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            Label(
                title,
                systemImage: systemImage
            )
            .font(.headline)

            ForEach(
                Array(rows.enumerated()),
                id: \.offset
            ) { _, row in
                HStack(
                    alignment: .firstTextBaseline,
                    spacing: 12
                ) {
                    Text(row.0)
                        .font(.subheadline)

                    Spacer()

                    Text(row.1)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            row.1.contains("100")
                                ? .green
                                : row.1.contains("50")
                                    ? .orange
                                    : .red
                        )
                        .multilineTextAlignment(.trailing)
                }

                if row.0 != rows.last?.0 {
                    Divider()
                }
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

    @ViewBuilder
    private func legalSection(
        title: String,
        text: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text(title)
                .font(.headline)

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }
}


private struct CoachPayoutPolicyView: View {

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 22
            ) {
                Text("コーチの売上・出金について")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(
                    "Tennis Connectでレッスンを提供する" +
                    "コーチ向けの、売上・手数料・出金に関する" +
                    "現在のルールです。"
                )
                .foregroundStyle(.secondary)

                VStack(spacing: 14) {
                    payoutSummaryRow(
                        title: "Tennis Connect手数料",
                        value:
                            "\(TennisConnectLegalInfo.platformFeePercent)%"
                    )

                    Divider()

                    payoutSummaryRow(
                        title: "コーチ受取割合",
                        value:
                            "原則\(TennisConnectLegalInfo.coachSharePercent)%"
                    )

                    Divider()

                    payoutSummaryRow(
                        title: "出金可能になる時期",
                        value:
                            "レッスン終了" +
                            "\(TennisConnectLegalInfo.payoutHoldHours)時間後"
                    )
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(
                    RoundedRectangle(cornerRadius: 16)
                )

                legalSection(
                    title: "1. 売上の計算",
                    text: """
                    コーチの受取額は、返金が確定した後の決済残額を基準として計算します。

                    現在のコーチ受取割合は原則90%で、1円未満の端数が生じる場合はコーチ受取額を1円単位で切り捨て、残額をTennis Connect手数料として扱います。

                    全額返金となった予約は、コーチ売上の対象になりません。
                    """
                )

                legalSection(
                    title: "2. 一部返金がある場合",
                    text: """
                    生徒都合のキャンセル等により一部返金が確定した場合は、元の決済金額から確定済み返金額を差し引いた残額を基準に、コーチ受取額とTennis Connect手数料を再計算します。

                    返金処理中または返金結果が確定していない予約は、原則として出金可能額には含まれません。
                    """
                )

                legalSection(
                    title: "3. 出金可能になる時期",
                    text: """
                    対象レッスンの終了時刻から24時間が経過し、支払いおよび返金の状態に問題がないことを確認できた売上が「出金可能」となります。

                    出金可能になる前の売上は「売上予定」として表示されます。
                    """
                )

                legalSection(
                    title: "4. 銀行口座への出金",
                    text: """
                    コーチは、Stripe Connectの本人確認および銀行口座登録が完了した後、アプリ内の「売上受取設定」から出金可能額を銀行口座へ出金できます。

                    出金依頼後は、Stripeおよび金融機関の処理状況に応じて「出金処理中」となり、Stripe上で出金完了が確認された後に「出金済み」として扱います。

                    銀行への着金時期は、Stripe、金融機関、営業日その他の事情により異なる場合があります。
                    """
                )

                legalSection(
                    title: "5. Stripe Connect",
                    text: """
                    本サービスの本人確認、銀行口座登録および出金処理にはStripe Connectを利用します。

                    Stripeの審査、本人確認、口座確認、リスク判定その他Stripe側の要件により、出金機能が一時的に制限される場合があります。
                    """
                )

                legalSection(
                    title: "6. 手数料等の変更",
                    text: """
                    サービス内容、決済コスト、法令その他の事情により、将来手数料または出金条件を変更する場合があります。

                    重要な変更を行う場合は、変更後の条件が適用される前に、本サービス内その他適切な方法でお知らせします。
                    """
                )

                draftNotice
            }
            .padding()
        }
        .navigationTitle("売上・出金")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var draftNotice: some View {
        Text(
            "※ 公開前に、Stripeの本番運用条件、" +
            "税務上の取扱い、振込・出金条件等と一致しているか" +
            "専門家を含めて最終確認してください。"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func payoutSummaryRow(
        title: String,
        value: String
    ) -> some View {
        HStack(
            alignment: .firstTextBaseline
        ) {
            Text(title)

            Spacer()

            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func legalSection(
        title: String,
        text: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text(title)
                .font(.headline)

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }
}


private struct CommercialTransactionView: View {

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 20
            ) {
                Text("特定商取引法に基づく表記")
                    .font(.title2)
                    .fontWeight(.bold)

                VStack(
                    alignment: .leading,
                    spacing: 10
                ) {
                    Label(
                        "公開前に事業者情報の確定が必要です",
                        systemImage:
                            "exclamationmark.triangle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(.orange)

                    Text(
                        "現在は開発用の草案です。" +
                        "運営形態（個人・法人）と、" +
                        "Tennis Connectと各コーチの法的な販売者・" +
                        "役務提供者としての位置付けを確定したうえで、" +
                        "専門家の確認を受けてください。"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.08))
                .clipShape(
                    RoundedRectangle(cornerRadius: 16)
                )

                infoRow(
                    title: "事業者名",
                    value:
                        TennisConnectLegalInfo.legalBusinessName
                )

                infoRow(
                    title: "代表者",
                    value:
                        TennisConnectLegalInfo.representativeName
                )

                infoRow(
                    title: "所在地",
                    value:
                        TennisConnectLegalInfo.businessAddress
                )

                infoRow(
                    title: "電話番号",
                    value:
                        TennisConnectLegalInfo.businessPhone
                )

                infoRow(
                    title: "メールアドレス",
                    value:
                        TennisConnectLegalInfo.contactEmail
                )

                infoRow(
                    title: "販売価格・役務の対価",
                    value:
                        "各コーチ詳細・予約確認画面に表示される金額"
                )

                infoRow(
                    title: "販売価格以外の負担",
                    value:
                        "別途費用が発生する場合は、" +
                        "予約画面その他本サービス内で事前に表示します。" +
                        "インターネット接続等の通信費は利用者負担です。"
                )

                infoRow(
                    title: "支払方法",
                    value:
                        "クレジットカード等、" +
                        "本サービスの決済画面に表示する方法。"
                )

                infoRow(
                    title: "支払時期",
                    value:
                        "予約手続きにおいて、" +
                        "決済画面で支払いが完了した時点。"
                )

                infoRow(
                    title: "役務の提供時期",
                    value:
                        "予約時に確定したレッスン日時。"
                )

                infoRow(
                    title: "キャンセル・返金",
                    value:
                        "通常キャンセルの返金条件、および雨天・施設都合について" +
                        "双方合意により100%返金となる条件は、" +
                        "本サービス内の「キャンセル・返金ポリシー」に従います。"
                )

                infoRow(
                    title: "コーチへの売上・出金",
                    value:
                        "本サービス内の「コーチの売上・出金について」" +
                        "に定める条件に従います。"
                )

                Text(
                    "※ この画面だけで法令上必要な表示が" +
                    "すべて充足することを保証するものではありません。" +
                    "正式公開前に、実際の取引構造・運営主体・" +
                    "料金表示と一致しているか確認してください。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .padding()
        }
        .navigationTitle("特商法表記")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func infoRow(
        title: String,
        value: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            Text(title)
                .font(.headline)

            Text(value)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.bottom, 4)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }
}


private struct TermsOfServiceView: View {

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 24
            ) {
                Text("Tennis Connect 利用規約")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(
                    "この利用規約（以下「本規約」といいます。）は、" +
                    "\(TennisConnectLegalInfo.operatorDisplayName)" +
                    "（以下「運営者」といいます。）が提供する" +
                    "Tennis Connect（以下「本サービス」といいます。）" +
                    "の利用条件を定めるものです。" +
                    "利用者は、本規約に同意のうえ本サービスを利用するものとします。"
                )
                .font(.body)

                termsSection(
                    title: "1. 適用",
                    text: """
                    本規約は、本サービスを利用するすべての利用者に適用されます。

                    本サービス内で個別のルール、ガイドライン、キャンセル・返金ポリシー、コーチの売上・出金に関するルールその他の定めが表示されている場合、それらは本規約の一部を構成します。
                    """
                )

                termsSection(
                    title: "2. 本サービスの内容",
                    text: """
                    本サービスは、テニスレッスンを希望する利用者と、レッスンを提供するコーチとの間で、コーチ情報・プロフィール画像・プレー動画・レビュー等の閲覧、空き時間の確認、予約、チャット、決済、返金、売上管理その他必要な機能を利用できる場を提供します。

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
                    コーチとして本サービスを利用する者は、プロフィール、経歴、テニス歴、指導歴、料金、対応可能日時、プロフィール画像、プレー動画その他登録する情報について、虚偽または誤解を招く表示を行ってはなりません。

                    コーチは、掲載する画像・動画・文章その他のコンテンツについて、自ら利用・掲載するために必要な権利を有していることを確認するものとします。

                    コーチは、自ら提供するレッスンについて利用者の安全に十分配慮し、関係法令、本規約および本サービス上のルールを遵守するものとします。
                    """
                )

                termsSection(
                    title: "6. 予約・決済",
                    text: """
                    レッスンの予約は、本サービス上に表示される手順に従って行うものとします。

                    レッスン料金その他の支払額は、予約または決済時に本サービス上に表示される内容に従います。

                    本サービスでは決済処理のためStripe等の外部決済サービスを利用します。決済処理には、当該外部サービスの規約その他の条件が適用される場合があります。
                    """
                )

                termsSection(
                    title: "7. キャンセル・返金",
                    text: """
                    生徒都合でレッスンを通常キャンセルする場合、レッスン開始時刻までの残り時間が24時間を超える場合は原則100%返金、12時間を超え24時間以下の場合は原則50%返金、12時間以下の場合は原則返金なしとします。

                    コーチ都合で確定済みの予約を通常キャンセルする場合は、原則として生徒へ100%返金します。

                    屋外コートでの雨天、コート・施設の利用不可その他レッスンの実施が困難となる事情がある場合、生徒またはコーチは、原則としてレッスン開始24時間前から開始時刻までの間に、雨天・施設都合によるキャンセル申請を行うことができます。

                    雨天・施設都合による申請は、申請しただけではキャンセルとして成立しません。相手が同意した場合に限り、双方合意によるキャンセルが成立し、生徒へ100%返金します。この場合、当該予約に対応するコーチ売上は発生せず、予約枠は再び予約可能な状態へ戻ります。

                    相手が同意しない場合、または申請者が相手の回答前に申請を取り下げた場合、予約はそのまま継続します。

                    運営者は、通常、雨天の程度や施設利用の可否を個別に判定せず、当事者双方の合意をもって雨天・施設都合キャンセルの成立を判断します。双方で解決できない場合は、本サービス内のお問い合わせ窓口から運営者へ連絡してください。

                    レッスン開始後は、通常のキャンセル操作および新たな雨天・施設都合キャンセル申請を行えない場合があります。

                    返金の処理状況およびカード等への反映時期は、Stripe、カード会社その他の決済機関の処理状況により異なる場合があります。

                    詳細は、本サービス内の「キャンセル・返金ポリシー」に従います。
                    """
                )

                termsSection(
                    title: "8. コーチの売上・手数料・出金",
                    text: """
                    コーチの受取額は、返金確定後の決済残額を基準として計算します。コーチ都合の全額返金、および雨天・施設都合について双方合意により100%返金となった予約は、コーチ売上の対象になりません。

                    現在のTennis Connect手数料は原則10%とし、コーチの受取額は原則90%です。コーチ受取額の計算で1円未満の端数が生じる場合は、コーチ受取額を1円単位で切り捨て、残額をTennis Connect手数料として扱います。

                    売上は、対象レッスンの終了から24時間が経過し、支払いおよび返金の状態に問題がないことを確認できた後に出金可能となります。

                    コーチへの銀行出金にはStripe Connectを利用し、本人確認、銀行口座登録、出金審査その他Stripeが求める手続きが必要となる場合があります。

                    出金依頼後の着金時期は、Stripe、金融機関、営業日その他の事情により異なる場合があります。

                    詳細は、本サービス内の「コーチの売上・出金について」に従います。
                    """
                )

                termsSection(
                    title: "9. チャット・プロフィール・動画・レビュー等",
                    text: """
                    利用者は、チャット、プロフィール、画像、動画、レビューその他本サービス上に投稿または登録する内容について、自ら責任を負うものとします。

                    他者の権利を侵害する内容、虚偽の内容、誹謗中傷、脅迫、差別的表現、わいせつな内容、無断転載、営業・勧誘を目的とする迷惑行為その他本規約に違反する内容を投稿してはなりません。

                    運営者は、本規約に違反する内容または本サービスの安全な運営上不適切と合理的に判断した内容について、必要に応じて非表示、削除、利用制限その他の措置を行う場合があります。

                    不適切な行為またはコンテンツを発見した場合は、本サービス内の「お問い合わせ」から運営者へ連絡できます。
                    """
                )

                termsSection(
                    title: "10. 禁止事項",
                    text: """
                    利用者は、本サービスの利用にあたり、次の行為を行ってはなりません。

                    ・法令または公序良俗に違反する行為
                    ・他の利用者または第三者の権利、利益、プライバシーを侵害する行為
                    ・虚偽の情報を登録または投稿する行為
                    ・嫌がらせ、誹謗中傷、脅迫、差別その他他者に不利益を与える行為
                    ・他者の画像、動画、文章その他の著作物等を無断で掲載する行為
                    ・本サービスを不正に操作し、または運営を妨害する行為
                    ・他人のアカウントを利用する行為
                    ・不正アクセス、リバースエンジニアリングその他本サービスの安全性を害する行為
                    ・本サービスの決済、手数料その他の仕組みを不当に回避し、不正な利益を得る行為
                    ・その他運営者が本サービスの運営上不適切と合理的に判断する行為
                    """
                )

                termsSection(
                    title: "11. 利用停止・投稿削除等",
                    text: """
                    運営者は、利用者が本規約に違反した場合、不正利用のおそれがある場合、他の利用者の安全を害するおそれがある場合、決済または出金に重大な問題がある場合その他本サービスの運営上必要と合理的に判断した場合、事前の通知なく、投稿の削除、機能の制限、アカウントの利用停止その他必要な措置を行う場合があります。
                    """
                )

                termsSection(
                    title: "12. アカウント削除",
                    text: """
                    利用者は、本サービス内の設定画面からアカウント削除を申し込むことができます。

                    未処理の予約、これから実施される支払い済み予約、返金処理中の予約その他処理を完了する必要がある事項が残っている場合、当該事項の処理が完了するまでアカウントを削除できない場合があります。

                    アカウント削除後のデータの取扱いについては、プライバシーポリシーに従います。
                    """
                )

                termsSection(
                    title: "13. 知的財産権",
                    text: """
                    本サービスに関するプログラム、デザイン、ロゴ、文章その他運営者が作成したコンテンツに関する権利は、運営者または正当な権利者に帰属します。

                    利用者が本サービスへ投稿した文章、画像、動画その他のコンテンツについて、利用者は投稿および本サービス上で表示するために必要な権利を有していることを確認するものとします。
                    """
                )

                termsSection(
                    title: "14. サービスの変更・中断",
                    text: """
                    運営者は、保守、障害対応、セキュリティ上の必要、外部サービスの障害、法令への対応その他合理的な理由がある場合、本サービスの全部または一部を変更、中断または終了することがあります。

                    重要な変更を行う場合は、可能な範囲で本サービス内その他適切な方法によりお知らせします。
                    """
                )

                termsSection(
                    title: "15. 責任",
                    text: """
                    運営者は、本サービスを安全かつ安定して提供できるよう努めますが、通信環境、端末、Stripe・Firebaseその他の外部サービス、天候、施設その他運営者が合理的に管理できない事由により、本サービスが一時的に利用できない場合があります。

                    利用者間または利用者とコーチとの間で問題が生じた場合、運営者は必要に応じて事実確認その他合理的な範囲で対応します。

                    運営者の責めに帰すべき事由により利用者に損害が生じた場合の責任については、適用される法令に従うものとします。本規約は、法令上認められない範囲で運営者の責任を免除または制限するものではありません。
                    """
                )

                termsSection(
                    title: "16. 本規約の変更",
                    text: """
                    運営者は、法令の変更、本サービスの内容変更、料金または手数料の変更その他必要に応じて、本規約を変更することがあります。

                    重要な変更を行う場合は、変更後の内容が適用される前に、本サービス内での表示その他適切な方法により利用者へお知らせします。
                    """
                )

                termsSection(
                    title: "17. 準拠法・裁判管轄",
                    text: """
                    本規約は日本法を準拠法とします。

                    本サービスに関して紛争が生じた場合は、まず当事者間で誠実に協議するものとし、解決しない場合の裁判管轄については、適用される法令に従います。
                    """
                )

                termsSection(
                    title: "18. お問い合わせ",
                    text: """
                    本規約に関するお問い合わせは、Tennis Connect内の「お問い合わせ」からご連絡ください。

                    運営者：\(TennisConnectLegalInfo.operatorDisplayName)
                    連絡先メールアドレス：\(TennisConnectLegalInfo.contactEmail)
                    制定日：\(TennisConnectLegalInfo.effectiveDate)
                    """
                )

                Text(
                    "※ 本内容は公開前の草案です。" +
                    "正式リリース前に、実際のサービス運用、" +
                    "料金、キャンセル条件、出金条件、" +
                    "利用者間の契約関係等と一致しているか確認し、" +
                    "専門家による最終確認を受けることを推奨します。"
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
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text(title)
                .font(.headline)

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }
}


private struct PrivacyPolicyView: View {

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 24
            ) {
                Text(
                    "Tennis Connect プライバシーポリシー"
                )
                .font(.title2)
                .fontWeight(.bold)

                Text(
                    "\(TennisConnectLegalInfo.operatorDisplayName)" +
                    "（以下「運営者」といいます。）は、" +
                    "Tennis Connect（以下「本サービス」といいます。）" +
                    "における利用者の情報を、以下のとおり取り扱います。"
                )
                .font(.body)

                policySection(
                    title: "1. 取得する情報",
                    text: """
                    本サービスでは、サービスの提供に必要な範囲で、メールアドレス、表示名、ユーザーID、プロフィール画像、プロフィール上のひとこと等のアカウント情報を取得します。

                    コーチとして本サービスを利用する場合、表示名、年代、活動地域、テニス歴、指導歴、経歴、自己紹介、レッスン料金、対応可能日時、プロフィール画像、プロフィール動画その他プロフィールに入力・登録された情報を取得します。

                    また、本サービスの利用に伴い、予約情報、通常キャンセルおよび雨天・施設都合キャンセルの申請・回答・成立状況、レッスン料金、決済・返金状況、売上・手数料・出金状況、お気に入り情報、レビューおよび評価、チャットの内容、お問い合わせ内容、通知に関する情報その他本サービスの利用履歴を取得する場合があります。
                    """
                )

                policySection(
                    title: "2. 決済・本人確認・銀行口座情報",
                    text: """
                    生徒の決済および返金、コーチの本人確認、銀行口座登録および売上出金にはStripeおよびStripe Connectを利用します。

                    クレジットカード情報、コーチの本人確認書類、銀行口座情報等は、Stripeが提供する画面または仕組みを通じてStripeにより処理されます。

                    Tennis Connectでは、サービス運営に必要な範囲で、Stripe上の処理を識別するID、決済金額、返金金額、決済・返金・出金の状態、本人確認・出金機能の利用可否等を取り扱う場合があります。
                    """
                )

                policySection(
                    title: "3. 利用目的",
                    text: """
                    取得した情報は、本サービスのアカウント管理、プロフィール表示、コーチと生徒のマッチング、空き時間表示、予約の受付・承認・管理、決済・返金処理、コーチ売上・出金処理、チャット機能、レビュー・評価機能、お気に入り機能、通知機能、お問い合わせ対応、不正利用の防止、本サービスの安全性確保、障害対応およびサービス改善のために利用します。

                    取得した情報を、あらかじめ明示した利用目的と合理的な関連性を有する範囲を超えて利用する必要が生じた場合には、法令に従い必要な対応を行います。
                    """
                )

                policySection(
                    title: "4. 画像・動画等の保存",
                    text: """
                    プロフィール画像、プロフィール動画その他利用者がアップロードするファイルは、サービス提供に必要な範囲でFirebase Storage等のクラウドストレージに保存する場合があります。

                    コーチが登録したプロフィール動画は、コーチを探す利用者に対してコーチ詳細画面等で表示・再生されます。

                    利用者は、アップロードする画像・動画について必要な権利を有し、第三者のプライバシー、肖像権、著作権その他の権利を侵害しないようにしてください。
                    """
                )

                policySection(
                    title: "5. 外部サービスの利用",
                    text: """
                    本サービスでは、サービス提供のために、Googleが提供するFirebaseのAuthentication、Firestore、Storage、Cloud Functions等、およびStripeが提供する決済・Stripe Connect関連サービス等の外部サービスを利用します。

                    これらの外部サービスにおいて、サービス提供、認証、データ保存、決済、返金、本人確認、銀行出金、不正利用防止、セキュリティ確保等のために、利用者に関する情報が処理される場合があります。

                    外部サービスにおける情報の取扱いについては、各サービス提供者が定めるプライバシーポリシーその他の規約が適用される場合があります。
                    """
                )

                policySection(
                    title: "6. 第三者提供および委託",
                    text: """
                    運営者は、法令に基づく場合その他法令上認められる場合を除き、利用者本人の同意なく個人データを第三者へ提供しません。

                    ただし、本サービスの提供に必要な範囲で、クラウドサービス、認証サービス、ストレージサービス、決済・本人確認・出金サービスその他の業務委託先に情報の取扱いを委託する場合があります。その場合、運営者は必要かつ適切な管理に努めます。
                    """
                )

                policySection(
                    title: "7. 情報の保存および削除",
                    text: """
                    運営者は、本サービスを提供するために必要な期間、または法令上・取引管理上保存が必要となる期間、利用者に関する情報を保存します。

                    利用者は、本サービス内の設定画面からアカウント削除を申し込むことができます。

                    アカウント削除が完了した場合、法令、決済・取引履歴の保存、不正利用防止その他正当な理由により保存する必要がある情報を除き、不要となったアカウント情報およびプロフィール情報等を削除または利用者を直接特定できない形へ変更します。

                    予約、支払い、返金その他の未処理事項がある場合、安全に処理を完了するため、未処理事項の完了後にアカウント削除が可能となる場合があります。
                    """
                )

                policySection(
                    title: "8. 安全管理",
                    text: """
                    運営者は、個人情報への不正アクセス、漏えい、滅失、毀損その他の事故を防止するため、認証、アクセス権限管理、データベースおよびストレージのアクセス制御、サーバー側での重要処理、外部サービスのセキュリティ機能その他合理的かつ適切な安全管理措置を講じるよう努めます。
                    """
                )

                policySection(
                    title: "9. 利用者による確認・訂正・削除等",
                    text: """
                    利用者は、本サービス上で変更可能なプロフィール情報等について、自ら確認または変更することができます。

                    保有する個人情報について、法令に基づく開示、訂正、利用停止または削除等の請求を希望する場合は、本サービスのお問い合わせ窓口からご連絡ください。
                    """
                )

                policySection(
                    title: "10. プライバシーポリシーの変更",
                    text: """
                    運営者は、法令の変更、本サービスの機能変更、利用する外部サービスの変更その他必要に応じて、本ポリシーを変更することがあります。

                    重要な変更を行う場合は、本サービス内での表示その他適切な方法により利用者へお知らせします。
                    """
                )

                policySection(
                    title: "11. お問い合わせ",
                    text: """
                    本ポリシーおよび個人情報の取扱いに関するお問い合わせは、Tennis Connect内の「お問い合わせ」からご連絡ください。

                    運営者：\(TennisConnectLegalInfo.operatorDisplayName)
                    連絡先メールアドレス：\(TennisConnectLegalInfo.contactEmail)
                    制定日：\(TennisConnectLegalInfo.effectiveDate)
                    """
                )

                Text(
                    "※ 本内容は公開前の草案です。" +
                    "正式リリース前に、実際に取得・保存する情報、" +
                    "Firebase・Stripe等の利用状況、" +
                    "アカウント削除時のデータ処理と一致しているか" +
                    "最終確認してください。"
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
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text(title)
                .font(.headline)

            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
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
