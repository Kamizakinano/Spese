import XCTest
@testable import Spese

/// Prove dei pagamenti da completare (2.60).
final class PagamentiDaCompletareTests: XCTestCase {
    func testAggiungiETogli() {
        let d = UserDefaults(suiteName: "prova-da-completare")!
        d.removePersistentDomain(forName: "prova-da-completare")
        let a = Date(timeIntervalSince1970: 1_800_000_000), b = a.addingTimeInterval(3600)
        addPendingPayment(a, d); addPendingPayment(b, d)
        XCTAssertEqual(pendingPayments(d), [a, b])
        removePendingPayment(a, d)
        XCTAssertEqual(pendingPayments(d), [b])
    }
}
