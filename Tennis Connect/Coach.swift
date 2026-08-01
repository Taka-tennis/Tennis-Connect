import Foundation

struct Coach: Identifiable {

    let id = UUID()

    let name: String
    let price: Int
    let area: String
    let imageURL: String
    let availableTimes: [(String, Bool)]

    let ageGroup: String

    // ←ここを変更
    let careers: [String]

    let tennisExperience: String
    let coachingExperience: String
    let introduction: String

}
