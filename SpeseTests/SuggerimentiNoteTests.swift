import XCTest
@testable import Spese

/// Prove dei suggerimenti per la nota.
final class SuggerimentiNoteTests: XCTestCase {
    private func e(_ note: String, _ cat: String, daysAgo: Double) -> Expense {
        Expense(amount: 5, categoryName: cat, date: Date().addingTimeInterval(-daysAgo * 86400), note: note)
    }

    func testPausaLavoroDallaTerzaVolta() {
        let una = [e("Pausa Lavoro", "Pranzi/Cene fuori", daysAgo: 3)]
        XCTAssertTrue(noteSuggestions(for: "paus", in: una).isEmpty, "Usata una volta sola: nessun suggerimento")

        let due = una + [e("pausa lavoro", "Pranzi/Cene fuori", daysAgo: 1)]
        let s = noteSuggestions(for: "paus", in: due)
        XCTAssertEqual(s.map(\.note), ["pausa lavoro"], "Si propone com'è stata scritta l'ultima volta")
        XCTAssertEqual(s.first?.category, "Pranzi/Cene fuori")
        XCTAssertEqual(noteSuggestions(for: "lav", in: due).count, 1, "Trova anche l'inizio di una parola interna")
        XCTAssertTrue(noteSuggestions(for: "p", in: due).isEmpty, "Servono almeno 2 lettere")
        XCTAssertTrue(noteSuggestions(for: "xyz", in: due).isEmpty)
        XCTAssertTrue(noteSuggestions(for: "Pausa lavoro", in: due).isEmpty, "Già scritta per intero: niente da suggerire")
    }

    func testCategoriaPiuUsataEOrdine() {
        let list = [
            e("Diesel", "Trasporti", daysAgo: 5), e("Diesel", "Trasporti", daysAgo: 3), e("Diesel", "Altro", daysAgo: 1),
            e("Distributore", "Trasporti", daysAgo: 9), e("Distributore", "Trasporti", daysAgo: 8)
        ]
        let s = noteSuggestions(for: "di", in: list)
        XCTAssertEqual(s.map(\.note), ["Diesel", "Distributore"], "La più usata per prima")
        XCTAssertEqual(s.first?.category, "Trasporti", "La categoria usata più spesso con quella nota")
    }
}
