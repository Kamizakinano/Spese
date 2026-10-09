import SwiftUI
import SwiftData
import Charts
import UserNotifications
import LocalAuthentication

struct ContentView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.scenePhase) private var phase
    @Query private var recurring: [Recurring]
    @Query private var accounts: [Account]
    @AppStorage("lockOn") private var lockOn = false
    @State private var locked = true

    var body: some View {
        Group {
            if accounts.isEmpty {
                SetupView()
            } else {
                TabView {
                    HomeView().tabItem { Label("Spese", systemImage: "list.bullet.rectangle") }
                    ContiView().tabItem { Label("Conti", systemImage: "creditcard") }
                    SavingsView().tabItem { Label("Risparmi", systemImage: "banknote") }
                    StatsView().tabItem { Label("Statistiche", systemImage: "chart.xyaxis.line") }
                    SettingsView().tabItem { Label("Altro", systemImage: "gearshape") }
                }
            }
        }
        .task {
            if lockOn { authenticate() } else { locked = false }
            seed()
            generateAll()
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        .overlay { if lockOn && locked { LockView(unlock: authenticate) } }
        .onChange(of: phase) { _, p in
            if p == .active { generateAll(); if lockOn && locked { authenticate() } }
            if p == .background && lockOn { locked = true }
        }
        .onChange(of: recurring.count) { _, _ in generateAll() }
        .onChange(of: accounts.count) { _, _ in generateAll() }
    }

    private func authenticate() {
        let c = LAContext()
        var err: NSError?
        guard c.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { locked = false; return }
        c.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Sblocca le tue spese") { ok, _ in
            DispatchQueue.main.async { if ok { locked = false } }
        }
    }

    private func seed() {
        let n = (try? ctx.fetchCount(FetchDescriptor<CategoryItem>())) ?? 0
        guard n == 0 else { return }
        for (i, c) in defaultCategories.enumerated() {
            ctx.insert(CategoryItem(name: c.0, icon: c.1, colorHex: c.2, order: i))
        }
    }

    private func generateAll() {
        for r in (try? ctx.fetch(FetchDescriptor<Recurring>())) ?? [] {
            let due = dueDates(from: r.nextKey, day: r.day)
            for d in due.dates { ctx.insert(Expense(amount: r.amount, categoryName: r.categoryName, date: d, note: r.name)) }
            if !due.dates.isEmpty { r.nextKey = due.next }
        }
        if let a = (try? ctx.fetch(FetchDescriptor<Account>()))?.first, a.salaryAmount > 0, !a.salaryNextKey.isEmpty {
            let due = dueDates(from: a.salaryNextKey, day: a.salaryDay)
            for d in due.dates {
                let s = splitSaving(total: a.salaryAmount, mode: a.salaryMode, value: a.salaryValue)
                ctx.insert(Income(amount: a.salaryAmount, saved: s, kind: "Stipendio", date: d, note: "Stipendio"))
            }
            if !due.dates.isEmpty { a.salaryNextKey = due.next }
        }
    }
}

struct CatTotal: Identifiable {
    let name: String, icon: String, color: Color, total: Double
    var id: String { name }
}

struct HomeView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Expense.date, order: .reverse) private var all: [Expense]
    @Query private var incomes: [Income]
    @Query private var moves: [SavingsMove]
    @Query private var cashMoves: [CashMove]
    @Query private var accounts: [Account]
    @Query(sort: \CategoryItem.order) private var cats: [CategoryItem]

    @State private var month = Date()
    @State private var showAdd = false
    @State private var search = ""
    @State private var filterCat = ""
    @State private var filterMethod = ""
    @State private var editing: Expense?

    private var expenses: [Expense] {
        all.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }
    private var ledger: Ledger { Ledger(incomes: incomes, expenses: all, moves: moves, cash: cashMoves, account: accounts.first) }
    private var fig: Figures { ledger.figures(for: month) }
    private var total: Double { expenses.reduce(0) { $0 + $1.amount } }
    private var budget: Double { fig.budget }
    private var left: Double { fig.left }
    private var cashNow: Double {
        let end = Calendar.current.dateInterval(of: .month, for: month)?.end ?? Ledger.endOfToday
        return ledger.cashBalance(asOf: min(end, Ledger.endOfToday))
    }
    private var totalAvailable: Double { left + cashNow }

    private func look(_ n: String) -> (icon: String, color: Color) {
        if let c = cats.first(where: { $0.name == n }) { return (c.icon, Color(hex: c.colorHex)) }
        return ("questionmark.circle", .gray)
    }

    private var byCat: [CatTotal] {
        Dictionary(grouping: expenses, by: \.categoryRaw).map { name, list in
            let l = look(name)
            return CatTotal(name: name, icon: l.icon, color: l.color, total: list.reduce(0) { $0 + $1.amount })
        }.sorted { $0.total > $1.total }
    }

    private var owedTotal: Double { all.filter { !$0.settled && $0.owedAmount > 0 }.reduce(0) { $0 + $1.owedAmount } }
    private var limited: [CategoryItem] { cats.filter { $0.limit > 0 } }
    private func spent(_ c: CategoryItem) -> Double {
        expenses.filter { $0.categoryRaw == c.name }.reduce(0) { $0 + $1.amount }
    }
    private func matches(_ e: Expense) -> Bool {
        if !filterCat.isEmpty && e.categoryRaw != filterCat { return false }
        if !filterMethod.isEmpty && e.method != filterMethod { return false }
        if search.isEmpty { return true }
        return [e.note, e.categoryRaw, e.tag, eur(e.amount)].contains { $0.localizedCaseInsensitiveContains(search) }
    }
    private var shown: [Expense] { (search.isEmpty ? expenses : all).filter(matches) }

    private var perDayText: String? {
        let cal = Calendar.current
        guard totalAvailable > 0, cal.isDate(month, equalTo: Date(), toGranularity: .month),
              let r = cal.range(of: .day, in: .month, for: Date()) else { return nil }
        let days = r.count - cal.component(.day, from: Date()) + 1
        return "\(eur(totalAvailable / Double(days))) al giorno per \(days) giorni"
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
                    }.buttonStyle(.borderless)
                }
                Section { hero }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)

                if owedTotal > 0 {
                    Section {
                        NavigationLink { OwedView() } label: {
                            HStack { Label("Ti devono", systemImage: "person.2"); Spacer(); Text(eur(owedTotal)).bold() }
                        }
                    }
                }

                if !byCat.isEmpty {
                    Section("Per categoria") {
                        Chart(byCat) { i in
                            SectorMark(angle: .value("Totale", i.total), innerRadius: .ratio(0.62), angularInset: 1.5)
                                .foregroundStyle(i.color).cornerRadius(4)
                        }.frame(height: 190)
                        ForEach(byCat) { i in
                            HStack {
                                Label(i.name, systemImage: i.icon).foregroundStyle(i.color)
                                Spacer()
                                Text(eur(i.total))
                                Text("\(Int((i.total / total * 100).rounded()))%")
                                    .foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                            }.font(.subheadline)
                        }
                    }
                }

                if !limited.isEmpty {
                    Section("Limiti per categoria") {
                        ForEach(limited) { c in
                            let s = spent(c)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Label(c.name, systemImage: c.icon).foregroundStyle(Color(hex: c.colorHex))
                                    Spacer()
                                    Text("\(eur(s)) di \(eur(c.limit))").font(.footnote)
                                        .foregroundStyle(s >= c.limit ? Color.red : Color.secondary)
                                }
                                ProgressView(value: min(s, c.limit), total: c.limit)
                                    .tint(s >= c.limit ? Color.red : Color(hex: c.colorHex))
                            }
                        }
                    }
                }

                Section("Movimenti") {
                    if shown.isEmpty { Text("Ancora nessuna spesa").foregroundStyle(.secondary) }
                    ForEach(shown) { e in
                        let l = look(e.categoryRaw)
                        HStack(spacing: 12) {
                            Image(systemName: l.icon).foregroundStyle(.white)
                                .frame(width: 34, height: 34).background(l.color, in: Circle())
                            VStack(alignment: .leading) {
                                Text(e.note.isEmpty ? e.categoryRaw : e.note)
                                Text("\(e.date.formatted(.dateTime.day().month(.abbreviated))) · \(e.categoryRaw)" + (e.tag.isEmpty ? "" : " · #\(e.tag)") + (e.isCash ? " · contanti" : ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(eur(e.amount)).bold()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editing = e }
                    }.onDelete { idx in idx.map { shown[$0] }.forEach(ctx.delete) }
                }
            }
            .navigationTitle("Le mie spese").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Cerca spese")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Categoria", selection: $filterCat) {
                            Text("Tutte").tag("")
                            ForEach(cats) { c in Text(c.name).tag(c.name) }
                        }
                        Picker("Pagamento", selection: $filterMethod) {
                            Text("Tutti").tag("")
                            Text("Carta").tag("carta")
                            Text("Contanti").tag("contanti")
                        }
                    } label: {
                        Image(systemName: filterCat.isEmpty && filterMethod.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus").font(.title2.bold()).foregroundStyle(.white)
                        .frame(width: 58, height: 58).background(Theme.accent, in: Circle())
                        .shadow(radius: 6, y: 3)
                }.padding(20)
            }
            .sheet(isPresented: $showAdd) { AddExpenseView(defaultDate: defaultDate()) }
            .sheet(item: $editing) { AddExpenseView(defaultDate: $0.date, editing: $0) }
            .onChange(of: total) { _, _ in checkAlerts() }
            .onChange(of: budget) { _, _ in checkAlerts() }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Totale disponibile").font(.subheadline).opacity(0.85)
            Text(eur(totalAvailable)).font(.system(size: 36, weight: .bold, design: .rounded))
            HStack {
                Label("Carta \(eur(left))", systemImage: "creditcard")
                Spacer()
                Label("Contanti \(eur(cashNow))", systemImage: "banknote")
            }.font(.footnote)
            HStack {
                Text("Spesi \(eur(total))")
                Spacer()
                Text("Entrate \(eur(fig.incomeNet))")
            }.font(.footnote)
            Text("Risparmi separati: \(eur(ledger.savingsTotal))").font(.footnote).opacity(0.85)
            if let t = perDayText { Text(t).font(.footnote).opacity(0.9) }
        }
        .foregroundStyle(.white).padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: totalAvailable < 0 ? [Color.red, Color.orange] : [Theme.accent, Color(hex: "0F6E56")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22))
    }

    private func shift(_ n: Int) { month = Calendar.current.date(byAdding: .month, value: n, to: month) ?? month }
    private func defaultDate() -> Date {
        Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month) ? Date() : month
    }

    private func checkCategoryLimits() {
        let k = monthKey(month)
        guard k == monthKey(Date()) else { return }
        for c in cats where c.limit > 0 {
            let s = spent(c)
            for (th, label) in [(0.8, "80%"), (1.0, "100%")] {
                let flag = "cat\(label)-\(c.name)-\(k)"
                if s / c.limit >= th && !UserDefaults.standard.bool(forKey: flag) {
                    UserDefaults.standard.set(true, forKey: flag)
                    notify("Limite \(c.name)", th < 1 ? "Hai usato l'80% del limite di \(eur(c.limit))."
                                                    : "Hai raggiunto il limite di \(eur(c.limit)).")
                }
            }
        }
    }

    private func checkAlerts() {
        checkCategoryLimits()
        let k = monthKey(month)
        guard budget > 0, k == monthKey(Date()) else { return }
        let ratio = (fig.spent + fig.moved) / budget
        for (th, label) in [(0.8, "80%"), (1.0, "100%")] {
            let flag = "alert\(label)-\(k)"
            if ratio >= th && !UserDefaults.standard.bool(forKey: flag) {
                UserDefaults.standard.set(true, forKey: flag)
                notify(th < 1 ? "Attenzione al budget" : "Budget esaurito",
                       th < 1 ? "Hai usato l'\(label) dei soldi disponibili. Restano \(eur(max(left, 0)))."
                              : "Hai esaurito i soldi disponibili di questo mese.")
            }
        }
    }
}

