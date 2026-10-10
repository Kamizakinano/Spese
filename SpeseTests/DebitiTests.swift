import XCTest
import SwiftData
@testable import Spese

/// Prove di "Ti devono" (incasso sul conto o in contanti) e "Devo dare".
final class DebitiTests: XCTestCase {

    @MainActor
    func testIncassatoInContantiVaNelPortafoglio() throws {
        let ctx = SharedStore.container.mainContext
        let who = "Prova \(UUID().uuidString.prefix(6))"
        let e = Expense(amount: 40, categoryName: "Altro", date: Date(), note: "Cena")
        e.owedBy = who; e.owedAmount = 20
        ctx.insert(e)
        defer {
            ctx.delete(e)
            for c in (try? ctx.fetch(FetchDescriptor<CashMove>())) ?? [] where c.note.contains(who) { ctx.delete(c) }
            for i in (try? ctx.fetch(FetchDescriptor<Income>())) ?? [] where i.note.contains(who) { ctx.delete(i) }
            try? ctx.save()
        }
        settleOwed(e, cash: true, ctx: ctx)
        XCTAssertTrue(e.settled)
        XCTAssertEqual(e.settledMethod, "contanti")
        let cash = try ctx.fetch(FetchDescriptor<CashMove>()).filter { $0.note.contains(who) }
        XCTAssertEqual(cash.first?.amount, 20)
        XCTAssertEqual(cash.first?.bank, false)
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<Income>()).filter { $0.note.contains(who) }.isEmpty,
                      "In contanti non deve entrare niente sul conto")
    }

    @MainActor
    func testIncassatoSulContoEUnRimborso() throws {
        let ctx = SharedStore.container.mainContext
        let who = "Prova \(UUID().uuidString.prefix(6))"
        let e = Expense(amount: 30, categoryName: "Altro", date: Date(), note: "")
        e.owedBy = who; e.owedAmount = 15
        ctx.insert(e)
        defer {
            ctx.delete(e)
            for i in (try? ctx.fetch(FetchDescriptor<Income>())) ?? [] where i.note.contains(who) { ctx.delete(i) }
            try? ctx.save()
        }
        settleOwed(e, cash: false, ctx: ctx)
        let inc = try ctx.fetch(FetchDescriptor<Income>()).filter { $0.note.contains(who) }
        XCTAssertEqual(inc.first?.amount, 15)
        XCTAssertEqual(inc.first?.kind, "Rimborso")
        XCTAssertEqual(e.settledMethod, "carta")
    }

    @MainActor
    func testPagatoCreaLaSpesa() throws {
        let ctx = SharedStore.container.mainContext
        let who = "Prova \(UUID().uuidString.prefix(6))"
        let d = Debt(person: who, amount: 12.5, note: "pizza", category: "Pranzi/Cene fuori", date: Date())
        ctx.insert(d)
        defer {
            ctx.delete(d)
            for e in (try? ctx.fetch(FetchDescriptor<Expense>())) ?? [] where e.note.contains(who) { ctx.delete(e) }
            try? ctx.save()
        }
        payDebt(d, cash: true, ctx: ctx)
        XCTAssertTrue(d.paid)
        XCTAssertEqual(d.paidMethod, "contanti")
        let e = try ctx.fetch(FetchDescriptor<Expense>()).filter { $0.note.contains(who) }
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e.first?.amount, 12.5)
        XCTAssertEqual(e.first?.method, "contanti")
        XCTAssertEqual(e.first?.categoryRaw, "Pranzi/Cene fuori")
        XCTAssertEqual(e.first?.note, "Restituiti a \(who) · pizza")
    }
}
