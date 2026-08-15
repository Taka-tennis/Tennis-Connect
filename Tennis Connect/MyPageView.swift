import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct MyPageView: View {

    @State private var displayName = ""
    @State private var isLoadingProfile = false
    @State private var profileError = ""
    @State private var showDisplayNameEditor = false

    private let db = Firestore.firestore()

    var body: some View {

        NavigationStack {

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
                                Text("12")
                                    .font(.title2)
                                    .bold()

                                Text("予約")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            VStack {
                                Text("8")
                                    .font(.title2)
                                    .bold()

                                Text("レビュー")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            VStack {
                                Text("❤️")
                                    .font(.title2)

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
                        Label("表示名を編集", systemImage: "person.text.rectangle")
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

                        Text("通知")

                    } label: {

                        Label("通知", systemImage: "bell")

                    }

                    NavigationLink {

                        Text("設定")

                    } label: {

                        Label("設定", systemImage: "gear")

                    }

                }

                Section {

                    Button(role: .destructive) {

                    } label: {

                        Text("ログアウト")

                    }

                }

            }
            .navigationTitle("マイページ")
            .onAppear {
                loadStudentProfile()
            }
            .sheet(isPresented: $showDisplayNameEditor) {
                DisplayNameEditView(
                    initialDisplayName: displayName
                ) { savedDisplayName in
                    displayName = savedDisplayName
                    profileError = ""
                }
            }

        }

    }

    private func loadStudentProfile() {
        guard let uid = Auth.auth().currentUser?.uid else {
            displayName = ""
            profileError = "プロフィールの確認にはログインが必要です"
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
