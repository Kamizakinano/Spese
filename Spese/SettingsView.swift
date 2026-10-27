import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var ctx
    @AppStorage("theme") private var theme = 0
    @AppStorage(appColorKey) private var appColor = AppColor.verde.rawValue
    @AppStorage("reminderOn") private var reminderOn = false
    @AppStorage("reminderHour") private var reminderHour = 21
    @AppStorage(budgetAlertKey) private var budgetAlert = false
    @AppStorage(weeklySummaryKey) private var weeklySummary = false
    @AppStorage(eveningCheckKey) private var eveningCheck = false
    @AppStorage(eveningCheckHourKey) private var eveningCheckHour = 21
    @AppStorage(cashCheckOnKey) private var cashCheckOn = true
    @AppStorage(yearRecapKey) private var yearRecapOn = false
    @AppStorage(spendMapKey) private var spendMapOn = false
    @State private var backupURL: URL?
    @State private var importing = false
    @State private var confirmRestore = false
    @State private var pickedURL: URL?
    @State private var message = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Aspetto") {
                    Picker("Tema", selection: $theme) {
                        Text("Sistema").tag(0); Text("Chiaro").tag(1); Text("Scuro").tag(2)
                    }.pickerStyle(.segmented)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Colore dell'app")
                        HStack(spacing: 0) {
                            ForEach(AppColor.allCases) { c in
                                Button { appColor = c.rawValue } label: {
                                    VStack(spacing: 4) {
                                        Circle().fill(c.swatch).frame(width: 34, height: 34)
                                            .overlay {
                                                if appColor == c.rawValue {
                                                    Image(systemName: "checkmark").font(.footnote.bold()).foregroundStyle(.white)
                                                }
                                            }
                                            .overlay(Circle().strokeBorder(Color.primary.opacity(appColor == c.rawValue ? 0.35 : 0), lineWidth: 2).padding(-4))
                                        Text(c.name).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(c.name)
                                .accessibilityAddTraits(appColor == c.rawValue ? .isSelected : [])
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Personalizza") {
                    NavigationLink { SalaryView() } label: { Label("Stipendio e risparmi", systemImage: "eurosign.circle") }
                    NavigationLink { CategoriesView() } label: { Label("Categorie e limiti", systemImage: "square.grid.2x2") }
                    NavigationLink { RecurringView() } label: { Label("Spese ricorrenti", systemImage: "repeat") }
                    NavigationLink { SubscriptionsView() } label: { Label("Abbonamenti", systemImage: "play.rectangle.on.rectangle") }
                    NavigationLink { TripsView() } label: { Label("Viaggi", systemImage: "airplane") }
                    NavigationLink { TagsView() } label: { Label("Tag", systemImage: "tag") }
                    NavigationLink { OwedView() } label: { Label("Ti devono", systemImage: "person.2") }
                    NavigationLink { DebtsView() } label: { Label("Devo dare", systemImage: "person.crop.circle.badge.minus") }
                    NavigationLink { CardLinkView() } label: { Label("Collega la carta (Apple Pay)", systemImage: "creditcard.and.123") }
                }
                Section {
                    Toggle(isOn: $yearRecapOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Il tuo anno in Spese")
                            Text("Il riassunto dell'anno, in Statistiche e a fine dicembre in Home").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $spendMapOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mappa delle spese")
                            Text("Ricorda dove fai le spese inserite nell'app").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Funzioni")
                } footer: {
                    if spendMapOn { Text("La posizione si usa solo quando inserisci una spesa e resta sul telefono. Le spese di prima non hanno il luogo.") }
                }
                Section("Sicurezza e promemoria") {
                    LockToggle()
                    Toggle("Promemoria giornaliero", isOn: $reminderOn)
                    if reminderOn { Stepper("Ora: \(reminderHour):00", value: $reminderHour, in: 6...23) }
                }
                Section("Dati") {
                    NavigationLink { AutoBackupView() } label: { Label("Backup automatico", systemImage: "icloud.and.arrow.up") }
                    NavigationLink { ExportView() } label: { Label("Esporta (Excel, CSV, PDF)", systemImage: "square.and.arrow.up") }
                    if let u = backupURL { ShareLink(item: u) { Label("Salva un backup", systemImage: "externaldrive") } }
                    Button { importing = true } label: { Label("Ripristina da backup", systemImage: "arrow.counterclockwise") }
                    if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    HStack {
                        Text("Versione")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Toggle(isOn: $budgetAlert) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Avviso la sera")
                            Text("Alle 21, solo se oggi hai superato il budget giornaliero").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $eveningCheck) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Controllo di stasera")
                            Text("Ogni sera le spese di oggi, per aggiungere quelle che mancano").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if eveningCheck {
                        Picker("Ora del controllo", selection: $eveningCheckHour) {
                            ForEach(18..<24, id: \.self) { Text("\($0):00").tag($0) }
                        }
                    }
                    Toggle(isOn: $weeklySummary) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Riepilogo della domenica")
                            Text("Alle 19: quanto hai speso nella settimana").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $cashCheckOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Controllo contanti")
                            Text("La domenica alle 10: quanti contanti hai nel portafoglio").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Notifiche")
                } footer: {
                    Text("Avvisi anche quando raggiungi l'80% e il 100% del disponibile e dei limiti per categoria.")
                }
            }
            .navigationTitle("Altro")
            .onAppear { backupURL = makeBackup(ctx) }
            .onChange(of: reminderOn) { _, v in scheduleReminder(on: v, hour: reminderHour) }
            .onChange(of: budgetAlert) { _, _ in scheduleSmartNotifications(ctx) }
            .onChange(of: weeklySummary) { _, _ in scheduleSmartNotifications(ctx) }
            .onChange(of: eveningCheck) { _, _ in scheduleSmartNotifications(ctx) }
            .onChange(of: eveningCheckHour) { _, _ in scheduleSmartNotifications(ctx) }
            .onChange(of: cashCheckOn) { _, _ in scheduleSmartNotifications(ctx) }
            .onChange(of: spendMapOn) { _, on in if on { SpendLocation.shared.requestPermission() } }
            .onChange(of: reminderHour) { _, h in if reminderOn { scheduleReminder(on: true, hour: h) } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { r in
                if case .success(let u) = r { pickedURL = u; confirmRestore = true }
            }
            .confirmationDialog("Il ripristino sostituisce tutti i dati attuali.", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("Ripristina", role: .destructive) {
                    if let u = pickedURL { message = restoreBackup(ctx, from: u) ? "Backup ripristinato." : "File non valido." }
                }
                Button("Annulla", role: .cancel) {}
            }
        }
    }
}

struct CategoriesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \CategoryItem.order) private var cats: [CategoryItem]
    @Query private var accounts: [Account]
    @State private var editing: CategoryItem?
    @State private var adding = false
    @AppStorage(limitPeriodOnKey) private var limitOn = false
    @AppStorage(limitStartKey) private var limitStart: Double = 0
    @AppStorage(limitEndKey) private var limitEnd: Double = 0

    private let cal = Calendar.current
    private var pay: (start: Date, end: Date)? {
        accounts.first.flatMap { payPeriod(day: $0.salaryDay, customStart: $0.periodStart, customEnd: $0.periodEnd) }
    }
    /// "Dal": primo giorno del periodo.
    private var fromDate: Binding<Date> {
        Binding(get: { limitStart > 0 ? Date(timeIntervalSinceReferenceDate: limitStart) : cal.startOfDay(for: Date()) },
                set: { v in
                    limitStart = cal.startOfDay(for: v).timeIntervalSinceReferenceDate
                    if limitEnd <= limitStart { limitEnd = (cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: v)) ?? v).timeIntervalSinceReferenceDate }
                })
    }
    /// "Al": ultimo giorno incluso (si salva il giorno dopo).
    private var toDate: Binding<Date> {
        Binding(get: {
                    let end = limitEnd > 0 ? Date(timeIntervalSinceReferenceDate: limitEnd) : Date()
                    return cal.date(byAdding: .day, value: -1, to: end) ?? end
                },
                set: { v in limitEnd = (cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: v)) ?? v).timeIntervalSinceReferenceDate })
    }
    private func useSalaryPeriod() {
        guard let p = pay else { return }
        limitStart = p.start.timeIntervalSinceReferenceDate
        limitEnd = p.end.timeIntervalSinceReferenceDate
    }

    var body: some View {
        List {
            Section {
                Toggle("Limiti su un periodo scelto da me", isOn: $limitOn)
                    .onChange(of: limitOn) { _, on in if on && limitEnd <= Date().timeIntervalSinceReferenceDate { useSalaryPeriod() } }
                if limitOn {
                    DatePicker("Dal", selection: fromDate, displayedComponents: .date)
                    DatePicker("Al", selection: toDate, in: fromDate.wrappedValue..., displayedComponents: .date)
                    Button("Usa il periodo dello stipendio") { useSalaryPeriod() }
                }
            } header: {
                Text("Periodo dei limiti")
            } footer: {
                Text(limitOn
                     ? "I limiti si contano dal giorno \"Dal\" al giorno \"Al\" compresi. Finito questo periodo seguono da soli il periodo dello stipendio, finché non scegli nuove date."
                     : "Spento: i limiti si contano sul mese di calendario, dal primo all'ultimo giorno.")
            }
            Section("Categorie") {
                ForEach(cats) { c in
                    Button { editing = c } label: {
                        Label { Text(c.name).foregroundStyle(.primary) }
                        icon: { Image(systemName: c.icon).foregroundStyle(Color(hex: c.colorHex)) }
                    }
                }.onDelete { i in i.map { cats[$0] }.forEach(ctx.delete) }
            }
        }
        .navigationTitle("Categorie e limiti")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(item: $editing) { CategoryEditor(cat: $0, count: cats.count) }
        .sheet(isPresented: $adding) { CategoryEditor(cat: nil, count: cats.count) }
    }
}

struct CategoryEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let cat: CategoryItem?
    let count: Int
    @State private var name = ""
    @State private var icon = "cart"
    @State private var color = Color.green
    @State private var limitText = ""
    private let icons = ["cart", "fork.knife", "cup.and.saucer", "airplane", "car", "bus", "house", "bolt",
                         "cross.case", "pills", "popcorn", "gamecontroller", "bag", "tshirt", "gift", "book",
                         "graduationcap", "pawprint", "dumbbell", "wifi", "phone", "fuelpump", "heart", "star", "ellipsis.circle"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome", text: $name)
                ColorPicker("Colore", selection: $color, supportsOpacity: false)
                TextField("Limite mensile (€, facoltativo)", text: $limitText).keyboardType(.decimalPad)
                Section("Icona") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(icons, id: \.self) { s in
                            Image(systemName: s).font(.title2).foregroundStyle(color)
                                .frame(width: 46, height: 46)
                                .background(icon == s ? color.opacity(0.25) : Color.clear, in: Circle())
                                .onTapGesture { icon = s }
                        }
                    }
                }
            }
            .navigationTitle(cat == nil ? "Nuova categoria" : "Modifica categoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") { save() } }
            }
            .onAppear {
                if let c = cat { name = c.name; icon = c.icon; color = Color(hex: c.colorHex); limitText = c.limit > 0 ? String(c.limit) : "" }
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        if let c = cat {
            let old = c.name
            if old != n {
                let ex = (try? ctx.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.categoryRaw == old }))) ?? []
                ex.forEach { $0.categoryRaw = n }
                let rc = (try? ctx.fetch(FetchDescriptor<Recurring>(predicate: #Predicate { $0.categoryName == old }))) ?? []
                rc.forEach { $0.categoryName = n }
                renameLearnedCategory(from: old, to: n)
            }
            c.name = n; c.icon = icon; c.colorHex = color.hex; c.limit = parseAmount(limitText) ?? 0
        } else {
            let ci = CategoryItem(name: n, icon: icon, colorHex: color.hex, order: count)
            ci.limit = parseAmount(limitText) ?? 0
            ctx.insert(ci)
        }
        dismiss()
    }
}

struct RecurringView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var items: [Recurring]
    @State private var adding = false
    @State private var editing: Recurring?

    var body: some View {
        List {
            if items.isEmpty {
                Text("Nessuna spesa ricorrente. Aggiungi affitto, abbonamenti, ecc.: verranno inserite da sole ogni mese.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(items) { r in
                Button { editing = r } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(r.name).foregroundStyle(.primary)
                            Text("\(r.categoryName) · il giorno \(r.day) di ogni mese\(r.isSubscription ? " · abbonamento" : "")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(eur(r.amount)).bold().foregroundStyle(.primary)
                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                    }
                }
            }.onDelete { i in i.map { items[$0] }.forEach(ctx.delete) }
            if !items.isEmpty {
                Section {
                    HStack { Text("Totale al mese"); Spacer(); Text(eur(items.reduce(0) { $0 + $1.amount })).bold() }
                } footer: {
                    Text("Tocca una spesa per modificarla. Scorri a sinistra per cancellarla.")
                }
            }
        }
        .navigationTitle("Spese ricorrenti")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $adding) { RecurringEditor() }
        .sheet(item: $editing) { r in RecurringEditor(editing: r) }
    }
}

struct RecurringEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryItem.order) private var cats: [CategoryItem]
    @State private var name = ""
    @State private var amountText = ""
    @State private var catName = ""
    @State private var day = 1
    /// Aperto da Abbonamenti: l'interruttore "È un abbonamento" parte acceso.
    var asSubscription = false
    /// La ricorrente da modificare (nil = nuova).
    var editing: Recurring? = nil
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var isSub = false
    @State private var confirmDelete = false

    /// Le ultime volte che è stata inserita (stesso nome).
    private var history: [Expense] {
        guard let r = editing else { return [] }
        return Array(expenses.filter { $0.note == r.name && $0.date < Ledger.endOfToday }.prefix(4))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome (es. Affitto, Netflix)", text: $name)
                TextField("Importo (€)", text: $amountText).keyboardType(.decimalPad)
                Picker("Categoria", selection: $catName) {
                    ForEach(cats) { c in Label(c.name, systemImage: c.icon).tag(c.name) }
                }
                Stepper("Giorno del mese: \(day)", value: $day, in: 1...31)
                Toggle("È un abbonamento", isOn: $isSub)
                if let r = editing {
                    Section {
                        if let next = nextRenewal(nextKey: r.nextKey, day: day) {
                            HStack {
                                Text(next.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                                Spacer()
                                Text(eur(parseAmount(amountText) ?? r.amount)).bold()
                            }
                        }
                    } header: { Text("Prossima volta") } footer: {
                        Text("Le spese già inserite nei mesi passati non cambiano: la modifica vale dalla prossima.")
                    }
                    if !history.isEmpty {
                        Section("Ultime volte") {
                            ForEach(history) { e in
                                HStack { Text(e.date.formatted(.dateTime.day().month(.wide))); Spacer(); Text(eur(e.amount)) }
                            }
                        }
                    }
                    Section {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Text(r.isSubscription ? "Elimina abbonamento" : "Elimina spesa ricorrente").frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .confirmationDialog("Eliminare \(editing?.name ?? "")? Non verrà più aggiunta ogni mese.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Elimina", role: .destructive) {
                    if let r = editing { ctx.delete(r); try? ctx.save(); Task { await scheduleSubscriptionReminders(ctx) } }
                    dismiss()
                }
            }
            .navigationTitle(editing != nil ? (isSub ? "Modifica abbonamento" : "Modifica ricorrente")
                             : (asSubscription ? "Nuovo abbonamento" : "Nuova ricorrente"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty, let a = parseAmount(amountText), a > 0 else { return }
                        if let r = editing {
                            r.name = n; r.amount = a; r.categoryName = catName; r.day = day; r.isSubscription = isSub
                        } else {
                            let r = Recurring(name: n, amount: a, categoryName: catName, day: day, nextKey: monthKey(Date()))
                            r.isSubscription = isSub
                            ctx.insert(r)
                        }
                        try? ctx.save()
                        Task { await scheduleSubscriptionReminders(ctx) }
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let r = editing {
                    name = r.name
                    amountText = String(format: "%.2f", r.amount).replacingOccurrences(of: ".", with: ",")
                    catName = r.categoryName; day = r.day; isSub = r.isSubscription
                } else {
                    if catName.isEmpty { catName = cats.first?.name ?? "Altro" }
                    isSub = asSubscription
                }
            }
        }
    }
}

// MARK: - Backup automatico

struct AutoBackupView: View {
    @Environment(\.modelContext) private var ctx
    @State private var folder: URL? = autoBackupFolder()
    @State private var last = UserDefaults.standard.object(forKey: autoBackupLastKey) as? Date
    @State private var picking = false
    @State private var message = ""

    var body: some View {
        List {
            Section {
                Text("Scegli una cartella in iCloud Drive: ogni 12 ore l'app ci salva da sola una copia di tutti i dati, quando la apri o quando registra un pagamento da Comandi rapidi. Così non perdi niente anche se cancelli l'app o cambi iPhone. Vengono tenuti gli ultimi 14 backup (circa una settimana).")
                    .font(.subheadline)
            }
            if let folder {
                Section("Attivo") {
                    HStack { Text("Cartella"); Spacer(); Text(folder.lastPathComponent).foregroundStyle(.secondary) }
                    HStack {
                        Text("Ultimo backup"); Spacer()
                        Text(last.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "mai").foregroundStyle(.secondary)
                    }
                    Button { backupNow() } label: { Label("Fai il backup adesso", systemImage: "arrow.clockwise") }
                    Button { picking = true } label: { Label("Cambia cartella", systemImage: "folder") }
                    Button("Disattiva il backup automatico", role: .destructive) {
                        UserDefaults.standard.removeObject(forKey: autoBackupFolderKey)
                        self.folder = nil; message = ""
                    }
                }
            } else {
                Section {
                    Button { picking = true } label: { Label("Scegli la cartella e attiva", systemImage: "folder.badge.plus").bold() }
                }
            }
            if !message.isEmpty { Section { Text(message).font(.footnote).foregroundStyle(.secondary) } }
            Section {
                Text("Per ripristinare: Altro → Ripristina da backup, poi scegli il file Spese-backup con la data più recente.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Backup automatico")
        // La data si rilegge ogni volta che si apre la pagina, così mostra sempre l'ultimo backup vero.
        .onAppear {
            folder = autoBackupFolder()
            last = UserDefaults.standard.object(forKey: autoBackupLastKey) as? Date
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { r in
            guard case .success(let url) = r else { return }
            if setAutoBackupFolder(url) {
                folder = autoBackupFolder()
                backupNow()
            } else {
                message = "Non riesco a usare questa cartella. Prova a sceglierne un'altra."
            }
        }
    }

    private func backupNow() {
        if let err = runAutoBackup(ctx, force: true) {
            message = err
        } else {
            last = UserDefaults.standard.object(forKey: autoBackupLastKey) as? Date
            message = "Backup salvato."
        }
    }
}
