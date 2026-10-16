import Foundation
import SwiftData
import AppIntents

// MARK: - Lettura delle email della banca

/// Cosa dice un'email della banca.
enum BankEmailKind: Equatable {
    case expense      // pagamento con carta, addebito, bonifico inviato
    case income       // bonifico o accredito ricevuto
    case withdrawal   // prelievo di contanti
}

struct BankEmail: Equatable {
    var kind: BankEmailKind
    var amount: Double
    var merchant: String    // esercente o beneficiario ("" se non c'è)
    var date: Date?         // data scritta nell'email, se c'è
    var salary: Bool        // l'accredito sembra uno stipendio
}

private func firstMatch(_ pattern: String, in text: String) -> [String]? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    return (0..<m.numberOfRanges).map { i in
        Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
    }
}

/// Legge oggetto e testo di un'email della banca (scritta come quelle di Intesa Sanpaolo):
/// tipo di movimento, importo, esercente e data. nil se non parla di un movimento di soldi.
func parseBankEmail(subject: String, body: String) -> BankEmail? {
    let text = (subject + "\n" + body).replacingOccurrences(of: "\u{00A0}", with: " ")
    let low = text.lowercased()

    // Importo: "12,50 euro", "1.234,56 EUR", "€ 12,50", "EUR 12,50".
    let num = #"(\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d+(?:[.,]\d{1,2})?)"#
    guard var raw = firstMatch(num + #"\s*(?:euro|eur|€)"#, in: text)?[1] ?? firstMatch(#"(?:€|eur)\s*"# + num, in: text)?[1]
    else { return nil }
    // "1.234 euro": il punto separa le migliaia, non i decimali.
    if !raw.contains(","), firstMatch(#"^\d{1,3}(?:\.\d{3})+$"#, in: raw) != nil { raw = raw.replacingOccurrences(of: ".", with: "") }
    guard let amount = parseLooseAmount(raw), amount > 0 else { return nil }

    let kind: BankEmailKind
    if low.contains("prelievo") || low.contains("prelevat") {
        kind = .withdrawal
    } else if low.contains("accredit") || low.contains("ricevuto un bonifico") || low.contains("rimborso") {
        kind = .income
    } else if ["pagamento", "utilizzo", "addebit", "acquisto", "bonifico", "transazione", "spesa", "operazione"]
                .contains(where: low.contains) {
        kind = .expense
    } else {
        return nil
    }

    // Esercente o beneficiario: dopo "presso", "c/o", "esercente", "a favore di"…
    var merchant = ""
    if let m = firstMatch(#"(?:presso|c/o|esercente:?|a favore di|beneficiario:?|verso)\s+(.+?)(?=\s+(?:in data|il giorno|il|alle ore|alle|del|con la carta|con carta|tramite|sul conto|dal conto|per un importo)\b|[.;\n]|\s+-\s|$)"#, in: text) {
        merchant = m[1].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    // Data: "in data 10.10.2026" o "10/10/2026".
    var date: Date?
    if let d = firstMatch(#"(\d{1,2})[./](\d{1,2})[./](\d{4})"#, in: text),
       let dd = Int(d[1]), let mm = Int(d[2]), let yy = Int(d[3]) {
        date = Calendar.current.date(from: DateComponents(year: yy, month: mm, day: dd, hour: 12))
    }

    let salary = kind == .income && ["stipendio", "emolument", "retribuzione", "busta paga"].contains(where: low.contains)
    return BankEmail(kind: kind, amount: amount, merchant: merchant, date: date, salary: salary)
}

/// Data da usare per il movimento: adesso se l'email parla di oggi, altrimenti il giorno scritto.
private func movementDate(_ d: Date?, now: Date = Date()) -> Date {
    guard let d, !Calendar.current.isDate(d, inSameDayAs: now) else { return now }
    return d
}

/// Registra il movimento letto da un'email. Restituisce cosa è stato fatto (va nel registro).
@MainActor
func recordBankEmail(_ e: BankEmail, ctx: ModelContext, now: Date = Date()) throws -> String {
    let when = movementDate(e.date, now: now)
    let cal = Calendar.current
    switch e.kind {
    case .expense:
        // È una rata di un acquisto a rate (es. l'addebito PayPal)? Si segna pagata, senza una spesa in più.
        let rates = ((try? ctx.fetch(FetchDescriptor<Expense>())) ?? []).filter {
            !$0.planID.isEmpty && abs($0.amount - e.amount) < 0.005 && abs($0.date.timeIntervalSince(when)) <= 3 * 86400
        }
        if let r = rates.min(by: { abs($0.date.timeIntervalSince(when)) < abs($1.date.timeIntervalSince(when)) }) {
            if r.date > when { r.date = when }
            try ctx.save()
            return "È la rata \(r.planIndex) di \(r.planCount) di \(r.planName): segnata pagata"
        }
        // È una spesa ricorrente (mutuo, affitto…) addebitata qualche giorno dopo il previsto? Va al giorno vero.
        if let msg = matchRecurringPayment(amount: e.amount, when: when, ctx: ctx) {
            try ctx.save()
            return msg
        }
        // Già entrata da Apple Pay (stesso importo, pochi minuti prima o dopo)? Non si conta due volte.
        let near = ((try? ctx.fetch(FetchDescriptor<Expense>())) ?? []).contains {
            abs($0.amount - e.amount) < 0.005 && abs($0.date.timeIntervalSince(when)) < 30 * 60
        }
        if near { return "Già registrata (stesso importo, stessa ora): ignorata" }
        let cats = (try? ctx.fetch(FetchDescriptor<CategoryItem>(sortBy: [SortDescriptor(\.order)]))) ?? []
        let cat = guessCategory(merchant: e.merchant, available: cats.map { $0.name })
        let x = Expense(amount: e.amount, categoryName: cat, date: when, note: e.merchant)
        x.method = "carta"
        applyActiveTrip(x, raw: "€", trips: (try? ctx.fetch(FetchDescriptor<Trip>())) ?? []) { _ in nil }
        ctx.insert(x)
        try ctx.save()
        return "Spesa registrata: \(eur(e.amount)) in \(cat)"

    case .income:
        let incomes = (try? ctx.fetch(FetchDescriptor<Income>())) ?? []
        if e.salary {
            let auto = ((try? ctx.fetch(FetchDescriptor<Account>()))?.first?.salaryAmount ?? 0) > 0
            if auto { return "Stipendio: già inserito in automatico ogni mese, ignorato" }
        }
        let kind = e.salary ? "Stipendio" : "Altra entrata"
        let dup = incomes.contains { $0.kind == kind && abs($0.amount - e.amount) < 0.005 && cal.isDate($0.date, inSameDayAs: when) }
        if dup { return "Entrata già registrata oggi: ignorata" }
        // Già segnato come "Incassato" in Ti devono (sul conto): è quel rimborso, non un'entrata in più.
        let refund = incomes.contains { $0.kind == "Rimborso" && abs($0.amount - e.amount) < 0.005 && abs($0.date.timeIntervalSince(when)) < 7 * 86400 }
        if refund { return "Rimborso già segnato come incassato: ignorata" }
        let note = e.salary ? "Stipendio" : (e.merchant.isEmpty ? "Bonifico ricevuto" : "Bonifico da \(e.merchant)")
        ctx.insert(Income(amount: e.amount, saved: 0, kind: kind, date: when, note: note))
        try ctx.save()
        return "Entrata registrata: \(eur(e.amount))"

    case .withdrawal:
        let moves = (try? ctx.fetch(FetchDescriptor<CashMove>())) ?? []
        let dup = moves.contains { $0.kind == "prelievo" && abs($0.amount - e.amount) < 0.005 && abs($0.date.timeIntervalSince(when)) < 30 * 60 }
        if dup { return "Prelievo già registrato: ignorato" }
        ctx.insert(CashMove(amount: e.amount, date: when, note: "Prelievo", kind: "prelievo", bank: true))
        try ctx.save()
        return "Prelievo registrato: \(eur(e.amount)) dalla banca ai contanti"
    }
}

/// L'addebito di una spesa ricorrente (es. il mutuo del giorno 1 che la banca addebita lunedì 3):
/// stesso importo (con uno scarto fino al 2%, per le rate che cambiano) e al massimo 6 giorni di distanza.
/// Se la spesa del mese c'è già la sposta al giorno dell'addebito, se non c'è ancora la crea lì.
@MainActor
func matchRecurringPayment(amount: Double, when: Date, ctx: ModelContext) -> String? {
    let cal = Calendar.current
    let window: TimeInterval = 6 * 86400
    func close(_ a: Double) -> Bool { abs(a - amount) <= max(0.01, a * 0.02) }
    let recurring = ((try? ctx.fetch(FetchDescriptor<Recurring>())) ?? []).filter { close($0.amount) }
    guard !recurring.isEmpty else { return nil }
    let expenses = (try? ctx.fetch(FetchDescriptor<Expense>())) ?? []
    let names = Set(recurring.map { $0.name.lowercased() })
    func dayText(_ d: Date) -> String { d.formatted(.dateTime.weekday(.wide).day().month(.wide)) }

    // 1. La spesa del mese è già stata inserita (il giorno previsto): si sposta al giorno dell'addebito.
    let generated = expenses.filter {
        names.contains($0.note.lowercased()) && close($0.amount) && abs($0.date.timeIntervalSince(when)) <= window
    }
    if let x = generated.min(by: { abs($0.date.timeIntervalSince(when)) < abs($1.date.timeIntervalSince(when)) }) {
        if cal.isDate(x.date, inSameDayAs: when) { return "\(x.note) già registrato oggi: ignorata" }
        let old = x.date
        x.date = when
        x.amount = amount
        return "\(x.note) pagato: \(eur(amount)). Spostato da \(dayText(old)) a \(dayText(when)), il giorno dell'addebito."
    }

    // 2. Non è ancora stata inserita (l'app non è stata aperta): si inserisce nel giorno dell'addebito.
    for r in recurring {
        guard let due = nextRenewal(nextKey: r.nextKey, day: r.day), abs(due.timeIntervalSince(when)) <= window else { continue }
        let x = Expense(amount: amount, categoryName: r.categoryName, date: when, note: r.name)
        x.method = "carta"
        ctx.insert(x)
        r.nextKey = nextMonthKey(r.nextKey)
        return "\(r.name) pagato: \(eur(amount)), registrato \(dayText(when)) (era previsto \(dayText(due)))."
    }
    return nil
}

/// Azione per l'automazione "Email" di Comandi rapidi: legge l'email della banca e registra il movimento.
struct AddFromBankEmailIntent: AppIntent {
    static let title: LocalizedStringResource = "Leggi email della banca"
    static let description = IntentDescription("Legge un'email della banca (pagamento, bonifico, prelievo) di PayPal (rata di Paga a rate) o di Klarna (prossimo pagamento) e registra il movimento in Spese.")
    static let openAppWhenRun = false

    @Parameter(title: "Oggetto", default: "") var subject: String
    @Parameter(title: "Testo") var body: String

    static var parameterSummary: some ParameterSummary {
        Summary("Leggi email della banca \(\.$body)") { \.$subject }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let excerpt = String((subject + " — " + body).prefix(300))
        let entry = ApplePayLog.begin(amount: excerpt, merchant: "", source: "Email")
        // Email di Klarna che annuncia il prossimo addebito di una rata.
        if let k = parseKlarnaEmail(subject: subject, body: body) {
            do {
                let ctx = SharedStore.container.mainContext
                let result = try recordKlarnaPayment(k, ctx: ctx)
                ApplePayLog.finish(entry, result)
                updateWidgetSnapshot(ctx)
                runAutoBackup(ctx)
                notify("Klarna", result)
            } catch {
                ApplePayLog.finish(entry, "Errore nel salvataggio: \(error.localizedDescription)")
                throw error
            }
            return .result()
        }
        // Email di PayPal per una rata di "Paga a rate".
        if let p = parsePayPalInstallmentEmail(subject: subject, body: body) {
            do {
                let ctx = SharedStore.container.mainContext
                let result = try recordPayPalInstallment(p, ctx: ctx)
                ApplePayLog.finish(entry, result)
                updateWidgetSnapshot(ctx)
                runAutoBackup(ctx)
                notify("PayPal", result)
            } catch {
                ApplePayLog.finish(entry, "Errore nel salvataggio: \(error.localizedDescription)")
                throw error
            }
            return .result()
        }
        guard let e = parseBankEmail(subject: subject, body: body) else {
            // Email della banca che non parla di soldi (avvisi, pubblicità): nessun errore, solo una riga nel registro.
            ApplePayLog.finish(entry, "Non è un movimento: ignorata")
            return .result()
        }
        do {
            let ctx = SharedStore.container.mainContext
            let result = try recordBankEmail(e, ctx: ctx)
            ApplePayLog.finish(entry, result + (e.merchant.isEmpty ? "" : " · \(e.merchant)"))
            updateWidgetSnapshot(ctx)
            runAutoBackup(ctx)
            if UserDefaults.standard.bool(forKey: applePayNotifyKey), !result.contains("ignorat") {
                notify("Dalla banca", result)
            }
        } catch {
            ApplePayLog.finish(entry, "Errore nel salvataggio: \(error.localizedDescription)")
            throw error
        }
        return .result()
    }
}
