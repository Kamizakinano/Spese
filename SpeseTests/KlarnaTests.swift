import XCTest
import SwiftData
@testable import Spese

/// Prove dell'email di Klarna "Prossimo pagamento programmato" (testo vero, ottobre 2026) e del totale del viaggio.
final class KlarnaTests: XCTestCase {
    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: day, hour: h))!
    }

    static let subject = "Prossimo pagamento programmato per 3DJake"
    static let body = """
    Prossimo pagamento programmato
    \u{00A0}
    Ciao Salvo! Il prossimo pagamento automatico per 3DJake sta per arrivare.
    \u{00A0}
    \t
    26,28 € saranno addebitati dalla tua carta **** 4833 il 17 ottobre 2026.
    \u{00A0}
    \u{00A0}
    Pagato\tPagato\t17 ott\t17 nov
    26,28 €\t26,28 €\t26,28 €\t25,88 €
    \u{00A0}
    Paga ora
    \u{00A0}
    Riepilogo
    \u{00A0}
    \t
    3DJake
    Riferimento dell'ordine del brand
    254901442452
    Riferimento dell'ordine Klarna
    PLS6MMBG
    Data dell'ordine
    13 novembre 2025
    Metodo di pagamento
    Mastercard\t
    **** 4833
    Opzioni di pagamento
    Paga in 12 mesi
    \u{00A0}
    Dettagli ordine
    \t
    Bambu Lab AMS 2 Pro
    275,80 €
    \t
    3DJAKE Inserti Filettati - Set di 50 Pezzi
    3,56 €
    Spedizione
    12,00 €
    Interesse (15.90% TAEG)
    23,60 €
    Totale
    314,96 €
    """

    func testLetturaEmail() throws {
        let k = try XCTUnwrap(parseKlarnaEmail(subject: Self.subject, body: Self.body))
        XCTAssertEqual(k.amount, 26.28, accuracy: 0.001)
        XCTAssertEqual(k.date, d(2026, 10, 17))
        XCTAssertEqual(k.merchant, "3DJake")
        XCTAssertEqual(k.reference, "PLS6MMBG")
        XCTAssertEqual(k.months, 12)
        XCTAssertEqual(k.orderDate, d(2025, 11, 13))
        XCTAssertEqual(k.total ?? 0, 314.96, accuracy: 0.001)
        XCTAssertEqual(k.schedule, [KlarnaRate(date: d(2026, 10, 17), amount: 26.28), KlarnaRate(date: d(2026, 11, 17), amount: 25.88)])
        XCTAssertEqual(klarnaRateIndex(k), 11)
    }

    func testAltreEmailNonSonoKlarna() {
        XCTAssertNil(parseKlarnaEmail(subject: "Pagamento con carta", body: "Pagamento di 26,28 euro presso KLARNA il 17.10.2026"))
        XCTAssertNil(parseKlarnaEmail(subject: "Klarna", body: "Scopri le offerte della settimana"))
        XCTAssertNotNil(parseKlarnaEmail(subject: "Klarna", body: "Il pagamento di 26,28 € per 3DJake sarà addebitato il 17 ottobre 2026. Tocca per vedere i dettagli."))
    }

    @MainActor
    func testCreaLeRateESpostaQuelleGiaInserite() throws {
        let ctx = SharedStore.container.mainContext
        func rates() throws -> [Expense] { try ctx.fetch(FetchDescriptor<Expense>()).filter { $0.planName == "3DJake" } }
        defer {
            for e in (try? rates()) ?? [] { ctx.delete(e) }
            try? ctx.save()
        }
        let k = try XCTUnwrap(parseKlarnaEmail(subject: Self.subject, body: Self.body))
        let msg = try recordKlarnaPayment(k, ctx: ctx)
        XCTAssertTrue(msg.contains("Nuovo acquisto"))
        var r = try rates().sorted { $0.date < $1.date }
        XCTAssertEqual(r.map(\.planIndex), [11, 12])
        XCTAssertEqual(r.map(\.amount), [26.28, 25.88])
        XCTAssertTrue(r.allSatisfy { $0.planProvider == "Klarna" && $0.planCount == 12 })
        XCTAssertEqual(r.first?.note, "3DJake · rata 11 di 12")

        // La stessa email una seconda volta: niente doppioni.
        _ = try recordKlarnaPayment(k, ctx: ctx)
        XCTAssertEqual(try rates().count, 2)

        // Rate inserite a mano un giorno prima: vengono spostate al 17, senza doppioni.
        for e in try rates() { ctx.delete(e) }
        for e in makeInstallments(total: 314.96, count: 12, paid: 10, first: d(2026, 10, 16), name: "3DJake", provider: "Klarna") { ctx.insert(e) }
        try ctx.save()
        let before = try rates().count
        _ = try recordKlarnaPayment(k, ctx: ctx)
        r = try rates().sorted { $0.date < $1.date }
        XCTAssertEqual(r.count, before)
        XCTAssertTrue(r.contains { $0.date == d(2026, 10, 17) && abs($0.amount - 26.28) < 0.001 })
        XCTAssertTrue(r.contains { $0.date == d(2026, 11, 17) && abs($0.amount - 25.88) < 0.001 })
    }

    func testTotaleDellaVacanzaComprendeLePrenotazioni() {
        let t = Trip(name: "Breslavia", currency: "PLN", startDate: d(2026, 10, 16), endDate: d(2026, 10, 17))
        let volo = Expense(amount: 89, categoryName: "Viaggi", date: d(2026, 10, 2), note: "Volo")
        let pranzo = Expense(amount: 12.36, categoryName: "Pranzi/Cene fuori", date: d(2026, 10, 16), note: "Zapiekenk")
        let altro = Expense(amount: 50, categoryName: "Alimentari", date: d(2026, 10, 16), note: "Spesa a casa")
        volo.tripID = t.uid; pranzo.tripID = t.uid
        let tot = tripTotals(t, [volo, pranzo, altro])
        XCTAssertEqual(tot.here, 12.36, accuracy: 0.001)
        XCTAssertEqual(tot.total, 101.36, accuracy: 0.001)
    }

    func testProvaPrezzi() {
        XCTAssertEqual(priceInEuro("45,90", rate: 4.37) ?? 0, 10.50, accuracy: 0.001)
        XCTAssertNil(priceInEuro("", rate: 4.37))
        XCTAssertNil(priceInEuro("10", rate: 0))
    }
}
