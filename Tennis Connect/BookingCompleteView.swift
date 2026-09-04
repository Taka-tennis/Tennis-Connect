import SwiftUI

private enum BookingCompleteUI {
    static let brandGreen = Color(
        red: 42 / 255,
        green: 174 / 255,
        blue: 102 / 255
    )

    static let softGreen = Color(
        red: 232 / 255,
        green: 245 / 255,
        blue: 236 / 255
    )

    static let background = Color(
        red: 248 / 255,
        green: 250 / 255,
        blue: 249 / 255
    )

    static let textPrimary = Color(
        red: 34 / 255,
        green: 34 / 255,
        blue: 34 / 255
    )

    static let textSecondary = Color(
        red: 102 / 255,
        green: 110 / 255,
        blue: 105 / 255
    )

    static let border = Color.black.opacity(0.08)
}

struct BookingCompleteView: View {
    @State private var showChat = false
    @Environment(\.returnHomeAction) private var returnHome

    let coach: Coach
    let date: Date
    let times: [String]
    let totalPrice: Int

    var body: some View {
        ZStack {
            BookingCompleteUI.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    completionHeader

                    coachCard

                    reservationCard

                    nextStepCard

                    VStack(spacing: 12) {
                        Button {
                            showChat = true
                        } label: {
                            primaryButtonLabel(
                                title: "コーチにメッセージを送る",
                                icon: "message.fill"
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            NotificationCenter.default.post(
                                name: .returnToStudentHome,
                                object: nil
                            )
                        } label: {
                            HStack(spacing: 8) {
                                Spacer()

                                Image(
                                    systemName:
                                        "house.fill"
                                )

                                Text("ホームへ戻る")
                                    .fontWeight(.semibold)

                                Spacer()
                            }
                            .frame(height: 50)
                            .foregroundStyle(
                                BookingCompleteUI.textPrimary
                            )
                            .background(Color.white)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 15,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 15,
                                    style: .continuous
                                )
                                .stroke(
                                    BookingCompleteUI.border,
                                    lineWidth: 1
                                )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
        }
        .tint(BookingCompleteUI.brandGreen)
        .navigationBarBackButtonHidden(true)
        .navigationDestination(
            isPresented: $showChat
        ) {
            ChatView(coach: coach)
        }
    }

    private var completionHeader: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        BookingCompleteUI.softGreen
                    )
                    .frame(
                        width: 96,
                        height: 96
                    )

                Image(
                    systemName:
                        "checkmark.circle.fill"
                )
                .font(.system(size: 58))
                .foregroundStyle(
                    BookingCompleteUI.brandGreen
                )
            }

            VStack(spacing: 7) {
                Text("予約が完了しました")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        BookingCompleteUI.textPrimary
                    )

                Text("お支払いが正常に完了し、予約が確定しました。")
                    .font(.subheadline)
                    .foregroundStyle(
                        BookingCompleteUI.textSecondary
                    )
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var coachCard: some View {
        HStack(spacing: 14) {
            BookingCompleteCoachAvatarView(
                imageURL: coach.imageURL,
                size: 58
            )

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text("担当コーチ")
                    .font(.caption)
                    .foregroundStyle(
                        BookingCompleteUI.textSecondary
                    )

                Text(coach.name)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(
                        BookingCompleteUI.textPrimary
                    )
                    .lineLimit(1)

                if !coach.area.isEmpty {
                    Label(
                        coach.area,
                        systemImage:
                            "mappin.and.ellipse"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        BookingCompleteUI.textSecondary
                    )
                }
            }

            Spacer()

            Image(
                systemName:
                    "checkmark.seal.fill"
            )
            .font(.system(size: 20))
            .foregroundStyle(
                BookingCompleteUI.brandGreen
            )
        }
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                BookingCompleteUI.border,
                lineWidth: 1
            )
        }
    }

    private var reservationCard: some View {
        VStack(
            alignment: .leading,
            spacing: 14
        ) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(
                        BookingCompleteUI.brandGreen
                    )

                Text("予約内容")
                    .font(.headline)
                    .foregroundStyle(
                        BookingCompleteUI.textPrimary
                    )
            }

            detailRow(
                title: "日付",
                value: displayDate(date),
                icon: "calendar"
            )

            Divider()

            detailRow(
                title: "時間",
                value:
                    combinedTimeRange(times),
                icon: "clock"
            )

            Divider()

            detailRow(
                title: "レッスン時間",
                value:
                    "\(max(times.count, 1))時間",
                icon: "hourglass"
            )

            Divider()

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            BookingCompleteUI.softGreen
                        )
                        .frame(
                            width: 34,
                            height: 34
                        )

                    Image(
                        systemName: "yensign"
                    )
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        BookingCompleteUI.brandGreen
                    )
                }

                Text("お支払い金額")
                    .foregroundStyle(
                        BookingCompleteUI.textSecondary
                    )

                Spacer()

                Text(
                    "¥\(totalPrice.formatted())"
                )
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(
                    BookingCompleteUI.brandGreen
                )
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(
                BookingCompleteUI.border,
                lineWidth: 1
            )
        }
    }

    private var nextStepCard: some View {
        HStack(
            alignment: .top,
            spacing: 12
        ) {
            ZStack {
                Circle()
                    .fill(
                        BookingCompleteUI.softGreen
                    )
                    .frame(
                        width: 42,
                        height: 42
                    )

                Image(
                    systemName:
                        "calendar.badge.checkmark"
                )
                .font(
                    .system(
                        size: 17,
                        weight: .semibold
                    )
                )
                .foregroundStyle(
                    BookingCompleteUI.brandGreen
                )
            }

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Text("予約は確定しています")
                    .font(.headline)
                    .foregroundStyle(
                        BookingCompleteUI.textPrimary
                    )

                Text(
                    "予約内容は「予約一覧」からいつでも確認できます。必要に応じて、コーチとメッセージで詳細を確認してください。"
                )
                .font(.caption)
                .foregroundStyle(
                    BookingCompleteUI.textSecondary
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }

            Spacer()
        }
        .padding(16)
        .background(
            BookingCompleteUI.softGreen.opacity(0.55)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    private func primaryButtonLabel(
        title: String,
        icon: String
    ) -> some View {
        HStack(spacing: 8) {
            Spacer()

            Image(systemName: icon)

            Text(title)
                .fontWeight(.semibold)

            Spacer()
        }
        .frame(height: 50)
        .foregroundStyle(.white)
        .background(
            BookingCompleteUI.brandGreen
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 15,
                style: .continuous
            )
        )
    }

    private func detailRow(
        title: String,
        value: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        BookingCompleteUI.softGreen
                    )
                    .frame(
                        width: 34,
                        height: 34
                    )

                Image(systemName: icon)
                    .font(
                        .system(
                            size: 14,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        BookingCompleteUI.brandGreen
                    )
            }

            Text(title)
                .foregroundStyle(
                    BookingCompleteUI.textSecondary
                )

            Spacer()

            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(
                    BookingCompleteUI.textPrimary
                )
                .multilineTextAlignment(.trailing)
        }
    }

    private func displayDate(
        _ date: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar =
            Calendar(identifier: .gregorian)
        formatter.locale =
            Locale(identifier: "ja_JP")
        formatter.dateFormat =
            "yyyy/MM/dd"
        return formatter.string(
            from: date
        )
    }

    private func combinedTimeRange(
        _ times: [String]
    ) -> String {
        guard
            let first =
                times.sorted().first,
            let last =
                times.sorted().last
        else {
            return ""
        }

        return
            "\(first)〜\(endTime(for: last))"
    }

    private func endTime(
        for startTime: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar =
            Calendar(identifier: .gregorian)
        formatter.locale =
            Locale(identifier: "en_US_POSIX")
        formatter.dateFormat =
            "HH:mm"

        guard
            let startDate =
                formatter.date(
                    from: startTime
                ),
            let endDate =
                Calendar.current.date(
                    byAdding: .hour,
                    value: 1,
                    to: startDate
                )
        else {
            return startTime
        }

        return formatter.string(
            from: endDate
        )
    }
}

private struct BookingCompleteCoachAvatarView: View {
    let imageURL: String
    let size: CGFloat

    var body: some View {
        AsyncImage(
            url: URL(
                string: imageURL
            )
        ) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()

            case .failure:
                placeholder

            case .empty:
                if imageURL.isEmpty {
                    placeholder
                } else {
                    ProgressView()
                }

            @unknown default:
                placeholder
            }
        }
        .frame(
            width: size,
            height: size
        )
        .background(
            BookingCompleteUI.softGreen
        )
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(
                    BookingCompleteUI.border,
                    lineWidth: 1
                )
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .resizable()
            .scaledToFit()
            .padding(size * 0.22)
            .foregroundStyle(
                BookingCompleteUI.brandGreen
            )
    }
}
