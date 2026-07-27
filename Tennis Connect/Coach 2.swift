struct Coach: Identifiable {
    let id = UUID()
    let name: String
    let level: String
    let price: Int
    let area: String
    let imageName: String

    let introduction: String
    let specialty: String
    let rating: Double
    let reviewCount: Int
}