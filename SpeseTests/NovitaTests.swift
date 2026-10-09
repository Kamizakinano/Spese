import XCTest
import SwiftData
@testable import Spese

/// Prove di: entrate senza saldo iniziale, categorie imparate, backup automatico, riepilogo del periodo.
final class NovitaTests: XCTestCase {
    private func d(_ y: Int, _ m: Int, _ day: Int, hour: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: day, hour: hour))!
    }

    // 1. Il saldo iniziale non è un'entrata del mese.
    func testEntrateSenzaSaldoIniziale() {
        let incomes = [
            Income(amount: 1000, saved: 0, kind: initialKind, date: d(2026, 10, 1, hour: 0), note: "Saldo iniziale"),
            Income(amount: 1500, saved: 300, kind: "Stipendio", date: d(2026, 10, 10), note: "Stipendio")
        ]
        let ex = [Expense(amount: 100, categoryName: "Svago", date: d(2026, 10, 12), note: "")]
        let l = Ledger(incomes: incomes, expenses: ex, moves: [], start: d(2026, 10, 1, hour: 0))
        let f = l.figures(for: d(2026, 10, 15))
        XCTAssertEqual(f.incomeNet, 1200, accuracy: 0.001, "Entrate = solo lo stipendio (al netto dei risparmi)")
        XCTAssertEqual(f.startAvail, 1000, accuracy: 0.001, "Il saldo iniziale conta come soldi già in banca")
        XCTAssertEqual(f.left, 2100, accuracy: 0.001, "Il disponibile non cambia")
    }

    // 3. Categorie imparate correggendo una spesa.
    func testCategoriaImparata() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let cats = defaultCategories.map { $0.0 }
        XCTAssertEqual(guessCategory(merchant: "CONAD SUPERSTORE", available: cats, defaults: defaults), "Alimentari")
        learnCategory(merchant: " CONAD SUPERSTORE ", category: "Casa e bollette", defaults: defaults)
        XCTAssertEqual(guessCategory(merchant: "Conad Superstore", available: cats, defaults: defaults), "Casa e bollette")
        XCTAssertEqual(guessCategory(merchant: "Bar Roma", available: cats, defaults: defaults), "Pranzi/Cene fuori", "Gli altri esercenti non cambiano")

        renameLearnedCategory(from: "Casa e bollette", to: "Casa", defaults: defaults)
        XCTAssertEqual(guessCategory(merchant: "conad superstore", available: cats + ["Casa"], defaults: defaults), "Casa")
        XCTAssertEqual(guessCategory(merchant: "conad superstore", available: cats, defaults: defaults), "Alimentari",
                       "Se la categoria imparata non esiste più si usano le regole")
    }

    // 4. Backup automatico.
    func testBackupSettimanale() {
        XCTAssertTrue(autoBackupDue(last: nil, now: d(2026, 10, 9)))
        XCTAssertFalse(autoBackupDue(last: d(2026, 10, 9), now: d(2026, 10, 15)))
        XCTAssertTrue(autoBackupDue(last: d(2026, 10, 9), now: d(2026, 10, 16)))
    }

    @MainActor
    func testBackupScrittoERipristinabileETieneGliUltimi8() throws {
        let ctx = SharedStore.container.mainContext
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = try writeBackup(ctx, to: dir, now: d(2026, 10, 9))
        XCTAssertEqual(url.lastPathComponent, "Spese-backup-2026-10-09.json")
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        XCTAssertNoThrow(try dec.decode(Backup.self, from: Data(contentsOf: url)), "Il file deve essere un backup ripristinabile")

        for week in 1...10 { try writeBackup(ctx, to: dir, now: d(2026, 10, 9).addingTimeInterval(Double(week) * 7 * 86400)) }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("Spese-backup-") }
        XCTAssertEqual(files.count, 8, "Vengono tenuti solo gli ultimi 8 backup")
        XCTAssertFalse(files.contains("Spese-backup-2026-10-09.json"), "Il più vecchio viene cancellato")
    }

    // 6. Riepilogo del periodo.
    func testRiepilogoPeriodo() {
        let ex = [
            Expense(amount: 10, categoryName: "Alimentari", date: d(2026, 10, 12), note: ""),
            Expense(amount: 20, categoryName: "Svago", date: d(2026, 10, 20), note: ""),
            Expense(amount: 5, categoryName: "Svago", date: d(2026, 11, 10), note: "")   // periodo dopo
        ]
        let inc = [
            Income(amount: 1500, saved: 0, kind: "Stipendio", date: d(2026, 10, 10), note: ""),
            Income(amount: 900, saved: 0, kind: initialKind, date: d(2026, 10, 11), note: "")
        ]
        let s = summarize(expenses: ex, incomes: inc, start: d(2026, 10, 10, hour: 0), end: d(2026, 11, 10, hour: 0))
        XCTAssertEqual(s.total, 30)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s.income, 1500, "Il saldo iniziale non è un'entrata")
        XCTAssertEqual(s.byCategory.first?.name, "Svago")
    }

    func testPeriodoPrecedente() {
        let p = previousPeriod(before: d(2026, 11, 10), day: 10)
        XCTAssertEqual(p?.start, d(2026, 10, 10, hour: 0))
        XCTAssertEqual(p?.end, d(2026, 11, 10, hour: 0))
        let q = previousPeriod(before: d(2026, 10, 9), day: 10)   // stipendio arrivato in anticipo il 9
        XCTAssertEqual(q?.start, d(2026, 9, 10, hour: 0))
        XCTAssertEqual(q?.end, d(2026, 10, 9, hour: 0))
    }
}
