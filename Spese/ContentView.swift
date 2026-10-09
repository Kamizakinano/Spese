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
            if !accounts.isEmpty { runAutoBackup(ctx) }
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        .overlay { if lockOn && locked { LockView(unlock: authenticate) } }
        .onChange(of: phase) { _, p in
            if p == .active {
                generateAll()
                if !accounts.isEmpty { runAutoBackup(ctx) }
                if lockOn && locked { authenticate() }
            }
            if p == .background {
                try? ctx.save()   // non perdere le ultime modifiche se l'app viene chiusa
                if lockOn { locked = true }
            }
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
    @State private var showPeriod = false
    @AppStorage("applePayBannerHidden") private var applePayBannerHidden = false
    @AppStorage(summarySeenKey) private var summarySeen: Double = 0
    @State private var endedSummary: EndedPeriod?
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

    /// Periodo dall'ultimo stipendio al prossimo (scelto dall'utente o calcolato dal giorno di accredito).
    private var period: (start: Date, end: Date)? {
        guard let a = accounts.first else { return nil }
        return payPeriod(day: a.salaryDay, customStart: a.periodStart, customEnd: a.periodEnd)
    }
    private func spentInPeriod(_ p: (start: Date, end: Date)) -> Double {
        all.filter { $0.date >= p.start && $0.date < p.end }.reduce(0) { $0 + $1.amount }
    }

    /// Quanto si può spendere al giorno fino al prossimo stipendio. Toccandolo si sceglie il periodo.
    @ViewBuilder private var perDay: some View {
        if Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month), let p = period {
            let days = max(daysLeft(until: p.end), 1)
            let endText = p.end.formatted(.dateTime.day().month(.wide))
            Button { showPeriod = true } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(totalAvailable > 0
                         ? "\(eur(totalAvailable / Double(days))) al giorno per \(days) giorni, fino al \(endText)"
                         : "Niente da spendere fino al \(endText) (\(days) giorni)")
                    HStack(spacing: 4) {
                        Text("Dallo stipendio del \(p.start.formatted(.dateTime.day().month(.wide))) hai speso \(eur(spentInPeriod(p)))")
                        Image(systemName: "square.and.pencil")
                    }.opacity(0.85)
                }
                .font(.footnote).foregroundStyle(.white).multilineTextAlignment(.leading)
            }
            .buttonStyle(.borderless)
        }
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

                if !applePayBannerHidden {
                    Section {
                        HStack(spacing: 12) {
                            NavigationLink { CardLinkView() } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Collega Apple Pay").bold()
                                        Text("Le spese pagate con l'iPhone entrano da sole").font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: { Image(systemName: "wave.3.right.circle.fill").foregroundStyle(Theme.accent) }
                            }
                            Button { applePayBannerHidden = true } label: {
                                Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Nascondi")
                        }
                    }
                }

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
            .sheet(isPresented: $showPeriod) { PayPeriodEditor() }
            .sheet(item: $endedSummary) { e in
                NavigationStack {
                    PeriodSummaryView(title: "È arrivato lo stipendio", summary: e.summary, previous: e.previous)
                        .toolbar { Button("Chiudi") { endedSummary = nil } }
                }
            }
            .onAppear(perform: checkEndedPeriod)
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
            perDay
        }
        .foregroundStyle(.white).padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: totalAvailable < 0 ? [Color.red, Color.orange] : [Theme.accent, Color(hex: "0F6E56")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22))
    }

    /// Quando inizia un nuovo periodo (è arrivato lo stipendio) mostra una volta il riepilogo di quello finito.
    private func checkEndedPeriod() {
        guard let a = accounts.first, let p = period else { return }
        let start = p.start.timeIntervalSinceReferenceDate
        if summarySeen == 0 { summarySeen = start; return }   // prima volta: niente riepilogo
        guard start > summarySeen else { return }
        summarySeen = start
        // Se il periodo finito era quello scelto a mano, si usano le sue date.
        let chosen: (start: Date, end: Date)? = {
            guard let s = a.periodStart, let e = a.periodEnd, Calendar.current.isDate(e, inSameDayAs: p.start) else { return nil }
            return (s, e)
        }()
        guard let prev = chosen ?? previousPeriod(before: p.start, day: a.salaryDay) else { return }
        let s = summarize(expenses: all, incomes: incomes, start: prev.start, end: prev.end)
        guard s.count > 0 else { return }
        let before = previousPeriod(before: prev.start, day: a.salaryDay)
            .map { summarize(expenses: all, incomes: incomes, start: $0.start, end: $0.end) }
        endedSummary = EndedPeriod(summary: s, previous: before)
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


struct EndedPeriod: Identifiable {
    let id = UUID()
    let summary: PeriodSummary
    let previous: PeriodSummary?
}

// MARK: - Periodo dello stipendio

/// Si indica quando è arrivato lo stipendio e quando arriverà il prossimo:
/// la cifra al giorno si calcola fino a quella data.
struct PayPeriodEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]
    @State private var start = Date()
    @State private var end = Date()

    private var cal: Calendar { Calendar.current }
    private var tomorrow: Date { cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date() }
    private var day: Int { accounts.first?.salaryDay ?? 27 }
    private var isCustom: Bool { (accounts.first?.periodEnd).map { $0 > Date() } ?? false }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Stipendio ricevuto il", selection: $start, in: ...Date(), displayedComponents: .date)
                    DatePicker("Prossimo stipendio il", selection: $end, in: tomorrow..., displayedComponents: .date)
                    HStack { Text("Giorni da coprire"); Spacer(); Text("\(max(daysLeft(until: end), 1))").bold() }
                } footer: {
                    Text("La cifra al giorno vale fino al giorno prima del prossimo stipendio. Passata quella data l'app torna al calcolo automatico (giorno \(day) di ogni mese, si cambia in Altro → Stipendio e risparmi).")
                }
                if isCustom {
                    Section {
                        Button("Usa il calcolo automatico (giorno \(day))", role: .destructive) {
                            accounts.first?.periodStart = nil
                            accounts.first?.periodEnd = nil
                            try? ctx.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Periodo dello stipendio").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        if let a = accounts.first {
                            a.periodStart = cal.startOfDay(for: start)
                            a.periodEnd = cal.startOfDay(for: end)
                            UserDefaults.standard.set(a.periodStart?.timeIntervalSinceReferenceDate ?? 0, forKey: summarySeenKey)
                            try? ctx.save()
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let a = accounts.first, let p = payPeriod(day: a.salaryDay, customStart: a.periodStart, customEnd: a.periodEnd) {
                    start = p.start; end = max(p.end, tomorrow)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
