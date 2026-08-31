import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

struct StudentPublicProfileView: View {

    let studentId: String
    let initialDisplayName: String
    let initialImageURL: String

    private let functions = Functions.functions(
        region: "asia-northeast1"
    )

    @State private var displayName: String
    @State private var profileComment = ""
    @State private var imageURL: String
    @State private var gender = "回答しない"
    @State private var ageGroup = "未設定"
    @State private var tennisExperience = "未設定"
    @State private var isLoading = false
    @State private var errorMessage = ""

    @State private var canMessageStudent = false
    @State private var isCheckingChatAccess = false
    @State private var currentCoachName = ""

    init(
        studentId: String,
        initialDisplayName: String = "",
        initialImageURL: String = ""
    ) {
        self.studentId = studentId
        self.initialDisplayName = initialDisplayName
        self.initialImageURL = initialImageURL

        _displayName = State(
            initialValue: initialDisplayName
        )
        _imageURL = State(
            initialValue: initialImageURL
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                StudentPublicAvatarView(
                    imageURL: imageURL,
                    size: 128
                )
                .padding(.top, 28)

                VStack(spacing: 8) {
                    Text(
                        displayName
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            .isEmpty
                            ? "生徒"
                            : displayName
                    )
                    .font(.title)
                    .fontWeight(.bold)

                    Text("生徒プロフィール")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(
                    alignment: .leading,
                    spacing: 12
                ) {
                    Label(
                        "ひとこと",
                        systemImage: "text.bubble"
                    )
                    .font(.headline)

                    if isLoading &&
                        profileComment.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 18)

                    } else {
                        Text(displayedProfileComment)
                            .font(.body)
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                    }
                }
                .padding(18)
                .background(
                    Color(
                        .secondarySystemGroupedBackground
                    )
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )

                VStack(spacing: 0) {
                    publicProfileRow(
                        title: "性別",
                        value: gender,
                        systemImage: "person.fill"
                    )

                    Divider()

                    publicProfileRow(
                        title: "年代",
                        value: ageGroup,
                        systemImage: "calendar"
                    )

                    Divider()

                    publicProfileRow(
                        title: "テニス歴",
                        value: tennisExperience,
                        systemImage: "clock"
                    )
                }
                .padding(.horizontal, 18)
                .background(
                    Color(
                        .secondarySystemGroupedBackground
                    )
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )

                if canMessageStudent &&
                    !isCheckingChatAccess,
                   let coachId =
                        Auth.auth().currentUser?.uid,
                   coachId != studentId {
                    NavigationLink {
                        ChatView(
                            coachId: coachId,
                            coachName:
                                resolvedCoachName,
                            studentId: studentId,
                            studentName:
                                resolvedStudentName,
                            currentRole: .coach
                        )
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

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
        }
        .background(
            Color(.systemGroupedBackground)
        )
        .navigationTitle("生徒プロフィール")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadProfile()
            await loadChatAccessState()
        }
    }

    private var resolvedStudentName: String {
        let trimmed =
            displayName
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        return trimmed.isEmpty
            ? "生徒"
            : trimmed
    }

    private var resolvedCoachName: String {
        let trimmed =
            currentCoachName
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        return trimmed.isEmpty
            ? "コーチ"
            : trimmed
    }

    private var displayedProfileComment: String {
        let trimmed =
            profileComment
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        return trimmed.isEmpty
            ? "テニスを楽しもう！"
            : trimmed
    }

    private func publicProfileRow(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 24)
                .foregroundStyle(.green)

            Text(title)
                .fontWeight(.semibold)

            Spacer()

            Text(
                value
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty
                    ? "未設定"
                    : value
            )
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 15)
    }

    @MainActor
    private func loadChatAccessState() async {
        guard
            let coachId =
                Auth.auth().currentUser?.uid,
            !coachId.isEmpty,
            coachId != studentId
        else {
            canMessageStudent = false
            isCheckingChatAccess = false
            return
        }

        isCheckingChatAccess = true
        canMessageStudent = false

        do {
            let coachSnapshot =
                try await Firestore.firestore()
                    .collection("coaches")
                    .document(coachId)
                    .getDocument()

            currentCoachName =
                coachSnapshot
                    .data()?["name"]
                as? String
                ?? ""

            let result =
                try await functions
                    .httpsCallable(
                        "getChatMessagingStatus"
                    )
                    .call(
                        [
                            "studentId": studentId,
                            "coachId": coachId
                        ]
                    )

            guard
                let data =
                    result.data
                    as? [String: Any]
            else {
                canMessageStudent = false
                isCheckingChatAccess = false
                return
            }

            canMessageStudent =
                data["canSend"]
                as? Bool
                ?? false

            isCheckingChatAccess = false

        } catch {
            canMessageStudent = false
            isCheckingChatAccess = false

            print(
                "生徒プロフィールのチャット利用可否確認失敗:",
                error.localizedDescription
            )
        }
    }

    @MainActor
    private func loadProfile() async {
        guard !studentId.isEmpty else {
            errorMessage =
                "生徒情報を確認できませんでした"
            return
        }

        isLoading = true
        errorMessage = ""

        do {
            let result = try await functions
                .httpsCallable(
                    "getStudentPublicProfile"
                )
                .call(
                    [
                        "studentId": studentId
                    ]
                )

            guard
                let data =
                    result.data
                    as? [String: Any]
            else {
                throw StudentProfileError
                    .invalidResponse
            }

            let loadedDisplayName =
                (
                    data["displayName"]
                    as? String
                    ?? ""
                )
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

            let loadedComment =
                data["profileComment"]
                as? String
                ?? ""

            let loadedImageURL =
                data["imageURL"]
                as? String
                ?? ""

            let loadedGender =
                data["gender"]
                as? String
                ?? "回答しない"

            let loadedAgeGroup =
                data["ageGroup"]
                as? String
                ?? "未設定"

            let loadedTennisExperience =
                data["tennisExperience"]
                as? String
                ?? "未設定"

            if !loadedDisplayName.isEmpty {
                displayName =
                    loadedDisplayName
            }

            profileComment =
                loadedComment

            if !loadedImageURL.isEmpty {
                imageURL =
                    loadedImageURL
            }

            gender =
                loadedGender.isEmpty
                ? "回答しない"
                : loadedGender

            ageGroup =
                loadedAgeGroup.isEmpty
                ? "未設定"
                : loadedAgeGroup

            tennisExperience =
                loadedTennisExperience.isEmpty
                ? "未設定"
                : loadedTennisExperience

            isLoading = false

        } catch {
            isLoading = false
            errorMessage =
                "プロフィールを取得できませんでした: "
                + error.localizedDescription
        }
    }
}

private enum StudentProfileError: Error {
    case invalidResponse
}

extension StudentProfileError:
    LocalizedError {

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "プロフィール情報の形式を確認できませんでした"
        }
    }
}

private struct StudentPublicAvatarView: View {

    let imageURL: String
    let size: CGFloat

    var body: some View {
        AsyncImage(
            url: URL(string: imageURL)
        ) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()

            case .failure:
                placeholder

            case .empty:
                if imageURL.isEmpty {
                    placeholder
                } else {
                    ProgressView()
                }

            @unknown default:
                placeholder
            }
        }
        .frame(
            width: size,
            height: size
        )
        .background(
            Color(.systemGray5)
        )
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(
                    Color(.separator)
                        .opacity(0.2),
                    lineWidth: 0.8
                )
        }
    }

    private var placeholder: some View {
        Image(
            systemName: "person.fill"
        )
        .resizable()
        .scaledToFit()
        .padding(size * 0.22)
        .foregroundStyle(.secondary)
    }
}
