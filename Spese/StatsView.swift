import SwiftUI
import SwiftData
import Charts

struct DayPoint: Identifiable { let day: Int; let cum: Double; var id: Int { day } }
struct MonthTotal: Identifiable { let id: Int; let label: String; let spent: Double; let income: Double }

struct StatsView: View {
    @Query private var allRaw: [Expense]
    @Query private var trips: [Trip]
    /// Spese che contano nelle statistiche (senza i viaggi tenuti a parte).
    private var all: [Expense] { statExpenses(allRaw, trips: trips) }
    @Query private var incomes: [Income]
    @Query private var moves: [SavingsMove]
    @Query private var cashMoves: [CashMove]
    @Query private var accounts: [Account]
    @Query private var payments: [TripPayment]

    private let cal = Calendar.current

    private func inMonth(_ d: Date) -> [Expense] {
        all.filter { cal.isDate($0.date, equalTo: d, toGranularity: .month) }
    }
    private var current: [Expense] { inMonth(Date()) }
    private var budget: Double {
        let l = Ledger(incomes: incomes, expenses: allRaw, moves: moves, cash: cashMoves, account: accounts.first, payments: payments)
        guard let iv = cal.dateInterval(of: .month, for: Date()) else { return 0 }
        let received = cashMoves.filter { !$0.bank && $0.date >= iv.start && $0.date < iv.end }.reduce(0) { $0 + $1.amount }
        return l.figures(for: Date()).budget + l.cashBalance(asOf: iv.start) + received
    }

    private var points: [DayPoint] {
        let today = cal.component(.day, from: Date())
        var cum = 0.0
        return (1...today).map { d in
            cum += current.filter { cal.component(.day, from: $0.date) == d }.reduce(0) { $0 + $1.myAmount }
            return DayPoint(day: d, cum: cum)
        }
    }

    private var months: [MonthTotal] {
        (0..<6).reversed().map { i in
            let d = cal.date(byAdding: .month, value: -i, to: Date()) ?? Date()
            let inc = incomes.filter { $0.kind != initialKind && $0.kind != "Rimborso" && cal.isDate($0.date, equalTo: d, toGranularity: .month) }
            return MonthTotal(id: i, label: d.formatted(.dateTime.month(.abbreviated)),
                              spent: inMonth(d).reduce(0) { $0 + $1.myAmount },
                              income: inc.reduce(0) { $0 + $1.amount })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                let total = current.reduce(0) { $0 + $1.myAmount }
                let today = max(cal.component(.day, from: Date()), 1)
                PeriodSummariesLinks()
                Section("Questo mese") {
                    HStack(spacing: 0) {
                        statColumn("Media\ngiornaliera", eur(total / Double(today)))
                        Divider().frame(height: 44)
                        statColumn("Numero di\nspese", "\(current.count)")
                        Divider().frame(height: 44)
                        statColumn("Spesa\npiù alta", current.max(by: { $0.amount < $1.amount }).map { eur($0.amount) } ?? "–")
                    }
                    .padding(.vertical, 4)
                }
                Section("Andamento del mese") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 14) {
                            Spacer()
                            if budget > 0 { legendDot(.red, "Disponibilità") }
                            legendDot(Theme.accent, "Spese")
                        }
                        Chart {
                            ForEach(points) { p in
                                AreaMark(x: .value("Giorno", p.day), y: .value("Speso", p.cum))
                                    .foregroundStyle(Theme.accent.opacity(0.2))
                                LineMark(x: .value("Giorno", p.day), y: .value("Speso", p.cum))
                                    .foregroundStyle(Theme.accent).lineStyle(StrokeStyle(lineWidth: 2.5))
                            }
                            if budget > 0 {
                                RuleMark(y: .value("Budget", budget))
                                    .foregroundStyle(.red).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: 5)) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                                AxisValueLabel()
                            }
                        }
                        .frame(height: 200)
                        if budget > 0 {
                            Divider()
                            Text("Linea rossa = soldi a disposizione nel mese").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Entrate e uscite, ultimi 6 mesi") {
                    Chart {
                        ForEach(months) { m in
                            BarMark(x: .value("Mese", m.label), y: .value("€", m.income))
                                .foregroundStyle(by: .value("Tipo", "Entrate"))
                                .position(by: .value("Tipo", "Entrate"))
                            BarMark(x: .value("Mese", m.label), y: .value("€", m.spent))
                                .foregroundStyle(by: .value("Tipo", "Uscite"))
                                .position(by: .value("Tipo", "Uscite"))
                        }
                    }
                    .chartForegroundStyleScale(["Entrate": Theme.accent, "Uscite": Color.red])
                    .frame(height: 200)
                }
                Section { NavigationLink { TagsView() } label: { Label("Totale per viaggio o tag", systemImage: "tag") } }
            }
            .navigationTitle("Statistiche")
        }
    }

    private func statColumn(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private func legendDot(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title).font(.footnote)
        }
    }
}
