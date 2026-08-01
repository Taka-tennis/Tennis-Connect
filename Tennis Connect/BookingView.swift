import SwiftUI
import FirebaseFirestore

struct BookingView: View {
    @State private var showAlert = false
    @State private var lessonDate = Date()
    @State private var selectedTime: String? = nil
    @State private var showConfirm = false
    
    let coach: Coach
    let db = Firestore.firestore()

    var body: some View {

        NavigationStack {

            ScrollView {
                
                VStack(spacing: 25) {
                    AsyncImage(url: URL(string: coach.imageURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .cornerRadius(15)

                    Text(coach.name)
                        .font(.largeTitle)
                        .bold()

                    Text(coach.careers.first ?? "経歴未登録")
                        .font(.headline)

                    Text(coach.area)

                    Text("¥\(coach.price)")
                        .font(.title2)
                        .bold()
                    Text("🎾 レッスン予約")
                        .font(.largeTitle)
                        .bold()
                    
                    DatePicker(
                        "日付",
                        selection: $lessonDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    
                
                    
                    VStack(alignment: .leading, spacing: 12) {

                        Text("⏰ 空き時間")
                            .font(.title3)
                            .bold()

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ],
                            spacing: 12
                        ) {

                            ForEach(coach.availableTimes.filter { $0.1 }, id: \.0) { time in

                                Button {

                                    selectedTime = time.0

                                } label: {

                                    Text(time.0)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(
                                            selectedTime == time.0
                                            ? Color.green
                                            : Color(.systemGray6)
                                        )
                                        .foregroundColor(
                                            selectedTime == time.0
                                            ? .white
                                            : .primary
                                        )
                                        .cornerRadius(12)
                                }

                            }
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(18)
                    .shadow(radius: 2)
                    
                    Text("料金")
                        .font(.headline)
                    
                    Text("¥3,000")
                        .font(.title)
                        .bold()
                    
                 
                    }
                Button {
                    showConfirm = true
                } label: {

                    Text("予約する")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            selectedTime == nil
                            ? Color.gray
                            : Color.green
                        )
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                .disabled(selectedTime == nil)
                
                    .alert("予約完了", isPresented: $showAlert) {
                        Button("OK") { }
                    } message: {
                        Text("レッスンを予約しました！")
                    }
                    Spacer()
                }
                .padding()
            
                .navigationDestination(isPresented: $showConfirm) {
                    BookingConfirmView(
                        coach: coach,
                        date: lessonDate,
                        time: selectedTime ?? ""
                    )
                }
            }
        }
    }

#Preview {
    BookingView(coach: sampleCoaches[0])
}
