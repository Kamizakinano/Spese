import XCTest

/// Prova automatica sul simulatore: usa l'app come farebbe una persona.
final class SpeseUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launchArguments += ["-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        // Chiude da solo l'avviso delle notifiche se compare.
        addUIInterruptionMonitor(withDescription: "Avvisi di sistema") { alert in
            for b in ["Allow", "Consenti", "OK"] where alert.buttons[b].exists { alert.buttons[b].tap(); return true }
            return false
        }
    }

    private func type(_ text: String, into field: XCUIElement) {
        var tries = 0
        while !field.isHittable && tries < 5 { app.swipeUp(); tries += 1 }
        field.tap()
        if let v = field.value as? String, !v.isEmpty, v != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count + 2))
        }
        field.typeText(text)
    }

    private func expectText(_ s: String, _ msg: String) {
        let el = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", s)).firstMatch
        XCTAssertTrue(el.waitForExistence(timeout: 5), msg)
    }

    private func editBalance(_ button: String, to value: String) {
        let b = app.buttons[button]
        var tries = 0
        while !b.isHittable && tries < 5 { app.swipeUp(); tries += 1 }
        b.tap()
        let field = app.textFields["Importo (€)"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Il campo dell'importo non si è aperto")
        type(value, into: field)
        app.navigationBars.buttons["Salva"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "La finestra non si è chiusa dopo Salva")
    }

    func testModificaSaldiBancaEContanti() {
        app.launch()

        // Prima configurazione: 1000 € in banca e 50 € in contanti.
        let bank = app.textFields["Soldi sul conto adesso (€)"]
        XCTAssertTrue(bank.waitForExistence(timeout: 10), "Manca la pagina di benvenuto")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Allow", "Consenti"] where springboard.buttons[name].waitForExistence(timeout: 3) {
            springboard.buttons[name].tap()
        }
        type("1000", into: bank)
        type("50", into: app.textFields["Contanti che ho adesso (€)"])
        let start = app.buttons["Inizia"]
        var tries = 0
        while !start.isHittable && tries < 6 { app.swipeUp(); tries += 1 }
        start.tap()

        app.tabBars.buttons["Conti"].tap()
        expectText("050,00", "Il totale iniziale dovrebbe essere 1.050 €")

        editBalance("Modifica soldi in banca", to: "800")
        expectText("800,00", "La banca dovrebbe essere 800 €")
        expectText("850,00", "Il totale dovrebbe essere 850 €")

        editBalance("Modifica contanti", to: "20")
        expectText("820,00", "Il totale dovrebbe essere 820 € (800 + 20)")

        // I valori restano anche riaprendo l'app.
        app.terminate()
        app.launch()
        app.tabBars.buttons["Conti"].tap()
        expectText("820,00", "Dopo la riapertura il totale dovrebbe restare 820 €")
    }
}
