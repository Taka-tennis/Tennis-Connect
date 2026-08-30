import SwiftUI
import FirebaseFirestore

struct CoachProfileDestinationView: View {

    let coachId: String

    private let db = Firestore.firestore()

    @State private var coach: Coach?
    @State private var isLoading = false
    @State private var errorMessage = ""

    var body: some View {
        Group {
            if let coach {
                CoachDetailView(
                    coach: coach
                )

            } else if isLoading {
                ProgressView(
                    "コーチプロフィールを読み込み中…"
                )

            } else {
                VStack(spacing: 16) {
                    Image(
                        systemName:
                            "exclamationmark.circle"
                    )
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                    Text(
                        errorMessage.isEmpty
                            ? "コーチプロフィールを確認できませんでした"
                            : errorMessage
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                    Button("再読み込み") {
                        loadCoach()
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if coach == nil {
                loadCoach()
            }
        }
    }

    private func loadCoach() {
        guard !coachId.isEmpty else {
            errorMessage =
                "コーチ情報を確認できませんでした"
            return
        }

        isLoading = true
        errorMessage = ""

        db.collection("coaches")
            .document(coachId)
            .getDocument {
                snapshot,
                error in

                DispatchQueue.main.async {
                    isLoading = false

                    if let error {
                        errorMessage =
                            "コーチプロフィールを取得できませんでした: "
                            + error.localizedDescription
                        return
                    }

                    guard
                        let snapshot,
                        snapshot.exists,
                        let data =
                            snapshot.data()
                    else {
                        errorMessage =
                            "コーチプロフィールが見つかりませんでした"
                        return
                    }

                    let careers =
                        resolvedCareers(
                            from: data
                        )

                    coach = Coach(
                        id:
                            snapshot.documentID,
                        name:
                            data["name"]
                            as? String
                            ?? "名前未登録",
                        price:
                            data["price"]
                            as? Int
                            ?? 0,
                        area:
                            data["area"]
                            as? String
                            ?? "エリア未登録",
                        imageURL:
                            data["imageURL"]
                            as? String
                            ?? "",
                        availableTimes: [],
                        ageGroup:
                            data["ageGroup"]
                            as? String
                            ?? "年代未登録",
                        careers:
                            careers,
                        tennisExperience:
                            data[
                                "tennisExperience"
                            ]
                            as? String
                            ?? "未登録",
                        coachingExperience:
                            data[
                                "coachingExperience"
                            ]
                            as? String
                            ?? "未登録",
                        introduction:
                            data["introduction"]
                            as? String
                            ?? "自己紹介はまだありません。"
                    )
                }
            }
    }

    private func resolvedCareers(
        from data: [String: Any]
    ) -> [String] {
        if let careers =
            data["careers"]
            as? [String] {
            let cleaned =
                careers.filter {
                    !$0.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty
                }

            if !cleaned.isEmpty {
                return cleaned
            }
        }

        if let legacyCareer =
            data["career"]
            as? String {
            let trimmed =
                legacyCareer
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

            if !trimmed.isEmpty {
                return [trimmed]
            }
        }

        return ["経歴未登録"]
    }
}
