import SwiftUI
import SwiftData
import Charts

// MARK: - Home: una pagina per ogni giorno

/// Riga di una spesa, uguale in Home, nell'elenco del mese e nelle altre liste.
struct ExpenseRow: View {
    let expense: Expense
    let look: (icon: String, color: Color)
    var trip: Trip? = nil
    var detail: String

    var body: some View {
        let e = expense
        let owe = e.paidByMe ? 0 : e.myAmount   // la mia parte di una spesa pagata da altri
        HStack(spacing: 12) {
            if e.planProvider.isEmpty, e.categoryRaw == otherCategory, let emoji = otherEmoji(e.note) {
                Text(emoji).font(.title3)
                    .frame(width: 40, height: 40).background(look.color.opacity(0.14), in: Circle())
            } else if e.planProvider.isEmpty {
                Image(systemName: look.icon).font(.body.weight(.semibold)).foregroundStyle(look.color)
                    .frame(width: 40, height: 40).background(look.color.opacity(0.14), in: Circle())
            } else {
                ProviderLogo(provider: e.planProvider, size: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(e.note.isEmpty ? e.categoryRaw : e.note).foregroundStyle(.primary).lineLimit(1)
                if !e.paidByMe {
                    // Pagata da un'altra persona: chi ha pagato e quanto le devo.
                    (Text("Pagato da \(e.paidBy)")
                     + (owe > 0 ? Text(" · ") + Text("devi \(eur(owe))").bold().foregroundColor(.orange) : Text("")))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    let shown = rowDetail(detail, note: e.note, category: e.categoryRaw)
                    if !shown.isEmpty { Text(shown).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                }
                if let trip { TripBadge(name: trip.name) }
                if e.owedAmount > 0 && e.tripID.isEmpty { OwedBadge(expense: e) }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(e.needsAmount ? "Da completare" : eur(owe > 0 ? owe : e.amount))
                    .font(e.needsAmount ? .caption.bold() : .body.bold())
                    .foregroundStyle(e.needsAmount ? Color.orange : Color.primary)
                if owe > 0 {
                    Text("di \(eur(e.amount))").font(.caption).foregroundStyle(.secondary)
                } else if e.originalAmount > 0, !e.originalCurrency.isEmpty, e.originalCurrency != "EUR" {
                    Text(e.originalAmount.formatted(.currency(code: e.originalCurrency))).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

/// Seconda riga di una spesa: se la spesa non ha nota il titolo è già la categoria, quindi non la ripete.
func rowDetail(_ detail: String, note: String, category: String) -> String {
    guard note.isEmpty else { return detail }
    var parts = detail.components(separatedBy: " · ")
    if let i = parts.firstIndex(of: category) { parts.remove(at: i) }
    return parts.joined(separator: " · ")
}

/// I sette giorni della settimana del giorno scelto, con una barretta alta quanto si è speso.
func weekDays(of day: Date) -> [Date] {
    let start = weekRange(day).start
    return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
}

struct HomeView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Expense.date, order: .reverse) private var all: [Expense]
    @Query private var incomes: [Income]
    @Query private var moves: [SavingsMove]
    @Query private var cashMoves: [CashMove]
    @Query private var accounts: [Account]
    @Query private var payments: [TripPayment]
    @Query(sort: \CategoryItem.order) private var cats: [CategoryItem]
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @Query private var recurringAll: [Recurring]
    @AppStorage(dailySaveKey) private var dailySave = 0.0
    @AppStorage(forecastDailyKey) private var forecastDaily = true
    @AppStorage(yearRecapKey) private var yearRecapOn = false
    @AppStorage("applePayBannerHidden") private var applePayBannerHidden = false
    @AppStorage(summarySeenKey) private var summarySeen: Double = 0
    @AppStorage(limitPeriodOnKey) private var limitOn = false
    @AppStorage(limitStartKey) private var limitStart: Double = 0
    @AppStorage(limitEndKey) private var limitEnd: Double = 0

    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var showAdd = false
    @State private var showPeriod = false
    @State private var showMonths = false
    @State private var openMonth: Date?
    @AppStorage(listScaleKey) private var listScale = ListScale.month.rawValue
    @State private var editing: Expense?
    @State private var editingRecurring: Recurring?
    @State private var tripAdding: Trip?
    @State private var cashCheck = false
    @State private var cashCheckSeen = Date()
    @State private var endedSummary: EndedPeriod?

    private let cal = Calendar.current
    private var isToday: Bool { cal.isDateInToday(day) }
    private var isFuture: Bool { day >= Ledger.endOfToday }

    // MARK: Numeri

    private var ledger: Ledger { Ledger(incomes: incomes, expenses: all, moves: moves, cash: cashMoves, account: accounts.first, payments: payments) }
    private var fig: Figures { ledger.figures(for: Date()) }
    private var card: Double { fig.left }
    private var cashNow: Double { ledger.cashBalance() }
    private var available: Double { card + cashNow }
    private var period: (start: Date, end: Date)? {
        guard let a = accounts.first else { return nil }
        return payPeriod(day: a.salaryDay, customStart: a.periodStart, customEnd: a.periodEnd)
    }
    private var upcomingAll: [Expense] { all.filter { $0.date >= Ledger.endOfToday }.sorted { $0.date < $1.date } }
    /// In "In arrivo": di ogni acquisto a rate solo la prossima rata.
    private var upcoming: [Expense] {
        var seen = Set<String>()
        return upcomingAll.filter { $0.planID.isEmpty || seen.insert($0.planID).inserted }
    }
    private func upcomingTotal(before end: Date) -> Double {
        upcomingAll.filter { $0.date < end && $0.paidByMe }.reduce(0) { $0 + $1.myAmount }
    }
    private var daysLeftInPeriod: Int { period.map { max(daysLeft(until: $0.end), 1) } ?? 1 }
    private var spentTodayCash: Double {
        all.filter { $0.paidByMe && cal.isDateInToday($0.date) }.reduce(0) { $0 + $1.amount }
    }
    /// Budget di oggi (calcolato con i soldi di stamattina).
    private var todayBudget: Double {
        guard let p = period else { return 0 }
        let d = Double(daysLeftInPeriod)
        return max(available + spentTodayCash - upcomingTotal(before: p.end) - dailySave * d, 0) / d
    }
    /// Budget da domani in poi.
    private var nextBudget: Double {
        guard let p = period else { return 0 }
        let d = Double(max(daysLeftInPeriod - 1, 1))
        return max(available - upcomingTotal(before: p.end) - dailySave * d, 0) / d
    }
    private func spentOn(_ d: Date) -> Double {
        statExpenses(all, trips: trips).filter { cal.isDate($0.date, inSameDayAs: d) }.reduce(0) { $0 + $1.myAmount }
    }
    private var dayExpenses: [Expense] {
        all.filter { cal.isDate($0.date, inSameDayAs: day) }.sorted { $0.date > $1.date }
    }
    /// Spese ricorrenti e abbonamenti che cadono nel giorno scelto (solo giorni futuri).
    private var dayRecurring: [Recurring] {
        guard isFuture, let end = cal.date(byAdding: .day, value: 1, to: day) else { return [] }
        return recurringAll.filter { r in
            monthlyDates(nextKey: r.nextKey, day: r.day, until: end).contains { cal.isDate($0, inSameDayAs: day) }
                && !recurringCovered(name: r.name, on: day, expenses: all)
        }
    }
    private var spentInPeriod: Double {
        guard let p = period else { return 0 }
        return statExpenses(all, trips: trips).filter { $0.date >= p.start && $0.date < min(p.end, Ledger.endOfToday) }.reduce(0) { $0 + $1.myAmount }
    }
    private var owedTotal: Double { all.filter { !$0.settled && $0.owedAmount > 0 }.reduce(0) { $0 + $1.owedAmount } }

    private func look(_ n: String) -> (icon: String, color: Color) {
        if let c = cats.first(where: { $0.name == n }) { return (c.icon, Color(hex: c.colorHex)) }
        return ("questionmark.circle", .gray)
    }
    private func detail(_ e: Expense) -> String {
        var parts = [e.categoryRaw]
        if !cal.isDate(e.date, inSameDayAs: day) { parts.insert(e.date.formatted(.dateTime.day().month(.abbreviated)), at: 0) }
        if !e.planProvider.isEmpty { parts.append(e.planProvider) }
        if !e.tag.isEmpty { parts.append("#\(e.tag)") }
        if e.isCash { parts.append("contanti") }
        if !e.paidByMe { parts.append("pagato da \(e.paidBy)") }
        return parts.joined(separator: " · ")
    }

    // MARK: Pagina

    var body: some View {
        NavigationStack {
            List {
                Section {
                    dayHeader
                    WeekStrip(day: $day, spent: { spentOn($0) }, budget: todayBudget)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                // Trascinando il dito sulla data o sui giorni si cambia giorno.
                .simultaneousGesture(daySwipe)

                Section { ringCard; chips }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                // Per tre giorni dopo il rientro: com'è andato il viaggio.
                if activeTrip(trips) == nil, let t = recentlyEndedTrip(trips) {
                    Section {
                        NavigationLink { TripDetailView(trip: t) } label: {
                            Label("Com'è andato il viaggio a \(t.name)? · \(eur(tripTotals(t, all).total))", systemImage: "airplane.arrival")
                                .foregroundStyle(tripBlue)
                        }
                    }
                }
                // Nei giorni del viaggio il riquadro sta in alto, per aggiungere le spese al volo.
                if let t = activeTrip(trips) {
                    Section {
                        NavigationLink { TripDetailView(trip: t) } label: { TripHomeCard(trip: t, expenses: all) }
                            .listRowBackground(LinearGradient(colors: [tripBlue, tripBlueDark], startPoint: .topLeading, endPoint: .bottomTrailing))
                        if t.isForeign { TripPriceCheck(trip: t) }
                        Button { tripAdding = t } label: {
                            Label("Spesa del viaggio", systemImage: "plus.circle.fill").bold().foregroundStyle(tripBlue)
                        }
                    }
                }

                daySection
                extraSections
                weekSection

                Section {
                    Button { listScale = ListScale.month.rawValue; openMonth = day } label: {
                        Text("Tutte le spese di \(day.formatted(.dateTime.month(.wide)))")
                            .bold().frame(maxWidth: .infinity)
                    }
                }
            }
            .listSectionSpacing(.compact)
            .contentMargins(.top, 4, for: .scrollContent)
            .safeAreaPadding(.bottom, 72)   // il pulsante + non copre l'ultimo riquadro
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showMonths = true } label: {
                        // Testo e icona insieme: nella barra in alto una Label mostrerebbe solo l'icona.
                        HStack(spacing: 5) {
                            Image(systemName: "calendar")
                            Text(day.formatted(.dateTime.month(.wide).year()).capitalized)
                            Image(systemName: "chevron.down").font(.caption.bold())
                        }
                        .font(.subheadline.bold())
                    }
                    .accessibilityLabel("Scegli il mese")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { openMonth = day } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("Cerca nelle spese del mese")
                }
            }
            .navigationDestination(item: $openMonth) { m in
                MonthView(month: m) { picked in
                    day = cal.startOfDay(for: picked)
                    openMonth = nil
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus").font(.title2.bold()).foregroundStyle(.white)
                        .frame(width: 58, height: 58).background(Theme.accent, in: Circle())
                        .shadow(radius: 6, y: 3)
                }
                .padding(20)
                .accessibilityLabel("Nuova spesa")
            }
            .sheet(isPresented: $showAdd) { AddExpenseView(defaultDate: isToday ? Date() : (cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day)) }
            .sheet(item: $editing) { e in
                if let t = trips.first(where: { $0.uid == e.tripID }) { TripExpenseEditor(trip: t, editing: e) }
                else { AddExpenseView(defaultDate: e.date, editing: e) }
            }
            .sheet(item: $tripAdding) { TripExpenseEditor(trip: $0, editing: nil) }
            .sheet(item: $editingRecurring) { r in RecurringEditor(editing: r) }
            .sheet(isPresented: $cashCheck, onDismiss: { cashCheckSeen = Date() }) { CashCheckView() }
            .sheet(isPresented: $showPeriod) { PayPeriodEditor() }
            .sheet(isPresented: $showMonths) {
                MonthPickerView(selected: day) { m in
                    showMonths = false
                    openMonth = m
                }
            }
            .sheet(item: $endedSummary) { e in
                NavigationStack {
                    PeriodSummaryView(title: "È arrivato lo stipendio", summary: e.summary, previous: e.previous)
                        .toolbar { Button("Chiudi") { endedSummary = nil } }
                }
            }
            .task(id: upcomingAll.map { "\($0.date.timeIntervalSince1970)|\($0.amount)|\($0.note)" }) { await scheduleUpcomingReminders(ctx) }
            .onAppear(perform: checkEndedPeriod)
            .onChange(of: all.count) { _, _ in checkAlerts() }
        }
    }

    private func recurringRow(_ r: Recurring) -> some View {
        HStack(spacing: 12) {
            Image(systemName: r.isSubscription ? "play.rectangle" : "repeat").foregroundStyle(.secondary)
                .frame(width: 40, height: 40).background(Color.secondary.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name).lineLimit(1)
                Text(r.isSubscription ? "Abbonamento" : "Spesa ricorrente").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(eur(r.amount)).bold()
        }
        .contentShape(Rectangle())
    }

    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 30).onEnded { v in
            guard abs(v.translation.width) > 60, abs(v.translation.width) > abs(v.translation.height) else { return }
            shiftDay(v.translation.width < 0 ? 1 : -1)
        }
    }
    private func shiftDay(_ n: Int) {
        withAnimation { day = cal.date(byAdding: .day, value: n, to: day) ?? day }
    }

    private var dayHeader: some View {
        // Un tocco sulla data riporta a oggi. Le frecce cambiano settimana (stesso giorno), il dito cambia giorno.
        VStack(spacing: 3) {
            HStack {
                Button { shiftDay(-7) } label: { Image(systemName: "chevron.left").font(.title3.weight(.semibold)) }
                    .accessibilityLabel("Settimana prima")
                Spacer()
                Button { withAnimation { day = cal.startOfDay(for: Date()) } } label: {
                    Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized).font(.headline).foregroundStyle(.primary)
                }
                Spacer()
                Button { shiftDay(7) } label: { Image(systemName: "chevron.right").font(.title3.weight(.semibold)) }
                    .accessibilityLabel("Settimana dopo")
            }
            Button { withAnimation { day = cal.startOfDay(for: Date()) } } label: {
                Text(isToday ? "Oggi" : "Torna a oggi").font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(isToday ? Theme.accent.opacity(0.15) : Color.secondary.opacity(0.12), in: Capsule())
                    .foregroundStyle(isToday ? Theme.accent : Color.secondary)
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 4).padding(.vertical, 4)
    }

    /// Anello del giorno: quanto si è speso rispetto al budget. Toccandolo si sceglie il periodo dello stipendio.
    @ViewBuilder private var ringCard: some View {
        let spent = isFuture
            ? dayExpenses.filter(\.paidByMe).reduce(0) { $0 + $1.myAmount } + dayRecurring.reduce(0) { $0 + $1.amount }
            : spentOn(day)
        let budget = isToday ? todayBudget : nextBudget
        let share = budget > 0 ? min(spent / budget, 1) : (spent > 0 ? 1 : 0)
        let over = budget > 0 && spent > budget + 0.005
        Button { showPeriod = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 12)
                    Circle().trim(from: 0, to: share)
                        .stroke(isFuture ? Color.secondary.opacity(0.5) : (over ? Color.red : Theme.accent),
                                style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(isFuture ? "previsto" : (isToday ? "speso oggi" : "speso")).font(.caption2).foregroundStyle(.secondary)
                        Text(eur(spent)).font(.system(.headline, design: .rounded).bold()).lineLimit(1).minimumScaleFactor(0.6)
                        if budget > 0 { Text("di \(eur(budget))").font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7) }
                    }
                    .padding(14)
                }
                .frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 5) {
                    if isFuture {
                        Text("Giorno futuro").font(.headline)
                        Text("Le spese in arrivo sono già tenute da parte nel budget.").font(.caption).foregroundStyle(.secondary)
                    } else if isToday && budget > 0 {
                        Text(over ? "Oltre di \(eur(spent - budget))" : "Restano \(eur(budget - spent))").font(.headline)
                            .foregroundStyle(over ? Color.red : Color.primary)
                        Text("per oggi. Da domani \(eur(nextBudget)) al giorno.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(isToday ? "Oggi" : "Speso in questo giorno").font(.headline)
                    }
                    if let p = period {
                        let days = daysLeftInPeriod
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Fino al \(p.end.formatted(.dateTime.day().month(.wide)))").font(.caption.bold())
                            Text("ancora \(days) \(days == 1 ? "giorno" : "giorni")").font(.caption)
                        }
                        .foregroundStyle(Theme.accent)
                        Text("Speso dal \(p.start.formatted(.dateTime.day().month(.abbreviated))): \(eur(spentInPeriod))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var chips: some View {
        HStack(spacing: 8) {
            chip("Disponibile", available, available < 0 ? .red : .primary)
            chip("Carta", card, .primary)
            chip("Contanti", cashNow, .primary)
        }
    }
    private func chip(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(eur(value)).font(.subheadline.bold()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var daySection: some View {
        let list = dayExpenses
        Section {
            if list.isEmpty && dayRecurring.isEmpty {
                Text(isFuture ? "Nessuna spesa prevista in questo giorno." : "Nessuna spesa in questo giorno.").foregroundStyle(.secondary)
            }
            ForEach(list) { e in
                Button { editing = e } label: {
                    ExpenseRow(expense: e, look: look(e.categoryRaw), trip: trips.first { $0.uid == e.tripID }, detail: detail(e))
                }
                .buttonStyle(.plain)
            }
            .onDelete { idx in idx.map { list[$0] }.forEach { deleteExpense($0, ctx: ctx) } }
            ForEach(dayRecurring) { r in
                Button { editingRecurring = r } label: { recurringRow(r) }
                    .buttonStyle(.plain)
            }
        } header: {
            HStack {
                Text(isFuture ? "In arrivo questo giorno" : (isToday ? "Spese di oggi" : "Spese del giorno"))
                Spacer()
                Text(eur(list.reduce(0) { $0 + ($1.paidByMe ? $1.amount : $1.myAmount) } + dayRecurring.reduce(0) { $0 + $1.amount }))
            }
        }
    }

    /// Questa settimana: una barretta per giorno e il confronto con la settimana scorsa allo stesso punto.
    @ViewBuilder private var weekSection: some View {
        let now = Date()
        let days = weekDays(of: now)
        let values = days.map { $0 < Ledger.endOfToday ? spentOn($0) : 0 }
        let total = values.reduce(0, +)
        let lastWeek = days.compactMap { cal.date(byAdding: .day, value: -7, to: $0) }
            .filter { $0 < (cal.date(byAdding: .day, value: -7, to: Ledger.endOfToday) ?? now) }
            .map(spentOn).reduce(0, +)
        let top = max(values.max() ?? 0, 1)
        Section {
            Button { listScale = ListScale.week.rawValue; openMonth = cal.startOfDay(for: now) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Questa settimana").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if let t = weekCompareText(this: total, last: lastWeek) {
                            Text(t).font(.caption.bold()).foregroundStyle(total <= lastWeek ? Theme.accent : Color.orange)
                        }
                    }
                    HStack(alignment: .bottom) {
                        Text(eur(total)).font(.title3.bold()).foregroundStyle(.primary)
                        Spacer(minLength: 12)
                        HStack(alignment: .bottom, spacing: 5) {
                            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                                let today = cal.isDateInToday(d)
                                VStack(spacing: 2) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(d >= Ledger.endOfToday ? Color.secondary.opacity(0.15) : (today ? Theme.accent : Theme.accent.opacity(0.4)))
                                        .frame(width: 14, height: max(3, 34 * values[i] / top))
                                    Text(d.formatted(.dateTime.weekday(.narrow))).font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(height: 48, alignment: .bottom)
                    }
                }
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Questa settimana \(eur(total)). Apri l'elenco della settimana")
        }
    }

    /// Le altre cose della Home di sempre, sotto le spese del giorno.
    @ViewBuilder private var extraSections: some View {
        let pending = all.filter(\.needsAmount)
        if !pending.isEmpty {
            Section {
                ForEach(pending) { e in
                    Button { editing = e } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.note.isEmpty ? "Pagamento con Apple Pay" : e.note).bold().foregroundStyle(.primary)
                                Text("\(e.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())) · tocca per inserire l'importo")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange) }
                    }
                }
            } header: { Text("Da completare") }
        }

        if !accounts.isEmpty {
            Section {
                NavigationLink { Prossimi30View() } label: {
                    Prossimi30Tile(card: card,
                                   planned: plannedMoves(expenses: all, recurring: recurringAll, account: accounts.first),
                                   perDay: (forecastDaily ? dailyCardAverage(all, recurringNames: Set(recurringAll.map(\.name))) : 0) + dailySave)
                }
            }
        }

        if yearRecapOn, let y = yearRecapSeason(Date()) {
            Section {
                NavigationLink { YearRecapView(year: y) } label: {
                    Label("È pronto il tuo \(String(y)) in Spese", systemImage: "sparkles").bold()
                }
            }
        }

        if cashCheckDue(last: UserDefaults.standard.object(forKey: cashCheckLastKey) as? Date, now: cashCheckSeen) {
            Section {
                Button { cashCheck = true } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Controlla i contanti").bold().foregroundStyle(.primary)
                            Text("Per l'app hai \(eur(cashNow)) nel portafoglio: è giusto?").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "banknote").foregroundStyle(Theme.accent) }
                }
            }
        }

        if !upcoming.isEmpty {
            Section {
                ForEach(upcoming) { e in
                    let n = daysLeft(until: e.date)
                    Button { editing = e } label: {
                        ExpenseRow(expense: e, look: look(e.categoryRaw),
                                   detail: "\(e.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(n == 1 ? "domani" : "tra \(n) giorni")"
                                    + (e.planProvider.isEmpty ? "" : " · \(e.planProvider)"))
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { idx in idx.map { upcoming[$0] }.forEach { deleteExpense($0, ctx: ctx) } }
            } header: {
                HStack { Label("In arrivo", systemImage: "hourglass"); Spacer(); Text(eur(upcomingAll.filter(\.paidByMe).reduce(0) { $0 + $1.myAmount })) }
            } footer: {
                Text("Spese con data futura: scendono dalla carta il giorno indicato, ma il budget le tiene già da parte.")
            }
        }


        if owedTotal > 0 {
            Section {
                NavigationLink { OwedView() } label: {
                    HStack { Label("Ti devono", systemImage: "person.2"); Spacer(); Text(eur(owedTotal)).bold() }
                }
            }
        }

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
    }

    // MARK: Avvisi e riepilogo (come prima)

    private var limitRange: (start: Date, end: Date)? {
        limitPeriod(on: limitOn,
                    customStart: limitStart > 0 ? Date(timeIntervalSinceReferenceDate: limitStart) : nil,
                    customEnd: limitEnd > 0 ? Date(timeIntervalSinceReferenceDate: limitEnd) : nil,
                    pay: period, month: Date())
    }

    private func checkAlerts() {
        if let r = limitRange {
            let k = limitOn ? "p\(Int(r.start.timeIntervalSinceReferenceDate))" : monthKey(Date())
            for c in cats where c.limit > 0 {
                let s = statExpenses(all, trips: trips).filter { $0.categoryRaw == c.name && $0.date >= r.start && $0.date < r.end }
                    .reduce(0) { $0 + $1.myAmount }
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
        let k = monthKey(Date())
        guard fig.budget > 0 else { return }
        let ratio = (fig.spent + fig.moved) / fig.budget
        for (th, label) in [(0.8, "80%"), (1.0, "100%")] {
            let flag = "alert\(label)-\(k)"
            if ratio >= th && !UserDefaults.standard.bool(forKey: flag) {
                UserDefaults.standard.set(true, forKey: flag)
                notify(th < 1 ? "Attenzione al budget" : "Budget esaurito",
                       th < 1 ? "Hai usato l'\(label) dei soldi disponibili. Restano \(eur(max(card, 0)))."
                              : "Hai esaurito i soldi disponibili di questo mese.")
            }
        }
    }

    /// Quando inizia un nuovo periodo (è arrivato lo stipendio) mostra una volta il riepilogo di quello finito.
    private func checkEndedPeriod() {
        guard let a = accounts.first, let p = period else { return }
        let start = p.start.timeIntervalSinceReferenceDate
        if summarySeen == 0 { summarySeen = start; return }
        guard start > summarySeen else { return }
        summarySeen = start
        let chosen: (start: Date, end: Date)? = {
            guard let s = a.periodStart, let e = a.periodEnd, cal.isDate(e, inSameDayAs: p.start) else { return nil }
            return (s, e)
        }()
        guard let prev = chosen ?? previousPeriod(before: p.start, day: a.salaryDay) else { return }
        let s = summarize(expenses: statExpenses(all, trips: trips), incomes: incomes, cash: cashMoves, start: prev.start, end: prev.end)
        guard s.count > 0 else { return }
        let before = previousPeriod(before: prev.start, day: a.salaryDay)
            .map { summarize(expenses: statExpenses(all, trips: trips), incomes: incomes, cash: cashMoves, start: $0.start, end: $0.end) }
        endedSummary = EndedPeriod(summary: s, previous: before)
    }
}

/// La settimana del giorno scelto: tocchi un giorno per aprirlo.
struct WeekStrip: View {
    @Binding var day: Date
    let spent: (Date) -> Double
    let budget: Double

    var body: some View {
        let days = weekDays(of: day)
        let values = days.map(spent)
        let top = max(values.max() ?? 0, budget, 1)
        HStack(spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                let on = Calendar.current.isDate(d, inSameDayAs: day)
                let future = d >= Ledger.endOfToday
                let over = budget > 0 && values[i] > budget
                Button { withAnimation { day = Calendar.current.startOfDay(for: d) } } label: {
                    VStack(spacing: 3) {
                        Text(d.formatted(.dateTime.weekday(.narrow))).font(.caption2)
                        Text(d.formatted(.dateTime.day())).font(.subheadline.bold())
                        Capsule().fill(on ? Color.white : (future ? Color.secondary.opacity(0.3) : (over ? Color.red : Theme.accent)))
                            .frame(width: 6, height: max(3, 22 * values[i] / top))
                            .frame(height: 22, alignment: .bottom)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .background(on ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(d.formatted(.dateTime.weekday(.wide).day().month(.wide)) + ", \(eur(values[i]))")
            }
        }
    }
}

// MARK: - Scegli il mese

struct MonthPickerView: View {
    let selected: Date
    let onPick: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query private var all: [Expense]
    @Query private var trips: [Trip]
    @State private var year: Int

    init(selected: Date, onPick: @escaping (Date) -> Void) {
        self.selected = selected; self.onPick = onPick
        _year = State(initialValue: Calendar.current.component(.year, from: selected))
    }

    var body: some View {
        let cal = Calendar.current
        let stats = statExpenses(all, trips: trips).filter { $0.date < Ledger.endOfToday && cal.component(.year, from: $0.date) == year }
        let totals = (1...12).map { m in stats.filter { cal.component(.month, from: $0.date) == m }.reduce(0) { $0 + $1.myAmount } }
        let top = max(totals.max() ?? 0, 1)
        let now = Date()
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        Button { year -= 1 } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        Text(String(year)).font(.title3.bold())
                        Spacer()
                        Button { year += 1 } label: { Image(systemName: "chevron.right") }
                            .disabled(year >= cal.component(.year, from: now))
                    }
                    .padding(.horizontal, 8)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(1...12, id: \.self) { m in
                            let date = cal.date(from: DateComponents(year: year, month: m, day: 1)) ?? now
                            let future = date > now
                            let current = cal.isDate(date, equalTo: selected, toGranularity: .month)
                            Button { onPick(date) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(date.formatted(.dateTime.month(.abbreviated)).capitalized).font(.subheadline.bold()).foregroundStyle(.primary)
                                    Text(future ? "–" : eur(totals[m - 1])).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                                    GeometryReader { g in
                                        Capsule().fill(Color.secondary.opacity(0.15))
                                            .overlay(alignment: .leading) {
                                                Capsule().fill(Theme.accent).frame(width: g.size.width * totals[m - 1] / top)
                                            }
                                    }
                                    .frame(height: 5)
                                }
                                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(current ? Theme.accent : .clear, lineWidth: 2.5))
                                .opacity(future ? 0.45 : 1)
                            }
                            .buttonStyle(.plain)
                            .disabled(future)
                        }
                    }
                    LabeledContent("Totale \(String(year))", value: eur(totals.reduce(0, +)))
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Scegli il mese").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Oggi") { onPick(now) } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Elenco delle spese: giorno, settimana o mese

let listScaleKey = "elencoScala"

enum ListScale: Int, CaseIterable {
    case day, week, month
    var name: String { ["Giorno", "Settimana", "Mese"][rawValue] }
    var component: Calendar.Component { [.day, .weekOfYear, .month][rawValue] }
}

/// Il giorno, la settimana (da lunedì) o il mese che contiene `date`.
func listRange(_ scale: ListScale, around date: Date) -> (start: Date, end: Date) {
    let cal = Calendar.current
    switch scale {
    case .day:
        let s = cal.startOfDay(for: date)
        return (s, cal.date(byAdding: .day, value: 1, to: s) ?? s)
    case .week:
        return weekRange(date)
    case .month:
        let iv = cal.dateInterval(of: .month, for: date)
        return (iv?.start ?? date, iv?.end ?? date)
    }
}

/// Titolo del periodo: "Giovedì 15 ottobre", "12 – 18 ottobre", "Ottobre 2026".
func listTitle(_ scale: ListScale, around date: Date) -> String {
    let r = listRange(scale, around: date)
    let cal = Calendar.current
    switch scale {
    case .day:
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized
    case .week:
        let last = cal.date(byAdding: .day, value: -1, to: r.end) ?? r.end
        if cal.isDate(r.start, equalTo: last, toGranularity: .month) {
            return "\(r.start.formatted(.dateTime.day())) – \(last.formatted(.dateTime.day().month(.wide)))"
        }
        return "\(r.start.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated)))"
    case .month:
        return date.formatted(.dateTime.month(.wide).year()).capitalized
    }
}

/// "−18% della scorsa": confronto con la settimana scorsa allo stesso punto. nil se la settimana scorsa era vuota.
func weekCompareText(this: Double, last: Double) -> String? {
    guard last > 0.5 else { return nil }
    let d = Int(((this - last) / last * 100).rounded())
    if d == 0 { return "come la scorsa" }
    return "\(d > 0 ? "+" : "−")\(abs(d))% della scorsa"
}

struct MonthView: View {
    let onOpenDay: (Date) -> Void
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Expense.date, order: .reverse) private var all: [Expense]
    @Query private var incomes: [Income]
    @Query private var moves: [SavingsMove]
    @Query private var cashMoves: [CashMove]
    @Query private var accounts: [Account]
    @Query private var payments: [TripPayment]
    @Query(sort: \CategoryItem.order) private var cats: [CategoryItem]
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @AppStorage(limitPeriodOnKey) private var limitOn = false
    @AppStorage(limitStartKey) private var limitStart: Double = 0
    @AppStorage(limitEndKey) private var limitEnd: Double = 0
    @State private var month: Date          // il giorno da cui parte il periodo scelto
    @AppStorage(listScaleKey) private var scaleRaw = ListScale.month.rawValue
    @State private var mode = 0
    @State private var search = ""
    @State private var filterCat = ""
    @State private var filterMethod = ""
    @State private var editing: Expense?

    init(month: Date, onOpenDay: @escaping (Date) -> Void) {
        _month = State(initialValue: month)
        self.onOpenDay = onOpenDay
    }

    private let cal = Calendar.current
    private var scale: ListScale { ListScale(rawValue: scaleRaw) ?? .month }
    private var range: (start: Date, end: Date) { listRange(scale, around: month) }
    private var isCurrentMonth: Bool { cal.isDate(month, equalTo: Date(), toGranularity: .month) }
    private var isCurrent: Bool { Date() >= range.start && Date() < range.end }
    private var expenses: [Expense] {
        all.filter { $0.date >= range.start && $0.date < range.end && $0.date < Ledger.endOfToday }
    }
    private func shift(_ n: Int) {
        withAnimation { month = cal.date(byAdding: scale.component, value: n, to: month) ?? month }
    }
    private var statMonth: [Expense] { statExpenses(expenses, trips: trips) }
    private var total: Double { statMonth.reduce(0) { $0 + $1.myAmount } }
    private var fig: Figures {
        Ledger(incomes: incomes, expenses: all, moves: moves, cash: cashMoves, account: accounts.first, payments: payments).figures(for: month)
    }
    private func look(_ n: String) -> (icon: String, color: Color) {
        if let c = cats.first(where: { $0.name == n }) { return (c.icon, Color(hex: c.colorHex)) }
        return ("questionmark.circle", .gray)
    }
    private func matches(_ e: Expense) -> Bool {
        if !filterCat.isEmpty && e.categoryRaw != filterCat { return false }
        if !filterMethod.isEmpty && e.method != filterMethod { return false }
        if search.isEmpty { return true }
        return [e.note, e.categoryRaw, e.tag, eur(e.amount)].contains { $0.localizedCaseInsensitiveContains(search) }
    }
    /// Con la ricerca si cerca in tutti i mesi, come prima.
    private var shown: [Expense] { (search.isEmpty ? expenses : all).filter(matches) }
    private var byDay: [(day: Date, items: [Expense])] {
        Dictionary(grouping: shown) { cal.startOfDay(for: $0.date) }.map { (day: $0.key, items: $0.value) }.sorted { $0.day > $1.day }
    }
    private var byCat: [CatTotal] {
        Dictionary(grouping: statMonth, by: \.categoryRaw).map { name, list in
            let l = look(name)
            return CatTotal(name: name, icon: l.icon, color: l.color, total: list.reduce(0) { $0 + $1.myAmount })
        }.filter { $0.total > 0 }.sorted { $0.total > $1.total }
    }
    private var limited: [CategoryItem] { cats.filter { $0.limit > 0 } }
    private var period: (start: Date, end: Date)? {
        accounts.first.flatMap { payPeriod(day: $0.salaryDay, customStart: $0.periodStart, customEnd: $0.periodEnd) }
    }
    private var limitRange: (start: Date, end: Date)? {
        limitPeriod(on: limitOn,
                    customStart: limitStart > 0 ? Date(timeIntervalSinceReferenceDate: limitStart) : nil,
                    customEnd: limitEnd > 0 ? Date(timeIntervalSinceReferenceDate: limitEnd) : nil,
                    pay: period, month: month)
    }
    private func spent(_ c: CategoryItem) -> Double {
        guard let r = limitRange else { return 0 }
        return statExpenses(all, trips: trips).filter { $0.categoryRaw == c.name && $0.date >= r.start && $0.date < r.end }.reduce(0) { $0 + $1.myAmount }
    }
    private var limitsTitle: String {
        guard limitOn, let r = limitRange else { return "Limiti per categoria" }
        let last = cal.date(byAdding: .day, value: -1, to: r.end) ?? r.end
        return "Limiti dal \(r.start.formatted(.dateTime.day().month(.wide))) al \(last.formatted(.dateTime.day().month(.wide)))"
    }

    var body: some View {
        List {
            Section {
                Picker("Periodo", selection: $scaleRaw) {
                    ForEach(ListScale.allCases, id: \.rawValue) { Text($0.name).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                VStack(spacing: 2) {
                    HStack {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left").font(.headline) }
                            .accessibilityLabel("Prima")
                        Spacer()
                        Button { withAnimation { month = Date() } } label: {
                            Text(listTitle(scale, around: month)).font(.headline).foregroundStyle(.primary)
                        }
                        Spacer()
                        Button { shift(1) } label: { Image(systemName: "chevron.right").font(.headline) }
                            .accessibilityLabel("Dopo")
                    }
                    if !isCurrent {
                        Button { withAnimation { month = Date() } } label: { Text("Torna a oggi").font(.caption).foregroundStyle(Theme.accent) }
                    }
                }
                .buttonStyle(.borderless)
                Picker("Vista", selection: $mode) { Text("Elenco").tag(0); Text("Categorie").tag(1) }.pickerStyle(.segmented)
                summaryRow
                if scale == .week { weekBars }
            }
            .listRowSeparator(.hidden)

            if mode == 0 { listSections } else { categorySections }
        }
        .navigationTitle("Elenco spese").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Cerca spese")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Categoria", selection: $filterCat) {
                        Text("Tutte").tag("")
                        ForEach(cats) { c in Text(c.name).tag(c.name) }
                    }
                    Picker("Pagamento", selection: $filterMethod) {
                        Text("Tutti").tag(""); Text("Carta").tag("carta"); Text("Contanti").tag("contanti")
                    }
                } label: {
                    Image(systemName: filterCat.isEmpty && filterMethod.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
        }
        .sheet(item: $editing) { e in
            if let t = trips.first(where: { $0.uid == e.tripID }) { TripExpenseEditor(trip: t, editing: e) }
            else { AddExpenseView(defaultDate: e.date, editing: e) }
        }
    }

    /// Mese: entrate, spese e differenza. Giorno e settimana: speso, con carta e contanti.
    @ViewBuilder private var summaryRow: some View {
        HStack(spacing: 8) {
            if scale == .month {
                summary("Entrate", fig.incomeNet, Theme.accent)
                summary("Spese", total, .primary)
                summary("Differenza", fig.incomeNet - total, fig.incomeNet - total < 0 ? .red : .primary)
            } else {
                let cash = statMonth.filter(\.isCash).reduce(0) { $0 + $1.myAmount }
                summary("Speso", total, .primary)
                summary("Carta", total - cash, .primary)
                summary("Contanti", cash, .primary)
            }
        }
    }

    /// Settimana: una barretta per giorno. Tocchi un giorno per aprirlo.
    private var weekBars: some View {
        let days = weekDays(of: month)
        let stats = statMonth
        let values = days.map { d in stats.filter { cal.isDate($0.date, inSameDayAs: d) }.reduce(0) { $0 + $1.myAmount } }
        let top = max(values.max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                Button { onOpenDay(d) } label: {
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(d >= Ledger.endOfToday ? Color.secondary.opacity(0.15)
                                  : (cal.isDateInToday(d) ? Theme.accent : Theme.accent.opacity(0.45)))
                            .frame(height: max(3, 54 * values[i] / top))
                        Text(d.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(d.formatted(.dateTime.weekday(.wide).day()) + ", \(eur(values[i]))")
            }
        }
        .frame(height: 76, alignment: .bottom)
    }

    private func summary(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(eur(value)).font(.subheadline.bold()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyText: String {
        ["Nessuna spesa in questo giorno.", "Nessuna spesa in questa settimana.", "Nessuna spesa in questo mese."][scale.rawValue]
    }

    @ViewBuilder private var listSections: some View {
        if byDay.isEmpty {
            Section { Text(search.isEmpty ? emptyText : "Nessuna spesa trovata.").foregroundStyle(.secondary) }
        }
        ForEach(byDay, id: \.day) { g in
            Section {
                ForEach(g.items) { e in
                    Button { editing = e } label: {
                        ExpenseRow(expense: e, look: look(e.categoryRaw), trip: trips.first { $0.uid == e.tripID },
                                   detail: e.categoryRaw + (e.isCash ? " · contanti" : "") + (e.planProvider.isEmpty ? "" : " · \(e.planProvider)"))
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { idx in idx.map { g.items[$0] }.forEach { deleteExpense($0, ctx: ctx) } }
            } header: {
                Button { onOpenDay(g.day) } label: {
                    HStack {
                        Text(g.day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)).capitalized)
                        Spacer()
                        Text(eur(g.items.reduce(0) { $0 + $1.amount }))
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                }
                .accessibilityHint("Apri la pagina del giorno")
            }
        }
    }

    @ViewBuilder private var categorySections: some View {
        if byCat.isEmpty {
            Section { Text(emptyText).foregroundStyle(.secondary) }
        } else {
            Section {
                ZStack {
                    Chart(byCat) { i in
                        SectorMark(angle: .value("Totale", i.total), innerRadius: .ratio(0.64), outerRadius: .ratio(0.86), angularInset: 1.5)
                            .foregroundStyle(i.color.opacity(0.14))
                    }
                    Chart(byCat) { i in
                        SectorMark(angle: .value("Totale", i.total), innerRadius: .ratio(0.80), angularInset: 1.5)
                            .foregroundStyle(i.color).cornerRadius(6)
                    }
                    Text(eur(total)).font(.system(size: 28, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6).frame(maxWidth: 140)
                }
                .frame(height: 220).padding(.vertical, 8)
                ForEach(byCat) { i in
                    let share = total > 0 ? i.total / total : 0
                    let row = HStack(spacing: 12) {
                        Image(systemName: i.icon).font(.body).foregroundStyle(i.color)
                            .frame(width: 38, height: 38)
                            .background(i.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                        Text(i.name).foregroundStyle(i.color).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 6)
                        Text(eur(i.total)).lineLimit(1)
                        Text("\(Int((share * 100).rounded()))%").font(.footnote).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                    }
                    // La pagina della categoria è per mese: dal giorno o dalla settimana si vede solo il totale.
                    if scale == .month {
                        NavigationLink { CategoryExpensesView(category: i.name, month: month) } label: { row }
                    } else {
                        row
                    }
                    if i.name == installmentCategory {
                        ForEach(installmentProviderTotals(statMonth), id: \.name) { p in
                            HStack(spacing: 8) {
                                ProviderLogo(provider: p.name, size: 22)
                                Text(p.name).font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                                Text(eur(p.total)).font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(.leading, 50)
                        }
                    }
                }
            }
        }
        if scale == .month && !limited.isEmpty && (!limitOn || isCurrentMonth) {
            Section(limitsTitle) {
                ForEach(limited) { c in
                    let s = spent(c)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(c.name, systemImage: c.icon).foregroundStyle(Color(hex: c.colorHex))
                            Spacer()
                            Text("\(eur(s)) di \(eur(c.limit))").font(.footnote).foregroundStyle(s >= c.limit ? Color.red : Color.secondary)
                        }
                        ProgressView(value: min(s, c.limit), total: c.limit).tint(s >= c.limit ? Color.red : Color(hex: c.colorHex))
                    }
                }
            }
        }
    }
}
