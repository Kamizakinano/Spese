import SwiftUI
import SwiftData
import Charts

// MARK: - Dettaglio di una categoria (dalle Statistiche)

enum CatScale: String, CaseIterable, Identifiable {
    case giorno = "Giorno", settimana = "Settimana", mese = "Mese", periodo = "Periodo", scegli = "Scegli"
    var id: String { rawValue }
}

/// L'intervallo di `scale` che contiene `anchor`, spostato indietro di `back` volte (0 = quello attuale).
/// "Periodo" va da uno stipendio all'altro; senza giorno dello stipendio vale come il mese.
func scaleRange(_ scale: CatScale, anchor: Date, back: Int, payDay: Int?) -> (start: Date, end: Date) {
    let cal = Calendar.current
    let day = cal.startOfDay(for: anchor)
    switch scale {
    case .giorno, .scegli:
        let s = cal.date(byAdding: .day, value: -back, to: day) ?? day
        return (s, cal.date(byAdding: .day, value: 1, to: s) ?? s)
    case .settimana:
        let w = weekRange(anchor)
        let s = cal.date(byAdding: .day, value: -7 * back, to: w.start) ?? w.start
        return (s, cal.date(byAdding: .day, value: 7, to: s) ?? s)
    case .mese:
        let m = cal.date(byAdding: .month, value: -back, to: anchor) ?? anchor
        let iv = cal.dateInterval(of: .month, for: m)
        return (iv?.start ?? day, iv?.end ?? day)
    case .periodo:
        guard let d = payDay, var p = payPeriod(day: d, customStart: nil, customEnd: nil, now: anchor) else {
            return scaleRange(.mese, anchor: anchor, back: back, payDay: nil)
        }
        for _ in 0..<back { if let q = previousPeriod(before: p.start, day: d) { p = q } }
        return p
    }
}

/// Testo breve di un intervallo: "18 ott", "13–19 ott", "ottobre".
func rangeText(_ r: (start: Date, end: Date)) -> String {
    let cal = Calendar.current
    let last = cal.date(byAdding: .day, value: -1, to: r.end) ?? r.start
    if cal.isDate(r.start, inSameDayAs: last) { return r.start.formatted(.dateTime.day().month(.abbreviated)) }
    return "\(r.start.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated)))"
}

/// Totale della categoria per ogni giorno dell'intervallo (indice 0 = primo giorno).
func dailyCategoryTotals(_ expenses: [Expense], range: (start: Date, end: Date)) -> [Double] {
    let cal = Calendar.current
    let n = max((cal.dateComponents([.day], from: range.start, to: range.end).day ?? 1), 1)
    var out = Array(repeating: 0.0, count: n)
    for e in expenses where e.date >= range.start && e.date < range.end {
        let i = cal.dateComponents([.day], from: range.start, to: cal.startOfDay(for: e.date)).day ?? 0
        if i >= 0 && i < n { out[i] += e.myAmount }
    }
    return out
}

struct CategoryDetailView: View {
    let category: String
    @Query private var raw: [Expense]
    @Query private var trips: [Trip]
    @Query private var accounts: [Account]
    @Query(sort: \CategoryItem.order) private var cats: [CategoryItem]
    @State private var scale: CatScale = .periodo
    @State private var compareBack = 1
    @State private var fromA = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var toA = Date()
    @State private var fromB = Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date()
    @State private var editing: Expense?

    private struct Bar: Identifiable { let i: Int; let value: Double; let series: String; var id: String { "\(i)\(series)" } }

    private var expenses: [Expense] {
        statExpenses(raw, trips: trips).filter { $0.categoryRaw == category && $0.date < Ledger.endOfToday }
    }
    private var payDay: Int? { accounts.first.map(\.salaryDay) }
    private var rangeA: (start: Date, end: Date) {
        if scale == .scegli {
            let cal = Calendar.current
            let s = cal.startOfDay(for: min(fromA, toA)), e = cal.startOfDay(for: max(fromA, toA))
            return (s, cal.date(byAdding: .day, value: 1, to: e) ?? e)
        }
        return scaleRange(scale, anchor: Date(), back: 0, payDay: payDay)
    }
    private var rangeB: (start: Date, end: Date) {
        if scale == .scegli {
            let cal = Calendar.current
            let len = cal.dateComponents([.day], from: rangeA.start, to: rangeA.end).day ?? 1
            let s = cal.startOfDay(for: fromB)
            return (s, cal.date(byAdding: .day, value: len, to: s) ?? s)
        }
        return scaleRange(scale, anchor: Date(), back: compareBack, payDay: payDay)
    }
    private func total(_ r: (start: Date, end: Date)) -> Double {
        expenses.filter { $0.date >= r.start && $0.date < r.end }.reduce(0) { $0 + $1.myAmount }
    }
    private var color: Color { cats.first { $0.name == category }.map { Color(hex: $0.colorHex) } ?? Theme.accent }
    private var icon: String { cats.first { $0.name == category }?.icon ?? "tag" }

    var body: some View {
        let a = rangeA, b = rangeB
        let ta = total(a), tb = total(b)
        let list = expenses.filter { $0.date >= a.start && $0.date < a.end }.sorted { $0.date > $1.date }
        List {
            Section {
                Picker("Quanto", selection: $scale) {
                    ForEach(CatScale.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if scale == .scegli {
                    DatePicker("Dal", selection: $fromA, displayedComponents: .date)
                    DatePicker("Al", selection: $toA, displayedComponents: .date)
                    DatePicker("Confronta dal", selection: $fromB, displayedComponents: .date)
                } else {
                    Picker("Confronta con", selection: $compareBack) {
                        ForEach(1...12, id: \.self) { n in
                            Text(rangeText(scaleRange(scale, anchor: Date(), back: n, payDay: payDay))).tag(n)
                        }
                    }
                }
            }
            Section {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading) {
                        Text(rangeText(a)).font(.caption).foregroundStyle(.secondary)
                        Text(eur(ta)).font(.title2.bold())
                    }
                    Spacer()
                    Text("vs").foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(rangeText(b)).font(.caption).foregroundStyle(.secondary)
                        Text(eur(tb)).font(.title2.bold()).foregroundStyle(.secondary)
                    }
                }
                let diff = ta - tb
                Text(abs(diff) < 0.005 ? "Uguale" :
                        "\(diff > 0 ? "▲ +" : "▼ −")\(eur(abs(diff)))" + (tb > 0 ? " (\(diff > 0 ? "+" : "−")\(Int((abs(diff) / tb * 100).rounded()))%)" : ""))
                    .font(.subheadline.bold())
                    .foregroundStyle(diff > 0.005 ? Color.orange : Theme.accent)
                    .frame(maxWidth: .infinity)
                let da = dailyCategoryTotals(expenses, range: a), db = dailyCategoryTotals(expenses, range: b)
                if da.count > 1 && da.count <= 62 {
                    let bars = da.enumerated().map { Bar(i: $0.offset + 1, value: $0.element, series: "Scelto") }
                        + db.prefix(da.count).enumerated().map { Bar(i: $0.offset + 1, value: $0.element, series: "Confronto") }
                    Chart(bars) { bar in
                        BarMark(x: .value("Giorno", bar.i), y: .value("€", bar.value))
                            .position(by: .value("Serie", bar.series))
                            .foregroundStyle(by: .value("Serie", bar.series))
                    }
                    .chartForegroundStyleScale(["Scelto": color, "Confronto": color.opacity(0.3)])
                    .frame(height: 150)
                    Text("Giorni dall'inizio dell'intervallo. Colore pieno: \(rangeText(a)); chiaro: \(rangeText(b)).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Le spese (\(list.count))") {
                if list.isEmpty { Text("Nessuna spesa in questo intervallo.").foregroundStyle(.secondary) }
                ForEach(list) { e in
                    Button { editing = e } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.note.isEmpty ? e.categoryRaw : e.note).foregroundStyle(.primary).lineLimit(1)
                                Text(e.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(eur(e.myAmount)).bold().foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .navigationTitle(category)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { Label(category, systemImage: icon).labelStyle(.titleAndIcon).font(.headline) } }
        .onChange(of: scale) { _, _ in compareBack = 1 }
        .sheet(item: $editing) { e in
            if let t = trips.first(where: { $0.uid == e.tripID }) { TripExpenseEditor(trip: t, editing: e) }
            else { AddExpenseView(defaultDate: e.date, editing: e) }
        }
    }
}
