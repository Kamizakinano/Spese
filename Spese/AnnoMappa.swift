import SwiftUI
import SwiftData
import MapKit
import CoreLocation

// MARK: - Funzioni facoltative (Altro → Funzioni)

let yearRecapKey = "yearRecapOn"     // Il tuo anno in Spese
let spendMapKey = "spendMapOn"       // Mappa delle spese

// MARK: - Il tuo anno

struct YearRecap {
    var year: Int
    var total: Double = 0
    var count = 0
    var perDay: Double = 0
    var topMonth: (date: Date, total: Double)?
    var topCategory: (name: String, total: Double)?
    var topPlace: (name: String, times: Int)?
    var saved: Double = 0
    var salary: Double = 0
}

func yearRecap(year: Int, expenses: [Expense], incomes: [Income], moves: [SavingsMove], now: Date = Date()) -> YearRecap {
    let cal = Calendar.current
    var r = YearRecap(year: year)
    guard let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
          let end = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return r }
    let cutoff = min(end, cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? end)
    let ex = expenses.filter { $0.date >= start && $0.date < cutoff }
    r.total = ex.reduce(0) { $0 + everydaySpend($1) }
    r.count = ex.count
    let days = max(cal.dateComponents([.day], from: start, to: cutoff).day ?? 1, 1)
    r.perDay = r.total / Double(days)
    let months = Dictionary(grouping: ex) { cal.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        .mapValues { $0.reduce(0) { $0 + everydaySpend($1) } }
    if let m = months.max(by: { $0.value < $1.value }) { r.topMonth = (m.key, m.value) }
    let cats = Dictionary(grouping: ex, by: \.categoryRaw).mapValues { $0.reduce(0) { $0 + everydaySpend($1) } }
    if let c = cats.max(by: { $0.value < $1.value }) { r.topCategory = (c.key, c.value) }
    let places = Dictionary(grouping: ex.filter { !$0.note.isEmpty && $0.planID.isEmpty }) {
        $0.note.trimmingCharacters(in: .whitespaces).capitalized
    }.mapValues(\.count)
    if let p = places.max(by: { $0.value < $1.value }), p.value > 1 { r.topPlace = (p.key, p.value) }
    let inc = incomes.filter { $0.date >= start && $0.date < cutoff }
    r.saved = inc.reduce(0) { $0 + $1.saved } + moves.filter { $0.date >= start && $0.date < cutoff }.reduce(0) { $0 + $1.amount }
    r.salary = inc.filter { $0.kind == "Stipendio" }.reduce(0) { $0 + $1.amount }
    return r
}

struct YearRecapView: View {
    @Query private var raw: [Expense]
    @Query private var trips: [Trip]
    @Query private var incomes: [Income]
    @Query private var moves: [SavingsMove]
    @State private var year: Int

    init(year: Int = Calendar.current.component(.year, from: Date())) { _year = State(initialValue: year) }

    var body: some View {
        let r = yearRecap(year: year, expenses: statExpenses(raw, trips: trips), incomes: incomes, moves: moves)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button { year -= 1 } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text("Il tuo \(String(year))").font(.headline)
                    Spacer()
                    Button { year += 1 } label: { Image(systemName: "chevron.right") }
                        .disabled(year >= Calendar.current.component(.year, from: Date()))
                }
                .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hai speso").font(.footnote).textCase(.uppercase).opacity(0.8)
                    Text(eur(r.total)).font(.system(size: 40, weight: .heavy, design: .rounded))
                    Text("in \(r.count) spese, \(eur(r.perDay)) al giorno").font(.subheadline).opacity(0.85)
                }
                if let m = r.topMonth {
                    tile("Mese più caro", "\(m.date.formatted(.dateTime.month(.wide).locale(Locale(identifier: "it_IT"))).capitalized) · \(eur(m.total))")
                }
                if let c = r.topCategory { tile("Categoria preferita", "\(c.name) · \(eur(c.total))") }
                if let p = r.topPlace { tile("Il posto dove torni di più", "\(p.name) · \(p.times) volte") }
                if r.saved > 0 {
                    tile("Messi da parte", eur(r.saved) + (r.salary > 0 ? " · \(Int((r.saved / r.salary * 100).rounded())) % dello stipendio" : ""))
                }
            }
            .foregroundStyle(.white)
            .padding(20)
        }
        .background(LinearGradient(colors: [HeroStyle.top, HeroStyle.bottom, Color(hex: "14211C")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
        .navigationTitle("Il tuo anno").navigationBarTitleDisplayMode(.inline)
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.footnote).opacity(0.8)
            Text(value).font(.title3.bold())
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// A fine anno (dal 20 dicembre al 10 gennaio) la Home ricorda che il riassunto è pronto.
func yearRecapSeason(_ now: Date) -> Int? {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: now)
    guard let y = c.year, let m = c.month, let d = c.day else { return nil }
    if m == 12 && d >= 20 { return y }
    if m == 1 && d <= 10 { return y - 1 }
    return nil
}

// MARK: - Mappa delle spese

/// Posizione del telefono, chiesta solo se la mappa è accesa.
final class SpendLocation: NSObject, CLLocationManagerDelegate {
    static let shared = SpendLocation()
    private let manager = CLLocationManager()
    private(set) var last: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    func requestPermission() { manager.requestWhenInUseAuthorization() }
    /// Chiede la posizione attuale (arriva dopo qualche istante).
    func refresh() {
        guard UserDefaults.standard.bool(forKey: spendMapKey) else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .notDetermined: manager.requestWhenInUseAuthorization()
        default: break
        }
    }
    /// L'ultima posizione, se recente (meno di 10 minuti).
    var recent: CLLocation? {
        guard let l = last ?? manager.location, abs(l.timestamp.timeIntervalSinceNow) < 600 else { return nil }
        return l
    }
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) { last = locs.last }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}
    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        if m.authorizationStatus == .authorizedWhenInUse || m.authorizationStatus == .authorizedAlways { m.requestLocation() }
    }
}

/// Un posto sulla mappa: spese vicine (circa 100 metri) messe insieme.
struct SpendPlace: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let name: String
    let total: Double
    let count: Int
}

func spendPlaces(_ expenses: [Expense]) -> [SpendPlace] {
    let located = expenses.filter { $0.latitude != 0 || $0.longitude != 0 }
    let groups = Dictionary(grouping: located) { e in
        "\((e.latitude * 1000).rounded() / 1000),\((e.longitude * 1000).rounded() / 1000)"
    }
    return groups.map { key, list in
        let lat = list.reduce(0) { $0 + $1.latitude } / Double(list.count)
        let lon = list.reduce(0) { $0 + $1.longitude } / Double(list.count)
        let names = Dictionary(grouping: list) { $0.note.isEmpty ? $0.categoryRaw : $0.note }.mapValues(\.count)
        return SpendPlace(id: key, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                          name: names.max { $0.value < $1.value }?.key ?? "",
                          total: list.reduce(0) { $0 + everydaySpend($1) }, count: list.count)
    }
    .sorted { $0.total > $1.total }
}

struct SpendMapView: View {
    @Query private var raw: [Expense]
    @Query private var trips: [Trip]
    @State private var months = 1

    var body: some View {
        let from = Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? Date()
        let places = spendPlaces(statExpenses(raw, trips: trips).filter { $0.date >= from && $0.date < Ledger.endOfToday })
        let top = places.first?.total ?? 1
        List {
            Section {
                Picker("Periodo", selection: $months) {
                    Text("1 mese").tag(1); Text("3 mesi").tag(3); Text("1 anno").tag(12)
                }.pickerStyle(.segmented)
                if places.isEmpty {
                    Text("Ancora nessuna spesa con il luogo. Da quando hai acceso la mappa, le spese inserite nell'app ricordano dove sei.")
                        .foregroundStyle(.secondary)
                } else {
                    Map {
                        ForEach(places) { p in
                            Annotation(p.name, coordinate: p.coordinate) {
                                Text(eur(p.total)).font(.caption2.bold()).foregroundStyle(.white).lineLimit(1)
                                    .padding(6).frame(minWidth: 30 + 30 * p.total / top)
                                    .background(Theme.accent, in: Capsule())
                            }
                        }
                    }
                    .frame(height: 300)
                    .listRowInsets(EdgeInsets())
                }
            }
            if !places.isEmpty {
                Section("Dove spendi di più") {
                    ForEach(places.prefix(10)) { p in
                        LabeledContent { Text(eur(p.total)) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).lineLimit(1)
                                Text("\(p.count) \(p.count == 1 ? "spesa" : "spese")").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Dove spendi").navigationBarTitleDisplayMode(.inline)
    }
}
