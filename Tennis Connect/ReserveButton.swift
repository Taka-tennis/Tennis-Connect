import SwiftUI

struct ReserveButton: View {

    let coach: Coach

    var body: some View {

        NavigationLink {
            BookingView(coach: coach)
        } label: {

            Text("レッスンを予約する")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(12)

        }

    }

}

#Preview {
    ReserveButton(
        coach: sampleCoaches[0]
    )
}
