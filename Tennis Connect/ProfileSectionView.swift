import SwiftUI
import PhotosUI

struct ProfileSectionView: View {
    
    @Binding var selectedItem: PhotosPickerItem?
    @Binding var selectedImage: Image?
    @Binding var imageData: Data?
    @Binding var imageURL: String

    @Binding var introduction: String
    @Binding var specialty: String

    let uploadImage: (Data, @escaping (String?) -> Void) -> Void

    var body: some View {
        Section("プロフィール") {
            PhotosPicker(
                selection: $selectedItem,
                matching: .images
            ) {
                if let selectedImage {
                    selectedImage
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 120, height: 120)
                        .foregroundColor(.gray)
                }
            }.onChange(of: selectedItem) { _ in
                Task {
                    if let data = try? await selectedItem?.loadTransferable(type: Data.self) {
                        imageData = data
                        
                        if let uiImage = UIImage(data: data) {
                            selectedImage = Image(uiImage: uiImage)
                        }
                        
                        uploadImage(data) { url in
                            if let url = url {
                                imageURL = url
                                print("画像URL:", url)
                            }
                        }
                    }
                }
            }
            TextField("自己紹介", text: $introduction)
            TextField("得意レッスン", text: $specialty)
        }
    }
}
