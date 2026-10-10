import SwiftUI
import SwiftData
import Charts

// MARK: - Calcoli (puri, provati nei test)

/// Dove si arriva allo stipendio continuando a spendere come finora.
struct Forecast {
    let start: Date          // ultimo stipendio
    let end: Date            // prossimo stipendio (escluso)
    let available: Double    // soldi disponibili adesso (banca + contanti)
    let spent: Double        // speso dall'ultimo stipendio
    let elapsedDays: Int     // giorni passati dallo stipendio, oggi compreso
    let daysLeft: Int        // giorni da oggi al prossimo stipendio, oggi compreso
    var avgPerDay: Double { spent / Double(max(elapsedDays, 1)) }
    var budgetPerDay: Double { max(available, 0) / Double(max(daysLeft, 1)) }
    /// Soldi che restano il giorno prima dello stipendio se la media resta questa.
    var projected: Double { available - avgPerDay * Double(max(daysLeft, 0)) }
    var lastDay: Date { Calendar.current.date(byAdding: .day, value: -1, to: end) ?? end }
}

func makeForecast(available: Double, spent: Double, period: (start: Date, end: Date), now: Date = Date()) -> Forecast {
    let cal = Calendar.current
    let elapsed = (cal.dateComponents([.day], from: cal.startOfDay(for: period.start), to: cal.startOfDay(for: now)).day ?? 0) + 1
    return Forecast(start: period.start, end: period.end, available: available, spent: spent,
                    elapsedDays: max(elapsed, 1), daysLeft: max(daysLeft(until: period.end, from: now), 0))
}

/// Una categoria confrontata con lo stesso numero di giorni del periodo precedente.
struct CategoryChange: Identifiable {
    let name: String
    let now: Double
    let before: Double
    var id: String { name }
    /// Variazione in percentuale (nil se prima non c'era nessuna spesa).
    var percent: Double? { before > 0 ? (now - before) / before * 100 : nil }
}

/// Confronta le spese per categoria da `start` a oggi con gli stessi giorni del periodo precedente.
func compareCategories(_ expenses: [Expense], current: (start: Date, end: Date), previousStart: Date,
                       now: Date = Date()) -> [CategoryChange] {
    let cal = Calendar.current
    let today = cal.startOfDay(for: now)
    let elapsed = (cal.dateComponents([.day], from: cal.startOfDay(for: current.start), to: today).day ?? 0) + 1
    let prevEnd = min(cal.date(byAdding: .day, value: elapsed, to: previousStart) ?? current.start, current.start)
    let nowEnd = cal.date(byAdding: .day, value: 1, to: today) ?? now
    func totals(_ a: Date, _ b: Date) -> [String: Double] {
        expenses.filter { $0.date >= a && $0.date < b }
            .reduce(into: [:]) { $0[$1.categoryRaw, default: 0] += $1.myAmount }
    }
    let n = totals(current.start, nowEnd), p = totals(previousStart, prevEnd)
    return Set(n.keys).union(p.keys)
        .map { CategoryChange(name: $0, now: n[$0] ?? 0, before: p[$0] ?? 0) }
        .filter { $0.now > 0 || $0.before > 0 }
        .sorted { max($0.now, $0.before) > max($1.now, $1.before) }
}

/// Totale speso per ogni giorno del mese (chiave: numero del giorno).
func dailyTotals(_ expenses: [Expense], month: Date) -> [Int: Double] {
    let cal = Calendar.current
    return expenses.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) }
        .reduce(into: [:]) { $0[cal.component(.day, from: $1.date), default: 0] += $1.myAmount }
}

/// Livello di colore da 0 (niente) a 4 (giorno più caro), in proporzione al giorno più caro del mese.
func spendLevel(_ amount: Double, max top: Double) -> Int {
    guard amount > 0, top > 0 else { return 0 }
    return min(4, max(1, Int((amount / top * 4).rounded(.up))))
}

// MARK: - Dati comuni alle sezioni

/// Raccoglie dal database quello che serve a previsione e confronto.
private struct PeriodData {
    let all: [Expense]
    let available: Double
    let period: (start: Date, end: Date)?
    let previousStart: Date?

    init(all raw: [Expense], trips: [Trip], incomes: [Income], moves: [SavingsMove], cash: [CashMove],
         account: Account?, payments: [TripPayment]) {
        let l = Ledger(incomes: incomes, expenses: raw, moves: moves, cash: cash, account: account, payments: payments)
        all = statExpenses(raw, trips: trips)
        available = l.figures(for: Date()).left + l.cashBalance()
        if let a = account, let p = payPeriod(day: a.salaryDay, customStart: a.periodStart, customEnd: a.periodEnd) {
            period = p
            previousStart = previousPeriod(before: p.start, day: a.salaryDay)?.start
        } else {
            period = nil; previousStart = nil
        }
    }

    func spent(from a: Date, to b: Date) -> Double {
        all.filter { $0.date >= a && $0.date < b }.reduce(0) { $0 + $1.myAmount }
    }
}

// MARK: - Previsione di fine periodo

struct ForecastSection: View {
    @Query private var raw: [Expense]
    @Query private var trips: [Trip]
    @Query private var incomes: [Income]
    @Query private var moves: [SavingsMove]
    @Query private var cash: [CashMove]
    @Query private var accounts: [Account]
    @Query private var payments: [TripPayment]

    private struct Point: Identifiable { let date: Date; let value: Double; let forecast: Bool; var id: String { "\(date)\(forecast)" } }

    var body: some View {
        let d = PeriodData(all: raw, trips: trips, incomes: incomes, moves: moves, cash: cash,
                           account: accounts.first, payments: payments)
        if let p = d.period {
            let f = makeForecast(available: d.available, spent: d.spent(from: p.start, to: Ledger.endOfToday), period: p)
            Section("Previsione") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Di questo passo, il \(f.lastDay.formatted(.dateTime.day().month(.wide))) avrai")
                        .font(.footnote).opacity(0.85)
                    Text((f.projected >= 0 ? "+ " : "− ") + eur(abs(f.projected)))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Spendi in media \(eur(f.avgPerDay)) al giorno, il budget è \(eur(f.budgetPerDay))")
                        .font(.footnote).opacity(0.85)
                }
                .foregroundStyle(.white).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: f.projected >= 0 ? [HeroStyle.top, HeroStyle.bottom] : [Color.red, Color.orange],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 18))
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)

                Chart(points(d, f)) { pt in
                    LineMark(x: .value("Giorno", pt.date), y: .value("Rimasti", pt.value),
                             series: .value("Tipo", pt.forecast ? "Previsione" : "Reale"))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(pt.forecast ? StrokeStyle(lineWidth: 2, dash: [5, 4]) : StrokeStyle(lineWidth: 2.5))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .frame(height: 160)
                Text("Linea piena: com'è andata. Tratteggio: previsione fino al prossimo stipendio.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func points(_ d: PeriodData, _ f: Forecast) -> [Point] {
        let cal = Calendar.current
        let startMoney = f.available + f.spent
        var out: [Point] = []
        var cum = 0.0
        for i in 0..<f.elapsedDays {
            guard let day = cal.date(byAdding: .day, value: i, to: cal.startOfDay(for: f.start)),
                  let next = cal.date(byAdding: .day, value: 1, to: day) else { continue }
            cum += d.spent(from: day, to: next)
            out.append(Point(date: day, value: startMoney - cum, forecast: false))
        }
        if let last = out.last {
            out.append(Point(date: last.date, value: last.value, forecast: true))
            out.append(Point(date: cal.startOfDay(for: f.lastDay), value: f.projected, forecast: true))
        }
        return out
    }
}

// MARK: - Confronto con il periodo precedente

struct ComparisonSection: View {
    @Query private var raw: [Expense]
    @Query private var trips: [Trip]
    @Query private var accounts: [Account]
    @Query(sort: \CategoryItem.order) private var cats: [CategoryItem]

    private func look(_ name: String) -> (icon: String, color: Color) {
        if let c = cats.first(where: { $0.name == name }) { return (c.icon, Color(hex: c.colorHex)) }
        return ("questionmark", .gray)
    }

    private func badge(_ c: CategoryChange) -> some View {
        Group {
            if let p = c.percent {
                Text("\(p > 0 ? "▲" : p < 0 ? "▼" : "=") \(Int(abs(p).rounded()))%")
                    .foregroundStyle(p > 0 ? Color.red : p < 0 ? Theme.accent : Color.secondary)
            } else {
                Text("nuova").foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.bold())
    }

    var body: some View {
        if let a = accounts.first, let p = payPeriod(day: a.salaryDay, customStart: a.periodStart, customEnd: a.periodEnd),
           let prev = previousPeriod(before: p.start, day: a.salaryDay) {
            let changes = compareCategories(statExpenses(raw, trips: trips), current: p, previousStart: prev.start)
            if !changes.isEmpty {
                let now = changes.reduce(0) { $0 + $1.now }, before = changes.reduce(0) { $0 + $1.before }
                let total = CategoryChange(name: "Totale", now: now, before: before)
                Section {
                    ForEach(changes) { c in
                        let l = look(c.name)
                        HStack(spacing: 12) {
                            Image(systemName: l.icon).foregroundStyle(.white)
                                .frame(width: 32, height: 32).background(l.color, in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.name).lineLimit(1)
                                Text("\(eur(c.now)) · prima \(eur(c.before))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            badge(c)
                        }
                    }
                    HStack {
                        Text("Totale").bold()
                        Spacer()
                        Text("\(eur(now)) · prima \(eur(before))").font(.subheadline).foregroundStyle(.secondary)
                        badge(total)
                    }
                } header: {
                    Text("Rispetto al periodo scorso")
                } footer: {
                    Text("Confronto con gli stessi giorni dopo lo stipendio precedente.")
                }
            }
        }
    }
}

// MARK: - Calendario delle spese

struct SpendingCalendarView: View {
    @Query(sort: \Expense.date, order: .reverse) private var raw: [Expense]
    @Query private var trips: [Trip]
    @Query(sort: \CategoryItem.order) private var cats: [CategoryItem]
    @State private var month = Date()
    @State private var selected: Int? = Calendar.current.component(.day, from: Date())

    private let cal = Calendar.current
    private static let levels = ["E9EEEC", "D6EFE5", "8FD3B5", "1D9E75", "0F4632"]

    private func look(_ name: String) -> (icon: String, color: Color) {
        if let c = cats.first(where: { $0.name == name }) { return (c.icon, Color(hex: c.colorHex)) }
        return ("questionmark", .gray)
    }

    var body: some View {
        let expenses = statExpenses(raw, trips: trips)
        let totals = dailyTotals(expenses, month: month)
        let top = totals.values.max() ?? 0
        let first = cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month
        let days = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        // Lunedì come primo giorno della settimana.
        let offset = (cal.component(.weekday, from: first) + 5) % 7
        let isThisMonth = cal.isDate(month, equalTo: Date(), toGranularity: .month)
        let today = cal.component(.day, from: Date())

        List {
            Section {
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                }.buttonStyle(.borderless)

                let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
                LazyVGrid(columns: columns, spacing: 5) {
                    ForEach(["L", "M", "M", "G", "V", "S", "D"].indices, id: \.self) { i in
                        Text(["L", "M", "M", "G", "V", "S", "D"][i]).font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 36) }
                    ForEach(1...days, id: \.self) { d in
                        let future = isThisMonth && d > today
                        let lvl = spendLevel(totals[d] ?? 0, max: top)
                        Button { selected = d } label: {
                            Text("\(d)").font(.caption.bold())
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .foregroundStyle(future ? Color.secondary : (lvl >= 3 ? Color.white : Color.primary))
                                .background(future ? Color.clear : Color(hex: Self.levels[lvl]).opacity(lvl == 0 ? 0.5 : 1),
                                            in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(selected == d ? HeroStyle.coral : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .disabled(future)
                    }
                }
                HStack(spacing: 6) {
                    Spacer()
                    Text("poco").font(.caption2).foregroundStyle(.secondary)
                    ForEach(1..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3).fill(Color(hex: Self.levels[i])).frame(width: 14, height: 14)
                    }
                    Text("tanto").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if let d = selected, d <= days, let date = cal.date(byAdding: .day, value: d - 1, to: first) {
                let list = expenses.filter { cal.isDate($0.date, inSameDayAs: date) }
                Section("\(date.formatted(.dateTime.weekday(.wide).day().month(.wide))) · \(eur(totals[d] ?? 0))") {
                    if list.isEmpty { Text("Nessuna spesa").foregroundStyle(.secondary) }
                    ForEach(list) { e in
                        let l = look(e.categoryRaw)
                        HStack(spacing: 12) {
                            Image(systemName: l.icon).foregroundStyle(.white)
                                .frame(width: 32, height: 32).background(l.color, in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.note.isEmpty ? e.categoryRaw : e.note).lineLimit(1)
                                Text(e.categoryRaw).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(eur(e.myAmount)).bold()
                        }
                    }
                }
            }
        }
        .navigationTitle("Calendario")
    }

    private func shift(_ n: Int) {
        month = cal.date(byAdding: .month, value: n, to: month) ?? month
        selected = nil
    }
}
