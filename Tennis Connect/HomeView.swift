import SwiftUI

struct HomeView: View {

    @State private var searchText = ""
    
    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(alignment: .leading, spacing: 20) {

                    Text("🎾 Tennis Connect")
                        .font(.largeTitle)
                        .bold()

                    TextField(
                        "コーチ・地域・駅名で検索",
                        text: $searchText
                    )
                        .padding()
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(12)

                    VStack(alignment: .leading) {

                        Text("🔥 今日レッスンできます")
                            .font(.title2)
                            .bold()

                        ForEach(
                            sampleCoaches.filter {
                                searchText.isEmpty ||
                                $0.name.contains(searchText) ||
                                $0.area.contains(searchText) ||
                                $0.level.contains(searchText)
                            }
                        ) { coach in
                            NavigationLink {
                                ProfileDetailView(coach: coach)
                            } label: {
                                LessonCard(
                                    imageName: coach.imageName,
                                    name: coach.name,
                                    time: coach.level,
                                    place: coach.area,
                                    price: "¥\(coach.price)"
                                )
                            }
                        }
                    }

                }
                .padding()
            }
            .navigationTitle("ホーム")
        }
    }
}

struct LessonCard: View {
    let imageName: String
    let name: String
    let time: String
    let place: String
    let price: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(height: 180)
                .clipped()
                .cornerRadius(12)

            Text(name)
                .font(.headline)

            Text(time)
            Text(place)

            Text(price)
                .bold()

            Button("予約する") {

            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(10)

        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
}

#Preview {
    HomeView()
}
