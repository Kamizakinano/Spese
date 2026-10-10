import SwiftUI
import SwiftData

// MARK: - Impostazione iniziale

struct SavingRuleFields: View {
    @Binding var mode: Int
    @Binding var valueText: String
    var body: some View {
        Picker("Modalità", selection: $mode) {
            Text("Percentuale %").tag(0); Text("Importo €").tag(1)
        }.pickerStyle(.segmented)
        TextField(mode == 0 ? "Percentuale (es. 20)" : "Importo (es. 500)", text: $valueText)
            .keyboardType(.decimalPad)
    }
}

struct SetupView: View {
    @Environment(\.modelContext) private var ctx
    @State private var balanceText = ""
    @State private var mode = 0
    @State private var valueText = ""
    @State private var salaryText = ""
    @State private var salaryDay = 27
    @State private var salaryMode = 0
    @State private var salaryValueText = ""
    @State private var cashText = ""

    private var balance: Double { parseAmount(balanceText) ?? 0 }
    private var saved: Double { splitSaving(total: balance, mode: mode, value: parseAmount(valueText) ?? 0) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Conto bancario (carta)") {
                    Text("Quanti soldi hai sul conto in questo momento? Da qui in poi l'app terrà il conto di entrate e uscite.")
                        .font(.footnote).foregroundStyle(.secondary)
                    TextField("Soldi sul conto adesso (€)", text: $balanceText).keyboardType(.decimalPad)
                }
                Section("Quanto metti da parte (risparmi)") {
                    SavingRuleFields(mode: $mode, valueText: $valueText)
                    HStack { Text("Risparmi"); Spacer(); Text(eur(saved)).bold() }
                    HStack { Text("Disponibile da spendere"); Spacer(); Text(eur(balance - saved)).bold() }
                }
                Section("Stipendio mensile (facoltativo)") {
                    TextField("Importo stipendio (€)", text: $salaryText).keyboardType(.decimalPad)
                    Stepper("Giorno di accredito: \(salaryDay)", value: $salaryDay, in: 1...31)
                    SavingRuleFields(mode: $salaryMode, valueText: $salaryValueText)
                    Text("Ogni mese lo stipendio verrà aggiunto da solo e la quota scelta andrà ai risparmi.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Contanti (portafoglio)") {
                    Text("Quanti contanti hai nel portafoglio adesso? Lascia vuoto se non ne hai.")
                        .font(.footnote).foregroundStyle(.secondary)
                    TextField("Contanti che ho adesso (€)", text: $cashText).keyboardType(.decimalPad)
                }
                Section("Sicurezza (facoltativo)") { LockToggle() }
                Button("Inizia") { start() }.disabled(parseAmount(balanceText) == nil)
            }
            .navigationTitle("Benvenuto")
        }
    }

    private func start() {
        let day0 = Calendar.current.startOfDay(for: Date())
        let a = Account(startDate: day0)
        a.salaryAmount = parseAmount(salaryText) ?? 0
        a.salaryDay = salaryDay; a.salaryMode = salaryMode
        a.salaryValue = parseAmount(salaryValueText) ?? 0
        a.salaryNextKey = nextSalaryKey(day: salaryDay)
        a.cashStart = parseAmount(cashText) ?? 0
        ctx.insert(Income(amount: balance, saved: saved, kind: initialKind, date: day0, note: "Saldo iniziale"))
        ctx.insert(a)
    }
}

// MARK: - Entrate

struct IncomesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]
    @State private var adding = false
    @State private var editing: Income?

    private func icon(_ k: String) -> String {
        k == "Stipendio" ? "banknote" : k == initialKind ? "building.columns" : "plus.circle"
    }

    var body: some View {
        List {
            ForEach(incomes) { i in
                    HStack(spacing: 12) {
                        Image(systemName: icon(i.kind)).foregroundStyle(.white)
                            .frame(width: 34, height: 34).background(Theme.accent, in: Circle())
                        VStack(alignment: .leading) {
                            Text(i.note.isEmpty ? i.kind : i.note)
                            Text(i.date.formatted(.dateTime.day().month(.abbreviated).year()) +
                                 (i.saved > 0 ? " · risparmi \(eur(i.saved))" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text((i.amount >= 0 ? "+" : "") + eur(i.amount)).bold().foregroundStyle(Theme.accent)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = i }
                }.onDelete { idx in idx.map { incomes[$0] }.forEach(ctx.delete) }
            }
            .navigationTitle("Entrate")
            .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
            .sheet(isPresented: $adding) { AddIncomeView() }
            .sheet(item: $editing) { AddIncomeView(editing: $0) }
    }
}

struct AddIncomeView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]
    /// Entrata da modificare (nil = nuova).
    var editing: Income? = nil
    @State private var kind = "Stipendio"
    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var mode = 0
    @State private var valueText = ""

    private var amount: Double { parseAmount(amountText) ?? 0 }
    private var saved: Double { splitSaving(total: amount, mode: mode, value: parseAmount(valueText) ?? 0) }

    var body: some View {
        NavigationStack {
            Form {
                if kind != initialKind {
                    Picker("Tipo", selection: $kind) {
                        Text("Stipendio").tag("Stipendio"); Text("Altra entrata").tag("Altra entrata")
                        if kind == "Rimborso" { Text("Rimborso").tag("Rimborso") }
                    }.pickerStyle(.segmented)
                }
                TextField("Importo (€)", text: $amountText).keyboardType(.decimalPad)
                DatePicker("Data", selection: $date, displayedComponents: .date)
                TextField("Nota (facoltativa)", text: $note)
                Section("Quanto metti a risparmio") {
                    SavingRuleFields(mode: $mode, valueText: $valueText)
                    HStack { Text("A risparmio"); Spacer(); Text(eur(saved)).bold() }
                    HStack { Text("Disponibile da spendere"); Spacer(); Text(eur(amount - saved)).bold() }
                }
            }
            .navigationTitle(editing == nil ? "Nuova entrata" : "Modifica entrata").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        guard amount > 0 else { return }
                        if let e = editing {
                            e.amount = amount; e.saved = saved; e.kind = kind; e.date = date; e.note = note
                        } else {
                            ctx.insert(Income(amount: amount, saved: saved, kind: kind, date: date, note: note))
                        }
                        try? ctx.save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let e = editing {
                    // In modifica la quota a risparmio si mostra come importo fisso, quello già salvato.
                    kind = e.kind; date = e.date; note = e.note
                    amountText = amountString(e.amount)
                    mode = 1; valueText = e.saved > 0 ? amountString(e.saved) : ""
                } else if let a = accounts.first {
                    mode = a.salaryMode
                    valueText = a.salaryValue > 0 ? String(a.salaryValue) : ""
                }
            }
        }
    }
}

/// Importo per un campo di testo: "1250" o "1250,50".
func amountString(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",")
}

// MARK: - Stipendi ricevuti

/// Stipendi di un mese (di solito uno).
struct SalaryMonth: Identifiable {
    let month: Date            // primo giorno del mese
    let items: [Income]
    var total: Double { items.reduce(0) { $0 + $1.amount } }
    var id: Date { month }
}

/// Stipendi registrati raggruppati per mese, dal più recente.
func salaryMonths(_ incomes: [Income]) -> [SalaryMonth] {
    let cal = Calendar.current
    return Dictionary(grouping: incomes.filter { $0.kind == "Stipendio" }) {
        cal.date(from: cal.dateComponents([.year, .month], from: $0.date)) ?? $0.date
    }
    .map { SalaryMonth(month: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
    .sorted { $0.month > $1.month }
}

/// Media degli stipendi mensili registrati (0 se non ce ne sono).
func salaryAverage(_ months: [SalaryMonth]) -> Double {
    months.isEmpty ? 0 : months.reduce(0) { $0 + $1.total } / Double(months.count)
}

/// Righe degli stipendi: mese e importo; toccandone una si modifica.
struct SalaryRows: View {
    let months: [SalaryMonth]
    @Binding var editing: Income?

    var body: some View {
        ForEach(months) { m in
            Button { editing = m.items.first } label: {
                HStack(spacing: 12) {
                    Image(systemName: "banknote").foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Theme.accent, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.month.formatted(.dateTime.month(.wide).year()).capitalized).foregroundStyle(.primary)
                        Text(m.items.count > 1 ? "\(m.items.count) accrediti" : "ricevuto il \(m.items[0].date.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(eur(m.total)).bold().foregroundStyle(.primary)
                }
            }
        }
    }
}

struct SalaryHistoryView: View {
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]
    @State private var editing: Income?

    var body: some View {
        let months = salaryMonths(incomes)
        List {
            Section {
                SalaryRows(months: months, editing: $editing)
            } header: {
                HStack {
                    Text("Tutti gli stipendi")
                    Spacer()
                    if !months.isEmpty { Text("media \(eur(salaryAverage(months)))").textCase(nil) }
                }
            }
        }
        .navigationTitle("Stipendi")
        .sheet(item: $editing) { AddIncomeView(editing: $0) }
    }
}

// MARK: - Risparmi (sezione separata dal budget)

struct SavingsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Income.date, order: .reverse) private var incomes: [Income]
    @Query(sort: \SavingsMove.date, order: .reverse) private var moves: [SavingsMove]
    @State private var deposit = false
    @State private var withdraw = false
    @Query private var goals: [Goal]
    @State private var editingGoal: Goal?
    @State private var addGoal = false

    private var total: Double { incomes.reduce(0) { $0 + $1.saved } + moves.reduce(0) { $0 + $1.amount } }
    private var free: Double { total - goals.reduce(0) { $0 + $1.saved } }

    private func goalHint(_ g: Goal) -> String {
        let rest = g.target - g.saved
        if rest <= 0 { return "Obiettivo raggiunto" }
        let m = max(1, Calendar.current.dateComponents([.month], from: Date(), to: g.deadline).month ?? 1)
        return "Mancano \(eur(rest)) · circa \(eur(rest / Double(m))) al mese entro il \(g.deadline.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Risparmi").font(.subheadline).opacity(0.85)
                        Text(eur(total)).font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("Soldi messi da parte: non fanno parte del budget da spendere.")
                            .font(.footnote).opacity(0.9)
                        HStack {
                            Button("Versa") { deposit = true }
                            Button("Preleva") { withdraw = true }
                        }.buttonStyle(.bordered).tint(.white)
                    }
                    .foregroundStyle(.white).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [Color(hex: "2980B9"), Color(hex: "1B4F72")],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 22))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)

                Section {
                    ForEach(goals) { g in
                        Button { editingGoal = g } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(g.name).foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(eur(g.saved)) / \(eur(g.target))").font(.footnote).foregroundStyle(.secondary)
                                }
                                ProgressView(value: min(g.saved, g.target), total: max(g.target, 1))
                                Text(goalHint(g)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.onDelete { idx in idx.map { goals[$0] }.forEach(ctx.delete) }
                    Button { addGoal = true } label: { Label("Nuovo obiettivo", systemImage: "plus.circle") }
                } header: { Text("Obiettivi") } footer: { Text("Non assegnato a obiettivi: \(eur(free))") }

                Section("Versamenti e prelievi") {
                    if moves.isEmpty { Text("Nessun movimento manuale").foregroundStyle(.secondary) }
                    ForEach(moves) { m in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(m.note.isEmpty ? (m.amount >= 0 ? "Versamento" : "Prelievo") : m.note)
                                Text(m.date.formatted(.dateTime.day().month(.abbreviated).year()))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text((m.amount >= 0 ? "+" : "") + eur(m.amount)).bold()
                                .foregroundStyle(m.amount >= 0 ? Color.blue : Color.orange)
                        }
                    }.onDelete { idx in idx.map { moves[$0] }.forEach(ctx.delete) }
                }

                Section("Accantonati dalle entrate") {
                    ForEach(incomes.filter { $0.saved > 0 }) { i in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(i.note.isEmpty ? i.kind : i.note)
                                Text(i.date.formatted(.dateTime.day().month(.abbreviated).year()))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("+" + eur(i.saved)).bold().foregroundStyle(Color.blue)
                        }
                    }
                }
            }
            .navigationTitle("Risparmi")
            .sheet(isPresented: $deposit) { SavingsMoveView(isDeposit: true, maxWithdraw: total) }
            .sheet(isPresented: $withdraw) { SavingsMoveView(isDeposit: false, maxWithdraw: total) }
            .sheet(item: $editingGoal) { GoalEditor(goal: $0, freeSavings: free) }
            .sheet(isPresented: $addGoal) { GoalEditor(goal: nil, freeSavings: free) }
        }
    }
}

struct SavingsMoveView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let isDeposit: Bool
    let maxWithdraw: Double
    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Importo (€)", text: $amountText).keyboardType(.decimalPad)
                DatePicker("Data", selection: $date, displayedComponents: .date)
                TextField("Nota (facoltativa)", text: $note)
                Text(isDeposit ? "I soldi passano dal budget disponibile ai risparmi."
                               : "I soldi tornano dai risparmi al budget disponibile. Massimo \(eur(maxWithdraw)).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle(isDeposit ? "Versa nei risparmi" : "Preleva dai risparmi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        guard let a = parseAmount(amountText), a > 0, isDeposit || a <= maxWithdraw else { return }
                        ctx.insert(SavingsMove(amount: isDeposit ? a : -a, date: date, note: note))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Stipendio e regola di risparmio

struct SalaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]
    @State private var amountText = ""
    @State private var day = 27
    @State private var mode = 0
    @State private var valueText = ""
    @State private var loaded = false

    private var amount: Double { parseAmount(amountText) ?? 0 }
    private var saved: Double { splitSaving(total: amount, mode: mode, value: parseAmount(valueText) ?? 0) }

    var body: some View {
        Form {
            Section("Stipendio mensile") {
                TextField("Importo (€)", text: $amountText).keyboardType(.decimalPad)
                Stepper("Giorno di accredito: \(day)", value: $day, in: 1...31)
            }
            Section("Quanto metti a risparmio ogni mese") {
                SavingRuleFields(mode: $mode, valueText: $valueText)
                HStack { Text("A risparmio"); Spacer(); Text(eur(saved)).bold() }
                HStack { Text("Disponibile da spendere"); Spacer(); Text(eur(amount - saved)).bold() }
            }
            Text("La quota si calcola sull'importo ricevuto, non su quello che ti resta. Imposta 0 come stipendio per disattivare l'inserimento automatico. Il giorno di accredito serve anche per la stima di quanto puoi spendere al giorno, anche senza importo.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Stipendio e risparmi")
        .toolbar { Button("Salva") { save() } }
        .onAppear {
            guard !loaded, let a = accounts.first else { return }
            loaded = true
            amountText = a.salaryAmount > 0 ? String(a.salaryAmount) : ""
            day = a.salaryDay; mode = a.salaryMode
            valueText = a.salaryValue > 0 ? String(a.salaryValue) : ""
        }
    }

    private func save() {
        guard let a = accounts.first else { return }
        let wasNone = a.salaryAmount <= 0
        a.salaryAmount = amount; a.salaryDay = day; a.salaryMode = mode
        a.salaryValue = parseAmount(valueText) ?? 0
        if wasNone && amount > 0 { a.salaryNextKey = nextSalaryKey(day: day) }
        dismiss()
    }
}

struct GoalEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let goal: Goal?
    let freeSavings: Double
    @State private var name = ""
    @State private var targetText = ""
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var addText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome (es. Vacanza)", text: $name)
                TextField("Obiettivo (€)", text: $targetText).keyboardType(.decimalPad)
                DatePicker("Entro il", selection: $deadline, displayedComponents: .date)
                Section("Assegna dai risparmi") {
                    TextField("Importo da assegnare (€)", text: $addText).keyboardType(.decimalPad)
                    Text("Risparmi non ancora assegnati: \(eur(freeSavings)). Un importo negativo toglie soldi dall'obiettivo.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(goal == nil ? "Nuovo obiettivo" : "Modifica obiettivo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") { save() } }
            }
            .onAppear {
                if let g = goal { name = g.name; targetText = String(g.target); deadline = g.deadline }
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, let t = parseAmount(targetText), t > 0 else { return }
        let add = min(parseAmount(addText) ?? 0, freeSavings)
        if let g = goal {
            g.name = n; g.target = t; g.deadline = deadline
            g.saved = max(0, g.saved + add)
        } else {
            ctx.insert(Goal(name: n, target: t, saved: max(0, add), deadline: deadline))
        }
        dismiss()
    }
}
