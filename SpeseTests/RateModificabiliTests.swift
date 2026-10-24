import XCTest
@testable import Spese

/// Rate con importi scritti a mano: le altre si dividono il resto.
final class RateModificabiliTests: XCTestCase {
    func testAnticipoSullaPrimaRata() {
        let s = installmentSchedule(total: 20, count: 3, paid: 0, first: Date())
        XCTAssertEqual(s.map(\.amount), [6.67, 6.67, 6.66])
        let a = adjustedSchedule(s, fixed: [1: 10])
        XCTAssertEqual(a.map(\.amount), [10, 5, 5])
        XCTAssertEqual(adjustedSchedule(s, fixed: [2: 4]).map(\.amount), [8, 4, 8])
        XCTAssertEqual(adjustedSchedule(s, fixed: [:]).map(\.amount), s.map(\.amount))
        let odd = adjustedSchedule(s, fixed: [1: 10.01])
        XCTAssertEqual(odd.reduce(0) { $0 + $1.amount }, 20, accuracy: 0.001)
    }
}
