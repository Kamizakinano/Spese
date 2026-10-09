import AppIntents
import SwiftData
import Foundation

enum PayMethod: String, AppEnum {
    case carta, contanti
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Pagamento"
    static let caseDisplayRepresentations: [PayMethod: DisplayRepresentation] = [
        .carta: "Carta", .contanti: "Contanti"
    ]
}

/// Chiave dell'impostazione "avvisami quando arriva una spesa da Apple Pay" (spenta di partenza).
let applePayNotifyKey = "applePayNotify"

struct InvalidAmountError: Error, CustomLocalizedStringResourceConvertible {
    let text: String
    var localizedStringResource: LocalizedStringResource { "Importo non valido: \(text)" }
}

/// Azione per i Comandi rapidi: registra una spesa (per esempio da un pagamento con Apple Pay).
/// Lavora in silenzio: non apre l'app, non mostra messaggi e non manda notifiche (salvo se attivate).
struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Aggiungi spesa"
    static let description = IntentDescription("Registra una spesa in Spese, per esempio da un pagamento con Apple Pay.")
    static let openAppWhenRun = false

    @Parameter(title: "Importo") var amount: String
    @Parameter(title: "Esercente", default: "") var merchant: String
    @Parameter(title: "Pagamento", default: .carta) var method: PayMethod

    static var parameterSummary: some ParameterSummary {
        Summary("Aggiungi spesa di \(\.$amount) da \(\.$merchant)") { \.$method }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let value = parseLooseAmount(amount), value > 0 else { throw InvalidAmountError(text: amount) }
        let ctx = SharedStore.container.mainContext
        let cats = (try? ctx.fetch(FetchDescriptor<CategoryItem>(sortBy: [SortDescriptor(\.order)]))) ?? []
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let cat = guessCategory(merchant: name, available: cats.map { $0.name })
        let e = Expense(amount: value, categoryName: cat, date: Date(), note: name)
        e.method = method.rawValue
        ctx.insert(e)
        try ctx.save()
        if UserDefaults.standard.bool(forKey: applePayNotifyKey) {
            notify("Spesa registrata", "\(eur(value)) · \(name.isEmpty ? cat : name)")
        }
        return .result()
    }
}

/// Rende "Aggiungi spesa" disponibile subito in Comandi rapidi e con Siri, senza doverlo costruire.
struct SpeseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddExpenseIntent(),
                    phrases: ["Aggiungi spesa in \(.applicationName)", "Registra una spesa in \(.applicationName)"],
                    shortTitle: "Aggiungi spesa", systemImageName: "creditcard")
    }
}

/// Legge un importo anche se arriva come testo, per esempio "12,50 €" o "€1.234,50".
func parseLooseAmount(_ s: String) -> Double? {
    var t = s.filter { $0.isNumber || $0 == "," || $0 == "." }
    if t.contains(",") && t.contains(".") {
        if let lc = t.lastIndex(of: ","), let ld = t.lastIndex(of: "."), lc > ld {
            t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else {
            t = t.replacingOccurrences(of: ",", with: "")
        }
    } else {
        t = t.replacingOccurrences(of: ",", with: ".")
    }
    return Double(t)
}

/// Sceglie la categoria in base al nome dell'esercente.
func guessCategory(merchant: String, available: [String]) -> String {
    let m = merchant.lowercased()
    let words = m.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { String($0) }
    func hit(_ k: String) -> Bool { k.count <= 4 ? words.contains(k) : m.contains(k) }
    let rules: [(String, [String])] = [
        ("Alimentari", ["conad", "coop", "esselunga", "lidl", "carrefour", "eurospin", "penny", "despar", "aldi", "md", "pam",
                        "supermercato", "panificio", "macelleria", "ortofrutta"]),
        ("Pranzi/Cene fuori", ["bar", "caffè", "caffe", "ristorante", "pizzeria", "trattoria", "osteria", "mcdonald", "burger",
                               "sushi", "kebab", "gelateria", "pasticceria", "starbucks", "glovo", "deliveroo", "autogrill"]),
        ("Trasporti", ["eni", "q8", "tamoil", "esso", "ip", "carburanti", "telepass", "autostrade", "atm", "trenord", "uber", "taxi", "parcheggio"]),
        ("Viaggi", ["trenitalia", "italo", "ryanair", "easyjet", "wizz", "booking", "airbnb", "hotel", "flixbus", "expedia"]),
        ("Salute", ["farmacia", "parafarmacia", "ospedale", "dentista", "clinica", "ottica"]),
        ("Shopping", ["amazon", "zalando", "zara", "ikea", "decathlon", "mediaworld", "unieuro", "shein", "ebay"]),
        ("Svago", ["netflix", "spotify", "cinema", "disney", "steam", "playstation", "nintendo", "teatro", "youtube"]),
        ("Casa e bollette", ["enel", "edison", "a2a", "hera", "vodafone", "iliad", "fastweb", "bolletta", "leroy", "brico"])
    ]
    for (cat, keys) in rules where keys.contains(where: hit) && available.contains(cat) { return cat }
    return available.contains("Altro") ? "Altro" : (available.first ?? "Altro")
}
