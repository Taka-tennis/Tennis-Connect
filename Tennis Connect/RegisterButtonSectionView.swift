import SwiftUI
import FirebaseAuth
import FirebaseFunctions

struct RegisterButtonSectionView: View {

    @Binding var name: String
    @Binding var area: String
    @Binding var career: String
    @Binding var price: String
    @Binding var imageURL: String
    @Binding var introduction: String
    @Binding var tennisExperience: String
    @Binding var coachingExperience: String
    @Binding var availableTimes: String
    @Binding var ageGroup: String
    @Binding var showSuccessAlert: Bool

    @State private var registrationError = ""
    @State private var isRegistering = false

    private let functions = Functions.functions(
        region: "asia-northeast1"
    )

    var body: some View {
        Section {
            Button {
                registerCoach()
            } label: {
                HStack {
                    Spacer()

                    if isRegistering {
                        ProgressView()
                    } else {
                        Text("登録する")
                    }

                    Spacer()
                }
            }
            .disabled(isRegistering)

            if !registrationError.isEmpty {
                Text(registrationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .alert("登録完了", isPresented: $showSuccessAlert) {
            Button("OK") {
                NotificationCenter.default.post(
                    name: .coachRegistrationCompleted,
                    object: nil
                )
            }
        } message: {
            Text("コーチを登録しました！")
        }
    }

    private func registerCoach() {
        guard Auth.auth().currentUser?.uid != nil else {
            registrationError = "コーチ登録にはログインが必要です"
            return
        }

        guard !isRegistering else {
            return
        }

        guard let validatedPrice =
                validatedPriceForRegistration() else {
            return
        }

        registrationError = ""
        isRegistering = true

        let payload: [String: Any] = [
            "name": name,
            "area": area,
            "career": career,
            "price": validatedPrice,
            "imageURL": imageURL,
            "introduction": introduction,
            "tennisExperience": tennisExperience,
            "coachingExperience": coachingExperience,
            "availableTimes": availabilityEntries,
            "availability": availabilityPayload,
            "ageGroup": ageGroup
        ]

        functions
            .httpsCallable("registerCoachProfile")
            .call(payload) { _, error in
                DispatchQueue.main.async {
                    isRegistering = false

                    if let error {
                        print(
                            "コーチ登録失敗:",
                            error.localizedDescription
                        )

                        registrationError =
                            "登録に失敗しました: " +
                            error.localizedDescription
                        return
                    }

                    print("コーチ登録完了")
                    registrationError = ""
                    showSuccessAlert = true
                }
            }
    }

    private func validatedPriceForRegistration() -> Int? {
        let trimmedPrice =
            price.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        guard !trimmedPrice.isEmpty else {
            registrationError =
                "料金を入力してください。"
            return nil
        }

        let isASCIIInteger =
            trimmedPrice.unicodeScalars.allSatisfy {
                $0.value >= 48 && $0.value <= 57
            }

        guard isASCIIInteger else {
            registrationError =
                "料金は半角数字のみで入力してください。"
            return nil
        }

        guard let value = Int(trimmedPrice),
              (1...1_000_000).contains(value) else {
            registrationError =
                "料金は1円以上1,000,000円以下で入力してください。"
            return nil
        }

        return value
    }

    private var availabilityEntries: [String] {
        availableTimes
            .split(separator: ",")
            .map(String.init)
            .filter {
                !$0.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            }
    }

    private var groupedAvailability: [String: [String]] {
        var grouped: [String: [String]] = [:]

        for entry in availabilityEntries {
            let parts = entry.split(
                separator: " ",
                maxSplits: 1
            )

            guard parts.count == 2 else {
                continue
            }

            let date = String(parts[0])
                .replacingOccurrences(
                    of: "/",
                    with: "-"
                )

            let timeRange = String(parts[1])
                .replacingOccurrences(
                    of: "~",
                    with: "〜"
                )

            guard
                let startTime = timeRange
                    .components(
                        separatedBy: "〜"
                    )
                    .first?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                !startTime.isEmpty
            else {
                continue
            }

            if !(grouped[date] ?? []).contains(startTime) {
                grouped[date, default: []].append(startTime)
            }
        }

        return grouped
    }

    private var availabilityPayload: [[String: Any]] {
        groupedAvailability
            .keys
            .sorted()
            .map { date in
                [
                    "date": date,
                    "times":
                        (groupedAvailability[date] ?? [])
                            .sorted()
                ]
            }
    }
}

#Preview {
    Text("Preview")
}
