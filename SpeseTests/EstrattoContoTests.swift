import XCTest
@testable import Spese

/// Prove del controllo estratto conto (2.62). Il file è una copia del formato Intesa con dati finti.
final class EstrattoContoTests: XCTestCase {
    static let xlsx = Data(base64Encoded: "UEsDBBQAAAAIANo7Z13HHBc8CgAAAAgAAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbLMJqSxILda3AwBQSwMEFAAAAAgA2jtnXbLFzRQjAQAAowIAABQAAAB4bC9zaGFyZWRTdHJpbmdzLnhtbG1Sy07DMBD8lVUOHOMEKBWQpiopSJWqJvTBfWlMtJJjR7Zbqnw9TgWqsLsXy7Pj2dGss+mpFXDk2pCSkyiNk2iaZ8ZYcLg0k+gUuSvlmc0LJS0BhwK15U8Zs3nGhs6lqyBxBex8DOWT5mjRx8qOa+zddB6wubXYCLo+SsHeGQnkhiZ+kqC+v65aoOWN0hS8/EBxCPUWbae0VT5cYYMtH3xsNbZkOVTK+KQX9S1INlBpdUTYaOETVqWPvO7WPrSkWsBtMg7SvHgwB6jKDSwX8+WZCcmIpWnyOLo7bwtBxv7jzeKKXPxFEmVPv7JrFxWKIMFVDMn4/iFlY7di9rdreN+V25nPne33mtc0eLTUcVlTEOVaGUNwg233DG/0b9/MfcT8B1BLAwQUAAAACADaO2dd2/TMnRgBAAB7BAAAGAAAAHhsL3dvcmtzaGVldHMvc2hlZXQxLnhtbH2U226DMAxAfwXlnUvuqxRSDcrob1QV0qptRQJE+/ljo41sq+QNfIh9bKO4/f3nO5m7Ybz015LxrGB772798DV+dt2ULPQ6luzOvPsPHE7TybuhvyXD8vUSPf89VJwlU8nG5X32hctn7/Lzg9WQ8cDyJUdIJBgJyGfmdwlOC5y5gkySqpApzA6QacwayAxmH5BZzFrI3jA7QrZ7PQEVGlarspGStqvgIOmUEeSkKQRJ2hZBMsbjapNK9VpbB20dtEnxSsP8ZBU1gnQXCJJltDqmvdqkPFMb8zZB3DzFBVlbZWAFsu8aQXKyMTFxExNfbVIlZMY31G1Qt5vqFtbYEXUIBfmPGhtTtzF1+1hiURDvHNwcebha/C9QSwECFAMUAAAACADaO2ddxxwXPAoAAAAIAAAAEwAAAAAAAAAAAAAAgAEAAAAAW0NvbnRlbnRfVHlwZXNdLnhtbFBLAQIUAxQAAAAIANo7Z12yxc0UIwEAAKMCAAAUAAAAAAAAAAAAAACAATsAAAB4bC9zaGFyZWRTdHJpbmdzLnhtbFBLAQIUAxQAAAAIANo7Z13b9MydGAEAAHsEAAAYAAAAAAAAAAAAAACAAZABAAB4bC93b3Jrc2hlZXRzL3NoZWV0MS54bWxQSwUGAAAAAAMAAwDJAAAA3gIAAAAA")!

    private func d(_ m: Int, _ g: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: m, day: g, hour: 12))!
    }

    func testLeggeExcelIntesa() throws {
        let table = try XCTUnwrap(readSpreadsheet(Self.xlsx))
        let rows = bankRows(from: table)
        XCTAssertEqual(rows.count, 3, "Solo le uscite: l'accredito non conta")
        XCTAssertEqual(rows[0].merchant, "Bowling Prova Srl", "Operazione generica: si usa il dettaglio")
        XCTAssertEqual(rows[0].amount, 34)
        XCTAssertFalse(rows[0].booked)
        XCTAssertEqual(rows[0].date, d(11, 6))
        XCTAssertEqual(rows[1].merchant, "Lidl 2070")
        XCTAssertEqual(rows[1].amount, 1.49, accuracy: 0.001)
        XCTAssertEqual(rows[1].date, d(11, 5))
        XCTAssertTrue(rows[1].booked)
        XCTAssertEqual(rows[2].amount, 423.19, accuracy: 0.001)
    }

    func testLeggeCSV() {
        let rows = bankRows(from: readCSV("Data;Descrizione;Importo\n04/11/2026;Conad;-12,50\n05/11/2026;Stipendio;1.500,00"))
        XCTAssertEqual(rows, [BankRow(date: d(11, 4), amount: 12.5, merchant: "Conad", booked: true)])
    }

    func testGiornoVeroDaiDettagli() {
        let rows = bankRows(from: [["Data", "Operazione", "Dettagli", "Importo"],
                                   ["06/11/2026", "Lidl", "Pagamento su POS LIDL 04/111420 Carta n.", "-3,14"]])
        XCTAssertEqual(rows.first?.date, d(11, 4))
    }

    func testConfronto() {
        let lidl = Expense(amount: 1.49, categoryName: "Alimentari", date: d(11, 4), note: "Lidl")
        let conad = Expense(amount: 20, categoryName: "Alimentari", date: d(11, 5), note: "Conad")
        let doppia1 = Expense(amount: 7.99, categoryName: "Shopping", date: d(11, 5), note: "Amazon")
        let doppia2 = Expense(amount: 7.99, categoryName: "Shopping", date: d(11, 5), note: "Amazon")
        let rows = [BankRow(date: d(11, 5), amount: 1.49, merchant: "Lidl 2070", booked: true),
                    BankRow(date: d(11, 5), amount: 21.30, merchant: "CONAD SUPERSTORE", booked: true),
                    BankRow(date: d(11, 5), amount: 7.99, merchant: "Amazon", booked: true),
                    BankRow(date: d(11, 6), amount: 34, merchant: "Bowling Prova Srl", booked: false)]
        let diffs = compareBank(rows, with: [lidl, conad, doppia1, doppia2])
        XCTAssertEqual(diffs.count, 3)
        XCTAssertTrue(diffs.contains { if case .missing(let r) = $0 { return r.amount == 34 } else { return false } })
        XCTAssertTrue(diffs.contains { if case .different(_, _, let a) = $0 { return a == 20 } else { return false } })
        XCTAssertTrue(diffs.contains { if case .duplicate(_, let a, _, _) = $0 { return a == 7.99 } else { return false } })
        // Reimportando: le righe scartate non tornano, e se tutto torna non c'è niente.
        XCTAssertEqual(compareBank(rows, with: [lidl, conad, doppia1, doppia2], ignored: [rows[3].key]).count, 2)
        XCTAssertTrue(compareBank(Array(rows.prefix(1)), with: [lidl]).isEmpty)
    }

    func testCategorieDallaBanca() {
        let cats = ["Alimentari", "Pranzi/Cene fuori", "Trasporti", "Shopping", "Casa e bollette", "Altro"]
        let rows = bankRows(from: [["Data", "Operazione", "Dettagli", "Categoria", "Importo"],
                                   ["03/11/2026", "Mc Donald's", "Pagamento su POS", "Ristoranti e bar", "-6,40"],
                                   ["03/11/2026", "Addebito diretto disposto a favore di TELEPAS", "", "Pedaggi e Telepass", "-100,67"],
                                   ["02/01/2026", "Paypal *asos Com Eu 35314369001", "", "Altre uscite", "-9,91"],
                                   ["05/01/2026", "MGP*Vinted Vilnius", "", "Altre uscite", "-3,44"],
                                   ["05/01/2026", "Importo periodico", "", "Altre uscite", "-4,00"]])
        XCTAssertEqual(rows.map { categoryForBankRow($0, available: cats) },
                       ["Pranzi/Cene fuori", "Trasporti", "Shopping", "Shopping", "Altro"])
        XCTAssertEqual(rows[2].merchant, "Asos (PayPal)")
        XCTAssertEqual(rows[3].merchant, "Vinted")
        XCTAssertEqual(guessCategory(merchant: "Mc Donald's", available: cats, defaults: UserDefaults(suiteName: "prova-cat")!), "Pranzi/Cene fuori")
    }

    func testNonSpeseEscluse() {
        let rows = bankRows(from: [["Data", "Operazione", "Dettagli", "Importo"],
                                   ["03/11/2026", "Prelievo Carta", "ATM Intesa", "-50,00"],
                                   ["03/11/2026", "Giroconto", "verso Salvadanaio", "-100,00"],
                                   ["03/11/2026", "Lidl", "", "-3,00"]])
        XCTAssertEqual(rows.map(\.merchant), ["Lidl"])
    }

    func testMutuoConImportoDiverso() {
        let mutuo = Expense(amount: 420, categoryName: "Casa e bollette", date: d(11, 1), note: "Mutuo")
        let row = BankRow(date: d(11, 3), amount: 423.19, merchant: "Pag.finanziamento Rateale", booked: true)
        XCTAssertTrue(compareBank([row], with: [mutuo]).isEmpty, "La rata del mutuo già segnata non manca")
        let doppio = Expense(amount: 423.19, categoryName: "Altro", date: d(11, 3), note: "Pag.finanziamento Rateale")
        doppio.fromBank = true
        let prelievo = Expense(amount: 50, categoryName: "Altro", date: d(11, 3), note: "Prelievo Carta")
        prelievo.fromBank = true
        let lidl = Expense(amount: 3, categoryName: "Alimentari", date: d(11, 3), note: "Lidl")
        lidl.fromBank = true
        XCTAssertEqual(Set(suspiciousBankExpenses([mutuo, doppio, prelievo, lidl]).map(\.note)), ["Pag.finanziamento Rateale", "Prelievo Carta"])
    }
}
