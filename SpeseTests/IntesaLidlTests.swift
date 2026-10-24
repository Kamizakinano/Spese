import XCTest
@testable import Spese

/// Email vera di Intesa (pagamento al Lidl, data senza anno), importo di Wallet e doppioni Wallet + email.
final class IntesaLidlTests: XCTestCase {
    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 12) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: day, hour: h))!
    }

    static let body = """
    Gentile cliente,
    ti informiamo che in data 18.10 è stato richiesto un pagamento di 4,86 euro con la carta 5167_*_*_4833 presso LIDL 2070, VILLA CARCINA


    Cordiali saluti
    Intesa Sanpaolo


    Questo messaggio è stato inviato da un indirizzo email di sola notifica ti preghiamo di non rispondere.
    """

    func testEmailLidl() throws {
        let e = try XCTUnwrap(parseBankEmail(subject: "Intesa Sanpaolo: Pagamento con carta", body: Self.body, now: d(2026, 10, 18, 15)))
        XCTAssertEqual(e.kind, .expense)
        XCTAssertEqual(e.amount, 4.86, accuracy: 0.001)
        XCTAssertEqual(e.merchant, "LIDL 2070, VILLA CARCINA")
        XCTAssertEqual(e.date, d(2026, 10, 18), "Data senza anno: quest'anno")
        // Email di fine dicembre letta a gennaio: anno precedente.
        let old = parseBankEmail(subject: "Pagamento con carta", body: "in data 31.12 è stato richiesto un pagamento di 5,00 euro presso BAR", now: d(2027, 1, 2))
        XCTAssertEqual(old?.date, d(2026, 12, 31))
    }

    func testImportoDiWallet() {
        XCTAssertEqual(walletAmountText(Decimal(string: "32.73")!, currency: "PLN"), "32,73 PLN")
        XCTAssertEqual(walletAmountText(4.86, currency: "eur"), "4,86 EUR")
        XCTAssertTrue(looksLikeEuro(walletAmountText(4.86, currency: "EUR")))
    }

    func testDoppioniWalletEEmail() {
        let wallet = Expense(amount: 4.86, categoryName: "Alimentari", date: d(2026, 10, 18, 14), note: "Lidl")
        XCTAssertTrue(isLikelyDuplicate(amount: 4.86, merchant: "LIDL 2070, VILLA CARCINA", when: d(2026, 10, 18, 16), expenses: [wallet]),
                      "Stesso negozio e importo a due ore di distanza")
        XCTAssertTrue(isLikelyDuplicate(amount: 4.86, merchant: "", when: d(2026, 10, 18, 14).addingTimeInterval(600), expenses: [wallet]))
        XCTAssertFalse(isLikelyDuplicate(amount: 4.86, merchant: "Conad", when: d(2026, 10, 18, 18), expenses: [wallet]), "Altro negozio")
        XCTAssertFalse(isLikelyDuplicate(amount: 5.00, merchant: "Lidl", when: d(2026, 10, 18, 16), expenses: [wallet]), "Altro importo")
    }
}
