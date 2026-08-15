import SwiftUI
import FirebaseFirestore
import FirebaseFunctions

struct PaymentView: View {
    let reservationId: String
    let coach: Coach
    let date: Date
    let times: [String]
    let totalPrice: Int

    @Environment(\.openURL) private var openURL

    @State private var showComplete = false
    @State private var isPaying = false
    @State private var errorMessage = ""
    @State private var paymentListener: ListenerRegistration?

    private let db = Firestore.firestore()
    private let functions = Functions.functions(
        region: "asia-northeast1"
    )

    var body: some View {
        VStack(spacing: 25) {
            Text("💳 支払い")
                .font(.largeTitle)
                .bold()

            VStack(alignment: .leading, spacing: 16) {
                Text("予約内容")
                    .font(.headline)

                Divider()

                detailRow(title: "コーチ", value: coach.name)
                detailRow(title: "日付", value: displayDate(date))
                detailRow(
                    title: "時間",
                    value: combinedTimeRange(times)
                )
                detailRow(
                    title: "レッスン時間",
                    value: "\(times.count)時間"
                )
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(16)

            VStack(alignment: .leading, spacing: 10) {
                Label(
                    "Stripeの安全な支払い画面を開きます",
                    systemImage: "lock.shield.fill"
                )
                .font(.headline)

                Text(
                    "利用できる支払い方法は、Stripeの画面に表示されます。"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(16)

            Spacer()

            Text("合計")
                .font(.headline)

            Text("¥\(totalPrice.formatted())")
                .font(.largeTitle)
                .bold()

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                openStripeCheckout()
            } label: {
                HStack {
                    Spacer()

                    if isPaying {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Stripeで支払う")
                            .fontWeight(.semibold)
                    }

                    Spacer()
                }
                .padding()
                .background(isPaying ? Color.gray : Color.green)
                .foregroundColor(.white)
                .cornerRadius(15)
            }
            .disabled(isPaying)
        }
        .padding()
        .onAppear {
            startPaymentListener()
        }
        .onDisappear {
            stopPaymentListener()
        }
        .navigationDestination(isPresented: $showComplete) {
            BookingCompleteView(
                coach: coach,
                date: date,
                times: times,
                totalPrice: totalPrice
            )
        }
    }

    private func openStripeCheckout() {
        guard !reservationId.isEmpty else {
            errorMessage = "予約情報を確認できませんでした"
            return
        }

        isPaying = true
        errorMessage = ""
        startPaymentListener()

        functions
            .httpsCallable("createCheckoutSession")
            .call(["reservationId": reservationId]) { result, error in
                if let error = error {
                    finishWithError(
                        "支払い画面を準備できませんでした: " +
                        error.localizedDescription
                    )
                    return
                }

                guard
                    let data = result?.data as? [String: Any],
                    let urlString = data["checkoutUrl"] as? String,
                    let checkoutURL = URL(string: urlString)
                else {
                    finishWithError(
                        "Stripeの支払いURLを取得できませんでした"
                    )
                    return
                }

                DispatchQueue.main.async {
                    openURL(checkoutURL) { accepted in
                        DispatchQueue.main.async {
                            isPaying = false

                            if !accepted {
                                errorMessage =
                                    "支払い画面を開けませんでした"
                            }
                        }
                    }
                }
            }
    }

    private func startPaymentListener() {
        guard !reservationId.isEmpty else {
            return
        }

        stopPaymentListener()

        paymentListener = db
            .collection("reservations")
            .document(reservationId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    DispatchQueue.main.async {
                        if errorMessage.isEmpty {
                            errorMessage =
                                "支払い状況を確認できませんでした: " +
                                error.localizedDescription
                        }
                    }
                    return
                }

                guard let data = snapshot?.data() else {
                    return
                }

                let status = data["status"] as? String ?? ""
                let paymentStatus =
                    data["paymentStatus"] as? String ?? ""

                DispatchQueue.main.async {
                    if status == "paid" || paymentStatus == "paid" {
                        isPaying = false
                        errorMessage = ""
                        showComplete = true
                        stopPaymentListener()
                    } else if paymentStatus == "failed" {
                        isPaying = false
                        errorMessage =
                            "支払いを確認できませんでした。" +
                            "もう一度お試しください。"
                    } else if paymentStatus == "expired" {
                        isPaying = false
                        errorMessage =
                            "支払い画面の有効期限が切れました。" +
                            "もう一度お試しください。"
                    }
                }
            }
    }

    private func stopPaymentListener() {
        paymentListener?.remove()
        paymentListener = nil
    }

    private func finishWithError(_ message: String) {
        DispatchQueue.main.async {
            isPaying = false
            errorMessage = message
        }
    }

    private func detailRow(
        title: String,
        value: String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
        }
    }

    private func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d（E）"
        return formatter.string(from: date)
    }

    private func combinedTimeRange(_ times: [String]) -> String {
        guard let first = times.sorted().first,
              let last = times.sorted().last else {
            return ""
        }

        return "\(first)〜\(endTime(for: last))"
    }

    private func endTime(for startTime: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"

        guard let startDate = formatter.date(from: startTime),
              let endDate = Calendar.current.date(
                byAdding: .hour,
                value: 1,
                to: startDate
              ) else {
            return startTime
        }

        return formatter.string(from: endDate)
    }
}

#Preview {
    NavigationStack {
        PaymentView(
            reservationId: "sampleReservation",
            coach: sampleCoaches[0],
            date: Date(),
            times: ["09:00", "10:00"],
            totalPrice: sampleCoaches[0].price * 2
        )
    }
}
