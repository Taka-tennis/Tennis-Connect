// 修正版：本日レッスン可能コーチをコーチ側のON/OFFと連動し、日付検索も安全化

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct HomeView: View {
    let db = Firestore.firestore()
    let unreadNotificationCount: Int

    @State private var coaches: [Coach] = []
    @State private var sameDayCoaches: [Coach] = []
    @State private var isLoadingSameDayCoaches = false
    @State private var sameDayErrorMessage = ""
    @State private var isLoggedIn = false
    @State private var showLogin = false

    init(unreadNotificationCount: Int = 0) {
        self.unreadNotificationCount = unreadNotificationCount
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    func fetchCoaches() {
        Task {
            do {
                let snapshot = try await db.collection("coaches").getDocuments()

                let fetchedCoaches = snapshot.documents.map { document in
                    let data = document.data()

                    let savedCareers =
                        (data["careers"] as? [String] ?? [])
                            .map {
                                $0.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                            }
                            .filter {
                                !$0.isEmpty &&
                                $0 != "経歴未登録"
                            }

                    let legacyCareer =
                        (data["career"] as? String ?? "")
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )

                    let careers: [String]

                    if !savedCareers.isEmpty {
                        careers = savedCareers
                    } else if !legacyCareer.isEmpty {
                        careers = legacyCareer
                            .components(separatedBy: .newlines)
                            .map {
                                $0.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                )
                            }
                            .filter {
                                !$0.isEmpty
                            }
                    } else {
                        careers = ["経歴未登録"]
                    }

                    let tennisExperience =
                        (data["tennisExperience"] as? String ?? "")
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )

                    let coachingExperience =
                        (data["coachingExperience"] as? String ?? "")
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )

                    let introduction =
                        (data["introduction"] as? String ?? "")
                            .trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )

                    return Coach(
                        id: document.documentID,
                        name: data["name"] as? String ?? "名前未登録",
                        price: data["price"] as? Int ?? 0,
                        area: data["area"] as? String ?? "エリア未登録",
                        imageURL: data["imageURL"] as? String ?? "",
                        availableTimes: [
                            ("09:00", true),
                            ("10:00", true),
                            ("11:00", false),
                            ("13:00", true),
                            ("15:00", true),
                            ("16:00", false)
                        ],
                        ageGroup:
                            data["ageGroup"] as? String
                            ?? "年代未登録",
                        careers: careers,
                        tennisExperience:
                            tennisExperience.isEmpty
                                ? "未登録"
                                : tennisExperience,
                        coachingExperience:
                            coachingExperience.isEmpty
                                ? "未登録"
                                : coachingExperience,
                        introduction:
                            introduction.isEmpty
                                ? "自己紹介はまだありません。"
                                : introduction
                    )
                }

                await MainActor.run {
                    coaches = fetchedCoaches
                }

                loadSameDayCoaches(from: fetchedCoaches)

            } catch {
                print("コーチ取得エラー: \(error.localizedDescription)")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    NotificationCenter.default.post(
                        name: .returnToStartScreen,
                        object: nil
                    )
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
                .accessibilityLabel("スタート画面へ戻る")

                Text("🎾 Tennis Connect")
                    .font(.title)
                    .bold()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 4)

                if isLoggedIn {
                    NavigationLink {
                        NotificationView()
                    } label: {
                        Image(
                            systemName: unreadNotificationCount > 0
                                ? "bell.fill"
                                : "bell"
                        )
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                        .overlay(alignment: .topTrailing) {
                            if unreadNotificationCount > 0 {
                                Text(
                                    unreadNotificationCount > 99
                                        ? "99+"
                                        : "\(unreadNotificationCount)"
                                )
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Color.red)
                                .clipShape(Capsule())
                                .offset(x: 5, y: -5)
                            }
                        }
                    }
                    .accessibilityLabel(
                        unreadNotificationCount > 0
                            ? "未読通知が\(unreadNotificationCount)件あります"
                            : "通知"
                    )
                } else {
                    Button {
                        showLogin = true
                    } label: {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.title3)
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color(.systemGray6))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("ログイン")
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    NavigationLink {
                        ReservationListView()
                    } label: {
                        HStack {
                            Image(systemName: "calendar")
                            Text("予約一覧を見る")

                            Spacer()

                            Image(systemName: "chevron.right")
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        StudentCoachSearchView(coaches: coaches)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "magnifyingglass")
                                .font(.title2)
                                .foregroundStyle(.blue)
                                .frame(width: 38, height: 38)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text("コーチを探す")
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text("地域・駅名・希望日から検索")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(14)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 12) {

                        Text("🔥 本日レッスン可能コーチ")
                            .font(.title2)
                            .bold()

                        if isLoadingSameDayCoaches {
                            HStack {
                                Spacer()
                                ProgressView("本日受付中のコーチを確認中…")
                                Spacer()
                            }
                            .padding(.vertical, 28)

                        } else if sameDayCoaches.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "figure.tennis")
                                    .font(.system(size: 34))
                                    .foregroundStyle(.secondary)

                                Text("現在、本日レッスン可能なコーチはいません")
                                    .font(.headline)
                                    .multilineTextAlignment(.center)

                                Text("時間をおいてもう一度確認してみてください")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                            .padding(.horizontal)
                            .background(Color(.systemGray6))
                            .cornerRadius(14)

                        } else {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(sameDayCoaches) { coach in
                                    NavigationLink {
                                        CoachDetailView(coach: coach)
                                    } label: {
                                        CoachGridCard(coach: coach)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if !sameDayErrorMessage.isEmpty {
                            Text(sameDayErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear {
            isLoggedIn = Auth.auth().currentUser != nil
            fetchCoaches()
        }
        .sheet(isPresented: $showLogin) {
            LoginView {
                isLoggedIn = true
            }
        }
    }

    private func loadSameDayCoaches(from coaches: [Coach]) {
        let dateKey = firestoreDate(Date())
        let now = Date()

        isLoadingSameDayCoaches = true
        sameDayErrorMessage = ""
        sameDayCoaches = []

        Task {
            var availableCoaches: [Coach] = []
            var didEncounterError = false

            for coach in coaches {
                do {
                    let snapshot = try await db
                        .collection("coachAvailability")
                        .document(coach.id)
                        .collection("dates")
                        .document(dateKey)
                        .getDocument()

                    let data = snapshot.data() ?? [:]
                    let isSameDayAvailable =
                        data["sameDayAvailable"] as? Bool ?? false
                    let times =
                        data["times"] as? [String] ?? []

                    guard isSameDayAvailable else {
                        continue
                    }

                    let hasFutureTime = times.contains { time in
                        guard let lessonDate = lessonDate(
                            dateKey: dateKey,
                            time: time
                        ) else {
                            return false
                        }

                        return lessonDate > now
                    }

                    if hasFutureTime {
                        availableCoaches.append(coach)
                    }

                } catch {
                    didEncounterError = true
                    print(
                        "本日レッスン可能コーチ取得エラー " +
                        "\(coach.id): \(error.localizedDescription)"
                    )
                }
            }

            await MainActor.run {
                sameDayCoaches = availableCoaches
                isLoadingSameDayCoaches = false

                sameDayErrorMessage = didEncounterError
                    ? "一部のコーチ情報を取得できませんでした。再度お試しください。"
                    : ""
            }
        }
    }

    private func firestoreDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func lessonDate(
        dateKey: String,
        time: String
    ) -> Date? {
        let normalizedTime =
            time.replacingOccurrences(of: "~", with: "〜")
                .components(separatedBy: "〜")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? time

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        return formatter.date(
            from: "\(dateKey) \(normalizedTime)"
        )
    }
}

private struct StudentCoachSearchView: View {
    let coaches: [Coach]

    @State private var searchText = ""
    @State private var isDateFilterEnabled = false
    @State private var selectedDate =
        Calendar.current.startOfDay(for: Date())
    @State private var availableCoachIDs: Set<String> = []
    @State private var isCheckingAvailability = false
    @State private var availabilityErrorMessage = ""

    private let db = Firestore.firestore()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var filteredCoaches: [Coach] {
        let keyword = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return coaches.filter { coach in
            let matchesKeyword =
                keyword.isEmpty ||
                coach.name.localizedCaseInsensitiveContains(keyword) ||
                coach.area.localizedCaseInsensitiveContains(keyword) ||
                coach.careers
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(keyword)

            let matchesDate =
                !isDateFilterEnabled ||
                availableCoachIDs.contains(coach.id)

            return matchesKeyword && matchesDate
        }
    }

    private var resultTitle: String {
        if isDateFilterEnabled {
            return "\(displayDate(selectedDate))に予約可能なコーチ"
        }

        return searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
            ? "コーチ一覧"
            : "検索結果"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField(
                        "コーチ名・地域・駅名で検索",
                        text: $searchText
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("検索文字を消去")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Color(.systemGray6))
                .cornerRadius(12)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(
                            "レッスン希望日",
                            systemImage: "calendar"
                        )
                        .font(.headline)

                        Spacer()

                        Toggle(
                            "",
                            isOn: $isDateFilterEnabled
                        )
                        .labelsHidden()
                    }

                    if isDateFilterEnabled {
                        DatePicker(
                            "日付を選択",
                            selection: $selectedDate,
                            in: Calendar.current.startOfDay(for: Date())...,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .environment(
                            \.locale,
                            Locale(identifier: "ja_JP")
                        )

                        if isCheckingAvailability {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("空き日程を確認中…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text(
                                isToday(selectedDate)
                                    ? "本日は「本日レッスン可能」をONにしていて、これから空き枠があるコーチのみ表示します"
                                    : "\(displayDate(selectedDate))に空き枠があるコーチのみ表示します"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        if !availabilityErrorMessage.isEmpty {
                            Text(availabilityErrorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } else {
                        Text("ONにすると、希望日に空き枠があるコーチだけに絞り込めます")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(14)

                Text(resultTitle)
                    .font(.title2)
                    .bold()

                if isCheckingAvailability && isDateFilterEnabled {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)

                        Text("予約可能なコーチを確認しています")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 44)

                } else if filteredCoaches.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)

                        Text("条件に合うコーチが見つかりません")
                            .font(.headline)

                        Text(
                            isDateFilterEnabled
                                ? "別の日付や検索条件でお試しください"
                                : "検索条件を変えてお試しください"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 44)

                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredCoaches) { coach in
                            NavigationLink {
                                CoachDetailView(coach: coach)
                            } label: {
                                CoachGridCard(coach: coach)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("コーチを探す")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: isDateFilterEnabled) { isEnabled in
            if isEnabled {
                loadAvailableCoachesForSelectedDate()
            } else {
                availableCoachIDs = []
                availabilityErrorMessage = ""
                isCheckingAvailability = false
            }
        }
        .onChange(of: selectedDate) { _ in
            guard isDateFilterEnabled else {
                return
            }

            loadAvailableCoachesForSelectedDate()
        }
    }

    private func loadAvailableCoachesForSelectedDate() {
        let dateKey = firestoreDate(selectedDate)
        let targetIsToday = isToday(selectedDate)
        let now = Date()

        isCheckingAvailability = true
        availabilityErrorMessage = ""
        availableCoachIDs = []

        Task {
            var fetchedAvailableCoachIDs: Set<String> = []
            var didEncounterError = false

            for coach in coaches {
                do {
                    let snapshot = try await db
                        .collection("coachAvailability")
                        .document(coach.id)
                        .collection("dates")
                        .document(dateKey)
                        .getDocument()

                    let data = snapshot.data() ?? [:]
                    let times =
                        data["times"] as? [String] ?? []

                    guard !times.isEmpty else {
                        continue
                    }

                    if targetIsToday {
                        let isSameDayAvailable =
                            data["sameDayAvailable"] as? Bool ?? false

                        guard isSameDayAvailable else {
                            continue
                        }

                        let hasFutureTime = times.contains { time in
                            guard let lessonDate = lessonDate(
                                dateKey: dateKey,
                                time: time
                            ) else {
                                return false
                            }

                            return lessonDate > now
                        }

                        if hasFutureTime {
                            fetchedAvailableCoachIDs.insert(coach.id)
                        }

                    } else {
                        fetchedAvailableCoachIDs.insert(coach.id)
                    }

                } catch {
                    didEncounterError = true
                    print(
                        "空き日程取得エラー " +
                        "\(coach.id): \(error.localizedDescription)"
                    )
                }
            }

            await MainActor.run {
                guard isDateFilterEnabled,
                      firestoreDate(selectedDate) == dateKey else {
                    return
                }

                availableCoachIDs = fetchedAvailableCoachIDs
                isCheckingAvailability = false

                if didEncounterError {
                    availabilityErrorMessage =
                        "一部の空き日程を取得できませんでした。再度お試しください。"
                } else {
                    availabilityErrorMessage = ""
                }
            }
        }
    }

    private func firestoreDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func isToday(_ date: Date) -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.isDate(date, inSameDayAs: Date())
    }

    private func lessonDate(
        dateKey: String,
        time: String
    ) -> Date? {
        let normalizedTime =
            time.replacingOccurrences(of: "~", with: "〜")
                .components(separatedBy: "〜")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? time

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        return formatter.date(
            from: "\(dateKey) \(normalizedTime)"
        )
    }

    private func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone =
            TimeZone(identifier: "Asia/Tokyo") ?? .current
        formatter.dateFormat = "yyyy/M/d"
        return formatter.string(from: date)
    }
}

private struct CoachGridCard: View {
    let coach: Coach

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            AsyncImage(url: URL(string: coach.imageURL)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()

                case .failure:
                    ZStack {
                        Color.gray.opacity(0.15)

                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 45))
                            .foregroundColor(.gray)
                    }

                case .empty:
                    ZStack {
                        Color.gray.opacity(0.15)
                        ProgressView()
                    }

                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 130)
            .clipped()
            .cornerRadius(12)

            Text(coach.name)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(coach.careers.first ?? "経歴未登録")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Label(coach.area, systemImage: "mappin.and.ellipse")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Text("¥\(coach.price) / 1時間")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.blue)
        }
        .padding(10)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(
            color: Color.black.opacity(0.08),
            radius: 5,
            x: 0,
            y: 2
        )
    }
}

struct LessonCard: View {
    let imageURL: String
    let name: String
    let time: String
    let place: String
    let price: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            AsyncImage(url: URL(string: imageURL)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ProgressView()
            }
            .frame(height: 180)
            .clipped()
            .cornerRadius(12)

            Text(name)
                .font(.headline)

            Text(time)
            Text(place)

            Text(price)
                .bold()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(15)
    }
}

#Preview {
    HomeView()
}
