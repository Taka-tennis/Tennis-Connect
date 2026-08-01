import SwiftUI
import FirebaseFirestore
import PhotosUI
import FirebaseStorage

struct CoachRegisterView: View {

    @State private var name = ""
    @State private var area = ""
    @State private var level = ""
    @State private var price = ""
    @State private var introduction = ""
    @State private var specialty = ""
    @State private var availableTimes = ""
    @State private var selectedTime = Date()
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: Image?
    @State private var imageData: Data?
    @State private var imageURL = ""
    @State private var selectedLessonTimes: [String] = []

    let db = Firestore.firestore()
    let storage = Storage.storage()
    let timeSlots = [
        "09:00", "09:30",
        "10:00", "10:30",
        "11:00", "11:30",
        "12:00", "12:30",
        "13:00", "13:30",
        "14:00", "14:30",
        "15:00", "15:30",
        "16:00", "16:30",
        "17:00", "17:30",
        "18:00", "18:30",
        "19:00", "19:30",
        "20:00", "20:30",
        "21:00"
    ]
    func uploadImage(_ data: Data, completion: @escaping (String?) -> Void) {
        let fileName = UUID().uuidString + ".jpg"
        let ref = storage.reference().child("coachImages/\(fileName)")

        ref.putData(data, metadata: nil) { metadata, error in
            if let error = error {
                print("アップロード失敗: \(error)")
                completion(nil)
                return
            }

            ref.downloadURL { url, error in
                completion(url?.absoluteString)
            }
        }
    }

    var body: some View {

        NavigationStack {

            Form {

                Section("基本情報") {

                    TextField("名前", text: $name)
                    TextField("活動エリア", text: $area)
                    TextField("レベル", text: $level)
                    TextField("料金", text: $price)
                }

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
                    Section("空き時間") {

                        ForEach(timeSlots, id: \.self) { time in
                            Button {
                                let formatter = DateFormatter()
                                formatter.dateFormat = "HH:mm"

                                guard
                                    let startDate = formatter.date(from: time),
                                    let endDate = Calendar.current.date(
                                        byAdding: .hour,
                                        value: 1,
                                        to: startDate
                                    )
                                else {
                                    return
                                }

                                let end = formatter.string(from: endDate)
                                let lessonTime = "\(time)〜\(end)"

                                if selectedLessonTimes.contains(lessonTime) {
                                    selectedLessonTimes.removeAll { $0 == lessonTime }
                                } else {
                                    selectedLessonTimes.append(lessonTime)
                                    selectedLessonTimes.sort()
                                }

                                availableTimes = selectedLessonTimes.joined(separator: ",")

                            } label: {
                                HStack {
                                    Text(time)

                                    Spacer()

                                    if selectedLessonTimes.contains(where: {
                                        $0.hasPrefix("\(time)〜")
                                    }) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    } else {
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                        }

                        if selectedLessonTimes.isEmpty {
                            Text("時間が選択されていません")
                                .foregroundColor(.gray)
                        } else {
                            ForEach(selectedLessonTimes, id: \.self) { lessonTime in
                                HStack {
                                    Image(systemName: "clock")
                                    Text(lessonTime)

                                    Spacer()

                                    Button {
                                        selectedLessonTimes.removeAll { $0 == lessonTime }
                                        availableTimes = selectedLessonTimes.joined(separator: ",")
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }

                    }
                }

                Button("登録する") {

                    db.collection("coaches").addDocument(data: [

                        "name": name,
                        "area": area,
                        "level": level,
                        "price": Int(price) ?? 0,
                        "imageURL": imageURL,
                        "introduction": introduction,
                        "specialty": specialty,
                        "rating": 5.0,
                        "reviewCount": 0,
                        "availableTimes": availableTimes.components(separatedBy: ",")

                    ])

                    print("登録完了")
                }

            }
            .navigationTitle("コーチ登録")
        }
    }
}

#Preview {
    CoachRegisterView()
}
