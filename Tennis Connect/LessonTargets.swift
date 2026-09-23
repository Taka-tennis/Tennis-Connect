import SwiftUI
import FirebaseFirestore

struct LessonTargets {
    static let levelOptions = ["初心者・未経験", "初級", "中級", "上級", "選手"]
    static let audienceOptions = ["一般（大人）", "ジュニア"]
    static let competitionOptions = ["試合・大会に向けた指導", "ジュニア選手育成"]

    var levels: [String] = []
    var audiences: [String] = []
    var competition: [String] = []

    init() {}

    init(data: [String: Any]) {
        let savedLevels = data["lessonLevels"] as? [String] ?? []
        let savedAudiences = data["lessonAudiences"] as? [String] ?? []
        let savedCompetition = data["lessonCompetition"] as? [String] ?? []
        levels = Self.levelOptions.filter { savedLevels.contains($0) }
        audiences = Self.audienceOptions.filter { savedAudiences.contains($0) }
        competition = Self.competitionOptions.filter { savedCompetition.contains($0) }
    }
}

struct LessonTargetsEditor: View {
    @Binding var targets: LessonTargets

    var body: some View {
        Section {
            Text("指導に対応できる対象をすべて選択してください。")
                .font(.caption)
                .foregroundStyle(.secondary)
            options("対応レベル", values: LessonTargets.levelOptions, selection: $targets.levels)
            options("対応する生徒", values: LessonTargets.audienceOptions, selection: $targets.audiences)
        } header: {
            Text("レッスン対象（複数選択可）")
        } footer: {
            Text("コーチ自身が申告する情報です。選択した項目はコーチ詳細に表示されます。")
        }
    }

    private func options(_ title: String, values: [String], selection: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold))
            ForEach(values, id: \.self) { value in
                let selected = selection.wrappedValue.contains(value)
                Button {
                    var updated = selection.wrappedValue
                    if selected {
                        updated.removeAll { $0 == value }
                    } else {
                        updated.append(value)
                    }
                    selection.wrappedValue = values.filter { updated.contains($0) }
                } label: {
                    HStack(spacing: 10) {
                        Text(value).multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    }
                    .font(.subheadline)
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .background(selected ? Color.green : Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityValue(selected ? "選択済み" : "未選択")
            }
        }
        .padding(.vertical, 4)
    }
}

// どの画面から開いても最新の対象を取得するため、Coachの既存生成処理に依存しない。
struct CoachLessonTargetsSection: View {
    let coachId: String
    @State private var targets = LessonTargets()
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("レッスン対象").font(.title2.bold())
            if isLoading {
                ProgressView("読み込み中…")
            } else if loadFailed {
                Text("レッスン対象を取得できませんでした。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("再読み込み") { loadTargets() }
            } else {
                targetRow("対応レベル", values: targets.levels)
                targetRow("対応する生徒", values: targets.audiences)
                Text("コーチの自己申告による情報です。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.green.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onAppear { loadTargets() }
    }

    private func targetRow(_ title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            if values.isEmpty {
                Text("未設定").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(Color.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func loadTargets() {
        isLoading = true
        loadFailed = false
        Firestore.firestore().collection("coaches").document(coachId)
            .getDocument { snapshot, error in
                DispatchQueue.main.async {
                    isLoading = false
                    guard error == nil, let data = snapshot?.data() else {
                        loadFailed = true
                        return
                    }
                    targets = LessonTargets(data: data)
                }
            }
    }
}
