import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

struct CoachDetailView: View {

    let coach: Coach

    private let db = Firestore.firestore()
    private let functions = Functions.functions(
        region: "asia-northeast1"
    )

    @State private var isFavorite = false
    @State private var isUpdatingFavorite = false
    @State private var favoriteError = ""
    @State private var showFavoriteError = false

    @State private var isBlocked = false
    @State private var isUpdatingBlock = false
    @State private var blockError = ""
    @State private var blockAlertTitle =
        "ブロック機能を利用できませんでした"
    @State private var showBlockError = false
    @State private var showBlockConfirmation = false
    @State private var showReservationBlockConfirmation = false
    @State private var pendingBlockCancellationCount = 0
    @State private var pendingBlockPaidReservationCount = 0
    @State private var pendingBlockFullRefundCount = 0
    @State private var pendingBlockHalfRefundCount = 0
    @State private var pendingBlockNoRefundCount = 0
    @State private var pendingBlockExpectedRefundAmount = 0
    @State private var showUnblockConfirmation = false
    @State private var showReportSheet = false

    @State private var canMessageCoach = false
    @State private var isCheckingChatAccess = false

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    private var isOwnCoachProfile: Bool {
        guard let currentUserId else {
            return false
        }

        return currentUserId == coach.id
    }

    var body: some View {

        ScrollView {

            VStack(spacing: 20) {

                CoachHeaderView(coach: coach)

                CoachProfileSection(coach: coach)

                CoachVideoSection(coachId: coach.id)

                CoachReviewSection(
                    coachId: coach.id
                )

                CoachScheduleSection(coach: coach)

                if canShowMessageButton {
                    NavigationLink {
                        ChatView(coach: coach)
                    } label: {
                        Label(
                            "メッセージを送る",
                            systemImage: "message.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(Color.green)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 14
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }

                if isBlocked {
                    blockedNotice
                } else {
                    ReserveButton(coach: coach)
                }
            }
            .padding()
        }
        .navigationTitle("コーチ詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {

            ToolbarItemGroup(
                placement: .topBarTrailing
            ) {

                Button {
                    toggleFavorite()
                } label: {
                    if isUpdatingFavorite {
                        ProgressView()
                    } else {
                        Image(
                            systemName: isFavorite
                                ? "heart.fill"
                                : "heart"
                        )
                        .foregroundStyle(
                            isFavorite ? .red : .primary
                        )
                    }
                }
                .disabled(
                    isUpdatingFavorite ||
                    isBlocked
                )
                .accessibilityLabel(
                    isFavorite
                        ? "お気に入りから削除"
                        : "お気に入りに追加"
                )

                if !isOwnCoachProfile {
                    Menu {
                        Button {
                            showReportSheet = true
                        } label: {
                            Label(
                                "通報する",
                                systemImage:
                                    "exclamationmark.bubble"
                            )
                        }

                        Divider()

                        if isBlocked {
                            Button {
                                showUnblockConfirmation = true
                            } label: {
                                Label(
                                    "ブロックを解除",
                                    systemImage:
                                        "person.crop.circle.badge.checkmark"
                                )
                            }
                        } else {
                            Button(
                                role: .destructive
                            ) {
                                showBlockConfirmation = true
                            } label: {
                                Label(
                                    "ブロックする",
                                    systemImage:
                                        "person.crop.circle.badge.xmark"
                                )
                            }
                        }
                    } label: {
                        Image(
                            systemName: "ellipsis.circle"
                        )
                    }
                    .disabled(isUpdatingBlock)
                    .accessibilityLabel(
                        "コーチに関するメニュー"
                    )
                }
            }
        }
        .onAppear {
            loadFavoriteState()
            loadBlockState()
            loadChatAccessState()
        }
        .alert(
            "お気に入りを更新できませんでした",
            isPresented: $showFavoriteError
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(favoriteError)
        }
        .alert(
            blockAlertTitle,
            isPresented: $showBlockError
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(blockError)
        }
        .confirmationDialog(
            "\(coach.name)さんをブロックしますか？",
            isPresented: $showBlockConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                "ブロックする",
                role: .destructive
            ) {
                blockCoach(
                    confirmReservationCancellation: false
                )
            }

            Button(
                "キャンセル",
                role: .cancel
            ) { }
        } message: {
            Text(
                "予約状況を確認してからブロックします。" +
                "未決済の予約申請・承認済み予約は取り下げ、" +
                "支払い済みの今後の予約は通常のキャンセル・返金ポリシーに従って" +
                "キャンセルする前に、もう一度確認します。"
            )
        }
        .confirmationDialog(
            blockReservationConfirmationTitle,
            isPresented: $showReservationBlockConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                blockReservationConfirmationButtonTitle,
                role: .destructive
            ) {
                blockCoach(
                    confirmReservationCancellation: true
                )
            }

            Button(
                "キャンセル",
                role: .cancel
            ) {
                resetPendingBlockConfirmation()
            }
        } message: {
            Text(blockReservationConfirmationMessage)
        }
        .confirmationDialog(
            "ブロックを解除しますか？",
            isPresented: $showUnblockConfirmation,
            titleVisibility: .visible
        ) {
            Button("ブロックを解除") {
                unblockCoach()
            }

            Button(
                "キャンセル",
                role: .cancel
            ) { }
        } message: {
            Text(
                "解除すると、このコーチを再びお気に入り登録・予約できるようになります。"
            )
        }
        .sheet(
            isPresented: $showReportSheet
        ) {
            CoachReportView(
                coach: coach
            )
        }
    }

    @ViewBuilder
    private var blockedNotice: some View {
        VStack(spacing: 12) {
            Image(
                systemName:
                    "person.crop.circle.badge.xmark"
            )
            .font(.system(size: 34))
            .foregroundStyle(.red)

            Text("このコーチをブロックしています")
                .font(.headline)

            Text(
                "ブロック中は新しい予約を行えません。" +
                "右上の「…」からブロックを解除できます。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding()
        .frame(
            maxWidth: .infinity
        )
        .background(
            Color.red.opacity(0.06)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 16)
        )
    }

    private var canShowMessageButton: Bool {
        guard
            currentUserId != nil,
            !isOwnCoachProfile,
            !isBlocked
        else {
            return false
        }

        return canMessageCoach &&
            !isCheckingChatAccess
    }

    private func loadChatAccessState() {
        guard
            let studentId = currentUserId,
            studentId != coach.id
        else {
            canMessageCoach = false
            isCheckingChatAccess = false
            return
        }

        isCheckingChatAccess = true
        canMessageCoach = false

        functions
            .httpsCallable(
                "getChatMessagingStatus"
            )
            .call(
                [
                    "studentId": studentId,
                    "coachId": coach.id
                ]
            ) { result, error in
                DispatchQueue.main.async {
                    isCheckingChatAccess = false

                    if let error {
                        canMessageCoach = false
                        print(
                            "チャット利用可否確認失敗:",
                            error.localizedDescription
                        )
                        return
                    }

                    guard
                        let data =
                            result?.data
                            as? [String: Any]
                    else {
                        canMessageCoach = false
                        return
                    }

                    canMessageCoach =
                        data["canSend"]
                        as? Bool
                        ?? false
                }
            }
    }

    private var favoriteDocumentId: String? {
        guard let studentId = currentUserId else {
            return nil
        }

        return "\(studentId)__\(coach.id)"
    }

    private var blockDocumentId: String? {
        guard let blockerId = currentUserId else {
            return nil
        }

        return "\(blockerId)__\(coach.id)"
    }

    private func loadFavoriteState() {
        guard let studentId = currentUserId else {
            isFavorite = false
            return
        }

        db.collection("favorites")
            .whereField(
                "studentId",
                isEqualTo: studentId
            )
            .whereField(
                "coachId",
                isEqualTo: coach.id
            )
            .limit(to: 1)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    if let error {
                        favoriteError =
                            error.localizedDescription
                        showFavoriteError = true
                        return
                    }

                    isFavorite =
                        !(snapshot?.documents.isEmpty ?? true)
                }
            }
    }

    private func loadBlockState() {
        guard let blockerId = currentUserId else {
            isBlocked = false
            return
        }

        db.collection("blocks")
            .whereField(
                "blockerId",
                isEqualTo: blockerId
            )
            .whereField(
                "blockedUserId",
                isEqualTo: coach.id
            )
            .limit(to: 1)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    if let error {
                        blockError =
                            error.localizedDescription
                        showBlockError = true
                        return
                    }

                    isBlocked =
                        !(snapshot?.documents.isEmpty ?? true)
                }
            }
    }

    private func toggleFavorite() {
        guard !isBlocked else {
            favoriteError =
                "ブロック中のコーチはお気に入りに追加できません"
            showFavoriteError = true
            return
        }

        guard let studentId = currentUserId,
              let documentId = favoriteDocumentId else {
            favoriteError =
                "お気に入り機能を使うにはログインが必要です"
            showFavoriteError = true
            return
        }

        isUpdatingFavorite = true

        let favoriteRef = db
            .collection("favorites")
            .document(documentId)

        if isFavorite {
            favoriteRef.delete { error in
                DispatchQueue.main.async {
                    isUpdatingFavorite = false

                    if let error {
                        favoriteError =
                            error.localizedDescription
                        showFavoriteError = true
                        return
                    }

                    isFavorite = false
                }
            }
        } else {
            favoriteRef.setData(
                [
                    "studentId": studentId,
                    "coachId": coach.id,
                    "createdAt": Timestamp()
                ]
            ) { error in
                DispatchQueue.main.async {
                    isUpdatingFavorite = false

                    if let error {
                        favoriteError =
                            error.localizedDescription
                        showFavoriteError = true
                        return
                    }

                    isFavorite = true
                }
            }
        }
    }

    private var blockReservationConfirmationTitle: String {
        if pendingBlockPaidReservationCount > 0 {
            return "予約をキャンセルしてブロックしますか？"
        }

        return "予約を取り下げてブロックしますか？"
    }

    private var blockReservationConfirmationButtonTitle: String {
        pendingBlockPaidReservationCount > 0
            ? "キャンセルしてブロック"
            : "取り下げてブロック"
    }

    private var blockReservationConfirmationMessage: String {
        var messages: [String] = []

        if pendingBlockCancellationCount > 0 {
            messages.append(
                "未決済の予約申請・承認済み予約" +
                "\(pendingBlockCancellationCount)件を取り下げ、" +
                "予約枠を空き時間へ戻します。"
            )
        }

        if pendingBlockPaidReservationCount > 0 {
            var refundDetails: [String] = []

            if pendingBlockFullRefundCount > 0 {
                refundDetails.append(
                    "100%返金 \(pendingBlockFullRefundCount)件"
                )
            }

            if pendingBlockHalfRefundCount > 0 {
                refundDetails.append(
                    "50%返金 \(pendingBlockHalfRefundCount)件"
                )
            }

            if pendingBlockNoRefundCount > 0 {
                refundDetails.append(
                    "返金なし \(pendingBlockNoRefundCount)件"
                )
            }

            var paidMessage =
                "支払い済みの今後の予約" +
                "\(pendingBlockPaidReservationCount)件を、" +
                "通常の生徒都合キャンセルとして処理します。"

            if !refundDetails.isEmpty {
                paidMessage +=
                    "\n現在の返金条件: " +
                    refundDetails.joined(separator: " / ")
            }

            if pendingBlockExpectedRefundAmount > 0 {
                paidMessage +=
                    "\n返金予定額合計: ¥" +
                    "\(pendingBlockExpectedRefundAmount)"
            }

            paidMessage +=
                "\nキャンセル後、予約枠は空き時間へ戻ります。"

            messages.append(paidMessage)
        }

        messages.append(
            "ブロック後は、このコーチへの新しい予約はできません。"
        )

        return messages.joined(separator: "\n\n")
    }

    private func resetPendingBlockConfirmation() {
        pendingBlockCancellationCount = 0
        pendingBlockPaidReservationCount = 0
        pendingBlockFullRefundCount = 0
        pendingBlockHalfRefundCount = 0
        pendingBlockNoRefundCount = 0
        pendingBlockExpectedRefundAmount = 0
    }

    private func blockCoach(
        confirmReservationCancellation: Bool
    ) {
        guard !isUpdatingBlock else {
            return
        }

        guard let currentUserId else {
            blockError =
                "ブロック機能を使うにはログインが必要です"
            showBlockError = true
            return
        }

        guard currentUserId != coach.id else {
            blockError =
                "自分自身をブロックすることはできません"
            showBlockError = true
            return
        }

        isUpdatingBlock = true
        blockAlertTitle =
            "ブロック機能を利用できませんでした"
        blockError = ""

        functions
            .httpsCallable("blockCoach")
            .call(
                [
                    "coachId": coach.id,
                    "confirmReservationCancellation":
                        confirmReservationCancellation
                ]
            ) { result, error in
                DispatchQueue.main.async {
                    isUpdatingBlock = false

                    if let error {
                        blockError =
                            blockCoachErrorMessage(
                                from: error
                            )
                        showBlockError = true
                        return
                    }

                    guard
                        let data =
                            result?.data
                            as? [String: Any]
                    else {
                        blockError =
                            "ブロック処理の結果を確認できませんでした"
                        showBlockError = true
                        return
                    }

                    let requiresConfirmation =
                        data["requiresConfirmation"]
                            as? Bool ?? false

                    if requiresConfirmation {
                        pendingBlockCancellationCount =
                            intValue(
                                data[
                                    "cancellableReservationCount"
                                ]
                            )

                        pendingBlockPaidReservationCount =
                            intValue(
                                data[
                                    "paidUpcomingReservationCount"
                                ]
                            )

                        pendingBlockFullRefundCount =
                            intValue(
                                data[
                                    "fullRefundReservationCount"
                                ]
                            )

                        pendingBlockHalfRefundCount =
                            intValue(
                                data[
                                    "halfRefundReservationCount"
                                ]
                            )

                        pendingBlockNoRefundCount =
                            intValue(
                                data[
                                    "noRefundReservationCount"
                                ]
                            )

                        pendingBlockExpectedRefundAmount =
                            intValue(
                                data[
                                    "expectedRefundAmountTotal"
                                ]
                            )

                        showReservationBlockConfirmation = true
                        return
                    }

                    let blocked =
                        data["blocked"] as? Bool ?? false

                    guard blocked else {
                        blockError =
                            "ブロック処理を完了できませんでした"
                        showBlockError = true
                        return
                    }

                    isBlocked = true
                    isFavorite = false
                    canMessageCoach = false
                    resetPendingBlockConfirmation()

                    let refundFailureCount =
                        intValue(
                            data["refundFailureCount"]
                        )

                    if refundFailureCount > 0 {
                        blockAlertTitle =
                            "ブロックは完了しました"
                        blockError =
                            "予約のキャンセルは完了しましたが、" +
                            "一部の返金処理を開始できませんでした。" +
                            "予約一覧の返金状態をご確認ください。"
                        showBlockError = true
                    }
                }
            }
    }

    private func intValue(
        _ value: Any?
    ) -> Int {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        return 0
    }

    private func blockCoachErrorMessage(
        from error: Error
    ) -> String {
        let message =
            (error as NSError).localizedDescription

        if message.contains("支払い結果を確認中") {
            return message
        }

        if message.contains("予約状況が変わりました") {
            return message
        }

        return "ブロックできませんでした: \(message)"
    }

    private func unblockCoach() {
        guard !isUpdatingBlock else {
            return
        }

        guard let documentId = blockDocumentId else {
            blockError =
                "ブロック解除にはログインが必要です"
            showBlockError = true
            return
        }

        isUpdatingBlock = true
        blockError = ""

        db.collection("blocks")
            .document(documentId)
            .delete { error in
                DispatchQueue.main.async {
                    isUpdatingBlock = false

                    if let error {
                        blockError =
                            error.localizedDescription
                        showBlockError = true
                        return
                    }

                    isBlocked = false
                    loadChatAccessState()
                }
            }
    }
}


private struct CoachReportView: View {

    private enum ReportReason:
        String,
        CaseIterable,
        Identifiable {

        case inappropriateProfile =
            "不適切なプロフィール・投稿"
        case harassment =
            "迷惑行為・嫌がらせ"
        case falseInformation =
            "虚偽の情報・なりすまし"
        case transactionProblem =
            "予約・レッスンに関する問題"
        case other =
            "その他"

        var id: String {
            rawValue
        }
    }

    let coach: Coach

    @Environment(\.dismiss)
    private var dismiss

    @State private var selectedReason:
        ReportReason = .inappropriateProfile
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var errorMessage = ""
    @State private var showSuccess = false

    private let db = Firestore.firestore()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "\(coach.name)さんについて、該当する理由を選択してください。"
                    )
                    .font(.subheadline)
                }

                Section("通報理由") {
                    Picker(
                        "理由",
                        selection: $selectedReason
                    ) {
                        ForEach(
                            ReportReason.allCases
                        ) { reason in
                            Text(reason.rawValue)
                                .tag(reason)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section(
                    "詳細（任意）"
                ) {
                    TextEditor(
                        text: $details
                    )
                    .frame(minHeight: 120)

                    Text(
                        "個人情報やクレジットカード番号などの機密情報は入力しないでください。"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                        submitReport()
                    } label: {
                        if isSubmitting {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text("通報を送信")
                                .frame(
                                    maxWidth: .infinity
                                )
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
            .navigationTitle("通報する")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .topBarLeading
                ) {
                    Button("キャンセル") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
            .alert(
                "通報を受け付けました",
                isPresented: $showSuccess
            ) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text(
                    "内容を確認し、必要に応じて対応します。" +
                    "通報したことが相手へ直接通知されることはありません。"
                )
            }
        }
    }

    private func submitReport() {
        guard !isSubmitting else {
            return
        }

        guard let reporterId =
                Auth.auth().currentUser?.uid else {
            errorMessage =
                "通報するにはログインが必要です"
            return
        }

        guard reporterId != coach.id else {
            errorMessage =
                "自分自身を通報することはできません"
            return
        }

        isSubmitting = true
        errorMessage = ""

        let normalizedDetails =
            details.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        var reportData: [String: Any] = [
            "reporterId": reporterId,
            "reportedUserId": coach.id,
            "reportedRole": "coach",
            "reason": selectedReason.rawValue,
            "source": "coachDetail",
            "status": "open",
            "createdAt": FieldValue.serverTimestamp()
        ]

        if !normalizedDetails.isEmpty {
            reportData["details"] =
                normalizedDetails
        }

        db.collection("reports")
            .addDocument(
                data: reportData
            ) { error in
                DispatchQueue.main.async {
                    isSubmitting = false

                    if let error {
                        errorMessage =
                            "通報を送信できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    showSuccess = true
                }
            }
    }
}


#Preview {
    NavigationStack {
        CoachDetailView(
            coach: sampleCoaches[0]
        )
    }
}
