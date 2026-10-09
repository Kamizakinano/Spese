import Foundation
import SwiftData

// MARK: - Modelli dei viaggi

/// Nome con cui l'utente compare nelle divisioni delle spese.
let me = "Io"

@Model final class Trip {
    var uid: String = UUID().uuidString
    var name: String
    var currency: String          // codice valuta, es. "GBP" ("EUR" = euro)
    var startDate: Date
    var endDate: Date             // ultimo giorno del viaggio (compreso)
    var budget: Double = 0        // in euro (0 = nessun budget)
    var countInStats: Bool = false // conta nelle statistiche, nei limiti e nei riepiloghi
    var peopleJSON: String = "[]" // compagni di viaggio (oltre a me)
    var lastRate: Double = 0      // ultimo cambio usato (1 € = lastRate)
    init(name: String, currency: String, startDate: Date, endDate: Date) {
        self.name = name; self.currency = currency; self.startDate = startDate; self.endDate = endDate
    }

    var people: [String] {
        get { (try? JSONDecoder().decode([String].self, from: Data(peopleJSON.utf8))) ?? [] }
        set { peopleJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]" }
    }
    /// Io più i compagni.
    var everyone: [String] { [me] + people }
    var isForeign: Bool { currency != "EUR" }

    func contains(_ d: Date) -> Bool {
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: endDate)) ?? endDate
        return d >= cal.startOfDay(for: startDate) && d < end
    }
}

/// Un rimborso tra persone del viaggio (per esempio Marco mi restituisce 45 €).
@Model final class TripPayment {
    var tripID: String
    var from: String
    var to: String
    var amount: Double            // in euro
    var date: Date
    var method: String = "carta"  // se coinvolge me: carta o contanti
    init(tripID: String, from: String, to: String, amount: Double, date: Date) {
        self.tripID = tripID; self.from = from; self.to = to; self.amount = amount; self.date = date
    }
}

// MARK: - Divisione delle spese

extension Expense {
    var isTrip: Bool { !tripID.isEmpty }
    var paidByMe: Bool { paidBy.isEmpty }
    var payer: String { paidBy.isEmpty ? me : paidBy }

    /// Quote in euro di ognuno (vuoto = tutta la spesa è mia).
    var shares: [String: Double] {
        get { (try? JSONDecoder().decode([String: Double].self, from: Data(splitJSON.utf8))) ?? [:] }
        set { splitJSON = newValue.isEmpty ? "" : ((try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "") }
    }

    /// Quanto di questa spesa è davvero mio (per statistiche e limiti).
    var myAmount: Double {
        let s = shares
        if s.isEmpty { return amount }
        return s[me] ?? 0
    }
}

/// Divide un importo in parti uguali (in centesimi, il resto va ai primi).
func equalShares(_ amount: Double, among names: [String]) -> [String: Double] {
    guard !names.isEmpty else { return [:] }
    let cents = Int((amount * 100).rounded())
    let base = cents / names.count, extra = cents % names.count
    var out: [String: Double] = [:]
    for (i, n) in names.enumerated() { out[n] = Double(base + (i < extra ? 1 : 0)) / 100 }
    return out
}

/// Saldo di ognuno nel viaggio: positivo = deve ricevere, negativo = deve dare.
func tripBalances(expenses: [Expense], payments: [TripPayment]) -> [String: Double] {
    var net: [String: Double] = [:]
    for e in expenses {
        let s = e.shares
        guard !s.isEmpty else { continue }   // spesa solo mia: nessun debito
        net[e.payer, default: 0] += e.amount
        for (n, v) in s { net[n, default: 0] -= v }
    }
    for p in payments {
        net[p.from, default: 0] += p.amount
        net[p.to, default: 0] -= p.amount
    }
    return net
}

struct Transfer: Identifiable, Equatable {
    let from: String
    let to: String
    let amount: Double
    var id: String { "\(from)->\(to)" }
}

/// Il minor numero di passaggi di soldi per pareggiare i conti.
func settleUp(_ net: [String: Double]) -> [Transfer] {
    var debtors = net.filter { $0.value < -0.005 }.map { ($0.key, -$0.value) }.sorted { $0.1 > $1.1 }
    var creditors = net.filter { $0.value > 0.005 }.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    var out: [Transfer] = []
    var i = 0, j = 0
    while i < debtors.count && j < creditors.count {
        let x = min(debtors[i].1, creditors[j].1)
        out.append(Transfer(from: debtors[i].0, to: creditors[j].0, amount: (x * 100).rounded() / 100))
        debtors[i].1 -= x; creditors[j].1 -= x
        if debtors[i].1 < 0.005 { i += 1 }
        if creditors[j].1 < 0.005 { j += 1 }
    }
    return out
}

/// Viaggi le cui spese non vanno nelle statistiche, nei limiti e nei riepiloghi.
func tripsOutOfStats(_ trips: [Trip]) -> Set<String> { Set(trips.filter { !$0.countInStats }.map(\.uid)) }

/// Spese che contano nelle statistiche (fuori quelle dei viaggi tenuti a parte).
func statExpenses(_ all: [Expense], trips: [Trip]) -> [Expense] {
    let out = tripsOutOfStats(trips)
    return out.isEmpty ? all : all.filter { !out.contains($0.tripID) }
}

/// Il viaggio in corso oggi, se c'è.
func activeTrip(_ trips: [Trip], now: Date = Date()) -> Trip? {
    trips.filter { $0.contains(now) }.sorted { $0.startDate > $1.startDate }.first
}

// MARK: - Cambio (dati della Banca Centrale Europea)

enum Rates {
    /// Valute pubblicate ogni giorno dalla BCE (più l'euro).
    static let currencies = ["EUR", "USD", "GBP", "CHF", "JPY", "CZK", "DKK", "HUF", "PLN", "RON", "SEK", "NOK", "ISK",
                             "TRY", "AUD", "BRL", "CAD", "CNY", "HKD", "IDR", "ILS", "INR", "KRW", "MXN", "MYR",
                             "NZD", "PHP", "SGD", "THB", "ZAR"]
    static let source = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    static let cacheKey = "ratesCache"
    static let cacheDateKey = "ratesCacheDate"

    /// Legge il file della BCE: currency='GBP' rate='0.8612'.
    static func parse(_ xml: String) -> [String: Double] {
        var out: [String: Double] = [:]
        let rx = try! NSRegularExpression(pattern: "currency=['\"]([A-Z]{3})['\"]\\s+rate=['\"]([0-9.]+)['\"]")
        for m in rx.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)) {
            guard let c = Range(m.range(at: 1), in: xml), let r = Range(m.range(at: 2), in: xml),
                  let v = Double(xml[r]), v > 0 else { continue }
            out[String(xml[c])] = v
        }
        return out
    }

    static var cached: [String: Double] {
        UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: Double] ?? [:]
    }

    /// Scarica i cambi del giorno (al massimo ogni 6 ore). Se non c'è rete restano quelli salvati.
    static func refresh(force: Bool = false) async {
        if !force, let d = UserDefaults.standard.object(forKey: cacheDateKey) as? Date,
           Date().timeIntervalSince(d) < 6 * 3600, !cached.isEmpty { return }
        var req = URLRequest(url: source)
        req.timeoutInterval = 8
        guard let result = try? await URLSession.shared.data(for: req),
              let xml = String(data: result.0, encoding: .utf8) else { return }
        let r = parse(xml)
        guard !r.isEmpty else { return }
        UserDefaults.standard.set(r, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheDateKey)
    }

    /// Cambio per una valuta (1 € = valore). Euro = 1. nil se non disponibile.
    static func rate(for code: String) async -> Double? {
        if code == "EUR" { return 1 }
        await refresh()
        return cached[code]
    }
}

/// Indica se l'importo arrivato come testo è già in euro (per esempio "€12,50" o "12,50 EUR").
func looksLikeEuro(_ raw: String) -> Bool {
    raw.contains("€") || raw.uppercased().contains("EUR")
}
