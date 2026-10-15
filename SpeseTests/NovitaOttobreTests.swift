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

    func testFileCSV() {
        let ex = [Expense(amount: 7.10, categoryName: "Alimentari", date: d(2026, 10, 14), note: "Pausa; \"Lavoro\"")]
        let data = makeCSV(ex)
        XCTAssertEqual(Array(data.prefix(3)), [0xEF, 0xBB, 0xBF], "BOM per Excel")
        let text = String(decoding: data.dropFirst(3), as: UTF8.self)
        let lines = text.components(separatedBy: "\r\n")
        XCTAssertEqual(lines.count, 3, "Intestazione, una spesa, totale")
        XCTAssertEqual(lines[1], "14/10/2026;\"Pausa; \"\"Lavoro\"\"\";Alimentari;7,10;Carta;")
        XCTAssertEqual(lines[2], "Totale;;;7,10;;")
    }

    func testFilePDF() {
        let ex = (1...80).map { Expense(amount: Double($0), categoryName: "Alimentari", date: d(2026, 10, 1 + $0 % 28), note: "Spesa \($0)") }
        let data = makePDF(ex, title: "Spese di ottobre 2026", subtitle: "Dal 1 al 31 ottobre 2026")
        XCTAssertEqual(String(decoding: data.prefix(5), as: UTF8.self), "%PDF-")
        XCTAssertGreaterThan(data.count, 1000)
    }

    func testRigaSenzaCategoriaRipetuta() {
        XCTAssertEqual(rowDetail("Alimentari", note: "", category: "Alimentari"), "", "Senza nota il titolo è già la categoria")
        XCTAssertEqual(rowDetail("Alimentari · contanti", note: "", category: "Alimentari"), "contanti")
        XCTAssertEqual(rowDetail("Alimentari · contanti", note: "Lidl", category: "Alimentari"), "Alimentari · contanti")
    }

    func testPeriodoElenco() {
        let g = d(2026, 10, 15)   // giovedì
        let day = listRange(.day, around: g)
        XCTAssertEqual(day.end.timeIntervalSince(day.start), 86400, accuracy: 3600)
        let w = listRange(.week, around: g)
        XCTAssertEqual(Calendar.current.component(.day, from: w.start), 12, "La settimana parte da lunedì")
        XCTAssertEqual(Calendar.current.component(.day, from: w.end), 19)
        let m = listRange(.month, around: g)
        XCTAssertEqual(Calendar.current.component(.day, from: m.start), 1)
        XCTAssertEqual(Calendar.current.component(.month, from: m.end), 11)
    }

    func testConfrontoSettimana() {
        XCTAssertNil(weekCompareText(this: 50, last: 0))
        XCTAssertEqual(weekCompareText(this: 82, last: 100), "−18% della scorsa")
        XCTAssertEqual(weekCompareText(this: 120, last: 100), "+20% della scorsa")
        XCTAssertEqual(weekCompareText(this: 100, last: 100), "come la scorsa")
    }
}
