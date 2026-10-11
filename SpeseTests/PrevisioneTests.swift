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
}
