import SwiftUI
import SwiftData
import Charts

// MARK: - Prossimi 30 giorni: previsione del saldo della carta

let dailySaveKey = "dailySaveAmount"          // euro da mettere da parte ogni giorno (0 = spento)
let dailySaveMoveKey = "dailySaveMove"        // spostarli davvero nei Risparmi ogni sera
let dailySaveGoalKey = "dailySaveGoal"        // obiettivo a cui aggiungerli ("" = nessuno)
let dailySaveLastKey = "dailySaveLast"        // ultimo giorno già messo da parte
let forecastDailyKey = "forecastIncludesDaily"

/// Un movimento previsto: uscita (negativa) o entrata (positiva).
struct PlannedMove: Identifiable {
    let id = UUID()
    let name: String
    let date: Date
    let amount: Double
    let icon: String
}

/// Le date di un evento mensile (giorno `day`) dal mese `nextKey` fino a `end` escluso.
func monthlyDates(nextKey: String, day: Int, until end: Date) -> [Date] {
    var out: [Date] = []
    var key = nextKey
    for _ in 0..<24 {
        guard let d = nextRenewal(nextKey: key, day: day), d < end else { break }
        out.append(d)
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 2 else { break }
        key = p[1] == 12 ? String(format: "%04d-01", p[0] + 1) : String(format: "%04d-%02d", p[0], p[1] + 1)
    }
    return out
}

/// Uscite ed entrate note dei prossimi `days` giorni: spese con data futura (carta), rate,
/// spese ricorrenti e abbonamenti, stipendio automatico.
func plannedMoves(expenses: [Expense], recurring: [Recurring], account: Account?, now: Date = Date(), days: Int = 30) -> [PlannedMove] {
    let cal = Calendar.current
    let from = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
    let end = cal.date(byAdding: .day, value: days + 1, to: cal.startOfDay(for: now)) ?? now
    var out = expenses.filter { !$0.isCash && $0.paidByMe && $0.date >= from && $0.date < end }
        .map { PlannedMove(name: $0.note.isEmpty ? $0.categoryRaw : $0.note, date: $0.date, amount: -$0.amount,
                           icon: $0.planID.isEmpty ? "calendar" : "creditcard") }
    for r in recurring {
        for d in monthlyDates(nextKey: r.nextKey, day: r.day, until: end) where d >= from {
            out.append(PlannedMove(name: r.name, date: d, amount: -r.amount, icon: r.isSubscription ? "play.rectangle" : "repeat"))
        }
    }
    if let a = account, a.salaryAmount > 0, !a.salaryNextKey.isEmpty {
        let net = a.salaryAmount - splitSaving(total: a.salaryAmount, mode: a.salaryMode, value: a.salaryValue)
        for d in monthlyDates(nextKey: a.salaryNextKey, day: a.salaryDay, until: end) where d >= from {
            out.append(PlannedMove(name: "Stipendio", date: d, amount: net, icon: "eurosign.circle"))
        }
    }
    return out.sorted { $0.date < $1.date }
}

/// Spesa media di tutti i giorni con la carta negli ultimi 30 giorni, senza bollette, rate e spese ricorrenti.
func dailyCardAverage(_ expenses: [Expense], recurringNames: Set<String>, now: Date = Date()) -> Double {
    let cal = Calendar.current
    let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
    let start = cal.date(byAdding: .day, value: -30, to: end) ?? now
    let sum = expenses.filter {
        !$0.isCash && $0.paidByMe && $0.date >= start && $0.date < end && $0.planID.isEmpty
            && !isBillCategory($0.categoryRaw) && !recurringNames.contains($0.note)
    }.reduce(0) { $0 + everydaySpend($1) }
    return sum / 30
}

/// Saldo previsto giorno per giorno (oggi compreso) e saldo dopo ogni movimento.
struct Projection {
    var points: [(date: Date, balance: Double)] = []
    var after: [UUID: Double] = [:]
    var lowest: (date: Date, balance: Double)? { points.min { $0.balance < $1.balance } }
}

func project(start: Double, moves: [PlannedMove], perDay: Double, now: Date = Date(), days: Int = 30) -> Projection {
    let cal = Calendar.current
    var p = Projection()
    var bal = start
    let today = cal.startOfDay(for: now)
    p.points.append((today, bal))
    for i in 1...days {
        guard let day = cal.date(byAdding: .day, value: i, to: today) else { continue }
        bal -= perDay
        for m in moves where cal.isDate(m.date, inSameDayAs: day) {
            bal += m.amount
            p.after[m.id] = bal
        }
        p.points.append((day, bal))
    }
    return p
}

/// Quanto si può mettere da parte al giorno senza scendere sotto zero fino al punto più basso.
func maxDailySave(_ projectionWithoutSave: Projection, now: Date = Date()) -> Double {
    guard let low = projectionWithoutSave.lowest, low.balance > 0 else { return 0 }
    let days = max(daysLeft(until: low.date, from: now), 1)
    return (low.balance / Double(days) * 2).rounded(.down) / 2   // a mezzo euro
}

/// Mette da parte la cifra dei giorni già finiti (si chiama all'apertura dell'app).
@MainActor
func applyDailySavings(_ ctx: ModelContext, now: Date = Date(), defaults: UserDefaults = .standard) {
    let cal = Calendar.current
    let today = cal.startOfDay(for: now)
    let amount = defaults.double(forKey: dailySaveKey)
    guard amount > 0, defaults.object(forKey: dailySaveMoveKey) as? Bool ?? true else {
        defaults.removeObject(forKey: dailySaveLastKey)
        return
    }
    guard let last = defaults.object(forKey: dailySaveLastKey) as? Date else {
        // Appena acceso: si comincia da oggi, che verrà messo da parte stasera.
        defaults.set(cal.date(byAdding: .day, value: -1, to: today), forKey: dailySaveLastKey)
        return
    }
    let goalName = defaults.string(forKey: dailySaveGoalKey) ?? ""
    let goal = ((try? ctx.fetch(FetchDescriptor<Goal>())) ?? []).first { $0.name == goalName }
    var day = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: last)) ?? today
    var done = last
    while day < today {
        let at = cal.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? day
        ctx.insert(SavingsMove(amount: amount, date: at, note: "Da parte ogni giorno"))
        goal?.saved += amount
        done = day
        day = cal.date(byAdding: .day, value: 1, to: day) ?? today
    }
    defaults.set(done, forKey: dailySaveLastKey)
}

// MARK: - Pagina

struct Prossimi30View: View {
    @Query private var expenses: [Expense]
    @Query private var recurring: [Recurring]
    @Query private var accounts: [Account]
    @Query private var incomes: [Income]
    @Query private var moves: [SavingsMove]
    @Query private var cash: [CashMove]
    @Query private var payments: [TripPayment]
    @AppStorage(forecastDailyKey) private var includeDaily = true
    @AppStorage(dailySaveKey) private var dailySave = 0.0

    private var card: Double {
        Ledger(incomes: incomes, expenses: expenses, moves: moves, cash: cash, account: accounts.first, payments: payments)
            .figures(for: Date()).left
    }
    private var planned: [PlannedMove] { plannedMoves(expenses: expenses, recurring: recurring, account: accounts.first) }
    private var average: Double { dailyCardAverage(expenses, recurringNames: Set(recurring.map(\.name))) }

    var body: some View {
        let perDay = (includeDaily ? average : 0) + dailySave
        let proj = project(start: card, moves: planned, perDay: perDay)
        List {
            if let low = proj.lowest {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Il momento più stretto").font(.footnote).opacity(0.85)
                        Text(eur(low.balance)).font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(Calendar.current.isDateInToday(low.date) ? "oggi" : "il \(low.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                            .font(.footnote).opacity(0.85)
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                    .listRowBackground(LinearGradient(colors: low.balance < 0 ? [.red, .orange] : [HeroStyle.top, HeroStyle.bottom],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            Section {
                Chart {
                    ForEach(proj.points, id: \.date) { p in
                        AreaMark(x: .value("Giorno", p.date), y: .value("Saldo", p.balance))
                            .foregroundStyle(Theme.accent.opacity(0.12))
                        LineMark(x: .value("Giorno", p.date), y: .value("Saldo", p.balance))
                            .foregroundStyle(Theme.accent).lineStyle(StrokeStyle(lineWidth: 2.2))
                    }
                    RuleMark(y: .value("Zero", 0)).foregroundStyle(.red.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    if let low = proj.lowest {
                        PointMark(x: .value("Giorno", low.date), y: .value("Saldo", low.balance)).foregroundStyle(.red)
                    }
                }
                .frame(height: 200).padding(.vertical, 6)
                Toggle(isOn: $includeDaily) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Conta le spese di tutti i giorni")
                        Text("Media degli ultimi 30 giorni: \(eur(average)) al giorno").font(.caption).foregroundStyle(.secondary)
                    }
                }
                NavigationLink { DailySaveView() } label: {
                    LabeledContent("Da parte ogni giorno", value: dailySave > 0 ? eur(dailySave) : "Spento")
                }
            } footer: {
                Text("Parte dalla carta di oggi (\(eur(card))) e conta spese con data futura, rate, spese ricorrenti, abbonamenti e stipendio.")
            }
            let weeks = Dictionary(grouping: planned) { weekRange($0.date).start }.sorted { $0.key < $1.key }
            ForEach(weeks, id: \.key) { w in
                Section(weekTitle(w.key)) {
                    ForEach(w.value) { m in
                        HStack(spacing: 12) {
                            Image(systemName: m.icon).foregroundStyle(m.amount > 0 ? Theme.accent : Color.secondary).frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name).lineLimit(1)
                                Text("\(m.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · resta \(eur(proj.after[m.id] ?? 0))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text((m.amount > 0 ? "+" : "−") + eur(abs(m.amount))).bold()
                                .foregroundStyle(m.amount > 0 ? Theme.accent : Color.primary)
                        }
                    }
                }
            }
            if planned.isEmpty {
                Section { Text("Nessuna uscita o entrata nota nei prossimi 30 giorni.").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Prossimi 30 giorni").navigationBarTitleDisplayMode(.inline)
    }

    private func weekTitle(_ start: Date) -> String {
        let this = weekRange(Date()).start
        let n = (Calendar.current.dateComponents([.day], from: this, to: start).day ?? 0) / 7
        switch n {
        case 0: return "Questa settimana"
        case 1: return "Prossima settimana"
        default: return "Tra \(n) settimane"
        }
    }
}

/// Riquadro della Home: il punto più basso dei prossimi 30 giorni.
struct Prossimi30Tile: View {
    let card: Double
    let planned: [PlannedMove]
    let perDay: Double

    var body: some View {
        let proj = project(start: card, moves: planned, perDay: perDay)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Prossimi 30 giorni").font(.caption).foregroundStyle(.secondary)
                if let low = proj.lowest {
                    Text("Minimo \(eur(low.balance))").bold().foregroundStyle(low.balance < 0 ? Color.red : Color.primary)
                    Text(Calendar.current.isDateInToday(low.date) ? "oggi" : "il \(low.date.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Chart(proj.points, id: \.date) { p in
                LineMark(x: .value("Giorno", p.date), y: .value("Saldo", p.balance)).foregroundStyle(Theme.accent)
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .frame(width: 96, height: 36)
        }
    }
}

// MARK: - Da parte ogni giorno

struct DailySaveView: View {
    @Environment(\.modelContext) private var ctx
    @AppStorage(dailySaveKey) private var amount = 0.0
    @AppStorage(dailySaveMoveKey) private var move = true
    @AppStorage(dailySaveGoalKey) private var goalName = ""
    @Query private var goals: [Goal]
    @Query private var expenses: [Expense]
    @Query private var recurring: [Recurring]
    @Query private var accounts: [Account]
    @Query private var incomes: [Income]
    @Query private var moves: [SavingsMove]
    @Query private var cash: [CashMove]
    @Query private var payments: [TripPayment]

    var body: some View {
        let l = Ledger(incomes: incomes, expenses: expenses, moves: moves, cash: cash, account: accounts.first, payments: payments)
        let card = l.figures(for: Date()).left
        let avg = dailyCardAverage(expenses, recurringNames: Set(recurring.map(\.name)))
        let planned = plannedMoves(expenses: expenses, recurring: recurring, account: accounts.first)
        let base = project(start: card, moves: planned, perDay: avg)
        let withSave = project(start: card, moves: planned, perDay: avg + amount)
        let maxSave = maxDailySave(base)
        List {
            Section {
                Stepper(value: $amount, in: 0...100, step: 0.5) {
                    Text(amount > 0 ? eur(amount) : "Spento").font(.title2.bold())
                }
                Toggle(isOn: $move) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spostali nei Risparmi ogni sera")
                        Text("Alle 23:59, anche se l'app è chiusa li trovi alla prossima apertura").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if move && !goals.isEmpty {
                    Picker("Obiettivo", selection: $goalName) {
                        Text("Nessuno").tag("")
                        ForEach(goals) { g in Text(g.name).tag(g.name) }
                    }
                }
            } header: {
                Text("Quanto mettere da parte ogni giorno")
            } footer: {
                Text("Il budget giornaliero in Home scende di questa cifra e la previsione dei prossimi 30 giorni ne tiene conto.")
            }
            if amount > 0, let low = withSave.lowest {
                Section {
                    if low.balance < 0 {
                        Text("Con \(eur(amount)) al giorno, il \(low.date.formatted(.dateTime.day().month(.wide))) la carta scenderebbe a circa \(eur(low.balance)). Puoi permetterti al massimo \(eur(maxSave)) al giorno.")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Va bene: il punto più basso dei prossimi 30 giorni resta \(eur(low.balance)), il \(low.date.formatted(.dateTime.day().month(.wide))).")
                    }
                    LabeledContent("In 30 giorni metti da parte", value: eur(amount * 30))
                }
            }
        }
        .navigationTitle("Da parte ogni giorno").navigationBarTitleDisplayMode(.inline)
        .onChange(of: amount) { _, _ in applyDailySavings(ctx) }
        .onChange(of: move) { _, _ in applyDailySavings(ctx) }
    }
}
