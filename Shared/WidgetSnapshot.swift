import Foundation

/// Gruppo condiviso tra l'app e il widget (stesso valore negli entitlements).
let appGroupID = "group.com.tuonome.spese"

/// I numeri che il widget mostra. L'app li scrive ogni volta che cambiano, il widget li legge.
struct WidgetSnapshot: Codable {
    var available: Double        // soldi disponibili (banca + contanti)
    var periodStart: Date?       // ultimo stipendio
    var periodEnd: Date?         // prossimo stipendio (escluso)
    var spentSincePay: Double    // speso dall'ultimo stipendio
    var updated: Date

    static let key = "widgetSnapshot"
    static var store: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    static func load() -> WidgetSnapshot? {
        guard let d = store?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: d)
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { WidgetSnapshot.store?.set(d, forKey: WidgetSnapshot.key) }
    }

    /// Giorni da `now` (compreso) al prossimo stipendio.
    func remainingDays(now: Date = Date()) -> Int {
        guard let end = periodEnd else { return 0 }
        let cal = Calendar.current
        return max(cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: end)).day ?? 0, 0)
    }

    /// Quanto si può spendere al giorno fino al prossimo stipendio.
    func perDay(now: Date = Date()) -> Double { max(available, 0) / Double(max(remainingDays(now: now), 1)) }

    static let sample = WidgetSnapshot(available: 1595.56, periodStart: Date().addingTimeInterval(-86400 * 1),
                                       periodEnd: Date().addingTimeInterval(86400 * 32), spentSincePay: 501.36, updated: Date())
}

func widgetEuro(_ v: Double) -> String { v.formatted(.currency(code: "EUR")) }
