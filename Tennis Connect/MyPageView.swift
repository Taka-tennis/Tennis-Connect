import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import PhotosUI
import UIKit

private enum StudentMyPageUI {
    static let brandGreen = Color(
        red: 42 / 255,
        green: 174 / 255,
        blue: 102 / 255
    )

    static let softGreen = Color(
        red: 232 / 255,
        green: 245 / 255,
        blue: 236 / 255
    )

    static let background = Color(
        red: 248 / 255,
        green: 250 / 255,
        blue: 249 / 255
    )

    static let textPrimary = Color(
        red: 34 / 255,
        green: 34 / 255,
        blue: 34 / 255
    )

    static let textSecondary = Color(
        red: 102 / 255,
        green: 110 / 255,
        blue: 105 / 255
    )

    static let border = Color.black.opacity(0.08)
}

struct MyPageView: View {

    @State private var displayName = ""
    @State private var profileComment = ""
    @State private var profileImageURL = ""
    @State private var gender = "回答しない"
    @State private var ageGroup = "未設定"
    @State private var tennisExperience = "未設定"

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
                    ZStack {
                        StudentMyPageUI.background
                            .ignoresSafeArea()

                        ScrollView {
                            VStack(
                                alignment: .leading,
                                spacing: 18
                            ) {
                                headerSection
                                profileCard
                                statsSection
                                menuSection
                                accountSection

                                if !profileError.isEmpty {
                                    errorCard
                                }

                                logoutButton
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 30)
                        }
                    }
                } else {
                    loggedOutView
                }
            }
            .tint(StudentMyPageUI.brandGreen)
            .navigationTitle("マイページ")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                isLoggedIn =
                    Auth.auth().currentUser != nil

                if isLoggedIn {
                    loadMyPageData()
                } else {
                    resetMyPageState()
                }
            }
            .sheet(
                isPresented: $showProfileEditor
            ) {
                StudentProfileEditView(
                    initialDisplayName: displayName,
                    initialProfileComment: profileComment,
                    initialImageURL: profileImageURL,
                    initialGender: gender,
                    initialAgeGroup: ageGroup,
                    initialTennisExperience: tennisExperience
                ) {
                    savedDisplayName,
                    savedProfileComment,
                    savedImageURL,
                    savedGender,
                    savedAgeGroup,
                    savedTennisExperience in

                    displayName = savedDisplayName
                    profileComment = savedProfileComment
                    profileImageURL = savedImageURL
                    gender = savedGender
                    ageGroup = savedAgeGroup
                    tennisExperience = savedTennisExperience
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
                Button(
                    "キャンセル",
                    role: .cancel
                ) { }

                Button(
                    "ログアウト",
                    role: .destructive
                ) {
                    logout()
                }
            } message: {
                Text(
                    "再度利用するにはログインが必要です。"
                )
            }
        }
    }

    private var headerSection: some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            Text("マイページ")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(
                    StudentMyPageUI.textPrimary
                )

            Text(
                "プロフィールや予約、お気に入りを管理できます"
            )
            .font(.subheadline)
            .foregroundStyle(
                StudentMyPageUI.textSecondary
            )
        }
    }

    private var profileCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                studentProfileImage

                VStack(
                    alignment: .leading,
                    spacing: 6
                ) {
                    if isLoadingProfile {
                        ProgressView()
                            .tint(
                                StudentMyPageUI.brandGreen
                            )
                    } else {
                        Text(
                            displayName.isEmpty
                                ? "表示名未設定"
                                : displayName
                        )
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            StudentMyPageUI.textPrimary
                        )
                    }

                    Text(displayedProfileComment)
                        .font(.subheadline)
                        .foregroundStyle(
                            StudentMyPageUI.textSecondary
                        )
                        .lineLimit(2)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )

                    profileMetadata
                }

                Spacer()
            }

            Button {
                showProfileEditor = true
            } label: {
                Label(
                    "プロフィールを編集",
                    systemImage:
                        "person.crop.circle.badge.pencil"
                )
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .foregroundStyle(
                    StudentMyPageUI.brandGreen
                )
                .background(
                    StudentMyPageUI.softGreen
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 20,
                style: .continuous
            )
            .stroke(
                StudentMyPageUI.border,
                lineWidth: 1
            )
        }
    }

    @ViewBuilder
    private var profileMetadata: some View {
        let values = [
            ageGroup,
            tennisExperience
        ]
        .filter {
            !$0.isEmpty &&
            $0 != "未設定"
        }

        if !values.isEmpty {
            HStack(spacing: 6) {
                ForEach(values, id: \.self) {
                    value in

                    Text(value)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            StudentMyPageUI.brandGreen
                        )
                        .padding(.horizontal, 9)
                        .frame(height: 25)
                        .background(
                            StudentMyPageUI.softGreen
                        )
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var statsSection: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text("利用状況")
                .font(.headline)
                .foregroundStyle(
                    StudentMyPageUI.textPrimary
                )

            HStack(spacing: 10) {
                statCard(
                    title: "予約",
                    value: reservationCount,
                    isLoading:
                        isLoadingReservationCount,
                    icon: "calendar"
                )

                statCard(
                    title: "レビュー",
                    value: reviewCount,
                    isLoading:
                        isLoadingReviewCount,
                    icon: "star"
                )

                statCard(
                    title: "お気に入り",
                    value: favoriteCount,
                    isLoading:
                        isLoadingFavoriteCount,
                    icon: "heart"
                )
            }
        }
    }

    private func statCard(
        title: String,
        value: Int,
        isLoading: Bool,
        icon: String
    ) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        StudentMyPageUI.softGreen
                    )
                    .frame(width: 34, height: 34)

                Image(systemName: icon)
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        StudentMyPageUI.brandGreen
                    )
            }

            if isLoading {
                ProgressView()
                    .frame(height: 26)
                    .tint(
                        StudentMyPageUI.brandGreen
                    )
            } else {
                Text("\(value)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        StudentMyPageUI.textPrimary
                    )
                    .frame(height: 26)
            }

            Text(title)
                .font(.caption)
                .foregroundStyle(
                    StudentMyPageUI.textSecondary
                )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 16,
                style: .continuous
            )
            .stroke(
                StudentMyPageUI.border,
                lineWidth: 1
            )
        }
    }

    private var menuSection: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text("メニュー")
                .font(.headline)
                .foregroundStyle(
                    StudentMyPageUI.textPrimary
                )

            VStack(spacing: 0) {
                NavigationLink {
                    ReservationListView()
                } label: {
                    menuRow(
                        title: "予約一覧",
                        subtitle:
                            "今後の予定や履歴を確認",
                        icon: "calendar"
                    )
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 56)

                NavigationLink {
                    FavoriteView()
                } label: {
                    menuRow(
                        title: "お気に入り",
                        subtitle:
                            "保存したコーチを確認",
                        icon: "heart"
                    )
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 56)

                NavigationLink {
                    NotificationView()
                } label: {
                    menuRow(
                        title: "通知",
                        subtitle:
                            "予約やキャンセルのお知らせ",
                        icon: "bell"
                    )
                }
                .buttonStyle(.plain)
            }
            .background(Color.white)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
                .stroke(
                    StudentMyPageUI.border,
                    lineWidth: 1
                )
            }
        }
    }

    private var accountSection: some View {
        VStack(
            alignment: .leading,
            spacing: 10
        ) {
            Text("アカウント")
                .font(.headline)
                .foregroundStyle(
                    StudentMyPageUI.textPrimary
                )

            NavigationLink {
                SettingsView()
            } label: {
                menuRow(
                    title: "設定",
                    subtitle:
                        "アカウントや各種設定",
                    icon: "gearshape"
                )
                .background(Color.white)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                    .stroke(
                        StudentMyPageUI.border,
                        lineWidth: 1
                    )
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func menuRow(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 11,
                    style: .continuous
                )
                .fill(StudentMyPageUI.softGreen)
                .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(
                        .system(
                            size: 16,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        StudentMyPageUI.brandGreen
                    )
            }

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        StudentMyPageUI.textPrimary
                    )

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(
                        StudentMyPageUI.textSecondary
                    )
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(
                    .system(
                        size: 11,
                        weight: .bold
                    )
                )
                .foregroundStyle(
                    StudentMyPageUI.textSecondary
                )
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 66)
        .contentShape(Rectangle())
    }

    private var errorCard: some View {
        Label(
            profileError,
            systemImage:
                "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(.red)
        .padding(14)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color.red.opacity(0.06)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }

    private var logoutButton: some View {
        Button(role: .destructive) {
            showLogoutAlert = true
        } label: {
            Label(
                "ログアウト",
                systemImage:
                    "rectangle.portrait.and.arrow.right"
            )
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.white)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 15,
                    style: .continuous
                )
                .stroke(
                    Color.red.opacity(0.16),
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
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
                            .fill(
                                StudentMyPageUI.softGreen
                            )

                        ProgressView()
                            .tint(
                                StudentMyPageUI.brandGreen
                            )
                    }

                @unknown default:
                    defaultProfileImage
                }
            }
            .frame(width: 82, height: 82)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(
                        StudentMyPageUI.border,
                        lineWidth: 1
                    )
            }

        } else {
            defaultProfileImage
        }
    }

    private var defaultProfileImage: some View {
        ZStack {
            Circle()
                .fill(StudentMyPageUI.softGreen)
                .frame(width: 82, height: 82)

            Image(systemName: "person.fill")
                .font(.system(size: 34))
                .foregroundStyle(
                    StudentMyPageUI.brandGreen
                )
        }
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
        ZStack {
            StudentMyPageUI.background
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(
                            StudentMyPageUI.softGreen
                        )
                        .frame(width: 92, height: 92)

                    Image(
                        systemName:
                            "person.crop.circle"
                    )
                    .font(.system(size: 42))
                    .foregroundStyle(
                        StudentMyPageUI.brandGreen
                    )
                }

                Text(
                    "マイページを利用するにはログインが必要です"
                )
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(
                    StudentMyPageUI.textPrimary
                )
                .multilineTextAlignment(.center)

                Text(
                    "ログインすると、予約・レビュー・お気に入り・設定を確認できます。"
                )
                .font(.subheadline)
                .foregroundStyle(
                    StudentMyPageUI.textSecondary
                )
                .multilineTextAlignment(.center)

                Button {
                    showLogin = true
                } label: {
                    Label(
                        "ログイン・新規会員登録",
                        systemImage:
                            "person.crop.circle.badge.plus"
                    )
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        StudentMyPageUI.brandGreen
                    )
                    .foregroundStyle(.white)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 15,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 6)

                Spacer()
            }
            .padding(.horizontal, 28)
        }
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
        gender = "回答しない"
        ageGroup = "未設定"
        tennisExperience = "未設定"
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

                    gender =
                        data["gender"] as? String
                        ?? "回答しない"

                    ageGroup =
                        data["ageGroup"] as? String
                        ?? "未設定"

                    tennisExperience =
                        data["tennisExperience"] as? String
                        ?? "未設定"
                }
            }
    }
}

private struct StudentProfileEditView: View {

    let initialDisplayName: String
    let initialProfileComment: String
    let initialImageURL: String
    let initialGender: String
    let initialAgeGroup: String
    let initialTennisExperience: String

    let onSaved: (
        String,
        String,
        String,
        String,
        String,
        String
    ) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var profileComment: String
    @State private var imageURL: String
    @State private var gender: String
    @State private var ageGroup: String
    @State private var tennisExperience: String

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: Image?
    @State private var selectedImageData: Data?

    @State private var isSaving = false
    @State private var errorMessage = ""

    private let storage = Storage.storage()

    private let genderOptions = [
        "回答しない",
        "男性",
        "女性",
        "その他"
    ]

    private let ageGroupOptions = [
        "未設定",
        "10代",
        "20代",
        "30代",
        "40代",
        "50代",
        "60代",
        "70代以上"
    ]

    private let tennisExperienceOptions = [
        "未設定",
        "未経験",
        "1年未満",
        "1〜3年",
        "3〜5年",
        "5〜10年",
        "10年以上"
    ]

    init(
        initialDisplayName: String,
        initialProfileComment: String,
        initialImageURL: String,
        initialGender: String,
        initialAgeGroup: String,
        initialTennisExperience: String,
        onSaved: @escaping (
            String,
            String,
            String,
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

        self.initialGender =
            initialGender

        self.initialAgeGroup =
            initialAgeGroup

        self.initialTennisExperience =
            initialTennisExperience

        self.onSaved = onSaved

        _displayName =
            State(initialValue: initialDisplayName)

        _profileComment =
            State(initialValue: initialProfileComment)

        _imageURL =
            State(initialValue: initialImageURL)

        _gender =
            State(
                initialValue:
                    initialGender.isEmpty
                    ? "回答しない"
                    : initialGender
            )

        _ageGroup =
            State(
                initialValue:
                    initialAgeGroup.isEmpty
                    ? "未設定"
                    : initialAgeGroup
            )

        _tennisExperience =
            State(
                initialValue:
                    initialTennisExperience.isEmpty
                    ? "未設定"
                    : initialTennisExperience
            )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StudentMyPageUI.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: 18
                    ) {
                        editorHeader

                        profileImageCard

                        basicProfileCard

                        lessonProfileCard

                        if !errorMessage.isEmpty {
                            editorErrorCard
                        }

                        Color.clear
                            .frame(height: 92)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }
                .scrollDismissesKeyboard(
                    .interactively
                )
            }
            .tint(
                StudentMyPageUI.brandGreen
            )
            .navigationTitle(
                "プロフィールを編集"
            )
            .navigationBarTitleDisplayMode(
                .inline
            )
            .safeAreaInset(edge: .bottom) {
                saveArea
            }
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
            .onChange(
                of: selectedItem
            ) { _ in
                loadSelectedImage()
            }
        }
    }

    private var editorHeader: some View {
        VStack(
            alignment: .leading,
            spacing: 5
        ) {
            Text("プロフィールを編集")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(
                    StudentMyPageUI.textPrimary
                )

            Text(
                "コーチがレッスン前に確認する情報を設定できます"
            )
            .font(.subheadline)
            .foregroundStyle(
                StudentMyPageUI.textSecondary
            )
        }
    }

    private var profileImageCard: some View {
        VStack(spacing: 14) {
            HStack {
                sectionHeader(
                    "プロフィール画像",
                    icon: "person.crop.circle"
                )

                Spacer()
            }

            PhotosPicker(
                selection: $selectedItem,
                matching: .images
            ) {
                VStack(spacing: 10) {
                    editableProfileImage

                    Label(
                        "画像を変更",
                        systemImage: "camera.fill"
                    )
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        StudentMyPageUI.brandGreen
                    )
                }
                .frame(
                    maxWidth: .infinity
                )
            }
            .buttonStyle(.plain)
            .disabled(isSaving)

            Text(
                "画像をタップすると写真を選択できます。"
            )
            .font(.caption)
            .foregroundStyle(
                StudentMyPageUI.textSecondary
            )
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                StudentMyPageUI.border,
                lineWidth: 1
            )
        }
    }

    private var basicProfileCard: some View {
        VStack(
            alignment: .leading,
            spacing: 18
        ) {
            sectionHeader(
                "基本プロフィール",
                icon: "person.text.rectangle"
            )

            VStack(
                alignment: .leading,
                spacing: 7
            ) {
                HStack {
                    Text("表示名")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            StudentMyPageUI.textSecondary
                        )

                    Spacer()

                    Text(
                        "\(trimmedDisplayNameCount)/20"
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        trimmedDisplayNameCount > 20
                            ? Color.red
                            : StudentMyPageUI.textSecondary
                    )
                }

                TextField(
                    "例：たかひろ",
                    text: $displayName
                )
                .textInputAutocapitalization(
                    .never
                )
                .padding(.horizontal, 13)
                .frame(height: 48)
                .background(
                    StudentMyPageUI.background
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                    .stroke(
                        trimmedDisplayNameCount > 20
                            ? Color.red.opacity(0.5)
                            : StudentMyPageUI.border,
                        lineWidth: 1
                    )
                }

                Text(
                    "レビューにはこの表示名が表示されます。"
                )
                .font(.caption)
                .foregroundStyle(
                    StudentMyPageUI.textSecondary
                )
            }

            Divider()

            VStack(
                alignment: .leading,
                spacing: 7
            ) {
                HStack {
                    Text("ひとこと")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            StudentMyPageUI.textSecondary
                        )

                    Spacer()

                    Text(
                        "\(trimmedCommentCount)/50"
                    )
                    .font(.caption2)
                    .foregroundStyle(
                        trimmedCommentCount > 50
                            ? Color.red
                            : StudentMyPageUI.textSecondary
                    )
                }

                ZStack(
                    alignment: .topLeading
                ) {
                    if profileComment.isEmpty {
                        Text(
                            "例：週末に楽しくテニスしています！"
                        )
                        .foregroundStyle(
                            StudentMyPageUI.textSecondary.opacity(0.65)
                        )
                        .padding(.top, 13)
                        .padding(.leading, 13)
                        .allowsHitTesting(false)
                    }

                    TextEditor(
                        text: $profileComment
                    )
                    .frame(minHeight: 100)
                    .padding(7)
                    .scrollContentBackground(
                        .hidden
                    )
                    .background(Color.clear)
                }
                .background(
                    StudentMyPageUI.background
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 13,
                        style: .continuous
                    )
                    .stroke(
                        trimmedCommentCount > 50
                            ? Color.red.opacity(0.5)
                            : StudentMyPageUI.border,
                        lineWidth: 1
                    )
                }

                Text(
                    "未入力の場合は「テニスを楽しもう！」と表示されます。"
                )
                .font(.caption)
                .foregroundStyle(
                    StudentMyPageUI.textSecondary
                )
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                StudentMyPageUI.border,
                lineWidth: 1
            )
        }
    }

    private var lessonProfileCard: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            sectionHeader(
                "レッスンプロフィール",
                icon: "figure.tennis"
            )

            profilePickerRow(
                title: "性別",
                icon: "person.2",
                selection: $gender,
                options: genderOptions
            )

            Divider()

            profilePickerRow(
                title: "年代",
                icon: "calendar.badge.clock",
                selection: $ageGroup,
                options: ageGroupOptions
            )

            Divider()

            profilePickerRow(
                title: "テニス歴",
                icon: "figure.tennis",
                selection:
                    $tennisExperience,
                options:
                    tennisExperienceOptions
            )

            HStack(
                alignment: .top,
                spacing: 8
            ) {
                Image(
                    systemName: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(
                    StudentMyPageUI.brandGreen
                )

                Text(
                    "レッスン前にコーチが確認できる簡易プロフィールです。性別は「回答しない」を選択できます。"
                )
                .font(.caption)
                .foregroundStyle(
                    StudentMyPageUI.textSecondary
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }
            .padding(12)
            .background(
                StudentMyPageUI.softGreen.opacity(0.50)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
            )
        }
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                StudentMyPageUI.border,
                lineWidth: 1
            )
        }
    }

    private func profilePickerRow(
        title: String,
        icon: String,
        selection: Binding<String>,
        options: [String]
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 10,
                    style: .continuous
                )
                .fill(
                    StudentMyPageUI.softGreen
                )
                .frame(width: 38, height: 38)

                Image(systemName: icon)
                    .font(
                        .system(
                            size: 15,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        StudentMyPageUI.brandGreen
                    )
            }

            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(
                    StudentMyPageUI.textPrimary
                )

            Spacer()

            Picker(
                title,
                selection: selection
            ) {
                ForEach(
                    options,
                    id: \.self
                ) { option in
                    Text(option)
                        .tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(
                StudentMyPageUI.brandGreen
            )
        }
    }

    private var editorErrorCard: some View {
        HStack(
            alignment: .top,
            spacing: 8
        ) {
            Image(
                systemName:
                    "exclamationmark.triangle.fill"
            )

            Text(errorMessage)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
        }
        .font(.caption)
        .foregroundStyle(.red)
        .padding(14)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .background(
            Color.red.opacity(0.06)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
    }

    private var saveArea: some View {
        VStack(spacing: 7) {
            Button {
                saveProfile()
            } label: {
                HStack(spacing: 8) {
                    Spacer()

                    if isSaving {
                        ProgressView()
                            .tint(.white)

                        Text("保存中…")
                            .fontWeight(.semibold)
                    } else {
                        Image(
                            systemName:
                                "checkmark.circle.fill"
                        )

                        Text("変更を保存")
                            .fontWeight(.semibold)
                    }

                    Spacer()
                }
                .frame(height: 50)
                .foregroundStyle(.white)
                .background(
                    isSaving
                        ? Color.gray
                        : StudentMyPageUI.brandGreen
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 15,
                        style: .continuous
                    )
                )
            }
            .buttonStyle(.plain)
            .disabled(isSaving)

            Text(
                "保存した内容はマイページに反映されます"
            )
            .font(.caption2)
            .foregroundStyle(
                StudentMyPageUI.textSecondary
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private func sectionHeader(
        _ title: String,
        icon: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(
                    .system(
                        size: 15,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    StudentMyPageUI.brandGreen
                )

            Text(title)
                .font(.headline)
                .foregroundStyle(
                    StudentMyPageUI.textPrimary
                )
        }
    }

    private var trimmedDisplayNameCount: Int {
        displayName
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .count
    }

    private var trimmedCommentCount: Int {
        profileComment
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .count
    }

    @ViewBuilder
    private var editableProfileImage: some View {
        if let selectedImage {
            selectedImage
                .resizable()
                .scaledToFill()
                .frame(
                    width: 120,
                    height: 120
                )
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(
                            StudentMyPageUI.brandGreen.opacity(0.22),
                            lineWidth: 2
                        )
                }

        } else if !imageURL.isEmpty,
                  let url =
                    URL(string: imageURL) {

            AsyncImage(url: url) {
                phase in

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
                                StudentMyPageUI.softGreen
                            )

                        ProgressView()
                            .tint(
                                StudentMyPageUI.brandGreen
                            )
                    }

                @unknown default:
                    editPlaceholderImage
                }
            }
            .frame(
                width: 120,
                height: 120
            )
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(
                        StudentMyPageUI.brandGreen.opacity(0.22),
                        lineWidth: 2
                    )
            }

        } else {
            editPlaceholderImage
        }
    }

    private var editPlaceholderImage: some View {
        ZStack {
            Circle()
                .fill(
                    StudentMyPageUI.softGreen
                )
                .frame(
                    width: 120,
                    height: 120
                )

            Image(
                systemName: "person.fill"
            )
            .font(.system(size: 46))
            .foregroundStyle(
                StudentMyPageUI.brandGreen
            )

            ZStack {
                Circle()
                    .fill(
                        StudentMyPageUI.brandGreen
                    )
                    .frame(
                        width: 34,
                        height: 34
                    )

                Image(
                    systemName: "camera.fill"
                )
                .font(.system(size: 14))
                .foregroundStyle(.white)
            }
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
                    imageURL: uploadedURL,
                    gender: gender,
                    ageGroup: ageGroup,
                    tennisExperience: tennisExperience
                )
            }

        } else {
            saveStudentDocument(
                uid: uid,
                displayName: trimmedDisplayName,
                profileComment: trimmedComment,
                imageURL: imageURL,
                gender: gender,
                ageGroup: ageGroup,
                tennisExperience: tennisExperience
            )
        }
    }

    private func uploadProfileImage(
        data: Data,
        uid: String,
        completion: @escaping (String?) -> Void
    ) {
        guard let uiImage = UIImage(data: data),
              let jpegData = uiImage.jpegData(
                compressionQuality: 0.85
              ) else {
            DispatchQueue.main.async {
                errorMessage =
                    "プロフィール画像をJPEG形式に変換できませんでした"
            }
            completion(nil)
            return
        }

        let ref = storage.reference()
            .child("studentImages/\(uid).jpg")

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        ref.putData(
            jpegData,
            metadata: metadata
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
        imageURL: String,
        gender: String,
        ageGroup: String,
        tennisExperience: String
    ) {
        Firestore.firestore()
            .collection("students")
            .document(uid)
            .setData(
                [
                    "displayName": displayName,
                    "profileComment": profileComment,
                    "imageURL": imageURL,
                    "gender": gender,
                    "ageGroup": ageGroup,
                    "tennisExperience": tennisExperience,
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
                        imageURL,
                        gender,
                        ageGroup,
                        tennisExperience
                    )

                    dismiss()
                }
            }
    }
}

#Preview {
    MyPageView()
}
