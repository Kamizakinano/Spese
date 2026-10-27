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

    /// Email vera del 24.10 ("è stato richiesto un pagamento", data senza anno) e caso con testo vuoto.
    func testPagamentoRichiestoEVuoto() {
        let now = day(2026, 10, 24)
        let e = parseBankEmail(subject: "Intesa Sanpaolo: Pagamento con carta",
                               body: "Gentile cliente, ti informiamo che in data 24.10 è stato richiesto un pagamento di 52,94 euro con la carta 5167_*_*_4833 presso IPERTOSANO, VIMODRONE Cordiali saluti", now: now)
        XCTAssertEqual(e?.amount, 52.94)
        XCTAssertEqual(e?.merchant, "IPERTOSANO, VIMODRONE")
        XCTAssertEqual(e?.date, now)
        XCTAssertTrue(bankEmailMissingBody(subject: "Intesa Sanpaolo: Pagamento con carta", body: ""))
        XCTAssertFalse(bankEmailMissingBody(subject: "Novità", body: ""))
    }

    /// Il testo legale in fondo ("la filiale di Londra, sita in…") non diventa la descrizione.
    func testFondoEmailIgnorato() {
        let e = parseBankEmail(subject: "Intesa Sanpaolo: Accredito bonifico",
                               body: "Gentile Cliente, ti informiamo che in data 23.10.2026 è stato accreditato un bonifico di 423,00 euro sul conto xxx034. Cordiali saluti. Servizio offerto presso la filiale di Londra, sita in 90 Queen Street, London EC4N 1SA, registrata in Inghilterra")
        XCTAssertEqual(e?.amount, 423)
        XCTAssertEqual(e?.merchant, "")
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

    @MainActor
    func testMutuoSpostatoAlGiornoDellAddebito() throws {
        let ctx = SharedStore.container.mainContext
        let name = "Mutuo prova \(UUID().uuidString.prefix(6))"
        let amount = 423.19 + Double(Int.random(in: 1...900)) / 100   // importo unico per la prova
        let r = Recurring(name: name, amount: amount, categoryName: "Casa", day: 1, nextKey: "2031-02")
        ctx.insert(r)
        // La spesa del mese è già stata inserita sabato 1 febbraio 2031.
        let sat = day(2031, 2, 1)
        ctx.insert(Expense(amount: amount, categoryName: "Casa", date: sat, note: name))
        defer {
            for x in (try? ctx.fetch(FetchDescriptor<Expense>())) ?? [] where x.note == name { ctx.delete(x) }
            ctx.delete(r)
            try? ctx.save()
        }
        let mon = day(2031, 2, 3)
        let msg = matchRecurringPayment(amount: amount, when: mon, ctx: ctx)
        XCTAssertTrue(msg?.contains("Spostato") ?? false, msg ?? "nessun messaggio")
        let list = try ctx.fetch(FetchDescriptor<Expense>()).filter { $0.note == name }
        XCTAssertEqual(list.count, 1, "Niente seconda spesa")
        XCTAssertTrue(Calendar.current.isDate(list[0].date, inSameDayAs: mon), "Spostata al giorno dell'addebito")
    }

    @MainActor
    func testRicorrenteNonAncoraInserita() throws {
        let ctx = SharedStore.container.mainContext
        let name = "Affitto prova \(UUID().uuidString.prefix(6))"
        let amount = 611.0 + Double(Int.random(in: 1...900)) / 100
        let r = Recurring(name: name, amount: amount, categoryName: "Casa", day: 1, nextKey: "2031-03")
        ctx.insert(r)
        defer {
            for x in (try? ctx.fetch(FetchDescriptor<Expense>())) ?? [] where x.note == name { ctx.delete(x) }
            ctx.delete(r)
            try? ctx.save()
        }
        XCTAssertNotNil(matchRecurringPayment(amount: amount, when: day(2031, 3, 3), ctx: ctx))
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Expense>()).filter { $0.note == name }.count, 1)
        XCTAssertEqual(r.nextKey, "2031-04", "Il mese è fatto: non si aggiunge di nuovo")
        XCTAssertNil(matchRecurringPayment(amount: amount + 50, when: day(2031, 3, 3), ctx: ctx), "Importo diverso: non è la ricorrente")
    }

    func testRicorrenteGiaInserita() {
        let d = day(2026, 11, 1)
        let e = Expense(amount: 423.19, categoryName: "Casa e bollette", date: d, note: "Mutuo ")
        XCTAssertTrue(recurringCovered(name: "mutuo", on: d, expenses: [e]))
        XCTAssertFalse(recurringCovered(name: "Mutuo", on: day(2026, 12, 1), expenses: [e]))
        XCTAssertEqual(nextMonthKey("2026-12"), "2027-01")
    }
}
