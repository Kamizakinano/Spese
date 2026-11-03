import XCTest
import SwiftData
@testable import Spese

/// Prove dell'SMS di PayPal "hai inviato" (2.59).
final class PayPalInviatoTests: XCTestCase {
    func testLeggeLSMS() {
        let p = parsePayPalSentMessage("PayPal: hai inviato 25,00 € EUR a Alessandro bosio . Accedi o scarica l'app per gestire le notifiche nelle impostazioni: https://py.pl/2EWbOc")
        XCTAssertEqual(p?.amount, 25)
        XCTAssertEqual(p?.person, "Alessandro bosio")
        XCTAssertEqual(parsePayPalSentMessage("Hai inviato 1.250,50 € EUR a Mario Rossi")?.amount, 1250.5)
        XCTAssertNil(parsePayPalSentMessage("Hai pagato 2,99 € EUR a Apple Services"))
    }

    @MainActor
    func testRegistraSenzaDoppioni() throws {
        let ctx = SharedStore.container.mainContext
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 5))!
        defer {
            for e in (try? ctx.fetch(FetchDescriptor<Expense>())) ?? [] where e.note == "Prova Inviato" { ctx.delete(e) }
            try? ctx.save()
        }
        XCTAssertTrue(try recordPayPalSent(amount: 25, person: "Prova Inviato", ctx: ctx, now: now).hasPrefix("Spesa registrata"))
        XCTAssertTrue(try recordPayPalSent(amount: 25, person: "Prova Inviato", ctx: ctx, now: now).contains("ignorata"))
        let saved = try ctx.fetch(FetchDescriptor<Expense>()).filter { $0.note == "Prova Inviato" }
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.categoryRaw, otherCategory)
    }
}
