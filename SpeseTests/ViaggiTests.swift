import XCTest
import SwiftData
@testable import Spese

/// Prove dei viaggi: cambio, divisione delle spese, saldi tra persone, saldo personale, Apple Pay all'estero.
final class ViaggiTests: XCTestCase {

    private func trip(_ currency: String, people: [String] = [], from: Int = -1, to: Int = 1, inStats: Bool = false) -> Trip {
        let cal = Calendar.current
        let t = Trip(name: "Prova", currency: currency,
                     startDate: cal.date(byAdding: .day, value: from, to: Date())!,
                     endDate: cal.date(byAdding: .day, value: to, to: Date())!)
        t.people = people
        t.countInStats = inStats
        return t
    }
    private func expense(_ amount: Double, trip: Trip? = nil, paidBy: String = "", shares: [String: Double] = [:],
                         cash: Bool = false, ago: Double = 3600) -> Expense {
        let e = Expense(amount: amount, categoryName: "Svago", date: Date().addingTimeInterval(-ago), note: "")
        e.tripID = trip?.uid ?? ""; e.paidBy = paidBy; e.shares = shares; e.method = cash ? "contanti" : "carta"
        return e
    }

    func testCambioDellaBancaCentraleEuropea() {
        let xml = """
        <Cube time='2026-10-09'>
            <Cube currency='USD' rate='1.0921'/>
            <Cube currency='GBP' rate='0.8573'/>
            <Cube currency='JPY' rate='162.34'/>
        </Cube>
        """
        let r = Rates.parse(xml)
        XCTAssertEqual(r["GBP"], 0.8573)
        XCTAssertEqual(r["JPY"], 162.34)
        XCTAssertEqual(r.count, 3)
    }

    func testDivisioneInPartiUgualiAlCentesimo() {
        let s = equalShares(10, among: [me, "Marco", "Luca"])
        XCTAssertEqual(s.values.reduce(0, +), 10, accuracy: 0.0001)
        XCTAssertEqual(s[me], 3.34)
        XCTAssertEqual(s["Luca"], 3.33)
    }

    func testChiDeveAChi() {
        let t = trip("EUR", people: ["Marco", "Luca"])
        let cena = expense(90, trip: t, shares: equalShares(90, among: [me, "Marco", "Luca"]))   // ho pagato io
        let taxi = expense(30, trip: t, paidBy: "Marco", shares: [me: 15, "Marco": 15])            // ha pagato Marco
        var net = tripBalances(expenses: [cena, taxi], payments: [])
        XCTAssertEqual(net[me]!, 45, accuracy: 0.001)
        let transfers = settleUp(net)
        XCTAssertEqual(Set(transfers.map { "\($0.from)->\($0.to):\($0.amount)" }), ["Luca->\(me):30.0", "Marco->\(me):15.0"])

        let rimborso = TripPayment(tripID: t.uid, from: "Luca", to: me, amount: 30, date: Date())
        net = tripBalances(expenses: [cena, taxi], payments: [rimborso])
        XCTAssertEqual(settleUp(net), [Transfer(from: "Marco", to: me, amount: 15)])
        XCTAssertEqual(cena.myAmount, 30, accuracy: 0.001, "La mia parte della cena")
        XCTAssertEqual(taxi.myAmount, 15, accuracy: 0.001)
    }

    func testSaldoPersonaleConViaggi() {
        let t = trip("EUR", people: ["Marco", "Luca"])
        let start = Calendar.current.date(byAdding: .day, value: -3, to: Calendar.current.startOfDay(for: Date()))!
        let incomes = [Income(amount: 1000, saved: 0, kind: initialKind, date: start, note: "")]
        let ex = [
            expense(90, trip: t, shares: equalShares(90, among: [me, "Marco", "Luca"])),   // carta: -90
            expense(30, trip: t, paidBy: "Marco", shares: [me: 15, "Marco": 15])             // pagata da Marco: 0
        ]
        let pay1 = TripPayment(tripID: t.uid, from: "Luca", to: me, amount: 30, date: Date().addingTimeInterval(-60))
        let pay2 = TripPayment(tripID: t.uid, from: me, to: "Marco", amount: 10, date: Date().addingTimeInterval(-60))
        pay2.method = "contanti"
        let l = Ledger(incomes: incomes, expenses: ex, moves: [], start: start, cashStart: 50, payments: [pay1, pay2])
        XCTAssertEqual(l.figures(for: Date()).left, 940, accuracy: 0.001, "1000 - 90 (pagato io) + 30 (rimborso di Luca)")
        XCTAssertEqual(l.cashBalance(), 40, accuracy: 0.001, "50 - 10 dati a Marco in contanti")
    }

    func testViaggioAParteFuoriDalleStatistiche() {
        let aParte = trip("GBP", inStats: false)
        let conta = trip("EUR", inStats: true)
        let normale = expense(10), inViaggio = expense(20, trip: aParte), altro = expense(30, trip: conta)
        let s = statExpenses([normale, inViaggio, altro], trips: [aParte, conta])
        XCTAssertEqual(s.map(\.amount).sorted(), [10, 30])
    }

    func testApplePayAllEsteroVieneConvertito() {
        let t = trip("GBP")
        let e = Expense(amount: 12.75, categoryName: "Altro", date: Date(), note: "Pret")
        applyActiveTrip(e, raw: "12,75", trips: [t]) { $0 == "GBP" ? 0.85 : nil }
        XCTAssertEqual(e.tripID, t.uid)
        XCTAssertEqual(e.amount, 15, accuracy: 0.001)
        XCTAssertEqual(e.originalAmount, 12.75)
        XCTAssertEqual(e.originalCurrency, "GBP")
        XCTAssertEqual(t.lastRate, 0.85)

        let inEuro = Expense(amount: 10, categoryName: "Altro", date: Date(), note: "")
        applyActiveTrip(inEuro, raw: "€10,00", trips: [t]) { _ in 0.85 }
        XCTAssertEqual(inEuro.amount, 10, "Un importo già in euro non va convertito")
        XCTAssertEqual(inEuro.tripID, t.uid)

        let aCasa = Expense(amount: 10, categoryName: "Altro", date: Date(), note: "")
        applyActiveTrip(aCasa, raw: "10", trips: [trip("GBP", from: -10, to: -5)]) { _ in 0.85 }
        XCTAssertEqual(aCasa.tripID, "", "Fuori dalle date del viaggio la spesa resta normale")
        XCTAssertEqual(aCasa.amount, 10)
    }

    @MainActor
    func testBackupConViaggi() throws {
        let ctx = SharedStore.container.mainContext
        let t = trip("JPY", people: ["Aki"])
        t.name = "Prova backup \(UUID().uuidString.prefix(4))"
        ctx.insert(t)
        try ctx.save()
        defer { ctx.delete(t); try? ctx.save() }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let b = try dec.decode(Backup.self, from: XCTUnwrap(backupData(ctx)))
        let saved = try XCTUnwrap(b.trips?.first { $0.uid == t.uid })
        XCTAssertEqual(saved.currency, "JPY")
        XCTAssertTrue(saved.peopleJSON.contains("Aki"))
    }
}
