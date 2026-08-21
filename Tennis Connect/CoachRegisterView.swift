import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import PhotosUI
import FirebaseStorage
import UIKit

struct CoachRegisterView: View {

    @State private var name = ""
    @State private var area = ""
    @State private var career = ""
    @State private var price = ""
    @State private var introduction = ""
    @State private var tennisExperience = ""
    @State private var coachingExperience = ""
    @State private var availableTimes = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: Image?
    @State private var imageData: Data?
    @State private var imageURL = ""
    @State private var selectedLessonTimes: [String] = []
    @State private var ageGroup = "20代"
    @State private var showSuccessAlert = false

    @State private var isLoadingCoach = true
    @State private var isExistingCoach = false
    @State private var isSavingProfile = false
    @State private var showUpdateAlert = false
    @State private var profileErrorMessage = ""
    @State private var hasLoadedCoach = false

    @Environment(\.dismiss) private var dismiss

    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    private let timeSlots = [
        "09:00", "10:00", "11:00",
        "12:00", "13:00", "14:00",
        "15:00", "16:00", "17:00",
        "18:00", "19:00", "20:00",
        "21:00"
    ]

    var body: some View {
        NavigationStack {
            Group {
                if isLoadingCoach {
                    ProgressView("プロフィールを読み込み中…")
                } else {
                    Form {
                        BasicInfoSectionView(
                            name: $name,
                            area: $area,
                            career: $career,
                            price: $price,
                            ageGroup: $ageGroup,
                            tennisExperience: $tennisExperience,
                            coachingExperience: $coachingExperience
                        )

                        ProfileSectionView(
                            selectedItem: $selectedItem,
                            selectedImage: $selectedImage,
                            imageData: $imageData,
                            imageURL: $imageURL,
                            introduction: $introduction,
                            uploadImage: uploadImage
                        )

                        if isExistingCoach {
                            CoachVideoUploadSection()

                            Section("空き時間") {
                                Text(
                                    "空き日程は、コーチホームの「空き日程管理」から変更できます"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            updateButtonSection
                        } else {
                            AvailableTimeSectionView(
                                timeSlots: timeSlots,
                                selectedLessonTimes: $selectedLessonTimes,
                                availableTimes: $availableTimes
                            )

                            RegisterButtonSectionView(
                                name: $name,
                                area: $area,
                                career: $career,
                                price: $price,
                                imageURL: $imageURL,
                                introduction: $introduction,
                                tennisExperience: $tennisExperience,
                                coachingExperience: $coachingExperience,
                                availableTimes: $availableTimes,
                                ageGroup: $ageGroup,
                                showSuccessAlert: $showSuccessAlert
                            )
                        }
                    }
                }
            }
            .navigationTitle(
                isExistingCoach
                    ? "プロフィール編集"
                    : "コーチ登録"
            )
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !hasLoadedCoach {
                    loadCoachProfile()
                }
            }
            .alert(
                "更新完了",
                isPresented: $showUpdateAlert
            ) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("プロフィールを更新しました！")
            }
        }
    }

    @ViewBuilder
    private var updateButtonSection: some View {
        Section {
            Button {
                updateCoachProfile()
            } label: {
                HStack {
                    Spacer()

                    if isSavingProfile {
                        ProgressView()
                    } else {
                        Text("変更を保存")
                            .fontWeight(.semibold)
                    }

                    Spacer()
                }
            }
            .disabled(isSavingProfile)

            if !profileErrorMessage.isEmpty {
                Text(profileErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func uploadImage(
        _ data: Data,
        completion: @escaping (String?) -> Void
    ) {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("画像アップロード失敗: ログインが必要です")
            completion(nil)
            return
        }

        let ref = storage.reference()
            .child("coachImages/\(uid).jpg")

        let previousImageURL = imageURL

        ref.putData(data, metadata: nil) { _, error in
            if let error {
                print("アップロード失敗: \(error)")
                completion(nil)
                return
            }

            ref.downloadURL { url, error in
                if let error {
                    print("画像URL取得失敗: \(error)")
                    completion(nil)
                    return
                }

                guard let url else {
                    completion(nil)
                    return
                }

                if !previousImageURL.isEmpty {
                    let previousRef =
                        storage.reference(
                            forURL: previousImageURL
                        )

                    if previousRef.fullPath != ref.fullPath {
                        previousRef.delete { deleteError in
                            if let deleteError {
                                print(
                                    "旧プロフィール画像の削除に失敗: \(deleteError)"
                                )
                            }
                        }
                    }
                }

                completion(url.absoluteString)
            }
        }
    }

    private func loadCoachProfile() {
        guard let uid = Auth.auth().currentUser?.uid else {
            isLoadingCoach = false
            hasLoadedCoach = true
            profileErrorMessage =
                "プロフィールの確認にはログインが必要です"
            return
        }

        db.collection("coaches")
            .document(uid)
            .getDocument { snapshot, error in
                DispatchQueue.main.async {
                    isLoadingCoach = false
                    hasLoadedCoach = true

                    if let error {
                        profileErrorMessage =
                            "プロフィールを取得できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    guard let data = snapshot?.data() else {
                        isExistingCoach = false
                        return
                    }

                    isExistingCoach = true

                    name =
                        data["name"] as? String ?? ""

                    area =
                        data["area"] as? String ?? ""

                    career =
                        loadedCareer(from: data)

                    tennisExperience =
                        data["tennisExperience"] as? String ?? ""

                    coachingExperience =
                        data["coachingExperience"] as? String ?? ""

                    introduction =
                        data["introduction"] as? String ?? ""

                    imageURL =
                        data["imageURL"] as? String ?? ""

                    ageGroup =
                        data["ageGroup"] as? String ?? "20代"

                    if let savedPrice = data["price"] as? Int {
                        price = String(savedPrice)
                    } else if let savedPrice =
                                data["price"] as? NSNumber {
                        price = savedPrice.stringValue
                    } else {
                        price =
                            data["price"] as? String ?? ""
                    }

                    if let savedTimes =
                        data["availableTimes"] as? [String] {
                        selectedLessonTimes = savedTimes
                        availableTimes =
                            savedTimes.joined(separator: ",")
                    }

                    profileErrorMessage = ""
                }
            }
    }

    private func updateCoachProfile() {
        guard let uid = Auth.auth().currentUser?.uid else {
            profileErrorMessage =
                "プロフィールの更新にはログインが必要です"
            return
        }

        profileErrorMessage = ""
        isSavingProfile = true

        let trimmedCareer =
            career.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        let profileData: [String: Any] = [
            "coachId": uid,
            "ownerId": uid,
            "name": name,
            "area": area,
            "career": trimmedCareer,
            "careers": normalizedCareers(from: career),
            "tennisExperience":
                tennisExperience.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            "coachingExperience":
                coachingExperience.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            "price": Int(price) ?? 0,
            "imageURL": imageURL,
            "introduction": introduction,
            "ageGroup": ageGroup,

            // 旧プロフィールで使っていた項目は
            // 今回の仕様変更に合わせて削除します。
            "specialty": FieldValue.delete()
        ]

        db.collection("coaches")
            .document(uid)
            .setData(
                profileData,
                merge: true
            ) { error in
                DispatchQueue.main.async {
                    isSavingProfile = false

                    if let error {
                        profileErrorMessage =
                            "更新できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    showUpdateAlert = true
                }
            }
    }

    private func loadedCareer(
        from data: [String: Any]
    ) -> String {
        if let careers = data["careers"] as? [String] {
            let cleaned = careers
                .map {
                    $0.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                }
                .filter {
                    !$0.isEmpty &&
                    $0 != "経歴未登録"
                }

            if !cleaned.isEmpty {
                return cleaned.joined(separator: "\n")
            }
        }

        return data["career"] as? String ?? ""
    }

    private func normalizedCareers(
        from value: String
    ) -> [String] {
        value
            .components(separatedBy: .newlines)
            .map {
                $0.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
            .filter {
                !$0.isEmpty
            }
    }
}

#Preview {
    CoachRegisterView()
}
