import SwiftUI
import SwiftData

// MARK: - Spese di una categoria

/// Spese del mese `month` nella categoria, fino a oggi, come nel grafico "Per categoria" della Home.
func categoryExpenses(_ all: [Expense], trips: [Trip], category: String, month: Date, now: Date = Date()) -> [Expense] {
    let cutoff = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
    return statExpenses(all, trips: trips)
        .filter { $0.categoryRaw == category && $0.date < cutoff && Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
        .sorted { $0.date > $1.date }
}

struct CategoryExpensesView: View {
    let category: String
    let month: Date
    @Environment(\.modelContext) private var ctx
    @Query private var all: [Expense]
    @Query private var trips: [Trip]
    @Query(sort: \CategoryItem.order) private var cats: [CategoryItem]
    @State private var editing: Expense?

    private var list: [Expense] { categoryExpenses(all, trips: trips, category: category, month: month) }
    private var look: (icon: String, color: Color) {
        if let c = cats.first(where: { $0.name == category }) { return (c.icon, Color(hex: c.colorHex)) }
        return ("questionmark.circle", .gray)
    }
    /// Gruppi da mostrare: per i pagamenti a rate uno per PayPal, Klarna…; per le altre categorie uno solo.
    private var groups: [(name: String, items: [Expense])] {
        guard category == installmentCategory else { return [("", list)] }
        return Dictionary(grouping: list, by: { $0.planProvider.isEmpty ? "Altro" : $0.planProvider })
            .map { (name: $0.key, items: $0.value) }
            .sorted { $0.items.reduce(0) { $0 + $1.myAmount } > $1.items.reduce(0) { $0 + $1.myAmount } }
    }

    var body: some View {
        let total = list.reduce(0) { $0 + $1.myAmount }
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: look.icon).font(.title2).foregroundStyle(look.color)
                        .frame(width: 52, height: 52).background(look.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(eur(total)).font(.system(size: 28, weight: .bold, design: .rounded))
                        Text(month.formatted(.dateTime.month(.wide).year())).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 0) {
                    stat("Spese", "\(list.count)")
                    Divider().frame(height: 36)
                    stat("Media", list.isEmpty ? "–" : eur(total / Double(list.count)))
                    Divider().frame(height: 36)
                    stat("Più alta", list.map(\.myAmount).max().map { eur($0) } ?? "–")
                }
            }
            if list.isEmpty {
                Section { Text("Nessuna spesa in questa categoria nel mese.").foregroundStyle(.secondary) }
            }
            ForEach(groups, id: \.name) { g in
                Section {
                    ForEach(g.items) { e in
                        Button { editing = e } label: { row(e) }
                    }
                    .onDelete { idx in idx.map { g.items[$0] }.forEach { deleteExpense($0, ctx: ctx) } }
                } header: {
                    if !g.name.isEmpty {
                        HStack(spacing: 8) {
                            ProviderLogo(provider: g.name, size: 22)
                            Text("\(g.name) · \(eur(g.items.reduce(0) { $0 + $1.myAmount }))")
                        }
                    }
                }
            }
        }
        .navigationTitle(category).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { e in AddExpenseView(defaultDate: e.date, editing: e) }
    }

    private func row(_ e: Expense) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.note.isEmpty ? category : e.note).foregroundStyle(.primary).lineLimit(1)
                Text(e.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + (e.isCash ? " · contanti" : ""))
                    .font(.subheadline).foregroundStyle(.secondary)
                if let t = trips.first(where: { $0.uid == e.tripID }) { TripBadge(name: t.name) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(eur(e.myAmount)).bold().foregroundStyle(.primary)
                if abs(e.myAmount - e.amount) > 0.005 {
                    Text("su \(eur(e.amount))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
