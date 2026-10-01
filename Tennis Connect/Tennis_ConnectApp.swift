import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFunctions
import FirebaseMessaging
import UserNotifications


enum PushNotificationDestination: Equatable {
    case studentReservations
    case studentChat
    case coachReservations
    case coachChat
}

final class PushNotificationRouter: ObservableObject {

    static let shared = PushNotificationRouter()

    @Published private(set) var pendingDestination:
        PushNotificationDestination?

    private init() {}

    func handleNotificationTap(
        userInfo: [AnyHashable: Any]
    ) {

        let type =
            (userInfo["type"] as? String ?? "")
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        switch type {

        case "reservationRequested":
            pendingDestination = .coachReservations

        case "reservationApproved",
             "reservationRejected":
            pendingDestination = .studentReservations

        case "chatMessage":

            let currentUID =
                Auth.auth().currentUser?.uid ?? ""

            let coachId =
                (userInfo["coachId"] as? String ?? "")
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

            let studentId =
                (userInfo["studentId"] as? String ?? "")
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )

            if !currentUID.isEmpty,
               currentUID == coachId {
                pendingDestination = .coachChat
            } else if !currentUID.isEmpty,
                      currentUID == studentId {
                pendingDestination = .studentChat
            } else {
                print(
                    "チャットPushの遷移先を判定できませんでした"
                )
            }

        default:
            print(
                "画面遷移対象外のPush通知です: \(type)"
            )
        }
    }

    func consume(
        _ destination: PushNotificationDestination
    ) {
        guard pendingDestination == destination else {
            return
        }

        pendingDestination = nil
    }

    func clear() {
        pendingDestination = nil
    }
}

enum PushNotificationDeviceIdentity {

    private static let userDefaultsKey =
        "tennisConnect.pushNotificationDeviceID"

    static let deviceID: String = {

        if let savedValue =
            UserDefaults.standard.string(
                forKey: userDefaultsKey
            ),
           UUID(uuidString: savedValue) != nil {

            return savedValue.lowercased()
        }

        let newValue =
            UUID().uuidString.lowercased()

        UserDefaults.standard.set(
            newValue,
            forKey: userDefaultsKey
        )

        return newValue
    }()
}

final class AppDelegate: NSObject,
                         UIApplicationDelegate,
                         UNUserNotificationCenterDelegate,
                         MessagingDelegate {

    private var authStateHandle:
        AuthStateDidChangeListenerHandle?

    private var hasAPNsDeviceToken = false

    // MARK: - App Launch

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [
            UIApplication.LaunchOptionsKey: Any
        ]? = nil
    ) -> Bool {

        FirebaseApp.configure()

        UNUserNotificationCenter.current().delegate =
            self

        Messaging.messaging().delegate =
            self

        configureRemoteNotifications(
            application
        )

        startAuthStateListener()

        return true
    }

    // MARK: - Remote Notifications

    private func configureRemoteNotifications(
        _ application: UIApplication
    ) {

        let notificationCenter =
            UNUserNotificationCenter.current()

        notificationCenter.getNotificationSettings {
            settings in

            switch settings.authorizationStatus {

            case .notDetermined:

                notificationCenter.requestAuthorization(
                    options: [
                        .alert,
                        .badge,
                        .sound
                    ]
                ) { granted, error in

                    if let error {

                        print(
                            "通知許可リクエストエラー: "
                            + error.localizedDescription
                        )

                        return
                    }

                    guard granted else {

                        print(
                            "ユーザーが通知を許可しませんでした"
                        )

                        return
                    }

                    print(
                        "通知表示が許可されました"
                    )

                    DispatchQueue.main.async {

                        application
                            .registerForRemoteNotifications()

                        print(
                            "APNsへのリモート通知登録を要求しました"
                        )
                    }
                }

            case .authorized:

                print(
                    "通知表示は許可済みです"
                )

                DispatchQueue.main.async {

                    application
                        .registerForRemoteNotifications()

                    print(
                        "APNsへのリモート通知登録を要求しました"
                    )
                }

            case .provisional:

                print(
                    "通知は暫定許可されています"
                )

                DispatchQueue.main.async {

                    application
                        .registerForRemoteNotifications()

                    print(
                        "APNsへのリモート通知登録を要求しました"
                    )
                }

            case .ephemeral:

                print(
                    "通知は一時的に許可されています"
                )

                DispatchQueue.main.async {

                    application
                        .registerForRemoteNotifications()

                    print(
                        "APNsへのリモート通知登録を要求しました"
                    )
                }

            case .denied:

                print(
                    "通知がiPhoneの設定で拒否されています"
                )

            @unknown default:

                print(
                    "不明な通知許可状態です"
                )
            }
        }
    }

    // MARK: - Firebase Auth

    private func startAuthStateListener() {

        if let authStateHandle {

            Auth.auth()
                .removeStateDidChangeListener(
                    authStateHandle
                )
        }

        authStateHandle =
            Auth.auth()
                .addStateDidChangeListener {
                    [weak self] _,
                    user in

                    guard let self else {
                        return
                    }

                    guard user != nil else {

                        print(
                            "未ログインのためFCMトークン登録を待機します"
                        )

                        return
                    }

                    self.registerCurrentFCMTokenIfReady()
                }
    }

    // MARK: - APNs

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken
            deviceToken: Data
    ) {

        Messaging.messaging().apnsToken =
            deviceToken

        hasAPNsDeviceToken = true

        print(
            "APNs device tokenを取得しました"
        )

        registerCurrentFCMTokenIfReady()
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError
            error: Error
    ) {

        hasAPNsDeviceToken = false

        print(
            "APNs登録エラー: "
            + error.localizedDescription
        )
    }

    // MARK: - Firebase Messaging

    func messaging(
        _ messaging: Messaging,
        didReceiveRegistrationToken
            fcmToken: String?
    ) {

        guard let fcmToken,
              !fcmToken.isEmpty else {

            print(
                "FCMトークンを取得できませんでした"
            )

            return
        }

        guard hasAPNsDeviceToken else {

            print(
                "APNsトークン取得前のためFCMトークン保存を待機します"
            )

            return
        }

        guard Auth.auth().currentUser != nil else {

            print(
                "未ログインのためFCMトークンを保存しません"
            )

            return
        }

        print(
            "FCM registration tokenを取得しました"
        )

        registerPushTokenIfPossible(
            fcmToken
        )
    }

    private func registerCurrentFCMTokenIfReady() {

        guard Auth.auth().currentUser != nil else {
            return
        }

        guard hasAPNsDeviceToken else {

            print(
                "APNsトークン取得待ちのためFCMトークン取得を保留します"
            )

            return
        }

        Messaging.messaging().token {
            [weak self] token,
            error in

            guard let self else {
                return
            }

            if let error {

                print(
                    "FCMトークン取得エラー: "
                    + error.localizedDescription
                )

                return
            }

            guard let token,
                  !token.isEmpty else {

                print(
                    "保存対象のFCMトークンがありません"
                )

                return
            }

            print(
                "FCMトークン取得に成功しました"
            )

            self.registerPushTokenIfPossible(
                token
            )
        }
    }

    private func registerPushTokenIfPossible(
        _ token: String
    ) {

        guard hasAPNsDeviceToken else {

            print(
                "APNs未登録のためFCMトークンを保存しません"
            )

            return
        }

        guard Auth.auth().currentUser != nil else {

            print(
                "未ログインのためFCMトークンを保存しません"
            )

            return
        }

        guard let firebaseApp =
                FirebaseApp.app() else {

            print(
                "Firebase初期化前のためFCMトークンを保存しません"
            )

            return
        }

        let functions =
            Functions.functions(
                app: firebaseApp,
                region: "asia-northeast1"
            )

        functions
            .httpsCallable(
                "registerPushToken"
            )
            .call(
                [
                    "token": token,
                    "deviceId":
                        PushNotificationDeviceIdentity
                            .deviceID
                ]
            ) {
                result,
                error in

                if let error {

                    print(
                        "FCMトークン保存エラー: "
                        + error.localizedDescription
                    )

                    return
                }

                guard
                    let data =
                        result?.data
                            as? [String: Any],
                    data["success"]
                        as? Bool == true
                else {

                    print(
                        "FCMトークン保存結果を確認できませんでした"
                    )

                    return
                }

                print(
                    "FCMトークンをFirestoreへ登録しました"
                )
            }
    }

    // MARK: - Foreground Notification

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification:
            UNNotification,
        withCompletionHandler
            completionHandler:
                @escaping (
                    UNNotificationPresentationOptions
                ) -> Void
    ) {

        completionHandler([
            .banner,
            .list,
            .sound,
            .badge
        ])
    }

    // MARK: - Notification Tap

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response:
            UNNotificationResponse,
        withCompletionHandler
            completionHandler:
                @escaping () -> Void
    ) {

        let userInfo =
            response
                .notification
                .request
                .content
                .userInfo

        DispatchQueue.main.async {
            PushNotificationRouter.shared
                .handleNotificationTap(
                    userInfo: userInfo
                )

            completionHandler()
        }
    }
}

@main
struct Tennis_ConnectApp: App {

    @UIApplicationDelegateAdaptor(
        AppDelegate.self
    )
    var delegate

    var body: some Scene {

        WindowGroup {

            StartView()
                .preferredColorScheme(
                    .light
                )
        }
    }
}
