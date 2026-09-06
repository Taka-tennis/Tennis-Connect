import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

extension Notification.Name {
    static let coachRegistrationCompleted =
        Notification.Name("coachRegistrationCompleted")
}

struct StartView: View {

    @State private var showCoachLogin = false
    @State private var showCoachHome = false
    @State private var showCoachRegister = false
    @State private var showStudentHome = false
    @State private var studentHomeId = UUID()
    @State private var shouldRouteAfterAuthentication = false
    @State private var isCheckingCoach = false
    @State private var coachErrorMessage = ""

    private let db = Firestore.firestore()

    var body: some View {

        NavigationStack {

            ZStack {

                TennisConnectStartBackground()

                VStack(spacing: 0) {

                    Spacer(minLength: 48)

                    VStack(spacing: 22) {

                        TennisConnectLogoMark()

                        VStack(spacing: 9) {

                            Text("Tennis Connect")
                                .font(
                                    .system(
                                        size: 36,
                                        weight: .bold,
                                        design: .rounded
                                    )
                                )
                                .foregroundStyle(Color.tcTextPrimary)
                                .minimumScaleFactor(0.85)

                            Text("コーチと生徒をつなぐ")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.tcTextSecondary)

                            Text("テニスレッスンのマッチングアプリ")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Color.tcTextSecondary)
                        }
                    }

                    Spacer()

                    VStack(spacing: 14) {

                        Button {
                            showStudentHome = true
                        } label: {
                            StartPrimaryButtonLabel(
                                title: "レッスンを受ける",
                                subtitle: "生徒の方はこちら",
                                systemImage: "person.fill"
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            handleCoachEntry()
                        } label: {
                            StartSecondaryButtonLabel(
                                title: "コーチとして利用する",
                                subtitle: "初めてのコーチ登録もこちら",
                                systemImage: "person.badge.plus"
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isCheckingCoach)

                        if isCheckingCoach {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(Color.tcBrandGreen)

                                Text("コーチ情報を確認しています")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.tcTextSecondary)
                            }
                            .padding(.top, 4)
                        }

                        if !coachErrorMessage.isEmpty {
                            Text(coachErrorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 32)

                    Text("Tennis Connect")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.tcTextTertiary)
                        .padding(.bottom, 10)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(
                isPresented: $showStudentHome
            ) {
                MainTabView()
                    .id(studentHomeId)
                    .navigationBarBackButtonHidden(true)
            }
            .navigationDestination(
                isPresented: $showCoachHome
            ) {
                CoachHomeView()
            }
            .navigationDestination(
                isPresented: $showCoachRegister
            ) {
                CoachRegisterView()
            }
            .sheet(
                isPresented: $showCoachLogin,
                onDismiss: {
                    if shouldRouteAfterAuthentication {
                        shouldRouteAfterAuthentication = false
                        routeAuthenticatedCoach()
                    }
                }
            ) {
                LoginView {
                    shouldRouteAfterAuthentication = true
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .returnToStudentHome
                )
            ) { _ in
                print("StartViewでホーム通知を受信しました")

                showStudentHome = false

                DispatchQueue.main.async {
                    studentHomeId = UUID()
                    showStudentHome = true
                    print("生徒ホームを開き直しました")
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .returnToStartScreen
                )
            ) { _ in
                print("スタート画面へ戻ります")
                studentHomeId = UUID()
                showStudentHome = false
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .coachRegistrationCompleted
                )
            ) { _ in
                print("コーチ登録完了通知を受信しました")

                coachErrorMessage = ""
                showCoachRegister = false

                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 0.15
                ) {
                    showCoachHome = true
                    print("コーチホームへ移動しました")
                }
            }
        }
    }

    private func handleCoachEntry() {

        coachErrorMessage = ""

        guard Auth.auth().currentUser != nil else {
            shouldRouteAfterAuthentication = false
            showCoachLogin = true
            return
        }

        routeAuthenticatedCoach()
    }

    private func routeAuthenticatedCoach() {

        guard let uid = Auth.auth().currentUser?.uid else {
            showCoachLogin = true
            return
        }

        isCheckingCoach = true
        coachErrorMessage = ""

        db.collection("coaches")
            .document(uid)
            .getDocument { snapshot, error in

                DispatchQueue.main.async {

                    isCheckingCoach = false

                    if let error = error {
                        coachErrorMessage =
                            "コーチ情報を確認できませんでした: \(error.localizedDescription)"
                        return
                    }

                    if snapshot?.exists == true {
                        showCoachHome = true
                    } else {
                        showCoachRegister = true
                    }
                }
            }
    }
}

// MARK: - Brand Logo

private struct TennisConnectLogoMark: View {

    var body: some View {

        ZStack {

            Circle()
                .stroke(
                    Color.tcBrandGreen.opacity(0.95),
                    lineWidth: 3.5
                )
                .frame(width: 126, height: 126)

            Circle()
                .fill(Color.tcBrandGreen)
                .frame(width: 17, height: 17)
                .offset(y: -63)

            Circle()
                .fill(Color.tcBrandGreen)
                .frame(width: 17, height: 17)
                .offset(x: 63)

            Circle()
                .fill(Color.tcLime)
                .frame(width: 68, height: 68)
                .overlay {
                    TennisBallSeams()
                        .stroke(
                            Color.white.opacity(0.96),
                            style: StrokeStyle(
                                lineWidth: 3.2,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .clipShape(Circle())
                }
                .shadow(
                    color: Color.tcBrandGreen.opacity(0.12),
                    radius: 12,
                    y: 6
                )
        }
        .frame(width: 154, height: 154)
        .accessibilityHidden(true)
    }
}

private struct TennisBallSeams: Shape {

    func path(in rect: CGRect) -> Path {

        var path = Path()

        let w = rect.width
        let h = rect.height

        // 実物のテニスボールに合わせ、
        // 上側は中央へ向かって「下」にふくらむ。
        path.move(
            to: CGPoint(
                x: -w * 0.04,
                y: h * 0.24
            )
        )

        path.addCurve(
            to: CGPoint(
                x: w * 1.04,
                y: h * 0.24
            ),
            control1: CGPoint(
                x: w * 0.27,
                y: h * 0.39
            ),
            control2: CGPoint(
                x: w * 0.73,
                y: h * 0.39
            )
        )

        // 下側は中央へ向かって「上」にふくらむ。
        // 2本合わせて「）（」の向き。
        path.move(
            to: CGPoint(
                x: -w * 0.04,
                y: h * 0.76
            )
        )

        path.addCurve(
            to: CGPoint(
                x: w * 1.04,
                y: h * 0.76
            ),
            control1: CGPoint(
                x: w * 0.27,
                y: h * 0.61
            ),
            control2: CGPoint(
                x: w * 0.73,
                y: h * 0.61
            )
        )

        return path
    }
}

// MARK: - Buttons

private struct StartPrimaryButtonLabel: View {

    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {

        HStack(spacing: 14) {

            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {

                Text(title)
                    .font(.system(size: 17, weight: .bold))

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .opacity(0.82)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .opacity(0.85)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .frame(height: 68)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.tcBrandGreen)
        )
        .shadow(
            color: Color.tcBrandGreen.opacity(0.18),
            radius: 14,
            y: 7
        )
        .contentShape(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

private struct StartSecondaryButtonLabel: View {

    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {

        HStack(spacing: 14) {

            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {

                Text(title)
                    .font(.system(size: 17, weight: .bold))

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.tcTextSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(Color.tcBrandGreen)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .frame(height: 68)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.96))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    Color.tcBrandGreen.opacity(0.42),
                    lineWidth: 1.2
                )
        }
        .contentShape(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

// MARK: - Background

private struct TennisConnectStartBackground: View {

    var body: some View {

        ZStack {

            Color.tcBackground
                .ignoresSafeArea()

            Circle()
                .fill(Color.tcSoftGreen.opacity(0.85))
                .frame(width: 330, height: 330)
                .blur(radius: 4)
                .offset(x: -155, y: 390)

            Circle()
                .fill(Color.tcLime.opacity(0.10))
                .frame(width: 280, height: 280)
                .blur(radius: 10)
                .offset(x: 175, y: 455)

            Circle()
                .fill(Color.tcSoftGreen.opacity(0.50))
                .frame(width: 220, height: 220)
                .blur(radius: 16)
                .offset(x: 160, y: -340)
        }
    }
}

// MARK: - Brand Colors

private extension Color {

    static let tcBrandGreen = Color(
        red: 34 / 255,
        green: 168 / 255,
        blue: 102 / 255
    )

    static let tcLime = Color(
        red: 151 / 255,
        green: 207 / 255,
        blue: 63 / 255
    )

    static let tcSoftGreen = Color(
        red: 232 / 255,
        green: 245 / 255,
        blue: 236 / 255
    )

    static let tcBackground = Color(
        red: 250 / 255,
        green: 251 / 255,
        blue: 250 / 255
    )

    static let tcTextPrimary = Color(
        red: 34 / 255,
        green: 34 / 255,
        blue: 34 / 255
    )

    static let tcTextSecondary = Color(
        red: 101 / 255,
        green: 109 / 255,
        blue: 104 / 255
    )

    static let tcTextTertiary = Color(
        red: 150 / 255,
        green: 158 / 255,
        blue: 153 / 255
    )
}

#Preview {
    StartView()
}
