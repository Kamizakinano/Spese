import XCTest
import SwiftData
@testable import Spese

/// Prove dell'azione "Aggiungi spesa" usata da Comandi rapidi con Apple Pay.
final class AddExpenseIntentTests: XCTestCase {

    func testImportiComeArrivanoDaApplePay() {
        XCTAssertEqual(parseLooseAmount("12,50 €"), 12.5)
        XCTAssertEqual(parseLooseAmount("€1.234,50"), 1234.5)
        XCTAssertEqual(parseLooseAmount("€1,234.50"), 1234.5)
        XCTAssertEqual(parseLooseAmount("7"), 7)
        XCTAssertNil(parseLooseAmount("abc"))
    }

    func testCategoriaDallEsercente() {
        let cats = defaultCategories.map { $0.0 }
        XCTAssertEqual(guessCategory(merchant: "CONAD SUPERSTORE", available: cats), "Alimentari")
        XCTAssertEqual(guessCategory(merchant: "Bar Roma", available: cats), "Pranzi/Cene fuori")
        XCTAssertEqual(guessCategory(merchant: "Amazon EU", available: cats), "Shopping")
        XCTAssertEqual(guessCategory(merchant: "Negozio sconosciuto", available: cats), "Altro")
        XCTAssertEqual(guessCategory(merchant: "Zalando Gift Card", available: cats), giftCardCategory)
        XCTAssertEqual(guessCategory(merchant: "Buono regalo Amazon", available: cats), giftCardCategory)
    }

    /// Esegue l'azione come farebbe Comandi rapidi e controlla la spesa salvata.
    @MainActor
    func testAzioneRegistraLaSpesaInSilenzio() async throws {
        let ctx = SharedStore.container.mainContext
        let marker = "Prova Apple Pay \(UUID().uuidString.prefix(6))"
        defer {
            for e in (try? ctx.fetch(FetchDescriptor<Expense>())) ?? [] where e.note == marker { ctx.delete(e) }
            try? ctx.save()
        }
        UserDefaults.standard.removeObject(forKey: applePayNotifyKey)

        var intent = AddExpenseIntent()
        intent.amount = "€23,40"
        intent.merchant = marker
        intent.method = .carta
        _ = try await intent.perform()

        let saved = try ctx.fetch(FetchDescriptor<Expense>()).filter { $0.note == marker }
        XCTAssertEqual(saved.count, 1, "La spesa dovrebbe essere registrata una volta")
        XCTAssertEqual(saved.first?.amount, 23.4)
        XCTAssertEqual(saved.first?.method, "carta")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: applePayNotifyKey), "Le notifiche devono essere spente di partenza")
    }

    /// Importo illeggibile ma esercente presente: la spesa si salva "da completare" e finisce nel registro.
    @MainActor
    func testImportoIllegibileSalvaDaCompletare() async throws {
        let ctx = SharedStore.container.mainContext
        let marker = "Bar Prova \(UUID().uuidString.prefix(6))"
        defer {
            for e in (try? ctx.fetch(FetchDescriptor<Expense>())) ?? [] where e.note == marker { ctx.delete(e) }
            try? ctx.save()
        }
        var intent = AddExpenseIntent()
        intent.amount = "niente"
        intent.merchant = marker
        intent.method = .carta
        _ = try await intent.perform()
        let saved = try ctx.fetch(FetchDescriptor<Expense>()).filter { $0.note == marker }
        XCTAssertEqual(saved.count, 1, "La spesa deve essere salvata anche senza importo")
        XCTAssertEqual(saved.first?.needsAmount, true)
        XCTAssertEqual(saved.first?.amount, 0)
        let log = ApplePayLog.all().first
        XCTAssertEqual(log?.merchant, marker)
        XCTAssertEqual(log?.amount, "niente")
        XCTAssertTrue(log?.result.contains("da completare") == true, "Il registro deve dire com'è andata: \(log?.result ?? "")")
    }

    /// Senza importo e senza esercente non c'è niente da salvare: errore, ma il registro lo annota.
    @MainActor
    func testTuttoVuotoNonRegistraNulla() async throws {
        let ctx = SharedStore.container.mainContext
        let before = try ctx.fetchCount(FetchDescriptor<Expense>())
        var intent = AddExpenseIntent()
        intent.amount = ""
        intent.merchant = ""
        intent.method = .carta
        do {
            _ = try await intent.perform()
            XCTFail("Senza importo né esercente l'azione dovrebbe dare errore")
        } catch {}
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Expense>()), before)
        XCTAssertTrue(ApplePayLog.all().first?.result.hasPrefix("Non registrata") == true)
    }

    func testAzioneDisponibileInComandiRapidi() {
        XCTAssertFalse(SpeseShortcuts.appShortcuts.isEmpty, "L'azione deve comparire già pronta in Comandi rapidi")
        XCTAssertFalse(AddExpenseIntent.openAppWhenRun, "L'azione non deve aprire l'app")
    }
}
