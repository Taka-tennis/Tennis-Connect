import SwiftUI
import AVKit
import FirebaseFirestore

struct CoachVideoSection: View {

    let coachId: String

    @State private var player: AVPlayer?
    @State private var loadedVideoURL = ""

    private let db = Firestore.firestore()

    var body: some View {
        // EmptyViewを最上位にするとonAppearが安定して呼ばれない場合があるため、
        // 常に存在するVStackを最上位にしています。
        VStack(alignment: .leading, spacing: 0) {
            if let player {
                VStack(alignment: .leading, spacing: 14) {
                    Label(
                        "プレー動画",
                        systemImage: "play.rectangle.fill"
                    )
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.green)

                    VideoPlayer(player: player)
                        .frame(height: 220)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 18
                            )
                        )

                    Text(
                        "コーチが登録した15秒以内のプロフィール動画です。"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
                .background(Color(.systemGray6))
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 20
                    )
                )
            }
        }
        .onAppear {
            loadVideo()
        }
        .onChange(of: coachId) { _ in
            loadVideo()
        }
        .onDisappear {
            player?.pause()
        }
    }

    private func loadVideo() {
        guard !coachId.isEmpty else {
            clearVideo()
            return
        }

        // 最新のprofileVideoURLを確実に取得するため、
        // まずFirestoreサーバーから直接読み込みます。
        db.collection("coaches")
            .document(coachId)
            .getDocument(source: .server) { snapshot, error in

                if let error {
                    print(
                        "プロフィール動画サーバー取得エラー: " +
                        error.localizedDescription
                    )

                    // 一時的にサーバー取得ができない場合は
                    // キャッシュを含む通常取得へフォールバックします。
                    loadVideoWithDefaultSource()
                    return
                }

                applyVideo(
                    from: snapshot?.data() ?? [:]
                )
            }
    }

    private func loadVideoWithDefaultSource() {
        db.collection("coaches")
            .document(coachId)
            .getDocument { snapshot, error in

                if let error {
                    print(
                        "プロフィール動画取得エラー: " +
                        error.localizedDescription
                    )
                    clearVideo()
                    return
                }

                applyVideo(
                    from: snapshot?.data() ?? [:]
                )
            }
    }

    private func applyVideo(
        from data: [String: Any]
    ) {
        let urlString =
            (data["profileVideoURL"] as? String ?? "")
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        guard !urlString.isEmpty,
              let url = URL(string: urlString) else {
            clearVideo()
            return
        }

        DispatchQueue.main.async {
            if loadedVideoURL == urlString,
               player != nil {
                return
            }

            player?.pause()
            loadedVideoURL = urlString
            player = AVPlayer(url: url)

            print(
                "プロフィール動画を読み込みました: " +
                coachId
            )
        }
    }

    private func clearVideo() {
        DispatchQueue.main.async {
            player?.pause()
            player = nil
            loadedVideoURL = ""
        }
    }
}

#Preview {
    CoachVideoSection(
        coachId: "preview-coach"
    )
    .padding()
}
