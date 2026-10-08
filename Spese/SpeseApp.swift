import SwiftUI
import SwiftData

@main
struct SpeseApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .modelContainer(for: [Expense.self, MonthBudget.self])
    }
}

enum Category: String, CaseIterable, Identifiable, Codable {
    case alimentari = "Alimentari"
    case fuori = "Pranzi/Cene fuori"
    case viaggi = "Viaggi"
    case trasporti = "Trasporti"
    case casa = "Casa e bollette"
    case salute = "Salute"
    case svago = "Svago"
    case shopping = "Shopping"
    case altro = "Altro"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .alimentari: "cart"
        case .fuori: "fork.knife"
        case .viaggi: "airplane"
        case .trasporti: "car"
        case .casa: "house"
        case .salute: "cross.case"
        case .svago: "popcorn"
        case .shopping: "bag"
        case .altro: "ellipsis.circle"
        }
    }

    var color: Color {
        switch self {
        case .alimentari: .green
        case .fuori: .orange
        case .viaggi: .blue
        case .trasporti: .purple
        case .casa: .teal
        case .salute: .red
        case .svago: .yellow
        case .shopping: .pink
        case .altro: .gray
        }
    }
}

@Model
final class Expense {
    var amount: Double
    var categoryRaw: String
    var date: Date
    var note: String

    init(amount: Double, category: Category, date: Date, note: String) {
        self.amount = amount
        self.categoryRaw = category.rawValue
        self.date = date
        self.note = note
    }

    var category: Category { Category(rawValue: categoryRaw) ?? .altro }
}

@Model
final class MonthBudget {
    var key: String   // es. "2026-10"
    var amount: Double

    init(key: String, amount: Double) {
        self.key = key
        self.amount = amount
    }
}
