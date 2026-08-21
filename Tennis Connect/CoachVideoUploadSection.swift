import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import AVFoundation
import AVKit
import CoreTransferable
import UniformTypeIdentifiers

struct CoachVideoUploadSection: View {

    private let maxDurationSeconds: Double = 15
    private let maxUploadBytes = 20 * 1024 * 1024

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedVideoURL: URL?
    @State private var currentVideoURL = ""
    @State private var currentVideoPath = ""

    @State private var previewPlayer: AVPlayer?
    @State private var isLoading = true
    @State private var isPreparingVideo = false
    @State private var isUploading = false
    @State private var isDeleting = false
    @State private var errorMessage = ""
    @State private var successMessage = ""

    private let db = Firestore.firestore()
    private let storage = Storage.storage()

    var body: some View {
        Section("プロフィール動画") {
            VStack(alignment: .leading, spacing: 14) {

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("動画を確認中…")
                        Spacer()
                    }
                    .padding(.vertical, 12)
                } else {
                    videoPreview
                }

                Text("15秒以内のプレー動画を1本登録できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(
                    "アップロード時に720p程度へ圧縮して、" +
                    "通信量と保存容量を抑えます。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                PhotosPicker(
                    selection: $selectedItem,
                    matching: .videos
                ) {
                    HStack {
                        Spacer()
                        Label(
                            currentVideoURL.isEmpty
                                ? "動画を選択"
                                : "動画を変更",
                            systemImage: "video.badge.plus"
                        )
                        .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(
                    isPreparingVideo ||
                    isUploading ||
                    isDeleting
                )

                if isPreparingVideo {
                    HStack {
                        Spacer()
                        ProgressView("動画を準備中…")
                        Spacer()
                    }
                }

                if selectedVideoURL != nil {
                    Button {
                        uploadSelectedVideo()
                    } label: {
                        HStack {
                            Spacer()

                            if isUploading {
                                ProgressView()
                            } else {
                                Label(
                                    "この動画を保存",
                                    systemImage: "icloud.and.arrow.up.fill"
                                )
                                .fontWeight(.semibold)
                            }

                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isUploading || isDeleting)
                }

                if !currentVideoURL.isEmpty {
                    Button(role: .destructive) {
                        deleteCurrentVideo()
                    } label: {
                        HStack {
                            Spacer()

                            if isDeleting {
                                ProgressView()
                            } else {
                                Label(
                                    "登録中の動画を削除",
                                    systemImage: "trash"
                                )
                            }

                            Spacer()
                        }
                    }
                    .disabled(isUploading || isDeleting)
                }

                if !successMessage.isEmpty {
                    Text(successMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
        }
        .onAppear {
            loadCurrentVideo()
        }
        .onChange(of: selectedItem) { newItem in
            guard let newItem else {
                return
            }

            prepareSelectedVideo(newItem)
        }
        .onDisappear {
            previewPlayer?.pause()
        }
    }

    @ViewBuilder
    private var videoPreview: some View {
        if let player = previewPlayer {
            VideoPlayer(player: player)
                .frame(height: 220)
                .clipShape(
                    RoundedRectangle(cornerRadius: 16)
                )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
                    .frame(height: 180)

                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)

                    Text("動画はまだ登録されていません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func loadCurrentVideo() {
        guard let uid = Auth.auth().currentUser?.uid else {
            isLoading = false
            errorMessage =
                "プロフィール動画の確認にはログインが必要です。"
            return
        }

        db.collection("coaches")
            .document(uid)
            .getDocument { snapshot, error in
                DispatchQueue.main.async {
                    isLoading = false

                    if let error {
                        errorMessage =
                            "動画情報を取得できませんでした: " +
                            error.localizedDescription
                        return
                    }

                    let data = snapshot?.data() ?? [:]

                    currentVideoURL =
                        data["profileVideoURL"] as? String ?? ""

                    currentVideoPath =
                        data["profileVideoPath"] as? String ?? ""

                    if !currentVideoURL.isEmpty,
                       let url = URL(string: currentVideoURL) {
                        previewPlayer = AVPlayer(url: url)
                    } else {
                        previewPlayer = nil
                    }
                }
            }
    }

    private func prepareSelectedVideo(
        _ item: PhotosPickerItem
    ) {
        errorMessage = ""
        successMessage = ""
        isPreparingVideo = true

        Task {
            do {
                guard let picked =
                        try await item.loadTransferable(
                            type: PickedVideo.self
                        ) else {
                    throw VideoUploadError.couldNotLoadVideo
                }

                let asset = AVURLAsset(url: picked.url)
                let duration = try await asset.load(.duration)
                let durationSeconds =
                    CMTimeGetSeconds(duration)

                guard durationSeconds.isFinite,
                      durationSeconds > 0 else {
                    throw VideoUploadError.invalidDuration
                }

                guard durationSeconds <=
                        maxDurationSeconds + 0.15 else {
                    throw VideoUploadError.tooLong
                }

                let compressedURL =
                    try await compressVideo(asset: asset)

                let attributes =
                    try FileManager.default.attributesOfItem(
                        atPath: compressedURL.path
                    )

                let fileSize =
                    (attributes[.size] as? NSNumber)?
                        .intValue ?? 0

                guard fileSize > 0 else {
                    throw VideoUploadError.emptyFile
                }

                guard fileSize <= maxUploadBytes else {
                    try? FileManager.default.removeItem(
                        at: compressedURL
                    )
                    throw VideoUploadError.tooLarge
                }

                await MainActor.run {
                    selectedVideoURL = compressedURL
                    previewPlayer?.pause()
                    previewPlayer =
                        AVPlayer(url: compressedURL)
                    isPreparingVideo = false
                    errorMessage = ""
                }
            } catch {
                await MainActor.run {
                    isPreparingVideo = false
                    selectedItem = nil
                    selectedVideoURL = nil
                    errorMessage =
                        videoErrorMessage(error)
                }
            }
        }
    }

    private func compressVideo(
        asset: AVAsset
    ) async throws -> URL {
        guard let exportSession =
                AVAssetExportSession(
                    asset: asset,
                    presetName:
                        AVAssetExportPreset1280x720
                ) else {
            throw VideoUploadError.couldNotCompress
        }

        let outputURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "coach_profile_" +
                    UUID().uuidString
                )
                .appendingPathExtension("mp4")

        try? FileManager.default.removeItem(
            at: outputURL
        )

        guard exportSession
            .supportedFileTypes
            .contains(.mp4) else {
            throw VideoUploadError.unsupportedFormat
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        return try await withCheckedThrowingContinuation {
            continuation in

            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume(
                        returning: outputURL
                    )

                case .failed:
                    continuation.resume(
                        throwing:
                            exportSession.error ??
                            VideoUploadError.couldNotCompress
                    )

                case .cancelled:
                    continuation.resume(
                        throwing:
                            VideoUploadError.cancelled
                    )

                default:
                    continuation.resume(
                        throwing:
                            exportSession.error ??
                            VideoUploadError.couldNotCompress
                    )
                }
            }
        }
    }

    private func uploadSelectedVideo() {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage =
                "動画の保存にはログインが必要です。"
            return
        }

        guard let localURL = selectedVideoURL else {
            errorMessage =
                "保存する動画を選択してください。"
            return
        }

        isUploading = true
        errorMessage = ""
        successMessage = ""

        let newPath =
            "coachVideos/\(uid)/" +
            UUID().uuidString +
            ".mp4"

        let ref = storage.reference()
            .child(newPath)

        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"

        ref.putFile(
            from: localURL,
            metadata: metadata
        ) { _, error in

            if let error {
                DispatchQueue.main.async {
                    isUploading = false
                    errorMessage =
                        "動画をアップロードできませんでした: " +
                        error.localizedDescription
                }
                return
            }

            ref.downloadURL { url, error in
                if let error {
                    DispatchQueue.main.async {
                        isUploading = false
                        errorMessage =
                            "動画URLを取得できませんでした: " +
                            error.localizedDescription
                    }
                    return
                }

                guard let url else {
                    DispatchQueue.main.async {
                        isUploading = false
                        errorMessage =
                            "動画URLを取得できませんでした。"
                    }
                    return
                }

                let oldPath = currentVideoPath

                db.collection("coaches")
                    .document(uid)
                    .setData(
                        [
                            "profileVideoURL":
                                url.absoluteString,
                            "profileVideoPath":
                                newPath,
                            "profileVideoUpdatedAt":
                                Timestamp()
                        ],
                        merge: true
                    ) { error in

                        if let error {
                            ref.delete(completion: nil)

                            DispatchQueue.main.async {
                                isUploading = false
                                errorMessage =
                                    "動画情報を保存できませんでした: " +
                                    error.localizedDescription
                            }
                            return
                        }

                        if !oldPath.isEmpty &&
                            oldPath != newPath {
                            storage.reference()
                                .child(oldPath)
                                .delete { error in
                                    if let error {
                                        print(
                                            "旧動画の削除に失敗: " +
                                            error.localizedDescription
                                        )
                                    }
                                }
                        }

                        DispatchQueue.main.async {
                            currentVideoURL =
                                url.absoluteString
                            currentVideoPath =
                                newPath
                            selectedVideoURL = nil
                            selectedItem = nil
                            isUploading = false
                            successMessage =
                                "プロフィール動画を保存しました。"
                            errorMessage = ""

                            previewPlayer?.pause()
                            previewPlayer =
                                AVPlayer(url: url)

                            try? FileManager.default
                                .removeItem(at: localURL)
                        }
                    }
            }
        }
    }

    private func deleteCurrentVideo() {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage =
                "動画の削除にはログインが必要です。"
            return
        }

        isDeleting = true
        errorMessage = ""
        successMessage = ""

        let finishFirestoreDelete = {
            db.collection("coaches")
                .document(uid)
                .setData(
                    [
                        "profileVideoURL":
                            FieldValue.delete(),
                        "profileVideoPath":
                            FieldValue.delete(),
                        "profileVideoUpdatedAt":
                            FieldValue.delete()
                    ],
                    merge: true
                ) { error in
                    DispatchQueue.main.async {
                        isDeleting = false

                        if let error {
                            errorMessage =
                                "動画情報を削除できませんでした: " +
                                error.localizedDescription
                            return
                        }

                        previewPlayer?.pause()
                        previewPlayer = nil
                        currentVideoURL = ""
                        currentVideoPath = ""
                        selectedVideoURL = nil
                        selectedItem = nil
                        successMessage =
                            "プロフィール動画を削除しました。"
                    }
                }
        }

        guard !currentVideoPath.isEmpty else {
            finishFirestoreDelete()
            return
        }

        storage.reference()
            .child(currentVideoPath)
            .delete { error in

                if let error {
                    let nsError = error as NSError

                    if nsError.code !=
                        StorageErrorCode.objectNotFound.rawValue {
                        DispatchQueue.main.async {
                            isDeleting = false
                            errorMessage =
                                "動画ファイルを削除できませんでした: " +
                                error.localizedDescription
                        }
                        return
                    }
                }

                finishFirestoreDelete()
            }
    }

    private func videoErrorMessage(
        _ error: Error
    ) -> String {
        guard let videoError =
                error as? VideoUploadError else {
            return "動画を準備できませんでした: " +
                error.localizedDescription
        }

        switch videoError {
        case .couldNotLoadVideo:
            return "動画を読み込めませんでした。"
        case .invalidDuration:
            return "動画の長さを確認できませんでした。"
        case .tooLong:
            return "15秒以内の動画を選択してください。"
        case .couldNotCompress:
            return "動画を圧縮できませんでした。"
        case .unsupportedFormat:
            return "この動画形式には対応していません。"
        case .emptyFile:
            return "動画ファイルを確認できませんでした。"
        case .tooLarge:
            return "圧縮後の動画サイズが大きすぎます。別の動画を選択してください。"
        case .cancelled:
            return "動画の準備をキャンセルしました。"
        }
    }
}

private struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation:
        some TransferRepresentation {
        FileRepresentation(
            contentType: .movie
        ) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let copiedURL =
                FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "picked_" +
                        UUID().uuidString
                    )
                    .appendingPathExtension(
                        received.file
                            .pathExtension.isEmpty
                            ? "mov"
                            : received.file.pathExtension
                    )

            try? FileManager.default.removeItem(
                at: copiedURL
            )

            try FileManager.default.copyItem(
                at: received.file,
                to: copiedURL
            )

            return PickedVideo(url: copiedURL)
        }
    }
}

private enum VideoUploadError: Error {
    case couldNotLoadVideo
    case invalidDuration
    case tooLong
    case couldNotCompress
    case unsupportedFormat
    case emptyFile
    case tooLarge
    case cancelled
}

#Preview {
    Form {
        CoachVideoUploadSection()
    }
}
