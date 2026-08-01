import SwiftUI

struct CoachVideoSection: View {

    let videos = [
        "フォアハンド基礎",
        "サーブレッスン",
        "ボレー練習"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            Label("レッスン動画", systemImage: "play.rectangle.fill")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.green)

            ForEach(videos, id: \.self) { video in

                VStack(alignment: .leading, spacing: 10) {

                    ZStack {

                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 180)

                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 55))
                            .foregroundStyle(.green)
                    }

                    Text(video)
                        .font(.headline)
                }
            }
        }
        .padding(20)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

#Preview {
    CoachVideoSection()
        .padding()
}
