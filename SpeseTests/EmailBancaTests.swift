import XCTest
import SwiftData
@testable import Spese

/// Prove della lettura delle email della banca.
final class EmailBancaTests: XCTestCase {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    /// Email vera di Intesa Sanpaolo (bonifico ricevuto).
    func testBonificoRicevutoIntesa() {
        let e = parseBankEmail(subject: "Intesa Sanpaolo: Accredito bonifico",
                               body: "Gentile Cliente, ti informiamo che in data 10.10.2026 è stato accreditato un bonifico di 1,00 euro sul conto xxx034. Cordiali saluti Intesa Sanpaolo Questo messaggio è stato inviato automaticamente")
        XCTAssertEqual(e?.kind, .income)
        XCTAssertEqual(e?.amount, 1)
        XCTAssertEqual(e?.date, day(2026, 10, 10))
        XCTAssertEqual(e?.salary, false)
    }

    func testPagamentoConCarta() {
        let e = parseBankEmail(subject: "Intesa Sanpaolo: Pagamento con carta",
                               body: "Gentile Cliente, in data 11.10.2026 alle 12:30 è stato effettuato un pagamento di 23,40 euro presso CONAD SUPERSTORE con la carta xxx1234.")
        XCTAssertEqual(e?.kind, .expense)
        XCTAssertEqual(e?.amount, 23.4)
        XCTAssertEqual(e?.merchant, "CONAD SUPERSTORE")
    }

    func testAltriFormati() {
        XCTAssertEqual(parseBankEmail(subject: "Utilizzo carta", body: "Acquisto di EUR 1.234,50 presso AMAZON EU il 11.10.2026")?.amount, 1234.5)
        XCTAssertEqual(parseBankEmail(subject: "Utilizzo carta", body: "Acquisto di EUR 1.234,50 presso AMAZON EU il 11.10.2026")?.merchant, "AMAZON EU")
        XCTAssertEqual(parseBankEmail(subject: "Prelievo", body: "Prelievo di 50,00 euro allo sportello")?.kind, .withdrawal)
        XCTAssertEqual(parseBankEmail(subject: "Addebito", body: "addebito di 1.200 euro")?.amount, 1200)
        XCTAssertEqual(parseBankEmail(subject: "Accredito stipendio", body: "accreditato un bonifico di 1.550,00 euro")?.salary, true)
        XCTAssertNil(parseBankEmail(subject: "Novità", body: "Scopri la nuova app Intesa Sanpaolo Mobile"), "Email senza importo: ignorata")
        XCTAssertNil(parseBankEmail(subject: "Promo", body: "Ricevi un buono di 50 euro"), "Importo senza movimento: ignorata")
    }

    @MainActor
    func testRegistraEDoppioniIgnorati() throws {
        let ctx = SharedStore.container.mainContext
        let shop = "NEGOZIO PROVA \(UUID().uuidString.prefix(6))"
        defer {
            for x in (try? ctx.fetch(FetchDescriptor<Expense>())) ?? [] where x.note == shop { ctx.delete(x) }
            try? ctx.save()
        }
        let e = BankEmail(kind: .expense, amount: 17.31, merchant: shop, date: nil, salary: false)
        XCTAssertTrue(try recordBankEmail(e, ctx: ctx).hasPrefix("Spesa registrata"))
        XCTAssertTrue(try recordBankEmail(e, ctx: ctx).contains("ignorata"), "La stessa spesa non si registra due volte")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Expense>()).filter { $0.note == shop }.count, 1)
    }
}
