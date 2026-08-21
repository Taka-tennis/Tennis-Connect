import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import PhotosUI
import UIKit

struct MyPageView: View {

    @State private var displayName = ""
    @State private var profileComment = ""
    @State private var profileImageURL = ""

    @State private var isLoadingProfile = false
    @State private var profileError = ""
    @State private var showProfileEditor = false
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
                                studentProfileImage

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

                                Text(displayedProfileComment)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(
                                        horizontal: false,
                                        vertical: true
                                    )

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
                            .clipShape(
                                RoundedRectangle(cornerRadius: 20)
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical)
                        }

                        Section("メニュー") {
                            Button {
                                showProfileEditor = true
                            } label: {
                                Label(
                                    "プロフィールを編集",
                                    systemImage: "person.crop.circle.badge.pencil"
                                )
                            }
                            .foregroundStyle(.primary)

                            NavigationLink {
                                ReservationListView()
                            } label: {
                                Label(
                                    "予約一覧",
                                    systemImage: "calendar"
                                )
                            }

                            NavigationLink {
                                FavoriteView()
                            } label: {
                                Label(
                                    "お気に入り",
                                    systemImage: "heart"
                                )
                            }

                            NavigationLink {
                                NotificationView()
                            } label: {
                                Label(
                                    "通知",
                                    systemImage: "bell"
                                )
                            }

                            NavigationLink {
                                SettingsView()
                            } label: {
                                Label(
                                    "設定",
                                    systemImage: "gear"
                                )
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
            .sheet(isPresented: $showProfileEditor) {
                StudentProfileEditView(
                    initialDisplayName: displayName,
                    initialProfileComment: profileComment,
                    initialImageURL: profileImageURL
                ) {
                    savedDisplayName,
                    savedProfileComment,
                    savedImageURL in

                    displayName = savedDisplayName
                    profileComment = savedProfileComment
                    profileImageURL = savedImageURL
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

    @ViewBuilder
    private var studentProfileImage: some View {
        if !profileImageURL.isEmpty,
           let url = URL(string: profileImageURL) {

            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()

                case .failure:
                    defaultProfileImage

                case .empty:
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.12))

                        ProgressView()
                    }

                @unknown default:
                    defaultProfileImage
                }
            }
            .frame(width: 90, height: 90)
            .clipShape(Circle())

        } else {
            defaultProfileImage
        }
    }

    private var defaultProfileImage: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 90, height: 90)
            .foregroundStyle(.green)
    }

    private var displayedProfileComment: String {
        let trimmed =
            profileComment.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        return trimmed.isEmpty
            ? "テニスを楽しもう！"
            : trimmed
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
                .clipShape(
                    RoundedRectangle(cornerRadius: 14)
                )
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
        profileComment = ""
        profileImageURL = ""
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

                    if let error {
                        profileError =
                            "お気に入り件数を取得できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    favoriteCount =
                        snapshot?.documents.count ?? 0
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

                    if let error {
                        profileError =
                            "レビュー件数を取得できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    reviewCount =
                        snapshot?.documents.count ?? 0
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

                    if let error {
                        profileError =
                            "予約件数を取得できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    reservationCount =
                        snapshot?.documents.count ?? 0
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

                    if let error {
                        profileError =
                            "プロフィールを取得できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    let data = snapshot?.data() ?? [:]

                    displayName =
                        data["displayName"] as? String ?? ""

                    profileComment =
                        data["profileComment"] as? String ?? ""

                    profileImageURL =
                        data["imageURL"] as? String ?? ""
                }
            }
    }
}

private struct StudentProfileEditView: View {

    let initialDisplayName: String
    let initialProfileComment: String
    let initialImageURL: String

    let onSaved: (
        String,
        String,
        String
    ) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var profileComment: String
    @State private var imageURL: String

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: Image?
    @State private var selectedImageData: Data?

    @State private var isSaving = false
    @State private var errorMessage = ""

    private let storage = Storage.storage()

    init(
        initialDisplayName: String,
        initialProfileComment: String,
        initialImageURL: String,
        onSaved: @escaping (
            String,
            String,
            String
        ) -> Void
    ) {
        self.initialDisplayName =
            initialDisplayName

        self.initialProfileComment =
            initialProfileComment

        self.initialImageURL =
            initialImageURL

        self.onSaved = onSaved

        _displayName =
            State(initialValue: initialDisplayName)

        _profileComment =
            State(initialValue: initialProfileComment)

        _imageURL =
            State(initialValue: initialImageURL)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("プロフィール画像") {
                    HStack {
                        Spacer()

                        PhotosPicker(
                            selection: $selectedItem,
                            matching: .images
                        ) {
                            editableProfileImage
                        }

                        Spacer()
                    }

                    Text("画像をタップすると変更できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("表示名") {
                    TextField(
                        "例：たかひろ",
                        text: $displayName
                    )
                    .textInputAutocapitalization(.never)

                    Text(
                        "レビューにはこの表示名が表示されます。"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("ひとこと") {
                    ZStack(alignment: .topLeading) {
                        if profileComment.isEmpty {
                            Text("例：週末に楽しくテニスしています！")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $profileComment)
                            .frame(minHeight: 90)
                            .scrollContentBackground(.hidden)
                    }

                    Text(
                        "マイページの名前の下に表示されます。"
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
                        saveProfile()
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
            .navigationTitle("プロフィールを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(
                    placement: .cancellationAction
                ) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
            .onChange(of: selectedItem) { _ in
                loadSelectedImage()
            }
        }
    }

    @ViewBuilder
    private var editableProfileImage: some View {
        if let selectedImage {
            selectedImage
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 120)
                .clipShape(Circle())

        } else if !imageURL.isEmpty,
                  let url = URL(string: imageURL) {

            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()

                case .failure:
                    editPlaceholderImage

                case .empty:
                    ZStack {
                        Circle()
                            .fill(
                                Color.gray.opacity(0.12)
                            )

                        ProgressView()
                    }

                @unknown default:
                    editPlaceholderImage
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())

        } else {
            editPlaceholderImage
        }
    }

    private var editPlaceholderImage: some View {
        ZStack {
            Image(
                systemName: "person.crop.circle.fill"
            )
            .resizable()
            .scaledToFit()
            .frame(width: 120, height: 120)
            .foregroundStyle(.green)

            Image(
                systemName: "camera.circle.fill"
            )
            .font(.title)
            .foregroundStyle(.white, .green)
            .offset(x: 42, y: 42)
        }
    }

    private func loadSelectedImage() {
        Task {
            guard let data =
                    try? await selectedItem?
                        .loadTransferable(type: Data.self) else {
                return
            }

            guard let uiImage = UIImage(data: data) else {
                await MainActor.run {
                    errorMessage =
                        "選択した画像を読み込めませんでした"
                }
                return
            }

            await MainActor.run {
                selectedImageData = data
                selectedImage = Image(uiImage: uiImage)
                errorMessage = ""
            }
        }
    }

    private func saveProfile() {
        guard let uid =
                Auth.auth().currentUser?.uid else {
            errorMessage =
                "プロフィールの保存にはログインが必要です"
            return
        }

        let trimmedDisplayName =
            displayName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        let trimmedComment =
            profileComment.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !trimmedDisplayName.isEmpty else {
            errorMessage =
                "表示名を入力してください"
            return
        }

        guard trimmedDisplayName.count <= 20 else {
            errorMessage =
                "表示名は20文字以内で入力してください"
            return
        }

        guard trimmedComment.count <= 50 else {
            errorMessage =
                "ひとことは50文字以内で入力してください"
            return
        }

        isSaving = true
        errorMessage = ""

        if let selectedImageData {
            uploadProfileImage(
                data: selectedImageData,
                uid: uid
            ) { uploadedURL in
                guard let uploadedURL else {
                    DispatchQueue.main.async {
                        isSaving = false

                        if errorMessage.isEmpty {
                            errorMessage =
                                "プロフィール画像を保存できませんでした"
                        }
                    }
                    return
                }

                saveStudentDocument(
                    uid: uid,
                    displayName: trimmedDisplayName,
                    profileComment: trimmedComment,
                    imageURL: uploadedURL
                )
            }

        } else {
            saveStudentDocument(
                uid: uid,
                displayName: trimmedDisplayName,
                profileComment: trimmedComment,
                imageURL: imageURL
            )
        }
    }

    private func uploadProfileImage(
        data: Data,
        uid: String,
        completion: @escaping (String?) -> Void
    ) {
        let ref = storage.reference()
            .child("studentImages/\(uid).jpg")

        ref.putData(
            data,
            metadata: nil
        ) { _, error in
            if let error {
                DispatchQueue.main.async {
                    errorMessage =
                        "画像をアップロードできませんでした: " +
                        error.localizedDescription
                }

                completion(nil)
                return
            }

            ref.downloadURL { url, error in
                if let error {
                    DispatchQueue.main.async {
                        errorMessage =
                            "画像URLを取得できませんでした: " +
                            error.localizedDescription
                    }

                    completion(nil)
                    return
                }

                guard let url else {
                    completion(nil)
                    return
                }

                completion(url.absoluteString)
            }
        }
    }

    private func saveStudentDocument(
        uid: String,
        displayName: String,
        profileComment: String,
        imageURL: String
    ) {
        Firestore.firestore()
            .collection("students")
            .document(uid)
            .setData(
                [
                    "displayName": displayName,
                    "profileComment": profileComment,
                    "imageURL": imageURL,
                    "updatedAt":
                        FieldValue.serverTimestamp()
                ],
                merge: true
            ) { error in
                DispatchQueue.main.async {
                    isSaving = false

                    if let error {
                        errorMessage =
                            "プロフィールを保存できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    self.imageURL = imageURL

                    onSaved(
                        displayName,
                        profileComment,
                        imageURL
                    )

                    dismiss()
                }
            }
    }
}

#Preview {
    MyPageView()
}
