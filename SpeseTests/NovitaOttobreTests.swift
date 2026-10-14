import XCTest
@testable import Spese

/// Prove di: avviso della sera, riepilogo della domenica, bollette a confronto, file Excel.
final class NovitaOttobreTests: XCTestCase {
    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: day, hour: h))!
    }

    func testAvvisoSoloSeSuperiIlBudget() {
        XCTAssertNil(budgetAlertText(spentToday: 30, budget: 41.24, tomorrow: 40))
        let t = budgetAlertText(spentToday: 62.30, budget: 41.24, tomorrow: 40.46)
        XCTAssertEqual(t?.title, "Oggi \(eur(62.30)), budget \(eur(41.24))")
        XCTAssertTrue(t?.body.contains(eur(21.06)) ?? false)
        XCTAssertTrue(t?.body.contains(eur(40.46)) ?? false)
    }

    func testSettimanaDaLunediADomenica() {
        let w = weekRange(d(2026, 10, 14))            // mercoledì
        XCTAssertEqual(w.start, d(2026, 10, 12, 0))   // lunedì
        XCTAssertEqual(w.end, d(2026, 10, 19, 0))
    }

    func testRiepilogoDellaDomenica() {
        let ex = [
            Expense(amount: 50, categoryName: "Alimentari", date: d(2026, 10, 13), note: ""),
            Expense(amount: 20, categoryName: "Svago", date: d(2026, 10, 15), note: ""),
            Expense(amount: 100, categoryName: "Svago", date: d(2026, 10, 7), note: "")   // settimana prima
        ]
        let t = weeklySummaryText(ex, now: d(2026, 10, 18, 19))
        XCTAssertEqual(t.title, "La tua settimana: \(eur(70))")
        XCTAssertTrue(t.body.contains("\(eur(30)) meno della settimana scorsa"))
        XCTAssertTrue(t.body.contains("Alimentari"))
    }

    func testBolletteAConfronto() {
        let old1 = Expense(amount: 132.10, categoryName: "Casa e bollette", date: d(2025, 10, 10), note: "Enel")
        let old2 = Expense(amount: 144.90, categoryName: "Casa e bollette", date: d(2026, 8, 10), note: "enel ")
        let other = Expense(amount: 40, categoryName: "Casa e bollette", date: d(2026, 9, 1), note: "Acqua")
        let h = billHistory(note: "Enel", category: "Casa e bollette", in: [old1, old2, other])
        XCTAssertEqual(h.map(\.amount), [144.90, 132.10])
        XCTAssertEqual(billChange(170.63, previous: h.first?.amount) ?? 0, 17.75, accuracy: 0.01)
        XCTAssertTrue(billHistory(note: "Enel", category: "Svago", in: [old1]).isEmpty, "Solo nelle categorie delle bollette")
        XCTAssertTrue(billHistory(note: "Enel", category: "Casa e bollette", in: [old1], excluding: old1).isEmpty,
                      "Modificando una bolletta non la si confronta con se stessa")
    }

    func testCRC32() {
        XCTAssertEqual(crc32(Data("123456789".utf8)), 0xCBF43926)
    }

    func testFileExcel() {
        let ex = [Expense(amount: 7.10, categoryName: "Alimentari", date: d(2026, 10, 14), note: "Pausa <Lavoro> & co")]
        let rows = exportRows(ex)
        XCTAssertEqual(rows.count, 3, "Intestazione, una spesa, totale")
        let data = makeXLSX(sheet: "Spese", rows: rows, widths: [12, 30])
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4B], "Un file Excel è un archivio ZIP")
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("xl/worksheets/sheet1.xml"))
        XCTAssertTrue(text.contains("Pausa &lt;Lavoro&gt; &amp; co"))
        XCTAssertTrue(text.contains("<v>7.10</v>"))
    }
}
