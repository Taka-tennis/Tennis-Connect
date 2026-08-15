import SwiftUI

struct DashboardCard<Destination: View>: View {

    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {

        NavigationLink {
            destination()
        } label: {

            HStack(spacing: 16) {

                Image(systemName: systemImage)
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
                    .frame(width: 44, height: 44)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {

                    Text(title)
                        .font(.headline)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.gray)

            }
            .padding()
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)

        }

    }

}
