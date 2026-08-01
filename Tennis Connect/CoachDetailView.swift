import SwiftUI

struct CoachDetailView: View {

    let coach: Coach

    var body: some View {

        ScrollView {

            VStack(spacing: 20) {

                CoachHeaderView(coach: coach)

                CoachProfileSection(coach: coach)

                CoachSkillSection()

                CoachVideoSection()

                CoachReviewSection()

                CoachScheduleSection(coach: coach)

                ReserveButton(coach: coach)

            }
            .padding()

        }
        .navigationTitle("コーチ詳細")
        .navigationBarTitleDisplayMode(.inline)

    }
}

#Preview {
    CoachDetailView(
        coach: sampleCoaches[0]
    )
}
