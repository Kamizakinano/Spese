import SwiftUI
import SwiftData
import Charts

private func monthKey(_ d: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month], from: d)
    return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
}

private func parse(_ s: String) -> Double? {
    Double(s.replacingOccurrences(of: ",", with: "."))
}

struct CatTotal: Identifiable {
    let cat: Category
    let total: Double
    var id: String { cat.id }
}

struct ContentView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Expense.date, order: .reverse) private var all: [Expense]
    @Query private var budgets: [MonthBudget]

    @State private var month = Date()
    @State private var showAdd = false
    @State private var showBudget = false
    @State private var budgetText = ""

    private var expenses: [Expense] {
        all.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }
    private var budget: Double { budgets.first { $0.key == monthKey(month) }?.amount ?? 0 }
    private var total: Double { expenses.reduce(0) { $0 + $1.amount } }
    private var left: Double { budget - total }

    private var byCategory: [CatTotal] {
        Dictionary(grouping: expenses, by: \.category)
            .map { CatTotal(cat: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    private var perDayText: String? {
        let cal = Calendar.current
        guard budget > 0, left > 0, cal.isDate(month, equalTo: Date(), toGranularity: .month),
              let range = cal.range(of: .day, in: .month, for: Date()) else { return nil }
        let days = range.count - cal.component(.day, from: Date()) + 1
        return "\((left / Double(days)).formatted(.currency(code: "EUR"))) al giorno per \(days) giorni"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                        Spacer()
                        Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    }
                    .buttonStyle(.borderless)
                }

                Section("Budget") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Rimane a fine mese").font(.footnote).foregroundStyle(.secondary)
                        Text(budget > 0 ? left.formatted(.currency(code: "EUR")) : "—")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(budget > 0 && left < 0 ? .red : .primary)
                        if budget > 0 {
                            ProgressView(value: min(total, budget), total: budget)
                                .tint(left < 0 ? .red : .green)
                        }
                        Text("Spesi \(total.formatted(.currency(code: "EUR")))" +
                             (budget > 0 ? " su \(budget.formatted(.currency(code: "EUR")))" : ""))
                            .font(.footnote).foregroundStyle(.secondary)
                        if let t = perDayText { Text(t).font(.footnote).foregroundStyle(.secondary) }
                    }
                    Button(budget > 0 ? "Modifica budget" : "Imposta budget") {
                        budgetText = budget > 0 ? String(budget) : ""
                        showBudget = true
                    }
                }

                if !byCategory.isEmpty {
                    Section("Per categoria") {
                        Chart(byCategory) { item in
                            SectorMark(angle: .value("Totale", item.total), innerRadius: .ratio(0.6), angularInset: 1)
                                .foregroundStyle(item.cat.color)
                        }
                        .frame(height: 190)
                        ForEach(byCategory) { item in
                            HStack {
                                Label(item.cat.rawValue, systemImage: item.cat.icon)
                                    .foregroundStyle(item.cat.color)
                                Spacer()
                                Text(item.total.formatted(.currency(code: "EUR")))
                                Text("\(Int((item.total / total * 100).rounded()))%")
                                    .foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                Section("Movimenti") {
                    if expenses.isEmpty {
                        Text("Ancora nessuna spesa").foregroundStyle(.secondary)
                    }
                    ForEach(expenses) { e in
                        HStack {
                            Image(systemName: e.category.icon).foregroundStyle(e.category.color).frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(e.note.isEmpty ? e.category.rawValue : e.note)
                                Text("\(e.date.formatted(.dateTime.day().month(.abbreviated))) · \(e.category.rawValue)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(e.amount.formatted(.currency(code: "EUR"))).bold()
                        }
                    }
                    .onDelete { idx in idx.map { expenses[$0] }.forEach(ctx.delete) }
                }
            }
            .navigationTitle("Le mie spese")
            .toolbar {
                Button { showAdd = true } label: { Image(systemName: "plus.circle.fill") }
            }
            .sheet(isPresented: $showAdd) { AddExpenseView(defaultDate: defaultDate()) }
            .alert("Budget mensile", isPresented: $showBudget) {
                TextField("Importo in €", text: $budgetText).keyboardType(.decimalPad)
                Button("Salva") { saveBudget() }
                Button("Annulla", role: .cancel) {}
            }
        }
    }

    private func shift(_ n: Int) {
        month = Calendar.current.date(byAdding: .month, value: n, to: month) ?? month
    }

    private func defaultDate() -> Date {
        Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month) ? Date() : month
    }

    private func saveBudget() {
        guard let v = parse(budgetText), v >= 0 else { return }
        if let b = budgets.first(where: { $0.key == monthKey(month) }) { b.amount = v }
        else { ctx.insert(MonthBudget(key: monthKey(month), amount: v)) }
    }
}

struct AddExpenseView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let defaultDate: Date

    @State private var amountText = ""
    @State private var category = Category.alimentari
    @State private var date = Date()
    @State private var note = ""
    @FocusState private var focus: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Importo (€)", text: $amountText)
                    .keyboardType(.decimalPad).focused($focus)
                Picker("Categoria", selection: $category) {
                    ForEach(Category.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                }
                DatePicker("Data", selection: $date, displayedComponents: .date)
                TextField("Nota (facoltativa)", text: $note)
            }
            .navigationTitle("Nuova spesa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        guard let a = parse(amountText), a > 0 else { return }
                        ctx.insert(Expense(amount: a, category: category, date: date, note: note))
                        dismiss()
                    }
                }
            }
            .onAppear { date = defaultDate; focus = true }
        }
        .presentationDetents([.medium])
    }
}
