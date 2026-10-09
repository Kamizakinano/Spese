import SwiftUI
import SwiftData
import UserNotifications
import UIKit

final class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@main
struct SpeseApp: App {
    @AppStorage("theme") private var theme = 0
    static let notifDelegate = NotifDelegate()
    init() { UNUserNotificationCenter.current().delegate = SpeseApp.notifDelegate }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(theme == 1 ? .light : theme == 2 ? .dark : nil)
                .tint(Theme.accent)
        }
        .modelContainer(SharedStore.container)
    }
}

// MARK: - Modelli

@Model final class Expense {
    var amount: Double
    var categoryRaw: String   // nome della categoria
    var date: Date
    var note: String
    var tag: String = ""
    var owedBy: String = ""
    var owedAmount: Double = 0
    var settled: Bool = false
    var method: String = "carta"   // carta oppure contanti
    init(amount: Double, categoryName: String, date: Date, note: String) {
        self.amount = amount; self.categoryRaw = categoryName; self.date = date; self.note = note
    }
}

@Model final class MonthBudget {
    var key: String
    var amount: Double
    init(key: String, amount: Double) { self.key = key; self.amount = amount }
}

@Model final class CategoryItem {
    var name: String
    var icon: String
    var colorHex: String
    var order: Int
    var limit: Double = 0
    init(name: String, icon: String, colorHex: String, order: Int) {
        self.name = name; self.icon = icon; self.colorHex = colorHex; self.order = order
    }
}

@Model final class Recurring {
    var name: String
    var amount: Double
    var categoryName: String
    var day: Int
    var nextKey: String       // prossimo mese da generare, es. "2026-10"
    init(name: String, amount: Double, categoryName: String, day: Int, nextKey: String) {
        self.name = name; self.amount = amount; self.categoryName = categoryName
        self.day = day; self.nextKey = nextKey
    }
}

// MARK: - Utilità

enum Theme { static let accent = Color(hex: "1D9E75") }

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
    var hex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

let defaultCategories: [(String, String, String)] = [
    ("Alimentari", "cart", "2E8B57"), ("Pranzi/Cene fuori", "fork.knife", "E67E22"),
    ("Viaggi", "airplane", "2980B9"), ("Trasporti", "car", "8E44AD"),
    ("Casa e bollette", "house", "16A085"), ("Salute", "cross.case", "C0392B"),
    ("Svago", "popcorn", "D4A017"), ("Shopping", "bag", "E84393"),
    ("Altro", "ellipsis.circle", "7F8C8D")
]

func monthKey(_ d: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month], from: d)
    return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
}
func parseAmount(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }
func eur(_ v: Double) -> String { v.formatted(.currency(code: "EUR")) }

func notify(_ title: String, _ body: String) {
    let c = UNMutableNotificationContent()
    c.title = title; c.body = body; c.sound = .default
    let req = UNNotificationRequest(identifier: UUID().uuidString, content: c,
                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
    UNUserNotificationCenter.current().add(req)
}

// MARK: - Entrate e risparmi

@Model final class Account {
    var startDate: Date
    var salaryAmount: Double
    var salaryDay: Int
    var salaryMode: Int        // 0 = percentuale, 1 = importo fisso
    var salaryValue: Double
    var salaryNextKey: String
    var cashStart: Double = 0   // contanti nel portafoglio all'inizio
    init(startDate: Date) {
        self.startDate = startDate; salaryAmount = 0; salaryDay = 27
        salaryMode = 0; salaryValue = 0; salaryNextKey = ""
    }
}

@Model final class Income {
    var amount: Double
    var saved: Double          // parte messa a risparmio
    var kind: String
    var date: Date
    var note: String
    init(amount: Double, saved: Double, kind: String, date: Date, note: String) {
        self.amount = amount; self.saved = saved; self.kind = kind; self.date = date; self.note = note
    }
}

@Model final class SavingsMove {
    var amount: Double         // + versamento, - prelievo
    var date: Date
    var note: String
    init(amount: Double, date: Date, note: String) { self.amount = amount; self.date = date; self.note = note }
}

@Model final class Goal {
    var name: String
    var target: Double
    var saved: Double
    var deadline: Date
    init(name: String, target: Double, saved: Double, deadline: Date) {
        self.name = name; self.target = target; self.saved = saved; self.deadline = deadline
    }
}

@Model final class CashMove {
    var amount: Double         // + entra nel portafoglio, - esce dal portafoglio
    var date: Date
    var note: String
    var kind: String           // prelievo, versamento, ricevuti, correzione
    var bank: Bool             // true se i soldi si spostano tra banca e contanti
    init(amount: Double, date: Date, note: String, kind: String, bank: Bool) {
        self.amount = amount; self.date = date; self.note = note; self.kind = kind; self.bank = bank
    }
}

extension Expense {
    var isCash: Bool { method == "contanti" }
}

/// Contenitore dati unico, usato sia dall'app sia dai Comandi rapidi.
enum SharedStore {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Expense.self, MonthBudget.self, CategoryItem.self, Recurring.self,
                                      Account.self, Income.self, SavingsMove.self, Goal.self, CashMove.self)
        } catch {
            fatalError("Impossibile aprire i dati: \(error)")
        }
    }()
}
