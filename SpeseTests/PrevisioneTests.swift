import XCTest
import SwiftData
@testable import Spese

/// Prove della previsione e dei rimborsi incassati.
final class PrevisioneTests: XCTestCase {

    func testTutteLeSpeseFinoAllIncasso() {
        let cena = Expense(amount: 80, categoryName: "Pranzi/Cene fuori", date: Date(), note: "Cena")
        cena.owedBy = "Marco"; cena.owedAmount = 40
        XCTAssertEqual(everydaySpend(cena), 80, "Finché non incassi conta tutta la spesa")
        cena.settled = true
        XCTAssertEqual(everydaySpend(cena), 40, "Incassato: la parte restituita non conta più")
    }

    /// Un rimborso arrivato con bonifico (già letto dall'email) non va contato due volte.
    @MainActor
    func testIncassatoSulContoUsaIlBonificoGiaArrivato() throws {
        let ctx = SharedStore.container.mainContext
        let who = "Prova \(UUID().uuidString.prefix(6))"
        let bonifico = Income(amount: 27.5, saved: 0, kind: "Altra entrata", date: Date(), note: "Bonifico da \(who)")
        ctx.insert(bonifico)
        let e = Expense(amount: 55, categoryName: "Altro", date: Date(), note: "")
        e.owedBy = who; e.owedAmount = 27.5
        ctx.insert(e)
        defer {
            ctx.delete(e)
            for i in (try? ctx.fetch(FetchDescriptor<Income>())) ?? [] where i.note.contains(who) { ctx.delete(i) }
            try? ctx.save()
        }
        settleOwed(e, cash: false, ctx: ctx)
        let list = try ctx.fetch(FetchDescriptor<Income>()).filter { $0.note.contains(who) }
        XCTAssertEqual(list.count, 1, "Una sola entrata, non due")
        XCTAssertEqual(list.first?.kind, "Rimborso")
    }

    /// Cena da 80 €, Marco ne restituisce 40 sul conto: nel periodo spesi 40, entrate solo lo stipendio.
    func testRimborsiNonSonoEntrate() {
        let start = Date().addingTimeInterval(-5 * 86400), end = Date().addingTimeInterval(20 * 86400)
        let cena = Expense(amount: 80, categoryName: "Pranzi/Cene fuori", date: Date().addingTimeInterval(-86400), note: "Cena")
        cena.owedBy = "Marco"; cena.owedAmount = 40; cena.settled = true
        let inc = [Income(amount: 1500, saved: 0, kind: "Stipendio", date: start, note: ""),
                   Income(amount: 40, saved: 0, kind: "Rimborso", date: Date(), note: "Rimborso Marco")]
        let cash = [CashMove(amount: 10, date: Date(), note: "Rimborso Luca", kind: "ricevuti", bank: false)]
        let s = summarize(expenses: [cena], incomes: inc, cash: cash, start: start, end: end)
        XCTAssertEqual(s.total, 40, "Spesi: solo la mia parte")
        XCTAssertEqual(s.income, 1500, "Entrate: senza i rimborsi")
        XCTAssertEqual(s.refunds, 50, "Rimborsi ricevuti, sul conto e in contanti")
    }
}
