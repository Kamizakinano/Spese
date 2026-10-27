import SwiftUI
import SwiftData
import UserNotifications
import UIKit

final class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
    /// Notifica toccata: apre "Nuova spesa" o il "Controllo di stasera", se lo chiede.
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        switch response.notification.request.content.userInfo["apri"] as? String {
        case "nuova": await UIApplication.shared.open(quickAddURL)
        case "sera": await UIApplication.shared.open(eveningCheckURL)
        default: break
        }
    }
}

@main
struct SpeseApp: App {
    @AppStorage("theme") private var theme = 0
    @AppStorage(appColorKey) private var appColor = AppColor.verde.rawValue
    static let notifDelegate = NotifDelegate()
    init() { UNUserNotificationCenter.current().delegate = SpeseApp.notifDelegate }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(theme == 1 ? .light : theme == 2 ? .dark : nil)
                .tint((AppColor(rawValue: appColor) ?? .verde).accent)
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
    // Viaggi
    var tripID: String = ""          // viaggio a cui appartiene ("" = nessuno)
    var originalAmount: Double = 0   // importo nella valuta locale
    var originalCurrency: String = "" // valuta locale ("" = euro)
    var rate: Double = 0             // cambio usato: 1 € = rate nella valuta locale
    var paidBy: String = ""          // chi ha pagato ("" = io)
    var splitJSON: String = ""       // divisione: {"Io": 10, "Marco": 10} in euro
    var needsAmount: Bool = false    // arrivata da Apple Pay senza un importo leggibile: da completare
    var settledMethod: String = ""   // "Ti devono": incassato "carta" (sul conto) o "contanti"
    var refundKey: String = ""       // lega la spesa all'entrata (o ai contanti) del rimborso incassato
    // Pagamenti a rate: ogni rata è una spesa, legata alle altre dello stesso acquisto
    var planID: String = ""          // acquisto a cui appartiene ("" = nessuno)
    var planName: String = ""        // cosa è stato comprato
    var planProvider: String = ""    // PayPal, Klarna…
    var planIndex: Int = 0           // numero della rata (da 1)
    var planCount: Int = 0           // rate totali
    var planTotal: Double = 0        // importo totale dell'acquisto
    @Attribute(.externalStorage) var receipt: Data? = nil   // foto dello scontrino (JPEG)
    var latitude: Double = 0          // dove è stata fatta (0 = non si sa; solo con la mappa accesa)
    var longitude: Double = 0
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
    var isSubscription: Bool = false   // abbonamento: compare in Abbonamenti, con avviso prima del rinnovo
    init(name: String, amount: Double, categoryName: String, day: Int, nextKey: String) {
        self.name = name; self.amount = amount; self.categoryName = categoryName
        self.day = day; self.nextKey = nextKey
    }
}

// MARK: - Utilità

/// Colori scelti in Altro → Aspetto. Il verde è quello di partenza.
enum AppColor: String, CaseIterable, Identifiable {
    case verde, ardesia, blu, rosso, nero, rosa, viola
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    /// Colore principale (testi in evidenza, pulsanti, icone), riquadri grandi (dal chiaro allo scuro) e tono chiaro.
    var accent: Color {
        switch self {
        case .verde: return Color(hex: "1D9E75")
        case .ardesia: return Color(hex: "5D7584")   // il grigio-blu dell'icona
        case .blu: return Color(hex: "2F7FE0")
        case .rosso: return Color(hex: "D64545")
        // Nero col tema chiaro, grigio col tema scuro (così resta leggibile su entrambi gli sfondi).
        case .nero: return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.62, alpha: 1) : UIColor(white: 0.11, alpha: 1) })
        case .rosa: return Color(hex: "D9468E")
        case .viola: return Color(hex: "8E5BD0")
        }
    }
    var top: Color {
        switch self {
        case .verde: return Color(hex: "1A5E44")
        case .ardesia: return Color(hex: "5D7584")
        case .blu: return Color(hex: "1E4E8C")
        case .rosso: return Color(hex: "8E2A2A")
        case .nero: return Color(hex: "3A3A3C")
        case .rosa: return Color(hex: "A2336C")
        case .viola: return Color(hex: "5B3A93")
        }
    }
    var bottom: Color {
        switch self {
        case .verde: return Color(hex: "0E4632")
        case .ardesia: return Color(hex: "3C4E5A")
        case .blu: return Color(hex: "12325E")
        case .rosso: return Color(hex: "5E1818")
        case .nero: return Color(hex: "161618")
        case .rosa: return Color(hex: "6E1F48")
        case .viola: return Color(hex: "3B2466")
        }
    }
    var light: Color {
        switch self {
        case .verde: return Color(hex: "4CC38A")
        case .ardesia: return Color(hex: "FF9C88")   // il corallo dell'icona
        case .blu: return Color(hex: "6FB1FF")
        case .rosso: return Color(hex: "FF8A80")
        case .nero: return Color(hex: "B0B0B5")
        case .rosa: return Color(hex: "FF9CC8")
        case .viola: return Color(hex: "C3A6F2")
        }
    }
    /// Colore per il pallino di scelta (il nero si vede nero anche col tema scuro).
    var swatch: Color { self == .nero ? Color(hex: "1C1C1E") : accent }
}

let appColorKey = "appColor"

enum Theme {
    static var color: AppColor { AppColor(rawValue: UserDefaults.standard.string(forKey: appColorKey) ?? "") ?? .verde }
    static var accent: Color { color.accent }
}

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
    (giftCardCategory, "giftcard", "6C5CE7"),
    (installmentCategory, "calendar.badge.clock", "0E7C86"),
    (subscriptionCategory, "arrow.triangle.2.circlepath", "3D7DD8"),
    ("Altro", "ellipsis.circle", "7F8C8D")
]

/// Categoria degli abbonamenti (SIM, streaming…): da "Nuova spesa" si possono ripetere ogni mese.
let subscriptionCategory = "Abbonamenti"
let subscriptionAddedKey = "subscriptionCategoryAdded"

/// Abbonamento che ripete ogni mese una spesa segnata oggi: parte dal mese dopo (questo è già segnato).
func makeSubscription(note: String, amount: Double, date: Date) -> Recurring {
    let name = note.trimmingCharacters(in: .whitespaces)
    let r = Recurring(name: name.isEmpty ? "Abbonamento" : name, amount: amount, categoryName: subscriptionCategory,
                      day: Calendar.current.component(.day, from: date), nextKey: nextMonthKey(monthKey(date)))
    r.isSubscription = true
    return r
}

/// Categoria per l'acquisto di carte regalo (di qualsiasi negozio).
let giftCardCategory = "Gift Card"
/// Segna che la categoria Gift Card è già stata aggiunta (se poi la si elimina non ricompare).
let giftCardAddedKey = "giftCardAdded"

func monthKey(_ d: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month], from: d)
    return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
}
func parseAmount(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }
func eur(_ v: Double) -> String { v.formatted(.currency(code: "EUR")) }

func notify(_ title: String, _ body: String, openNewExpense: Bool = false) {
    let c = UNMutableNotificationContent()
    c.title = title; c.body = body; c.sound = .default
    if openNewExpense { c.userInfo = ["apri": "nuova"] }
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
    var periodStart: Date? = nil   // stipendio ricevuto il (scelto dall'utente)
    var periodEnd: Date? = nil     // prossimo stipendio il (scelto dall'utente)
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
    var refundKey: String = ""   // rimborso di una spesa "Ti devono" (stessa chiave della spesa)
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
    var refundKey: String = "" // rimborso in contanti di una spesa "Ti devono"
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
                                      Account.self, Income.self, SavingsMove.self, Goal.self, CashMove.self,
                                      Trip.self, TripPayment.self, Debt.self)
        } catch {
            fatalError("Impossibile aprire i dati: \(error)")
        }
    }()
}
