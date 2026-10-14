import SwiftUI
import SwiftData

// MARK: - Pagamenti a rate (PayPal, Klarna…)

/// Categoria delle rate: nelle statistiche contano tutte qui.
let installmentCategory = "Pagamenti a rate"
/// Segna che la categoria è già stata aggiunta (se poi la si elimina non ricompare).
let installmentAddedKey = "installmentCategoryAdded"
let installmentProviders = ["PayPal", "Klarna", "Altro"]

/// Una rata da pagare: numero (da 1), giorno dell'addebito e importo.
struct InstallmentRate: Equatable {
    let index: Int
    let date: Date
    let amount: Double
}

/// Le rate ancora da pagare di un acquisto da `total` € in `count` rate, di cui `paid` già pagate.
/// La prima mancante è il giorno `first`, le altre ogni mese; l'ultima assorbe l'arrotondamento.
func installmentSchedule(total: Double, count: Int, paid: Int, first: Date) -> [InstallmentRate] {
    guard total > 0, count > 0, paid >= 0, paid < count else { return [] }
    let base = (total / Double(count) * 100).rounded() / 100
    let last = ((total - base * Double(count - 1)) * 100).rounded() / 100
    return ((paid + 1)...count).map { i in
        let d = Calendar.current.date(byAdding: .month, value: i - paid - 1, to: first) ?? first
        return InstallmentRate(index: i, date: d, amount: i == count ? last : base)
    }
}

/// Crea le spese delle rate ancora da pagare (quelle già pagate non toccano il saldo).
func makeInstallments(total: Double, count: Int, paid: Int, first: Date, name: String, provider: String) -> [Expense] {
    let id = UUID().uuidString
    return installmentSchedule(total: total, count: count, paid: paid, first: first).map { r in
        let e = Expense(amount: r.amount, categoryName: installmentCategory, date: r.date, note: "\(name) · rata \(r.index) di \(count)")
        e.method = "carta"
        e.planID = id; e.planName = name; e.planProvider = provider
        e.planIndex = r.index; e.planCount = count; e.planTotal = total
        return e
    }
}

/// Cambia nome (cosa hai comprato) e PayPal/Klarna di tutte le rate di un acquisto.
func updateInstallmentPlan(_ rates: [Expense], name: String, provider: String) {
    let n = name.trimmingCharacters(in: .whitespaces)
    for e in rates {
        if !n.isEmpty {
            e.planName = n
            e.note = "\(n) · rata \(e.planIndex) di \(e.planCount)"
        }
        e.planProvider = provider
    }
}

/// Un acquisto a rate, ricostruito dalle sue rate.
struct InstallmentPlan: Identifiable {
    let id: String
    let name: String
    let provider: String
    let total: Double
    let count: Int
    let rates: [Expense]          // rate registrate, in ordine di data
    let paidCount: Int            // rate già pagate (anche quelle segnate alla creazione)
    let remaining: Double         // euro ancora da pagare
    let remainingCount: Int
    let end: Date?                // giorno dell'ultima rata
    let next: Expense?            // prossima rata da pagare
    var done: Bool { remainingCount == 0 }
}

func installmentPlans(_ expenses: [Expense], now: Date = Date()) -> [InstallmentPlan] {
    let cutoff = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
    return Dictionary(grouping: expenses.filter { !$0.planID.isEmpty }, by: \.planID).map { id, list in
        let rates = list.sorted { $0.date < $1.date }
        let future = rates.filter { $0.date >= cutoff }
        let before = max((rates.map(\.planIndex).min() ?? 1) - 1, 0)   // già pagate quando è stato inserito
        let f = rates.first
        return InstallmentPlan(id: id, name: f?.planName ?? "", provider: f?.planProvider ?? "",
                               total: f?.planTotal ?? 0, count: f?.planCount ?? rates.count, rates: rates,
                               paidCount: before + rates.count - future.count,
                               remaining: future.reduce(0) { $0 + $1.amount }, remainingCount: future.count,
                               end: rates.last?.date, next: future.first)
    }
    .sorted { ($0.done ? 1 : 0, $0.next?.date ?? .distantFuture) < ($1.done ? 1 : 0, $1.next?.date ?? .distantFuture) }
}

/// Spese della categoria rate divise per PayPal, Klarna…
func installmentProviderTotals(_ expenses: [Expense]) -> [(name: String, total: Double)] {
    Dictionary(grouping: expenses.filter { $0.categoryRaw == installmentCategory }, by: { $0.planProvider.isEmpty ? "Altro" : $0.planProvider })
        .map { (name: $0.key, total: $0.value.reduce(0) { $0 + $1.myAmount }) }
        .filter { $0.total > 0 }
        .sorted { $0.total > $1.total }
}

private func providerColor(_ p: String) -> Color {
    switch p {
    case "PayPal": return Color(hex: "1F5FBF")
    case "Klarna": return Color(hex: "D9488B")
    default: return Color(hex: "0E7C86")
    }
}

private struct ProviderBadge: View {
    let provider: String
    var body: some View {
        Text(provider == "PayPal" ? "PP" : String(provider.prefix(1)))
            .font(.footnote.weight(.heavy)).foregroundStyle(.white)
            .frame(width: 38, height: 38).background(providerColor(provider), in: Circle())
    }
}

// MARK: - Pagina "Pagamenti a rate"

struct InstallmentsView: View {
    @Query private var all: [Expense]
    @State private var adding = false
    private var plans: [InstallmentPlan] { installmentPlans(all) }

    var body: some View {
        List {
            let open = plans.filter { !$0.done }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ancora da pagare").font(.footnote).opacity(0.85)
                    Text(eur(open.reduce(0) { $0 + $1.remaining })).font(.system(size: 30, weight: .bold, design: .rounded))
                    if let last = open.compactMap(\.end).max() {
                        Text("\(open.reduce(0) { $0 + $1.remainingCount }) rate su \(open.count) acquisti · ultima il \(last.formatted(.dateTime.day().month(.wide)))")
                            .font(.footnote).opacity(0.85)
                    } else {
                        Text("Nessuna rata da pagare").font(.footnote).opacity(0.85)
                    }
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                .listRowBackground(LinearGradient(colors: [HeroStyle.top, HeroStyle.bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            if plans.isEmpty {
                Section {
                    Text("Tocca + per inserire un acquisto a rate: importo totale, numero di rate e quante ne hai già pagate. Le rate da pagare vanno in \"In arrivo\".")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(plans) { p in
                NavigationLink { InstallmentDetailView(planID: p.id) } label: { PlanRow(plan: p) }
            }
        }
        .navigationTitle("Pagamenti a rate").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nuovo acquisto a rate") }
        .sheet(isPresented: $adding) { AddExpenseView(defaultDate: Date(), presetCategory: installmentCategory) }
    }
}

private struct PlanRow: View {
    let plan: InstallmentPlan
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProviderBadge(provider: plan.provider)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.name).bold().lineLimit(1)
                    Text("\(plan.provider) · \(eur(plan.total)) in \(plan.count) rate").font(.caption).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: Double(plan.paidCount), total: Double(max(plan.count, 1))).tint(providerColor(plan.provider))
            HStack {
                Text("Pagate **\(plan.paidCount) di \(plan.count)**")
                Spacer()
                if plan.done { Text("**Finito**") } else { Text("Mancano **\(plan.remainingCount) \(plan.remainingCount == 1 ? "rata" : "rate")**") }
            }.font(.caption)
            HStack {
                Text("Restano **\(eur(plan.remaining))**")
                Spacer()
                if let end = plan.end { Text("\(plan.done ? "Finito" : "Finisce") il **\(end.formatted(.dateTime.day().month(.abbreviated)))**") }
            }.font(.caption)
        }
        .padding(.vertical, 4)
    }
}

struct InstallmentDetailView: View {
    let planID: String
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var all: [Expense]
    @State private var editing: Expense?
    @State private var askDelete = false
    @State private var nameText = ""
    @State private var loaded = false

    private var plan: InstallmentPlan? { installmentPlans(all.filter { $0.planID == planID }).first }

    var body: some View {
        List {
            if let p = plan {
                Section { PlanRow(plan: p) }
                Section {
                    TextField("Cosa hai comprato", text: $nameText)
                        .submitLabel(.done)
                        .onSubmit { updateInstallmentPlan(p.rates, name: nameText, provider: p.provider) }
                    HStack {
                        ForEach(installmentProviders, id: \.self) { v in
                            Button(v) { updateInstallmentPlan(p.rates, name: nameText, provider: v) }
                                .buttonStyle(.bordered).tint(p.provider == v ? Theme.accent : .gray)
                        }
                    }
                } header: { Text("Acquisto") }
                Section {
                    ForEach(p.rates) { e in
                        let future = e.date >= Ledger.endOfToday
                        Button { editing = e } label: {
                            HStack {
                                Image(systemName: future ? "hourglass" : "checkmark.circle.fill")
                                    .foregroundStyle(future ? Color.secondary : Theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Rata \(e.planIndex) di \(e.planCount)").foregroundStyle(.primary)
                                    Text(e.date.formatted(.dateTime.day().month(.wide).year())).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(eur(e.amount)).foregroundStyle(.primary)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if future {
                                Button("Pagata oggi") { e.date = Date() }.tint(Theme.accent)
                            }
                        }
                    }
                    .onDelete { idx in idx.map { p.rates[$0] }.forEach { deleteExpense($0, ctx: ctx) } }
                } header: { Text("Rate") } footer: {
                    Text("Tocca una rata per cambiarne importo o data. Scorri verso destra per segnarla pagata oggi.")
                }
                Section {
                    Button("Elimina acquisto", role: .destructive) { askDelete = true }
                }
            }
        }
        .navigationTitle(plan?.name ?? "Rate").navigationBarTitleDisplayMode(.inline)
        .onAppear { if !loaded, let p = plan { nameText = p.name; loaded = true } }
        // Il nome si salva anche uscendo dalla pagina senza premere Fine.
        .onDisappear { if let p = plan, nameText != p.name { updateInstallmentPlan(p.rates, name: nameText, provider: p.provider) } }
        .sheet(item: $editing) { e in AddExpenseView(defaultDate: e.date, editing: e) }
        .confirmationDialog("Eliminare l'acquisto?", isPresented: $askDelete, titleVisibility: .visible) {
            Button("Solo le rate da pagare", role: .destructive) {
                plan?.rates.filter { $0.date >= Ledger.endOfToday }.forEach { deleteExpense($0, ctx: ctx) }
                dismiss()
            }
            Button("Tutte, anche quelle pagate", role: .destructive) {
                plan?.rates.forEach { deleteExpense($0, ctx: ctx) }
                dismiss()
            }
        } message: {
            Text("Le rate già pagate sono soldi già usciti: se le elimini tornano nel saldo.")
        }
    }
}
