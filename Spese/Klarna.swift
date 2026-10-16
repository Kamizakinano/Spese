import Foundation
import SwiftData

// MARK: - Email di Klarna "Prossimo pagamento programmato"

/// Una rata del calendario scritto nell'email.
struct KlarnaRate: Equatable {
    var date: Date
    var amount: Double
}

/// Quello che dice l'email di Klarna qualche giorno prima di un addebito.
struct KlarnaEmail: Equatable {
    var amount: Double            // la rata in arrivo
    var date: Date                // giorno dell'addebito
    var merchant: String          // negozio ("" se non c'è)
    var reference: String         // riferimento dell'ordine Klarna (riconosce sempre lo stesso acquisto)
    var months: Int?              // "Paga in 12 mesi"
    var orderDate: Date?          // data dell'ordine
    var total: Double?            // totale dell'acquisto, interessi compresi
    var schedule: [KlarnaRate]    // questa rata e le successive scritte nell'email
}

private let klarnaMonths = ["gen": 1, "feb": 2, "mar": 3, "apr": 4, "mag": 5, "giu": 6,
                            "lug": 7, "ago": 8, "set": 9, "ott": 10, "nov": 11, "dic": 12]

private func klarnaMatch(_ pattern: String, in text: String) -> [String]? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: text).map { String(text[$0]) } ?? "" }
}

/// "17 ottobre 2026" (o "17 ott 2026") → data a mezzogiorno.
private func klarnaDate(_ day: String, _ month: String, _ year: Int) -> Date? {
    guard let d = Int(day), let m = klarnaMonths[String(month.lowercased().prefix(3))] else { return nil }
    return Calendar.current.date(from: DateComponents(year: year, month: m, day: d, hour: 12))
}

/// Legge l'email di Klarna che annuncia il prossimo addebito di un acquisto a rate.
/// nil se non è un'email di questo tipo.
func parseKlarnaEmail(subject: String, body: String) -> KlarnaEmail? {
    let text = (subject + "\n" + body).replacingOccurrences(of: "\u{00A0}", with: " ")
    let low = text.lowercased()
    guard low.contains("klarna") else { return nil }
    let money = #"(\d{1,3}(?:\.\d{3})*,\d{2}|\d+,\d{2})"#
    let date = #"(\d{1,2})\s+([a-zA-Z]+)\s+(\d{4})"#

    // "26,28 € saranno addebitati dalla tua carta **** 4833 il 17 ottobre 2026"
    // oppure "Il pagamento di 26,28 € per 3DJake sarà addebitato il 17 ottobre 2026"
    // oppure "Assicurati di avere 26,28 € disponibili sulla tua carta prima del 17 ottobre 2026"
    guard let m = klarnaMatch(money + #"\s*€\s*saranno addebitati[^\n]*?\bil\s+"# + date, in: text)
            ?? klarnaMatch(#"pagamento di\s+"# + money + #"\s*€[^\n]*?sarà addebitato\s+il\s+"# + date, in: text)
            ?? klarnaMatch(money + #"\s*€\s*disponibili[^\n]*?prima del\s+"# + date, in: text),
          let amount = parseLooseAmount(m[1]), amount > 0,
          let year = Int(m[4]), let due = klarnaDate(m[2], m[3], year) else { return nil }

    var merchant = ""
    if let r = klarnaMatch(#"pagamento automatico per\s+(.+?)\s+sta per arrivare"#, in: text)
        ?? klarnaMatch(#"pagamento di\s+"# + money + #"\s*€\s+per\s+(.+?)\s+sarà addebitato"#, in: text) {
        merchant = r[r.count - 1].trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let reference = klarnaMatch(#"riferimento dell'ordine klarna\s+([A-Z0-9]+)"#, in: text)?[1] ?? ""
    let months = klarnaMatch(#"paga in\s+(\d+)\s+(?:mesi|rate)"#, in: text).flatMap { Int($0[1]) }
    let orderDate = klarnaMatch(#"data dell'ordine\s+"# + date, in: text).flatMap { r in Int(r[3]).flatMap { klarnaDate(r[1], r[2], $0) } }
    let total = klarnaMatch(#"\btotale\s+"# + money, in: text).flatMap { parseLooseAmount($0[1]) }

    // Tabella delle rate: una riga "Pagato  Pagato  17 ott  17 nov" e sotto gli importi.
    var schedule: [KlarnaRate] = []
    let lines = text.components(separatedBy: .newlines)
    for (i, line) in lines.enumerated() {
        let heads = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard heads.count >= 2, heads.allSatisfy({ $0.lowercased() == "pagato" || klarnaMatch(#"^\d{1,2}\s+[a-zA-Z]{3}$"#, in: $0) != nil }),
              let next = lines[(i + 1)...].first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { continue }
        let amounts = next.components(separatedBy: "\t").compactMap { klarnaMatch("^\\s*" + money, in: $0).flatMap { parseLooseAmount($0[1]) } }
        guard amounts.count == heads.count else { continue }
        var y = year, lastMonth = Calendar.current.component(.month, from: due)
        for (h, a) in zip(heads, amounts) where h.lowercased() != "pagato" {
            let p = h.split(separator: " ").map(String.init)
            guard let mm = klarnaMonths[p[1].lowercased()] else { continue }
            if mm < lastMonth { y += 1 }        // dicembre → gennaio: anno dopo
            lastMonth = mm
            if let d = klarnaDate(p[0], p[1], y) { schedule.append(KlarnaRate(date: d, amount: a)) }
        }
        break
    }
    if !schedule.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: due) }) {
        schedule.insert(KlarnaRate(date: due, amount: amount), at: 0)
    }
    schedule = schedule.filter { $0.date >= due }.sorted { $0.date < $1.date }
    return KlarnaEmail(amount: amount, date: due, merchant: merchant, reference: reference, months: months,
                       orderDate: orderDate, total: total, schedule: schedule)
}

/// Numero della rata in arrivo, ricavato dalla data dell'ordine (una rata al mese dal mese dopo). nil se non si sa.
func klarnaRateIndex(_ k: KlarnaEmail) -> Int? {
    guard let o = k.orderDate, let n = k.months else { return nil }
    let cal = Calendar.current
    let a = cal.dateComponents([.year, .month], from: o), b = cal.dateComponents([.year, .month], from: k.date)
    let diff = ((b.year ?? 0) - (a.year ?? 0)) * 12 + (b.month ?? 0) - (a.month ?? 0)
    return min(max(diff, 1), n)
}

/// Registra l'email di Klarna: mette la rata (e le successive scritte nell'email) al giorno giusto.
/// Se le rate c'erano già (anche inserite a mano) le sposta, altrimenti crea l'acquisto. Restituisce cosa è stato fatto.
@MainActor
func recordKlarnaPayment(_ k: KlarnaEmail, ctx: ModelContext) throws -> String {
    let all = (try? ctx.fetch(FetchDescriptor<Expense>())) ?? []
    let day: Double = 86400
    let refID = k.reference.isEmpty ? "" : "klarna-" + k.reference
    // Rate inserite a mano: l'importo può differire di qualche centesimo (arrotondamenti).
    var plan = refID.isEmpty ? [] : all.filter { $0.planID == refID }
    if plan.isEmpty,   // rate inserite a mano: stesso importo, data vicina
       let r = all.filter({ !$0.planID.isEmpty && $0.planProvider == "Klarna" && abs($0.amount - k.amount) <= max(0.5, k.amount * 0.03)
                            && abs($0.date.timeIntervalSince(k.date)) <= 20 * day })
                  .min(by: { abs($0.date.timeIntervalSince(k.date)) < abs($1.date.timeIntervalSince(k.date)) }) {
        plan = all.filter { $0.planID == r.planID }
    }
    let when = k.date.formatted(.dateTime.day().month(.wide))

    if let first = plan.first {
        var used: [Expense] = []
        var added = 0
        for s in k.schedule {
            let free = plan.filter { e in !used.contains { $0 === e } && abs(e.date.timeIntervalSince(s.date)) <= 20 * day }
            if let r = free.min(by: { abs($0.date.timeIntervalSince(s.date)) < abs($1.date.timeIntervalSince(s.date)) }) {
                r.date = s.date; r.amount = s.amount
                used.append(r)
            } else {
                let e = Expense(amount: s.amount, categoryName: installmentCategory, date: s.date, note: "")
                e.method = "carta"
                e.planID = first.planID; e.planName = first.planName; e.planProvider = "Klarna"
                e.planIndex = (plan.map(\.planIndex).max() ?? 0) + 1; e.planTotal = first.planTotal
                ctx.insert(e); plan.append(e); used.append(e); added += 1
            }
        }
        renumber(plan)
        try ctx.save()
        return "Rata Klarna: \(first.planName), \(eur(k.amount)) il \(when)." + (added > 0 ? " Aggiunte \(added) rate." : " Rate allineate alle date di Klarna.")
    }

    // Nessun acquisto: lo crea con le rate scritte nell'email.
    let name = k.merchant.isEmpty ? "Klarna" : k.merchant
    let id = refID.isEmpty ? UUID().uuidString : refID
    let count = max(k.months ?? k.schedule.count, k.schedule.count)
    let start = klarnaRateIndex(k) ?? (count - k.schedule.count + 1)
    let total = k.total ?? k.schedule.reduce(0) { $0 + $1.amount }
    for (i, s) in k.schedule.enumerated() {
        let index = min(start + i, count)
        let e = Expense(amount: s.amount, categoryName: installmentCategory, date: s.date, note: "\(name) · rata \(index) di \(count)")
        e.method = "carta"
        e.planID = id; e.planName = name; e.planProvider = "Klarna"
        e.planIndex = index; e.planCount = count; e.planTotal = total
        ctx.insert(e)
    }
    try ctx.save()
    return "Nuovo acquisto a rate Klarna: \(name), \(eur(k.amount)) il \(when)."
        + (k.schedule.count > 1 ? " Aggiunte anche le \(k.schedule.count - 1) rate successive." : "")
}
