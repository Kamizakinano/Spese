import XCTest
@testable import Spese

/// Le spese "Altro" prendono un'emoji da quello che c'è scritto.
final class AltroEmojiTests: XCTestCase {
    func testEmojiDallaDescrizione() {
        XCTAssertEqual(otherEmoji("Regalo per mamma"), "🎁")
        XCTAssertEqual(otherEmoji("regali di Natale"), "🎁")
        XCTAssertEqual(otherEmoji("Parrucchiere"), "💇")
        XCTAssertEqual(otherEmoji("Veterinario Fido"), "🐶")
        XCTAssertEqual(otherEmoji("Ricarica telefono"), "📱")
        XCTAssertEqual(otherEmoji("Multa"), "🏛️")
        XCTAssertNil(otherEmoji(""))
        XCTAssertNil(otherEmoji("Boh"))
    }
}
