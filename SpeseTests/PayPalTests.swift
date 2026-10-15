import XCTest
import SwiftData
@testable import Spese

/// Prove dell'email di PayPal "Paga a rate" (testo vero, ottobre 2026).
final class PayPalTests: XCTestCase {
    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: day, hour: h))!
    }

    static let subject = "Il pagamento relativo al piano Paga a rate è stato ricevuto"
    static let body = """
    Abbiamo ricevuto il tuo pagamento relativo al piano Paga a rate
    Hai effettuato un pagamento di 28,60 € EUR per il finanziamento Paga a rate. L'importo è stato addebitato sul metodo di pagamento Carta di debito x-4833 in data 15 ottobre 2026.
    Ecco i dettagli:
    Importo del pagamento
    28,60 € EUR
    Metodo di pagamento
    INTESA SANPAOLO SPA
    Carta di debito
    x-4833
    Numero di riferimento addebito diretto
    Creditore
    PayPal (Europe) S.à r.l. et Cie, S.C.A.
    Inviato in data
    15 ottobre 2026
    Commerciante
    Bambulab GmbH
    Saldo attuale del finanziamento
    514,80 € EUR
    Ecco un promemoria dei prossimi pagamenti pianificati:
    28,60 € EUR in data 15 novembre 2026
    28,60 € EUR in data 15 dicembre 2026
    28,60 € EUR in data 15 gennaio 2027
    28,60 € EUR in data 15 febbraio 2027
    28,60 € EUR in data 15 marzo 2027
    28,60 € EUR in data 15 aprile 2027
    Il piano di rimborso completo è disponibile nel tuo contratto di rateizzazione.
    """

    func testLetturaEmail() throws {
        let p = try XCTUnwrap(parsePayPalInstallmentEmail(subject: Self.subject, body: Self.body))
        XCTAssertEqual(p.amount, 28.60, accuracy: 0.001)
        XCTAssertEqual(p.date, d(2026, 10, 15))
        XCTAssertEqual(p.merchant, "Bambulab GmbH")
        XCTAssertEqual(p.balance ?? 0, 514.80, accuracy: 0.001)
        XCTAssertEqual(p.upcoming.count, 6)
        XCTAssertEqual(p.upcoming.first, d(2026, 11, 15))
        XCTAssertEqual(remainingRates(p), 18)
        let dates = futureRateDates(p, after: d(2026, 10, 15), count: 18)
        XCTAssertEqual(dates.count, 18)
        XCTAssertEqual(dates.last, d(2028, 4, 15))
    }

    func testEmailDellaBancaNonEPayPal() {
        XCTAssertNil(parsePayPalInstallmentEmail(subject: "Pagamento con carta", body: "Pagamento di 12,50 euro presso Conad"))
    }

    @MainActor
    func testCreaLAcquistoDallEmail() throws {
        let ctx = SharedStore.container.mainContext
        defer {
            for e in (try? ctx.fetch(FetchDescriptor<Expense>())) ?? [] where e.planName == "Bambulab GmbH" { ctx.delete(e) }
            try? ctx.save()
        }
        let p = try XCTUnwrap(parsePayPalInstallmentEmail(subject: Self.subject, body: Self.body))
        let msg = try recordPayPalInstallment(p, ctx: ctx, now: d(2026, 10, 15, 9))
        XCTAssertTrue(msg.contains("Nuovo acquisto"))
        let rates = try ctx.fetch(FetchDescriptor<Expense>()).filter { $0.planName == "Bambulab GmbH" }
        XCTAssertEqual(rates.count, 19)
        XCTAssertEqual(rates.reduce(0) { $0 + $1.amount }, 543.40, accuracy: 0.001)
        XCTAssertTrue(rates.allSatisfy { $0.planProvider == "PayPal" && $0.planCount == 19 })

        // Una seconda email uguale (o quella di Intesa) non crea doppioni.
        _ = try recordPayPalInstallment(p, ctx: ctx, now: d(2026, 10, 15, 10))
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Expense>()).filter { $0.planName == "Bambulab GmbH" }.count, 19)
        let bank = BankEmail(kind: .expense, amount: 28.60, merchant: "PAYPAL", date: d(2026, 10, 15), salary: false)
        let r = try recordBankEmail(bank, ctx: ctx, now: d(2026, 10, 15, 11))
        XCTAssertTrue(r.contains("Bambulab"), "L'addebito in banca è la stessa rata")

        // Rate pagate prima: 5 → la prima diventa la rata 6 di 24.
        let all = try ctx.fetch(FetchDescriptor<Expense>()).filter { $0.planName == "Bambulab GmbH" }
        updateInstallmentPaidBefore(all, before: 5)
        XCTAssertEqual(all.map(\.planIndex).min(), 6)
        XCTAssertTrue(all.allSatisfy { $0.planCount == 24 })
    }
}
