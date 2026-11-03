import Foundation
import SwiftData

// MARK: - Email di PayPal "Paga a rate"

/// Quello che dice l'email di PayPal dopo il pagamento di una rata.
struct PayPalInstallmentEmail: Equatable {
    var amount: Double            // la rata pagata
    var date: Date?               // giorno dell'addebito
    var merchant: String          // commerciante ("" se non c'è)
    var balance: Double?          // quanto manca dopo questa rata
    var upcoming: [Date]          // date delle prossime rate elencate nell'email
}

private let italianMonths = ["gennaio": 1, "febbraio": 2, "marzo": 3, "aprile": 4, "maggio": 5, "giugno": 6,
                             "luglio": 7, "agosto": 8, "settembre": 9, "ottobre": 10, "novembre": 11, "dicembre": 12]

private func matches(_ pattern: String, in text: String) -> [[String]] {
    guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
    return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
        (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: text).map { String(text[$0]) } ?? "" }
    }
}

/// "15 ottobre 2026" → data (a mezzogiorno).
private func italianDate(_ day: String, _ month: String, _ year: String) -> Date? {
    guard let d = Int(day), let m = italianMonths[month.lowercased()], let y = Int(year) else { return nil }
    return Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12))
}

/// Legge l'email di PayPal per il pagamento di una rata (piano "Paga a rate" o "Paga in 3 rate").
/// nil se non è un'email di questo tipo.
func parsePayPalInstallmentEmail(subject: String, body: String) -> PayPalInstallmentEmail? {
    let text = (subject + "\n" + body).replacingOccurrences(of: "\u{00A0}", with: " ")
    let low = text.lowercased()
    guard low.contains("paga a rate") || low.contains("paga in 3 rate"), low.contains("pagamento") else { return nil }
    let money = #"(\d{1,3}(?:\.\d{3})*,\d{2}|\d+,\d{2})"#
    guard let raw = matches(#"pagamento di\s+"# + money, in: text).first?[1]
            ?? matches(#"importo del pagamento\s+"# + money, in: text).first?[1],
          let amount = parseLooseAmount(raw), amount > 0 else { return nil }

    let dateRx = #"(\d{1,2})\s+([a-zA-Z]+)\s+(\d{4})"#
    let date = (matches(#"addebitato.*?in data\s+"# + dateRx, in: text).first
                ?? matches(#"inviato in data\s+"# + dateRx, in: text).first)
        .flatMap { italianDate($0[1], $0[2], $0[3]) }

    var merchant = ""
    if let m = matches(#"commerciante\s*:?\s*(.+?)(?=\s*\n|\s+saldo attuale|$)"#, in: text).first {
        merchant = m[1].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
    let balance = matches(#"saldo attuale del finanziamento\s+"# + money, in: text).first.flatMap { parseLooseAmount($0[1]) }
    let upcoming = matches(money + #"\s*€?\s*EUR\s+in data\s+"# + dateRx, in: text)
        .compactMap { italianDate($0[2], $0[3], $0[4]) }
        .sorted()
    return PayPalInstallmentEmail(amount: amount, date: date, merchant: merchant, balance: balance, upcoming: upcoming)
}

/// Quante rate mancano dopo quella pagata.
func remainingRates(_ p: PayPalInstallmentEmail) -> Int {
    if let b = p.balance, p.amount > 0 { return max(Int((b / p.amount).rounded()), 0) }
    return p.upcoming.count
}

/// Le date delle rate future: quelle scritte nell'email e poi una al mese.
func futureRateDates(_ p: PayPalInstallmentEmail, after paid: Date, count: Int) -> [Date] {
    var out = Array(p.upcoming.filter { $0 > paid }.prefix(count))
    var last = out.last ?? paid
    let cal = Calendar.current
    while out.count < count {
        last = cal.date(byAdding: .month, value: 1, to: last) ?? last
        out.append(last)
    }
    return out
}

/// Riscrive "Nome · rata X di Y" su tutte le rate dell'acquisto.
func renumber(_ rates: [Expense]) {
    let count = rates.map(\.planIndex).max() ?? rates.count
    for e in rates {
        e.planCount = count
        e.note = "\(e.planName) · rata \(e.planIndex) di \(count)"
    }
}

/// Registra l'email di PayPal: segna pagata la rata (o crea l'acquisto se non c'è) e
/// allinea le rate future al saldo scritto nell'email. Restituisce cosa è stato fatto.
@MainActor
func recordPayPalInstallment(_ p: PayPalInstallmentEmail, ctx: ModelContext, now: Date = Date()) throws -> String {
    let cal = Calendar.current
    let when: Date = {
        guard let d = p.date, !cal.isDate(d, inSameDayAs: now) else { return now }
        return d
    }()
    let all = (try? ctx.fetch(FetchDescriptor<Expense>())) ?? []
    let remaining = remainingRates(p)

    // La stessa spesa già entrata dall'email della banca (addebito PayPal): la rata la sostituisce.
    for e in all where e.planID.isEmpty && abs(e.amount - p.amount) < 0.005
        && abs(e.date.timeIntervalSince(when)) < 2 * 86400 && e.note.localizedCaseInsensitiveContains("paypal") {
        ctx.delete(e)
    }

    // 1. C'è già un acquisto PayPal con una rata di questo importo vicina a questa data?
    let candidates = all.filter {
        !$0.planID.isEmpty && $0.planProvider == "PayPal" && abs($0.amount - p.amount) < 0.005
            && abs($0.date.timeIntervalSince(when)) <= 6 * 86400
    }
    if let rate = candidates.min(by: { abs($0.date.timeIntervalSince(when)) < abs($1.date.timeIntervalSince(when)) }) {
        if rate.date > when { rate.date = when }
        var rates = all.filter { $0.planID == rate.planID }
        // Rate future allineate al saldo dell'email.
        let future = rates.filter { $0.date > when && $0 !== rate }.sorted { $0.date < $1.date }
        if p.balance != nil || !p.upcoming.isEmpty {
            if future.count > remaining {
                for e in future.suffix(future.count - remaining) { ctx.delete(e) }
                rates.removeAll { e in future.suffix(future.count - remaining).contains { $0 === e } }
            } else if future.count < remaining {
                let lastIndex = rates.map(\.planIndex).max() ?? 0
                let dates = futureRateDates(p, after: future.last?.date ?? when, count: remaining - future.count)
                for (i, d) in dates.enumerated() {
                    let e = Expense(amount: p.amount, categoryName: installmentCategory, date: d, note: "")
                    e.method = "carta"
                    e.planID = rate.planID; e.planName = rate.planName; e.planProvider = "PayPal"
                    e.planIndex = lastIndex + i + 1; e.planTotal = rate.planTotal
                    ctx.insert(e); rates.append(e)
                }
            }
            renumber(rates)
        }
        try ctx.save()
        let left = rates.filter { $0.date > when }
        return "Rata PayPal pagata: \(rate.planName), rata \(rate.planIndex) di \(rate.planCount)."
            + (left.isEmpty ? " Acquisto finito." : " Mancano \(left.count) rate, \(eur(left.reduce(0) { $0 + $1.amount })).")
    }

    // 2. Nessun acquisto: lo crea dall'email, con questa rata pagata e le altre in arrivo.
    let name = p.merchant.isEmpty ? "PayPal" : p.merchant
    let id = UUID().uuidString
    let count = 1 + remaining
    let total = p.amount + (p.balance ?? p.amount * Double(remaining))
    func rate(_ index: Int, _ amount: Double, _ date: Date) -> Expense {
        let e = Expense(amount: amount, categoryName: installmentCategory, date: date, note: "\(name) · rata \(index) di \(count)")
        e.method = "carta"
        e.planID = id; e.planName = name; e.planProvider = "PayPal"
        e.planIndex = index; e.planCount = count; e.planTotal = total
        return e
    }
    ctx.insert(rate(1, p.amount, when))
    let dates = futureRateDates(p, after: when, count: remaining)
    for (i, d) in dates.enumerated() {
        var amount = p.amount
        if i == dates.count - 1, let b = p.balance {   // l'ultima assorbe i centesimi
            amount = ((b - p.amount * Double(remaining - 1)) * 100).rounded() / 100
        }
        ctx.insert(rate(i + 2, amount, d))
    }
    try ctx.save()
    return "Nuovo acquisto a rate PayPal: \(name), rata 1 di \(count) pagata."
        + (remaining > 0 ? " Mancano \(remaining) rate, \(eur(p.balance ?? p.amount * Double(remaining)))." : "")
        + " Se avevi già pagato altre rate, correggilo in Conti → Pagamenti a rate."
}

/// Cambia quante rate erano già state pagate prima di inserire l'acquisto: rinumera tutte le rate.
func updateInstallmentPaidBefore(_ rates: [Expense], before: Int) {
    guard let minIndex = rates.map(\.planIndex).min() else { return }
    let delta = max(before, 0) - (minIndex - 1)
    guard delta != 0 else { return }
    let rateAmount = rates.sorted { $0.planIndex < $1.planIndex }.first?.amount ?? 0
    for e in rates {
        e.planIndex += delta
        e.planTotal += Double(delta) * rateAmount
    }
    renumber(rates)
}

// MARK: - Soldi inviati con PayPal a una persona (SMS dal 43111)

/// "PayPal: hai inviato 25,00 € EUR a Alessandro bosio . Accedi…" → importo e persona.
/// nil se il testo non è di questo tipo.
func parsePayPalSentMessage(_ text: String) -> (amount: Double, person: String)? {
    let t = text.replacingOccurrences(of: "\u{00A0}", with: " ")
    guard let m = matches(#"hai inviato\s+€?\s*(\d{1,3}(?:\.\d{3})*(?:,\d{1,2})?|\d+(?:[.,]\d{1,2})?)\s*(?:€\s*)?(?:EUR\s*)?a\s+(.+?)\s*(?:\.|$|\n)"#, in: t).first,
          let amount = parseLooseAmount(m[1]), amount > 0 else { return nil }
    let person = m[2].trimmingCharacters(in: .whitespacesAndNewlines)
    return person.isEmpty ? nil : (amount, person)
}

/// Registra i soldi inviati con PayPal come spesa in "Altro", con il nome della persona nella nota.
@MainActor
func recordPayPalSent(amount: Double, person: String, ctx: ModelContext, now: Date = Date()) throws -> String {
    let all = (try? ctx.fetch(FetchDescriptor<Expense>())) ?? []
    if isLikelyDuplicate(amount: amount, merchant: person, when: now, expenses: all) {
        return "Già registrata (stesso pagamento): ignorata"
    }
    let e = Expense(amount: amount, categoryName: otherCategory, date: now, note: person)
    e.method = "carta"
    ctx.insert(e)
    try ctx.save()
    return "Spesa registrata: \(eur(amount)) a \(person)"
}
