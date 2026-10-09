import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var ctx
    @AppStorage("theme") private var theme = 0
    @AppStorage("reminderOn") private var reminderOn = false
    @AppStorage("reminderHour") private var reminderHour = 21
    @State private var csvURL: URL?
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
                }
                Section("Personalizza") {
                    NavigationLink { SalaryView() } label: { Label("Stipendio e risparmi", systemImage: "eurosign.circle") }
                    NavigationLink { CategoriesView() } label: { Label("Categorie e limiti", systemImage: "square.grid.2x2") }
                    NavigationLink { RecurringView() } label: { Label("Spese ricorrenti", systemImage: "repeat") }
                    NavigationLink { TripsView() } label: { Label("Viaggi", systemImage: "airplane") }
                    NavigationLink { TagsView() } label: { Label("Tag", systemImage: "tag") }
                    NavigationLink { OwedView() } label: { Label("Ti devono", systemImage: "person.2") }
                    NavigationLink { CardLinkView() } label: { Label("Collega la carta (Apple Pay)", systemImage: "creditcard.and.123") }
                }
                Section("Sicurezza e promemoria") {
                    LockToggle()
                    Toggle("Promemoria giornaliero", isOn: $reminderOn)
                    if reminderOn { Stepper("Ora: \(reminderHour):00", value: $reminderHour, in: 6...23) }
                }
                Section("Dati") {
                    NavigationLink { AutoBackupView() } label: { Label("Backup automatico", systemImage: "icloud.and.arrow.up") }
                    if let u = csvURL { ShareLink(item: u) { Label("Esporta in CSV (Excel)", systemImage: "tablecells") } }
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
                Section("Notifiche") {
                    Text("Avvisi quando raggiungi l'80% e il 100% del disponibile e dei limiti per categoria.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Altro")
            .onAppear { csvURL = makeCSV(ctx); backupURL = makeBackup(ctx) }
            .onChange(of: reminderOn) { _, v in scheduleReminder(on: v, hour: reminderHour) }
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

    var body: some View {
        List {
            if items.isEmpty {
                Text("Nessuna spesa ricorrente. Aggiungi affitto, abbonamenti, ecc.: verranno inserite da sole ogni mese.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(items) { r in
                HStack {
                    VStack(alignment: .leading) {
                        Text(r.name)
                        Text("\(r.categoryName) · il giorno \(r.day) di ogni mese").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(eur(r.amount)).bold()
                }
            }.onDelete { i in i.map { items[$0] }.forEach(ctx.delete) }
        }
        .navigationTitle("Spese ricorrenti")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $adding) { RecurringEditor() }
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

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome (es. Affitto, Netflix)", text: $name)
                TextField("Importo (€)", text: $amountText).keyboardType(.decimalPad)
                Picker("Categoria", selection: $catName) {
                    ForEach(cats) { c in Label(c.name, systemImage: c.icon).tag(c.name) }
                }
                Stepper("Giorno del mese: \(day)", value: $day, in: 1...31)
            }
            .navigationTitle("Nuova ricorrente").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty, let a = parseAmount(amountText), a > 0 else { return }
                        ctx.insert(Recurring(name: n, amount: a, categoryName: catName, day: day, nextKey: monthKey(Date())))
                        dismiss()
                    }
                }
            }
            .onAppear { if catName.isEmpty { catName = cats.first?.name ?? "Altro" } }
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
                Text("Scegli una cartella in iCloud Drive: una volta a settimana l'app ci salva da sola una copia di tutti i dati. Così non perdi niente anche se cancelli l'app o cambi iPhone. Vengono tenuti gli ultimi 8 backup.")
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
