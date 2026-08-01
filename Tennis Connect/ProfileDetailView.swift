import SwiftUI

struct ProfileDetailView: View {

    let coach: Coach

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .foregroundColor(.green)
                
                Text(coach.name)
                    .font(.largeTitle)
                    .bold()
                
                Text(coach.careers.first ?? "経歴未登録")
                    .font(.headline)
                
                Text("📍 \(coach.area)")
                
                Text("💰 ¥\(coach.price)")
                    .font(.title2)
                    .bold()
                
                VStack(alignment: .leading, spacing: 10) {
                    
                    Text("自己紹介")
                        .font(.title3)
                        .bold()
                    
                    Text("""
初心者から上級者まで対応します！

試合に勝ちたい方、
楽しく上達したい方、
ぜひ一緒に練習しましょう！
""")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                NavigationLink {
                    BookingView(coach: coach)
                } label: {
                    Text("予約する")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding()
        }
        .navigationTitle("プロフィール")
    }
}

#Preview {
    ProfileDetailView(coach: sampleCoaches[0])
}
