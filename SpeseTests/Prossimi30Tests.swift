import XCTest
import SwiftData
@testable import Spese

/// Prove di: prossimi 30 giorni, da parte ogni giorno, controllo contanti.
final class Prossimi30Tests: XCTestCase {
    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: day, hour: h))!
    }

    func testDateMensili() {
        let ds = monthlyDates(nextKey: "2026-10", day: 31, until: d(2026, 12, 15))
        XCTAssertEqual(ds, [d(2026, 10, 31), d(2026, 11, 30)], "Nei mesi corti vale l'ultimo giorno")
    }

    func testMovimentiPrevisti() {
        let now = d(2026, 10, 14)
        let rata = Expense(amount: 28.60, categoryName: installmentCategory, date: d(2026, 10, 15), note: "Zalando · rata 1 di 3")
        let oggi = Expense(amount: 7, categoryName: "Alimentari", date: d(2026, 10, 14), note: "Già spesa")
        let contanti = Expense(amount: 5, categoryName: "Altro", date: d(2026, 10, 20), note: "Contanti"); contanti.method = "contanti"
        let netflix = Recurring(name: "Netflix", amount: 12.99, categoryName: "Svago", day: 18, nextKey: "2026-10")
        let a = Account(startDate: d(2026, 1, 1)); a.salaryAmount = 1600; a.salaryDay = 10; a.salaryNextKey = "2026-11"
        a.salaryMode = 1; a.salaryValue = 0
        let m = plannedMoves(expenses: [rata, oggi, contanti], recurring: [netflix], account: a, now: now)
        XCTAssertEqual(m.map(\.name), ["Zalando · rata 1 di 3", "Netflix", "Stipendio"])
        XCTAssertEqual(m.map(\.amount), [-28.60, -12.99, 1600])
    }

    func testPuntoPiuBassoEMassimoDaParte() {
        let now = d(2026, 10, 14)
        let moves = [PlannedMove(name: "Mutuo", date: d(2026, 10, 17), amount: -400, icon: ""),
                     PlannedMove(name: "Stipendio", date: d(2026, 10, 24), amount: 1500, icon: "")]
        let p = project(start: 1000, moves: moves, perDay: 30, now: now)
        XCTAssertEqual(p.lowest?.balance ?? 0, 330, accuracy: 0.001)     // 1000 − 9 × 30 − 400
        XCTAssertEqual(p.lowest?.date, Calendar.current.startOfDay(for: d(2026, 10, 23)))
        XCTAssertEqual(maxDailySave(p, now: now), 36.5, "330 € in 9 giorni, a mezzo euro")
    }

    @MainActor
    func testDaParteOgniGiorno() throws {
        let ctx = SharedStore.container.mainContext
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defaults.set(5.0, forKey: dailySaveKey)
        defer {
            for m in (try? ctx.fetch(FetchDescriptor<SavingsMove>())) ?? [] where m.note == "Da parte ogni giorno" { ctx.delete(m) }
            try? ctx.save()
        }
        let before = try ctx.fetch(FetchDescriptor<SavingsMove>()).filter { $0.note == "Da parte ogni giorno" }.count
        applyDailySavings(ctx, now: d(2026, 10, 14), defaults: defaults)      // acceso oggi: niente ancora
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<SavingsMove>()).filter { $0.note == "Da parte ogni giorno" }.count, before)
        applyDailySavings(ctx, now: d(2026, 10, 17), defaults: defaults)      // 14, 15, 16 finiti
        let added = try ctx.fetch(FetchDescriptor<SavingsMove>()).filter { $0.note == "Da parte ogni giorno" }
        XCTAssertEqual(added.count - before, 3)
        applyDailySavings(ctx, now: d(2026, 10, 17, 20), defaults: defaults)  // stesso giorno: niente di nuovo
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<SavingsMove>()).filter { $0.note == "Da parte ogni giorno" }.count - before, 3)
    }

    func testControlloContanti() {
        XCTAssertEqual(lastSunday(d(2026, 10, 18, 9)), d(2026, 10, 18, 0), "Domenica: oggi")
        XCTAssertEqual(lastSunday(d(2026, 10, 14)), d(2026, 10, 11, 0), "Mercoledì: la domenica prima")
        XCTAssertFalse(cashCheckDue(last: d(2026, 10, 18, 10), now: d(2026, 10, 20)))
        XCTAssertTrue(cashCheckDue(last: d(2026, 10, 15), now: d(2026, 10, 18, 9)))
        XCTAssertFalse(cashCheckDue(last: nil, now: d(2026, 10, 18)))
    }
}
