import SwiftUI
import SwiftData
import Charts

struct DayPoint: Identifiable { let day: Int; let cum: Double; var id: Int { day } }
struct MonthTotal: Identifiable { let id: Int; let label: String; let spent: Double; let income: Double }

struct StatsView: View {
    @Query private var all: [Expense]
    @Query private var incomes: [Income]
    @Query private var moves: [SavingsMove]
    @Query private var cashMoves: [CashMove]
    @Query private var accounts: [Account]

    private let cal = Calendar.current

    private func inMonth(_ d: Date) -> [Expense] {
        all.filter { cal.isDate($0.date, equalTo: d, toGranularity: .month) }
    }
    private var current: [Expense] { inMonth(Date()) }
    private var budget: Double {
        let l = Ledger(incomes: incomes, expenses: all, moves: moves, cash: cashMoves, account: accounts.first)
        guard let iv = cal.dateInterval(of: .month, for: Date()) else { return 0 }
        let received = cashMoves.filter { !$0.bank && $0.date >= iv.start && $0.date < iv.end }.reduce(0) { $0 + $1.amount }
        return l.figures(for: Date()).budget + l.cashBalance(asOf: iv.start) + received
    }

    private var points: [DayPoint] {
        let today = cal.component(.day, from: Date())
        var cum = 0.0
        return (1...today).map { d in
            cum += current.filter { cal.component(.day, from: $0.date) == d }.reduce(0) { $0 + $1.amount }
            return DayPoint(day: d, cum: cum)
        }
    }

    private var months: [MonthTotal] {
        (0..<6).reversed().map { i in
            let d = cal.date(byAdding: .month, value: -i, to: Date()) ?? Date()
            let inc = incomes.filter { $0.kind != initialKind && $0.kind != "Rimborso" && cal.isDate($0.date, equalTo: d, toGranularity: .month) }
            return MonthTotal(id: i, label: d.formatted(.dateTime.month(.abbreviated)),
                              spent: inMonth(d).reduce(0) { $0 + $1.amount },
                              income: inc.reduce(0) { $0 + $1.amount })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                let total = current.reduce(0) { $0 + $1.amount }
                let today = max(cal.component(.day, from: Date()), 1)
                Section("Questo mese") {
                    HStack { Text("Media giornaliera"); Spacer(); Text(eur(total / Double(today))).bold() }
                    HStack { Text("Numero di spese"); Spacer(); Text("\(current.count)").bold() }
                    if let top = current.max(by: { $0.amount < $1.amount }) {
                        HStack { Text("Spesa più alta"); Spacer(); Text(eur(top.amount)).bold() }
                    }
                }
                Section("Andamento del mese") {
                    Chart {
                        ForEach(points) { p in
                            AreaMark(x: .value("Giorno", p.day), y: .value("Speso", p.cum))
                                .foregroundStyle(Theme.accent.opacity(0.2))
                            LineMark(x: .value("Giorno", p.day), y: .value("Speso", p.cum))
                                .foregroundStyle(Theme.accent)
                        }
                        if budget > 0 {
                            RuleMark(y: .value("Budget", budget))
                                .foregroundStyle(.red).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        }
                    }.frame(height: 190)
                    if budget > 0 { Text("Linea rossa = soldi a disposizione nel mese").font(.caption).foregroundStyle(.secondary) }
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
}
