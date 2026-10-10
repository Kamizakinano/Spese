import SwiftUI
import SwiftData

// MARK: - Devo dare

/// Soldi che devo restituire a qualcuno.
@Model final class Debt {
    var person: String
    var amount: Double
    var note: String
    var category: String        // categoria della spesa che si crea quando pago
    var date: Date
    var paid: Bool = false
    var paidMethod: String = "" // "carta" (dal conto) o "contanti"
    var paidDate: Date? = nil
    init(person: String, amount: Double, note: String, category: String, date: Date) {
        self.person = person; self.amount = amount; self.note = note; self.category = category; self.date = date
    }
}

/// Segna il debito come pagato e registra la spesa, dal conto o in contanti.
func payDebt(_ d: Debt, cash: Bool, ctx: ModelContext, now: Date = Date()) {
    d.paid = true
    d.paidMethod = cash ? "contanti" : "carta"
    d.paidDate = now
    let note = "Restituiti a \(d.person)" + (d.note.isEmpty ? "" : " · \(d.note)")
    let e = Expense(amount: d.amount, categoryName: d.category, date: now, note: note)
    e.method = cash ? "contanti" : "carta"
    ctx.insert(e)
    try? ctx.save()
}

struct DebtsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Debt.date, order: .reverse) private var all: [Debt]
    @State private var adding = false
    @State private var paying: Debt?

    private var open: [Debt] { all.filter { !$0.paid } }
    private var closed: [Debt] { all.filter(\.paid) }
    private var total: Double { open.reduce(0) { $0 + $1.amount } }

    private func row(_ d: Debt) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(d.person)
                Text(detail(d)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(eur(d.amount)).bold()
            if !d.paid {
                Button("Pagato") { paying = d }.buttonStyle(.bordered).font(.caption)
            }
        }
    }

    private func detail(_ d: Debt) -> String {
        var s = (d.note.isEmpty ? d.category : d.note) + " · \(d.date.formatted(.dateTime.day().month(.abbreviated)))"
        if d.paid, let p = d.paidDate {
            s += " · pagato il \(p.formatted(.dateTime.day().month(.abbreviated)))"
            s += d.paidMethod == "contanti" ? " in contanti" : " dal conto"
        }
        return s
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Devi restituire").font(.subheadline).opacity(0.85)
                    Text(eur(total)).font(.system(size: 32, weight: .bold, design: .rounded))
                    Text(open.isEmpty ? "Non devi soldi a nessuno" : "a \(Set(open.map(\.person)).count) \(Set(open.map(\.person)).count == 1 ? "persona" : "persone")")
                        .font(.footnote).opacity(0.85)
                }
                .foregroundStyle(.white).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [HeroStyle.top, HeroStyle.bottom], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 22))
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)

            Section("Da restituire") {
                if open.isEmpty { Text("Tocca + per segnare dei soldi che devi a qualcuno.").foregroundStyle(.secondary) }
                ForEach(open) { d in
                    row(d).swipeActions {
                        Button("Pagato") { paying = d }.tint(Theme.accent)
                        Button("Elimina", role: .destructive) { ctx.delete(d) }
                    }
                }
            }
            if !closed.isEmpty {
                Section("Già pagati") {
                    ForEach(closed) { row($0).foregroundStyle(.secondary) }
                        .onDelete { i in i.map { closed[$0] }.forEach(ctx.delete) }
                }
            }
            Section {
                Text("Quando restituisci i soldi tocca Pagato e scegli se dal conto o in contanti: viene registrata la spesa e il disponibile si aggiorna.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Devo dare")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Aggiungi") }
        .sheet(isPresented: $adding) { DebtEditor() }
        .confirmationDialog(paying.map { "Hai dato \(eur($0.amount)) a \($0.person)?" } ?? "",
                            isPresented: Binding(get: { paying != nil }, set: { if !$0 { paying = nil } }),
                            titleVisibility: .visible) {
            if let d = paying {
                Button("Sì, dal conto (bonifico, carta…)") { payDebt(d, cash: false, ctx: ctx); paying = nil }
                Button("Sì, in contanti") { payDebt(d, cash: true, ctx: ctx); paying = nil }
            }
            Button("Annulla", role: .cancel) { paying = nil }
        }
    }
}

struct DebtEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryItem.order) private var cats: [CategoryItem]
    @State private var person = ""
    @State private var amountText = ""
    @State private var note = ""
    @State private var catName = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                TextField("A chi (es. Marco)", text: $person)
                TextField("Importo (€)", text: $amountText).keyboardType(.decimalPad)
                TextField("Per cosa (facoltativo)", text: $note)
                Picker("Categoria quando paghi", selection: $catName) {
                    ForEach(cats) { c in Label(c.name, systemImage: c.icon).tag(c.name) }
                }
                DatePicker("Data", selection: $date, displayedComponents: .date)
            }
            .navigationTitle("Devo dare").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        let p = person.trimmingCharacters(in: .whitespaces)
                        guard !p.isEmpty, let a = parseAmount(amountText), a > 0 else { return }
                        ctx.insert(Debt(person: p, amount: a, note: note.trimmingCharacters(in: .whitespaces),
                                        category: catName, date: date))
                        dismiss()
                    }
                }
            }
            .onAppear { if catName.isEmpty { catName = cats.first(where: { $0.name == "Altro" })?.name ?? cats.first?.name ?? "Altro" } }
        }
    }
}
