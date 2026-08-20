import SwiftUI
import PhotosUI

struct ProfileSectionView: View {

    @Binding var selectedItem: PhotosPickerItem?
    @Binding var selectedImage: Image?
    @Binding var imageData: Data?
    @Binding var imageURL: String

    @Binding var introduction: String

    let uploadImage: (Data, @escaping (String?) -> Void) -> Void

    var body: some View {
        Section("プロフィール") {
            HStack {
                Spacer()

                PhotosPicker(
                    selection: $selectedItem,
                    matching: .images
                ) {
                    profileImage
                }

                Spacer()
            }
            .onChange(of: selectedItem) { _ in
                Task {
                    guard let data =
                            try? await selectedItem?
                                .loadTransferable(type: Data.self) else {
                        return
                    }

                    imageData = data

                    if let uiImage = UIImage(data: data) {
                        selectedImage = Image(uiImage: uiImage)
                    }

                    uploadImage(data) { url in
                        guard let url else {
                            return
                        }

                        DispatchQueue.main.async {
                            imageURL = url
                        }
                    }
                }
            }

            TextField(
                "自己紹介",
                text: $introduction,
                axis: .vertical
            )
            .lineLimit(3...8)
        }
    }

    @ViewBuilder
    private var profileImage: some View {
        if let selectedImage {
            selectedImage
                .resizable()
                .scaledToFill()
                .frame(width: 120, height: 120)
                .clipShape(Circle())

        } else if !imageURL.isEmpty,
                  let url = URL(string: imageURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()

                case .failure:
                    placeholderImage

                case .empty:
                    ZStack {
                        Color.gray.opacity(0.12)
                        ProgressView()
                    }

                @unknown default:
                    placeholderImage
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())

        } else {
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 120, height: 120)
            .foregroundStyle(.gray)
    }
}
