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
    @AppStorage(appColorKey) private var appColor = AppColor.verde.rawValue
    @State private var tab = 0
    @State private var locked = true
    @ObservedObject private var quick = QuickAddRouter.shared

    /// La spesa veloce si apre solo con l'app sbloccata e già configurata.
    private var quickShown: Binding<Bool> {
        Binding(get: { quick.show && !accounts.isEmpty && !(lockOn && locked) }, set: { quick.show = $0 })
    }

    var body: some View {
        Group {
            if accounts.isEmpty {
                SetupView()
            } else {
                TabView(selection: $tab) {
                    HomeView().tabItem { Label("Spese", systemImage: "calendar") }.tag(0)
                    ContiView().tabItem { Label("Conti", systemImage: "creditcard") }.tag(1)
                    SavingsView().tabItem { Label("Risparmi", systemImage: "banknote") }.tag(2)
                    StatsView().tabItem { Label("Statistiche", systemImage: "chart.xyaxis.line") }.tag(3)
                    SettingsView().tabItem { Label("Altro", systemImage: "gearshape") }.tag(4)
                }
                // Cambiando colore si ridisegna tutta l'app, restando nella stessa scheda.
                .id(appColor)
            }
        }
        .task {
            if lockOn { authenticate() } else { locked = false }
            seed()
            generateAll()
            applyDailySavings(ctx)
            if UserDefaults.standard.object(forKey: cashCheckLastKey) == nil { UserDefaults.standard.set(Date(), forKey: cashCheckLastKey) }
            if !accounts.isEmpty { runAutoBackup(ctx) }
            updateWidgetSnapshot(ctx)
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await scheduleSubscriptionReminders(ctx)
            await scheduleUpcomingReminders(ctx)
        }
        .onOpenURL { url in if url.host == quickAddURL.host { quick.show = true } }
        .sheet(isPresented: quickShown) { QuickAddView() }
        .overlay { if lockOn && locked { LockView(unlock: authenticate) } }
        .onChange(of: phase) { _, p in
            if p == .active {
                generateAll()
                applyDailySavings(ctx)
                if !accounts.isEmpty { runAutoBackup(ctx) }
                if lockOn && locked { authenticate() }
                updateWidgetSnapshot(ctx)
                Task { await scheduleSubscriptionReminders(ctx); await scheduleUpcomingReminders(ctx) }
            }
            if p == .background {
                try? ctx.save()   // non perdere le ultime modifiche se l'app viene chiusa
                updateWidgetSnapshot(ctx)
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
        let existing = (try? ctx.fetch(FetchDescriptor<CategoryItem>())) ?? []
        if existing.isEmpty {
            for (i, c) in defaultCategories.enumerated() {
                ctx.insert(CategoryItem(name: c.0, icon: c.1, colorHex: c.2, order: i))
            }
        } else {
            // Chi aveva già le categorie riceve quelle nuove prima di "Altro".
            var orders = existing.map(\.order)
            for (name, key) in [(giftCardCategory, giftCardAddedKey), (installmentCategory, installmentAddedKey)]
            where !UserDefaults.standard.bool(forKey: key) && !existing.contains(where: { $0.name == name }) {
                guard let c = defaultCategories.first(where: { $0.0 == name }) else { continue }
                let other = existing.first { $0.name == "Altro" }
                let order = other?.order ?? ((orders.max() ?? 0) + 1)
                if let other { other.order += 1 }
                orders.append(order)
                ctx.insert(CategoryItem(name: c.0, icon: c.1, colorHex: c.2, order: order))
            }
        }
        UserDefaults.standard.set(true, forKey: giftCardAddedKey)
        UserDefaults.standard.set(true, forKey: installmentAddedKey)
    }

    private func generateAll() {
        let expenses = (try? ctx.fetch(FetchDescriptor<Expense>())) ?? []
        for r in (try? ctx.fetch(FetchDescriptor<Recurring>())) ?? [] {
            let due = dueDates(from: r.nextKey, day: r.day)
            // Se la spesa c'è già (inserita a mano lo stesso giorno) non se ne aggiunge un'altra.
            for d in due.dates where !recurringCovered(name: r.name, on: d, expenses: expenses) {
                ctx.insert(Expense(amount: r.amount, categoryName: r.categoryName, date: d, note: r.name))
            }
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

/// Sotto un movimento pagato anche per altri: chi deve quanto, e la conferma quando è restituito.
struct OwedBadge: View {
    let expense: Expense

    var body: some View {
        let who = expense.owedBy.isEmpty ? "Qualcuno" : expense.owedBy
        if expense.settled {
            let how = expense.settledMethod == "contanti" ? " in contanti" : expense.settledMethod == "carta" ? " sul conto" : ""
            Label("\(who) ha restituito \(eur(expense.owedAmount))\(how)", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent).lineLimit(1)
        } else {
            Label("\(who) ti deve \(eur(expense.owedAmount))", systemImage: "person.crop.circle.badge.clock")
                .font(.caption.weight(.semibold)).foregroundStyle(.orange).lineLimit(1)
        }
    }
}

/// Colori del riquadro in cima alla Home.
enum HeroStyle {
    static var top: Color { Theme.color.top }
    static var bottom: Color { Theme.color.bottom }
    static var mint: Color { Theme.color.light }
    static let coral = Color(hex: "E8735F")
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
