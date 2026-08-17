import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct MyPageView: View {

    @State private var displayName = ""
    @State private var isLoadingProfile = false
    @State private var profileError = ""
    @State private var showDisplayNameEditor = false
    @State private var showLogoutAlert = false
    @State private var isLoggedIn = false
    @State private var showLogin = false
    @State private var reservationCount = 0
    @State private var isLoadingReservationCount = false
    @State private var reviewCount = 0
    @State private var isLoadingReviewCount = false
    @State private var favoriteCount = 0
    @State private var isLoadingFavoriteCount = false

    private let db = Firestore.firestore()

    var body: some View {

        NavigationStack {

            Group {
                if isLoggedIn {
                    List {

                        Section {

                            VStack(spacing: 16) {

                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 90))
                                    .foregroundStyle(.green)

                                if isLoadingProfile {
                                    ProgressView()
                                } else {
                                    Text(
                                        displayName.isEmpty
                                        ? "表示名未設定"
                                        : displayName
                                    )
                                    .font(.title)
                                    .fontWeight(.bold)
                                }

                                Text("テニスを楽しもう！")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 24) {

                                    VStack {
                                        if isLoadingReservationCount {
                                            ProgressView()
                                                .frame(height: 28)
                                        } else {
                                            Text("\(reservationCount)")
                                                .font(.title2)
                                                .bold()
                                        }

                                        Text("予約")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    VStack {
                                        if isLoadingReviewCount {
                                            ProgressView()
                                                .frame(height: 28)
                                        } else {
                                            Text("\(reviewCount)")
                                                .font(.title2)
                                                .bold()
                                        }

                                        Text("レビュー")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    VStack {
                                        if isLoadingFavoriteCount {
                                            ProgressView()
                                                .frame(height: 28)
                                        } else {
                                            Text("\(favoriteCount)")
                                                .font(.title2)
                                                .bold()
                                        }

                                        Text("お気に入り")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                if !profileError.isEmpty {
                                    Text(profileError)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical)
                        }

                        Section("メニュー") {

                            Button {
                                showDisplayNameEditor = true
                            } label: {
                                Label(
                                    "表示名を編集",
                                    systemImage: "person.text.rectangle"
                                )
                            }
                            .foregroundStyle(.primary)

                            NavigationLink {
                                ReservationListView()
                            } label: {
                                Label("予約一覧", systemImage: "calendar")
                            }

                            NavigationLink {
                                FavoriteView()
                            } label: {
                                Label("お気に入り", systemImage: "heart")
                            }

                            NavigationLink {
                                NotificationView()
                            } label: {
                                Label("通知", systemImage: "bell")
                            }

                            NavigationLink {
                                SettingsView()
                            } label: {
                                Label("設定", systemImage: "gear")
                            }
                        }

                        Section {
                            Button(role: .destructive) {
                                showLogoutAlert = true
                            } label: {
                                Text("ログアウト")
                            }
                        }
                    }
                } else {
                    loggedOutView
                }
            }
            .navigationTitle("マイページ")
            .onAppear {
                isLoggedIn = Auth.auth().currentUser != nil

                if isLoggedIn {
                    loadMyPageData()
                } else {
                    resetMyPageState()
                }
            }
            .sheet(isPresented: $showDisplayNameEditor) {
                DisplayNameEditView(
                    initialDisplayName: displayName
                ) { savedDisplayName in
                    displayName = savedDisplayName
                    profileError = ""
                }
            }
            .sheet(isPresented: $showLogin) {
                LoginView {
                    isLoggedIn = true
                    loadMyPageData()
                }
            }
            .alert(
                "ログアウトしますか？",
                isPresented: $showLogoutAlert
            ) {
                Button("キャンセル", role: .cancel) { }

                Button("ログアウト", role: .destructive) {
                    logout()
                }
            } message: {
                Text("再度利用するにはログインが必要です。")
            }
        }
    }

    private var loggedOutView: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "person.crop.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("マイページを利用するにはログインが必要です")
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(
                "ログインすると、予約・レビュー・お気に入り・設定を確認できます。"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Button {
                showLogin = true
            } label: {
                Label(
                    "ログイン・新規会員登録",
                    systemImage: "person.crop.circle.badge.plus"
                )
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.top, 6)

            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private func loadMyPageData() {
        loadStudentProfile()
        loadReservationCount()
        loadReviewCount()
        loadFavoriteCount()
    }

    private func resetMyPageState() {
        displayName = ""
        profileError = ""
        reservationCount = 0
        reviewCount = 0
        favoriteCount = 0
        isLoadingProfile = false
        isLoadingReservationCount = false
        isLoadingReviewCount = false
        isLoadingFavoriteCount = false
    }

    private func logout() {
        do {
            try Auth.auth().signOut()

            isLoggedIn = false
            resetMyPageState()

            NotificationCenter.default.post(
                name: .returnToStartScreen,
                object: nil
            )
        } catch {
            profileError =
                "ログアウトできませんでした: " +
                error.localizedDescription
        }
    }

    private func loadFavoriteCount() {
        guard let uid = Auth.auth().currentUser?.uid else {
            favoriteCount = 0
            return
        }

        isLoadingFavoriteCount = true

        db.collection("favorites")
            .whereField("studentId", isEqualTo: uid)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    isLoadingFavoriteCount = false

                    if let error = error {
                        profileError =
                            "お気に入り件数を取得できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    favoriteCount = snapshot?.documents.count ?? 0
                }
            }
    }

    private func loadReviewCount() {
        guard let uid = Auth.auth().currentUser?.uid else {
            reviewCount = 0
            return
        }

        isLoadingReviewCount = true

        db.collection("reviews")
            .whereField("studentId", isEqualTo: uid)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    isLoadingReviewCount = false

                    if let error = error {
                        profileError =
                            "レビュー件数を取得できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    reviewCount = snapshot?.documents.count ?? 0
                }
            }
    }

    private func loadReservationCount() {
        guard let uid = Auth.auth().currentUser?.uid else {
            reservationCount = 0
            return
        }

        isLoadingReservationCount = true

        db.collection("reservations")
            .whereField("studentId", isEqualTo: uid)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    isLoadingReservationCount = false

                    if let error = error {
                        profileError =
                            "予約件数を取得できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    reservationCount = snapshot?.documents.count ?? 0
                }
            }
    }

    private func loadStudentProfile() {
        guard let uid = Auth.auth().currentUser?.uid else {
            isLoggedIn = false
            resetMyPageState()
            return
        }

        isLoadingProfile = true
        profileError = ""

        db.collection("students")
            .document(uid)
            .getDocument { snapshot, error in
                DispatchQueue.main.async {
                    isLoadingProfile = false

                    if let error = error {
                        profileError =
                            "プロフィールを取得できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    displayName =
                        snapshot?.data()?["displayName"] as? String ?? ""
                }
            }
    }
}

private struct DisplayNameEditView: View {

    let initialDisplayName: String
    let onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var isSaving = false
    @State private var errorMessage = ""

    init(
        initialDisplayName: String,
        onSaved: @escaping (String) -> Void
    ) {
        self.initialDisplayName = initialDisplayName
        self.onSaved = onSaved
        _displayName = State(initialValue: initialDisplayName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("表示名") {
                    TextField("例：たかひろ", text: $displayName)
                        .textInputAutocapitalization(.never)

                    Text("レビューにはこの表示名が表示されます。")
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
                        saveDisplayName()
                    } label: {
                        HStack {
                            Spacer()

                            if isSaving {
                                ProgressView()
                            } else {
                                Text("保存する")
                                    .fontWeight(.semibold)
                            }

                            Spacer()
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .navigationTitle("表示名を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func saveDisplayName() {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "表示名の保存にはログインが必要です"
            return
        }

        let trimmedDisplayName =
            displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedDisplayName.isEmpty else {
            errorMessage = "表示名を入力してください"
            return
        }

        guard trimmedDisplayName.count <= 20 else {
            errorMessage = "表示名は20文字以内で入力してください"
            return
        }

        isSaving = true
        errorMessage = ""

        Firestore.firestore()
            .collection("students")
            .document(uid)
            .setData(
                [
                    "displayName": trimmedDisplayName,
                    "updatedAt": FieldValue.serverTimestamp()
                ],
                merge: true
            ) { error in
                DispatchQueue.main.async {
                    isSaving = false

                    if let error = error {
                        errorMessage =
                            "表示名を保存できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    onSaved(trimmedDisplayName)
                    dismiss()
                }
            }
    }
}

#Preview {
    MyPageView()
}
