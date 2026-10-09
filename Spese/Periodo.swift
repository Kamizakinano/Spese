import SwiftUI
import SwiftData

// MARK: - Riepilogo del periodo tra due stipendi

struct CategoryAmount: Identifiable {
    let name: String
    let total: Double
    var id: String { name }
}

struct PeriodSummary {
    let start: Date
    let end: Date
    let total: Double
    let count: Int
    let income: Double
    let byCategory: [CategoryAmount]
}

/// Totali di un periodo: spese (carta e contanti), entrate (senza il saldo iniziale) e categorie.
func summarize(expenses: [Expense], incomes: [Income], start: Date, end: Date) -> PeriodSummary {
    let ex = expenses.filter { $0.date >= start && $0.date < end }
    let cats = Dictionary(grouping: ex, by: \.categoryRaw)
        .map { CategoryAmount(name: $0.key, total: $0.value.reduce(0) { $0 + $1.myAmount }) }
        .filter { $0.total > 0 }
        .sorted { $0.total > $1.total }
    let inc = incomes.filter { $0.kind != initialKind && $0.date >= start && $0.date < end }
        .reduce(0) { $0 + $1.amount }
    return PeriodSummary(start: start, end: end, total: ex.reduce(0) { $0 + $1.myAmount },
                         count: ex.count, income: inc, byCategory: cats)
}

/// Il periodo che finisce il giorno `start` (da uno stipendio al precedente).
func previousPeriod(before start: Date, day: Int) -> (start: Date, end: Date)? {
    let cal = Calendar.current
    guard let dayBefore = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: start)),
          let prev = lastPayday(day: day, from: dayBefore) else { return nil }
    return (prev, cal.startOfDay(for: start))
}

// MARK: - Periodo dei limiti per categoria

let limitPeriodOnKey = "limitPeriodOn"
let limitStartKey = "limitStart"   // primo giorno (incluso)
let limitEndKey = "limitEnd"       // giorno dopo l'ultimo (escluso)

/// Periodo su cui si contano i limiti per categoria.
/// Spento: il mese di calendario mostrato. Acceso: le date scelte; finite quelle, il periodo dello stipendio.
func limitPeriod(on: Bool, customStart: Date?, customEnd: Date?, pay: (start: Date, end: Date)?,
                 month: Date, now: Date = Date()) -> (start: Date, end: Date)? {
    let cal = Calendar.current
    if on {
        if let s = customStart.map({ cal.startOfDay(for: $0) }), let e = customEnd.map({ cal.startOfDay(for: $0) }),
           s < e, e > cal.startOfDay(for: now) {
            return (s, e)
        }
        return pay
    }
    guard let iv = cal.dateInterval(of: .month, for: month) else { return nil }
    return (iv.start, iv.end)
}

/// Data salvata nelle impostazioni (0 = non impostata).
func storedDate(_ key: String) -> Date? {
    let v = UserDefaults.standard.double(forKey: key)
    return v > 0 ? Date(timeIntervalSinceReferenceDate: v) : nil
}

/// Chiave dell'inizio dell'ultimo periodo già mostrato nel riepilogo automatico.
let summarySeenKey = "summarySeenStart"

struct PeriodSummaryView: View {
    @Query(sort: \CategoryItem.order) private var cats: [CategoryItem]
    let title: String
    let summary: PeriodSummary
    let previous: PeriodSummary?

    private func look(_ n: String) -> (icon: String, color: Color) {
        if let c = cats.first(where: { $0.name == n }) { return (c.icon, Color(hex: c.colorHex)) }
        return ("questionmark.circle", .gray)
    }
    private var lastDay: Date { Calendar.current.date(byAdding: .day, value: -1, to: summary.end) ?? summary.end }
    private var range: String {
        "\(summary.start.formatted(.dateTime.day().month(.wide))) – \(lastDay.formatted(.dateTime.day().month(.wide)))"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(range).font(.subheadline).opacity(0.85)
                    Text(eur(summary.total)).font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("spesi in \(summary.count) \(summary.count == 1 ? "spesa" : "spese")").font(.footnote).opacity(0.9)
                    if let p = previous, p.total > 0 {
                        let diff = (summary.total - p.total) / p.total * 100
                        Text(abs(diff) < 1 ? "Come nel periodo prima (\(eur(p.total)))"
                             : "\(diff > 0 ? "+" : "")\(Int(diff.rounded()))% rispetto al periodo prima (\(eur(p.total)))")
                            .font(.footnote).bold()
                    }
                }
                .foregroundStyle(.white).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Theme.accent, Color(hex: "0F6E56")], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 22))
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)

            Section {
                HStack { Text("Entrate nel periodo"); Spacer(); Text(eur(summary.income)).bold() }
                if summary.income > 0 {
                    HStack {
                        Text(summary.income >= summary.total ? "Avanzato" : "Speso più delle entrate")
                        Spacer()
                        Text(eur(abs(summary.income - summary.total))).bold()
                            .foregroundStyle(summary.income >= summary.total ? Theme.accent : .red)
                    }
                }
            }

            Section("Dove sono andati i soldi") {
                if summary.byCategory.isEmpty { Text("Nessuna spesa in questo periodo").foregroundStyle(.secondary) }
                ForEach(summary.byCategory) { c in
                    let l = look(c.name)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(c.name, systemImage: l.icon).foregroundStyle(l.color)
                            Spacer()
                            Text(eur(c.total)).bold()
                        }
                        ProgressView(value: c.total, total: max(summary.total, 0.01)).tint(l.color)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Elenco dei riepiloghi (periodo in corso e precedente), per la scheda Statistiche.
struct PeriodSummariesLinks: View {
    @Query private var allRaw: [Expense]
    @Query private var trips: [Trip]
    private var all: [Expense] { statExpenses(allRaw, trips: trips) }
    @Query private var incomes: [Income]
    @Query private var accounts: [Account]

    var body: some View {
        if let a = accounts.first, let p = payPeriod(day: a.salaryDay, customStart: a.periodStart, customEnd: a.periodEnd) {
            let current = summarize(expenses: all, incomes: incomes, start: p.start, end: p.end)
            let prevRange = previousPeriod(before: p.start, day: a.salaryDay)
            let prev = prevRange.map { summarize(expenses: all, incomes: incomes, start: $0.start, end: $0.end) }
            let beforePrev = prevRange.flatMap { previousPeriod(before: $0.start, day: a.salaryDay) }
                .map { summarize(expenses: all, incomes: incomes, start: $0.start, end: $0.end) }
            Section("Da uno stipendio all'altro") {
                NavigationLink {
                    PeriodSummaryView(title: "Periodo in corso", summary: current, previous: prev)
                } label: {
                    HStack { Label("Periodo in corso", systemImage: "calendar"); Spacer(); Text(eur(current.total)).foregroundStyle(.secondary) }
                }
                if let prev {
                    NavigationLink {
                        PeriodSummaryView(title: "Periodo precedente", summary: prev, previous: beforePrev)
                    } label: {
                        HStack { Label("Periodo precedente", systemImage: "clock.arrow.circlepath"); Spacer(); Text(eur(prev.total)).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }
}
