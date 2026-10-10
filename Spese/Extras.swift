import SwiftUI
import SwiftData
import PhotosUI
import Vision
import VisionKit
import LocalAuthentication
import UserNotifications
import UIKit

// MARK: - Nuova spesa / modifica

struct AddExpenseView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryItem.order) private var cats: [CategoryItem]
    @Query private var all: [Expense]
    let defaultDate: Date
    var editing: Expense? = nil

    @State private var amountText = ""
    @AppStorage("lastMethod") private var lastMethod = "carta"
    @State private var method = "carta"
    @State private var catName = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var tag = ""
    @State private var shared = false
    @State private var owedBy = ""
    @State private var owedText = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showScanner = false
    @State private var scanMessage = ""
    @FocusState private var focus: Bool

    private var knownTags: [String] { Array(Set(all.map(\.tag).filter { !$0.isEmpty })).sorted() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Importo (€)", text: $amountText).keyboardType(.decimalPad).focused($focus)
                    Picker("Categoria", selection: $catName) {
                        ForEach(cats) { c in Label(c.name, systemImage: c.icon).tag(c.name) }
                    }
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                    TextField("Nota (facoltativa)", text: $note)
                }
                Section("Pagamento") {
                    Picker("Pagato con", selection: $method) {
                        Text("Carta").tag("carta")
                        Text("Contanti").tag("contanti")
                    }.pickerStyle(.segmented)
                }
                Section("Viaggio o tag") {
                    TextField("Tag (es. Roma 2026)", text: $tag)
                    if !knownTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack { ForEach(knownTags, id: \.self) { t in Button(t) { tag = t }.buttonStyle(.bordered) } }
                        }
                    }
                }
                Section("Spesa condivisa") {
                    Toggle("Ho pagato anche per altri", isOn: $shared)
                    if shared {
                        TextField("Chi ti deve i soldi", text: $owedBy)
                        TextField("Quanto ti deve (€)", text: $owedText).keyboardType(.decimalPad)
                    }
                }
                if editing == nil {
                    Section("Scontrino") {
                        Button { showScanner = true } label: { Label("Fotografa lo scontrino", systemImage: "camera") }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Scegli dalla libreria", systemImage: "photo")
                        }
                        if !scanMessage.isEmpty { Text(scanMessage).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Nuova spesa" : "Modifica spesa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") { save() } }
            }
            .onAppear(perform: load)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) { await scan([img]) }
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScanner { imgs in Task { await scan(imgs) } }.ignoresSafeArea()
            }
        }
        .presentationDetents([.large])
    }

    private func load() {
        if let e = editing {
            amountText = e.needsAmount ? "" : String(e.amount); catName = e.categoryRaw; date = e.date; note = e.note; tag = e.tag
            shared = e.owedAmount > 0; owedBy = e.owedBy; owedText = e.owedAmount > 0 ? String(e.owedAmount) : ""
            method = e.method
        } else {
            date = defaultDate
            method = lastMethod
            if catName.isEmpty { catName = cats.first?.name ?? "Altro" }
            focus = true
        }
    }

    private func scan(_ images: [UIImage]) async {
        scanMessage = "Leggo lo scontrino…"
        let found: Double? = await Task.detached { readReceiptAmount(images) }.value
        if let v = found {
            amountText = String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",")
            scanMessage = "Importo trovato: \(eur(v)). Controllalo prima di salvare."
        } else {
            scanMessage = "Non ho trovato un importo. Scrivilo a mano."
        }
    }

    private func save() {
        guard let a = parseAmount(amountText), a > 0 else { return }
        let t = tag.trimmingCharacters(in: .whitespaces)
        let owed = shared ? min(parseAmount(owedText) ?? 0, a) : 0
        let by = shared ? owedBy.trimmingCharacters(in: .whitespaces) : ""
        if let e = editing {
            // Se la categoria viene corretta, l'app la ricorda per questo esercente.
            if e.categoryRaw != catName { learnCategory(merchant: note, category: catName) }
            e.amount = a; e.categoryRaw = catName; e.date = date; e.note = note; e.tag = t
            e.owedAmount = owed; e.owedBy = by; e.method = method
            e.needsAmount = false
            if owed == 0 { e.settled = false }
        } else {
            let e = Expense(amount: a, categoryName: catName, date: date, note: note)
            e.tag = t; e.owedAmount = owed; e.owedBy = by; e.method = method
            ctx.insert(e)
        }
        lastMethod = method
        dismiss()
    }
}

// MARK: - Lettura scontrino

func readReceiptAmount(_ images: [UIImage]) -> Double? {
    var lines: [String] = []
    for img in images {
        guard let cg = img.cgImage else { continue }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.recognitionLanguages = ["it-IT", "en-US"]
        try? VNImageRequestHandler(cgImage: cg).perform([req])
        lines += (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
    guard let rx = try? NSRegularExpression(pattern: #"\d{1,6}[.,]\d{2}"#) else { return nil }
    func nums(_ s: String) -> [Double] {
        rx.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
            Range(m.range, in: s).flatMap { parseAmount(String(s[$0])) }
        }
    }
    let keys = ["totale", "total", "importo", "da pagare", "pagato"]
    var keyed: [Double] = []
    for (i, l) in lines.enumerated() where keys.contains(where: { l.localizedCaseInsensitiveContains($0) }) {
        keyed += nums(l)
        if i + 1 < lines.count { keyed += nums(lines[i + 1]) }
    }
    return keyed.max() ?? lines.flatMap(nums).max()
}

struct DocumentScanner: UIViewControllerRepresentable {
    let onDone: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let v = VNDocumentCameraViewController()
        v.delegate = context.coordinator
        return v
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ p: DocumentScanner) { parent = p }
        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            parent.onDone((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
            parent.dismiss()
        }
        func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) { parent.dismiss() }
        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFailWithError error: Error) { parent.dismiss() }
    }
}

// MARK: - Soldi da farsi restituire

struct OwedView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Expense.date, order: .reverse) private var all: [Expense]
    @State private var settling: Expense?

    private var open: [Expense] { all.filter { $0.owedAmount > 0 && !$0.settled } }
    private var closed: [Expense] { all.filter { $0.owedAmount > 0 && $0.settled } }

    private func row(_ e: Expense, done: Bool) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(e.owedBy.isEmpty ? "Qualcuno" : e.owedBy)
                Text("\(e.note.isEmpty ? e.categoryRaw : e.note) · \(e.date.formatted(.dateTime.day().month(.abbreviated)))\(done ? howText(e.settledMethod) : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(eur(e.owedAmount)).bold()
            if !done {
                Button("Incassato") { settling = e }.buttonStyle(.bordered).font(.caption)
            }
        }
    }

    private func howText(_ m: String) -> String {
        m == "contanti" ? " · in contanti" : m == "carta" ? " · sul conto" : ""
    }

    var body: some View {
        List {
            Section("Da farti restituire") {
                if open.isEmpty { Text("Nessuno ti deve soldi").foregroundStyle(.secondary) }
                ForEach(open) { e in
                    row(e, done: false).swipeActions {
                        Button("Incassato") { settling = e }.tint(Theme.accent)
                    }
                }
            }
            if !closed.isEmpty {
                Section("Già restituiti") { ForEach(closed) { row($0, done: true).foregroundStyle(.secondary) } }
            }
            Section { Text("Tocca Incassato quando ricevi i soldi e scegli se sono arrivati sul conto o in contanti: tornano nel disponibile come rimborso.")
                .font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("Ti devono")
        .confirmationDialog(settling.map { "\($0.owedBy.isEmpty ? "Qualcuno" : $0.owedBy) ti ha dato \(eur($0.owedAmount))?" } ?? "",
                            isPresented: Binding(get: { settling != nil }, set: { if !$0 { settling = nil } }),
                            titleVisibility: .visible) {
            if let e = settling {
                Button("Sì, sul conto (bonifico, carta…)") { settleOwed(e, cash: false, ctx: ctx); settling = nil }
                Button("Sì, in contanti") { settleOwed(e, cash: true, ctx: ctx); settling = nil }
            }
            Button("Annulla", role: .cancel) { settling = nil }
        }
    }
}

/// Segna come restituita una spesa anticipata per qualcuno: i soldi entrano sul conto
/// (entrata di tipo Rimborso) oppure nel portafoglio (contanti ricevuti).
func settleOwed(_ e: Expense, cash: Bool, ctx: ModelContext, now: Date = Date()) {
    e.settled = true
    e.settledMethod = cash ? "contanti" : "carta"
    let note = "Rimborso \(e.owedBy)".trimmingCharacters(in: .whitespaces)
    if cash {
        ctx.insert(CashMove(amount: e.owedAmount, date: now, note: note, kind: "ricevuti", bank: false))
    } else {
        ctx.insert(Income(amount: e.owedAmount, saved: 0, kind: "Rimborso", date: now, note: note))
    }
    try? ctx.save()
}

// MARK: - Viaggi e tag

struct TagsView: View {
    @Query(sort: \Expense.date, order: .reverse) private var all: [Expense]
    private var groups: [(String, Double, Int)] {
        Dictionary(grouping: all.filter { !$0.tag.isEmpty }, by: \.tag)
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.amount }, $0.value.count) }
            .sorted { $0.1 > $1.1 }
    }
    var body: some View {
        List {
            if groups.isEmpty { Text("Aggiungi un tag a una spesa (per esempio il nome di un viaggio) per vedere qui il totale.")
                .font(.footnote).foregroundStyle(.secondary) }
            ForEach(groups, id: \.0) { g in
                HStack {
                    VStack(alignment: .leading) { Text("#\(g.0)"); Text("\(g.2) spese").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Text(eur(g.1)).bold()
                }
            }
        }
        .navigationTitle("Viaggi e tag")
    }
}

// MARK: - Blocco

struct LockView: View {
    let unlock: () -> Void
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(Theme.accent)
                Text("Spese bloccate").font(.headline)
                Button("Sblocca", action: unlock).buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Esportazione e backup

func makeCSV(_ ctx: ModelContext) -> URL? {
    let ex = (try? ctx.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date)]))) ?? []
    let inc = (try? ctx.fetch(FetchDescriptor<Income>(sortBy: [SortDescriptor(\.date)]))) ?? []
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
    func num(_ v: Double) -> String { String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",") }
    func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    var out = "\u{FEFF}Tipo;Data;Importo;Categoria;Nota;Tag;Pagamento\n"
    for e in ex { out += "Spesa;\(f.string(from: e.date));-\(num(e.amount));\(q(e.categoryRaw));\(q(e.note));\(q(e.tag));\(e.method)\n" }
    for i in inc { out += "Entrata;\(f.string(from: i.date));\(num(i.amount));\(q(i.kind));\(q(i.note));;\n" }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Spese.csv")
    do { try out.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
}

struct Backup: Codable {
    struct E: Codable { var amount: Double; var category: String; var date: Date; var note: String
        var tag: String; var owedBy: String; var owedAmount: Double; var settled: Bool; var method: String? = nil
        var tripID: String? = nil; var originalAmount: Double? = nil; var originalCurrency: String? = nil
        var rate: Double? = nil; var paidBy: String? = nil; var splitJSON: String? = nil
        var needsAmount: Bool? = nil; var settledMethod: String? = nil }
    struct T: Codable { var uid: String; var name: String; var currency: String; var startDate: Date; var endDate: Date
        var budget: Double; var countInStats: Bool; var peopleJSON: String; var lastRate: Double }
    struct P: Codable { var tripID: String; var from: String; var to: String; var amount: Double; var date: Date; var method: String }
    struct I: Codable { var amount: Double; var saved: Double; var kind: String; var date: Date; var note: String }
    struct M: Codable { var amount: Double; var date: Date; var note: String }
    struct C: Codable { var name: String; var icon: String; var colorHex: String; var order: Int; var limit: Double }
    struct R: Codable { var name: String; var amount: Double; var categoryName: String; var day: Int; var nextKey: String
        var isSubscription: Bool? = nil }
    struct D: Codable { var person: String; var amount: Double; var note: String; var category: String; var date: Date
        var paid: Bool; var paidMethod: String; var paidDate: Date? }
    struct G: Codable { var name: String; var target: Double; var saved: Double; var deadline: Date }
    struct CM: Codable { var amount: Double; var date: Date; var note: String; var kind: String; var bank: Bool }
    struct A: Codable { var startDate: Date; var salaryAmount: Double; var salaryDay: Int
        var salaryMode: Int; var salaryValue: Double; var salaryNextKey: String
        var periodStart: Date? = nil; var periodEnd: Date? = nil }
    var expenses: [E]; var incomes: [I]; var moves: [M]; var categories: [C]
    var recurring: [R]; var goals: [G]; var account: A?
    var cashMoves: [CM]? = nil; var cashStart: Double? = nil
    var trips: [T]? = nil; var payments: [P]? = nil
    var debts: [D]? = nil
}

func makeBackup(_ ctx: ModelContext) -> URL? {
    guard let data = backupData(ctx) else { return nil }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Spese-backup.json")
    do { try data.write(to: url); return url } catch { return nil }
}

func backupData(_ ctx: ModelContext) -> Data? {
    func all<T: PersistentModel>(_ t: T.Type) -> [T] { (try? ctx.fetch(FetchDescriptor<T>())) ?? [] }
    var b = Backup(expenses: [], incomes: [], moves: [], categories: [], recurring: [], goals: [], account: nil)
    for x in all(Expense.self) {
        b.expenses.append(Backup.E(amount: x.amount, category: x.categoryRaw, date: x.date, note: x.note,
                                   tag: x.tag, owedBy: x.owedBy, owedAmount: x.owedAmount, settled: x.settled, method: x.method,
                                   tripID: x.tripID, originalAmount: x.originalAmount, originalCurrency: x.originalCurrency,
                                   rate: x.rate, paidBy: x.paidBy, splitJSON: x.splitJSON,
                                   needsAmount: x.needsAmount, settledMethod: x.settledMethod))
    }
    for x in all(Income.self) {
        b.incomes.append(Backup.I(amount: x.amount, saved: x.saved, kind: x.kind, date: x.date, note: x.note))
    }
    for x in all(SavingsMove.self) {
        b.moves.append(Backup.M(amount: x.amount, date: x.date, note: x.note))
    }
    for x in all(CategoryItem.self) {
        b.categories.append(Backup.C(name: x.name, icon: x.icon, colorHex: x.colorHex, order: x.order, limit: x.limit))
    }
    for x in all(Recurring.self) {
        b.recurring.append(Backup.R(name: x.name, amount: x.amount, categoryName: x.categoryName, day: x.day, nextKey: x.nextKey,
                                    isSubscription: x.isSubscription))
    }
    for x in all(Goal.self) {
        b.goals.append(Backup.G(name: x.name, target: x.target, saved: x.saved, deadline: x.deadline))
    }
    if let x = all(Account.self).first {
        b.account = Backup.A(startDate: x.startDate, salaryAmount: x.salaryAmount, salaryDay: x.salaryDay,
                             salaryMode: x.salaryMode, salaryValue: x.salaryValue, salaryNextKey: x.salaryNextKey,
                             periodStart: x.periodStart, periodEnd: x.periodEnd)
    }
    b.cashMoves = all(CashMove.self).map { Backup.CM(amount: $0.amount, date: $0.date, note: $0.note, kind: $0.kind, bank: $0.bank) }
    b.cashStart = all(Account.self).first?.cashStart
    b.trips = all(Trip.self).map { Backup.T(uid: $0.uid, name: $0.name, currency: $0.currency, startDate: $0.startDate, endDate: $0.endDate,
                                            budget: $0.budget, countInStats: $0.countInStats, peopleJSON: $0.peopleJSON, lastRate: $0.lastRate) }
    b.payments = all(TripPayment.self).map { Backup.P(tripID: $0.tripID, from: $0.from, to: $0.to, amount: $0.amount, date: $0.date, method: $0.method) }
    b.debts = all(Debt.self).map { Backup.D(person: $0.person, amount: $0.amount, note: $0.note, category: $0.category,
                                            date: $0.date, paid: $0.paid, paidMethod: $0.paidMethod, paidDate: $0.paidDate) }
    let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
    return try? enc.encode(b)
}

// MARK: - Backup automatico

let autoBackupFolderKey = "autoBackupFolder"
let autoBackupLastKey = "autoBackupLast"

/// Scrive un backup con la data nel nome e tiene solo gli ultimi `keep`.
@discardableResult
func writeBackup(_ ctx: ModelContext, to folder: URL, now: Date = Date(), keep: Int = 8) throws -> URL {
    guard let data = backupData(ctx) else { throw CocoaError(.fileWriteUnknown) }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
    let url = folder.appendingPathComponent("Spese-backup-\(f.string(from: now)).json")
    try data.write(to: url, options: .atomic)
    let fm = FileManager.default
    let backups = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.lastPathComponent.hasPrefix("Spese-backup-") && $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent > $1.lastPathComponent }
    for old in backups.dropFirst(keep) { try? fm.removeItem(at: old) }
    return url
}

/// Il backup automatico si fa una volta a settimana.
func autoBackupDue(last: Date?, now: Date = Date()) -> Bool {
    guard let last else { return true }
    return now.timeIntervalSince(last) >= 7 * 24 * 3600
}

/// Cartella scelta dall'utente (per esempio in iCloud Drive), ricordata con un segnalibro.
func autoBackupFolder() -> URL? {
    guard let d = UserDefaults.standard.data(forKey: autoBackupFolderKey) else { return nil }
    var stale = false
    guard let url = try? URL(resolvingBookmarkData: d, bookmarkDataIsStale: &stale) else { return nil }
    if stale, let fresh = try? url.bookmarkData() { UserDefaults.standard.set(fresh, forKey: autoBackupFolderKey) }
    return url
}

func setAutoBackupFolder(_ url: URL) -> Bool {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    guard let d = try? url.bookmarkData() else { return false }
    UserDefaults.standard.set(d, forKey: autoBackupFolderKey)
    return true
}

/// Fa il backup nella cartella scelta se è passata una settimana (o subito con `force`).
/// Restituisce un messaggio d'errore, oppure nil se è andato bene o non serviva.
@discardableResult
func runAutoBackup(_ ctx: ModelContext, force: Bool = false) -> String? {
    let last = UserDefaults.standard.object(forKey: autoBackupLastKey) as? Date
    guard force || autoBackupDue(last: last) else { return nil }
    guard let folder = autoBackupFolder() else { return "Scegli prima una cartella." }
    let access = folder.startAccessingSecurityScopedResource()
    defer { if access { folder.stopAccessingSecurityScopedResource() } }
    do {
        try? ctx.save()
        try writeBackup(ctx, to: folder)
        UserDefaults.standard.set(Date(), forKey: autoBackupLastKey)
        return nil
    } catch {
        return "Backup non riuscito: \(error.localizedDescription)"
    }
}

func restoreBackup(_ ctx: ModelContext, from url: URL) -> Bool {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    guard let data = try? Data(contentsOf: url), let b = try? dec.decode(Backup.self, from: data) else { return false }
    do {
        try ctx.delete(model: Expense.self); try ctx.delete(model: Income.self)
        try ctx.delete(model: SavingsMove.self); try ctx.delete(model: CategoryItem.self)
        try ctx.delete(model: Recurring.self); try ctx.delete(model: Goal.self); try ctx.delete(model: Account.self); try ctx.delete(model: CashMove.self)
        try ctx.delete(model: Trip.self); try ctx.delete(model: TripPayment.self); try ctx.delete(model: Debt.self)
    } catch { return false }
    for e in b.expenses {
        let x = Expense(amount: e.amount, categoryName: e.category, date: e.date, note: e.note)
        x.tag = e.tag; x.owedBy = e.owedBy; x.owedAmount = e.owedAmount; x.settled = e.settled; x.method = e.method ?? "carta"
        x.tripID = e.tripID ?? ""; x.originalAmount = e.originalAmount ?? 0; x.originalCurrency = e.originalCurrency ?? ""
        x.rate = e.rate ?? 0; x.paidBy = e.paidBy ?? ""; x.splitJSON = e.splitJSON ?? ""
        x.needsAmount = e.needsAmount ?? false; x.settledMethod = e.settledMethod ?? ""
        ctx.insert(x)
    }
    for i in b.incomes { ctx.insert(Income(amount: i.amount, saved: i.saved, kind: i.kind, date: i.date, note: i.note)) }
    for m in b.moves { ctx.insert(SavingsMove(amount: m.amount, date: m.date, note: m.note)) }
    for c in b.categories {
        let x = CategoryItem(name: c.name, icon: c.icon, colorHex: c.colorHex, order: c.order); x.limit = c.limit; ctx.insert(x)
    }
    for r in b.recurring {
        let x = Recurring(name: r.name, amount: r.amount, categoryName: r.categoryName, day: r.day, nextKey: r.nextKey)
        x.isSubscription = r.isSubscription ?? false
        ctx.insert(x)
    }
    for d in b.debts ?? [] {
        let x = Debt(person: d.person, amount: d.amount, note: d.note, category: d.category, date: d.date)
        x.paid = d.paid; x.paidMethod = d.paidMethod; x.paidDate = d.paidDate
        ctx.insert(x)
    }
    for c in b.cashMoves ?? [] { ctx.insert(CashMove(amount: c.amount, date: c.date, note: c.note, kind: c.kind, bank: c.bank)) }
    for t in b.trips ?? [] {
        let x = Trip(name: t.name, currency: t.currency, startDate: t.startDate, endDate: t.endDate)
        x.uid = t.uid; x.budget = t.budget; x.countInStats = t.countInStats; x.peopleJSON = t.peopleJSON; x.lastRate = t.lastRate
        ctx.insert(x)
    }
    for p in b.payments ?? [] {
        let x = TripPayment(tripID: p.tripID, from: p.from, to: p.to, amount: p.amount, date: p.date); x.method = p.method
        ctx.insert(x)
    }
    for g in b.goals { ctx.insert(Goal(name: g.name, target: g.target, saved: g.saved, deadline: g.deadline)) }
    if let a = b.account {
        let x = Account(startDate: a.startDate)
        x.salaryAmount = a.salaryAmount; x.salaryDay = a.salaryDay; x.salaryMode = a.salaryMode
        x.salaryValue = a.salaryValue; x.salaryNextKey = a.salaryNextKey; x.cashStart = b.cashStart ?? 0
        x.periodStart = a.periodStart; x.periodEnd = a.periodEnd
        ctx.insert(x)
    }
    return true
}

func scheduleReminder(on: Bool, hour: Int) {
    let c = UNUserNotificationCenter.current()
    c.removePendingNotificationRequests(withIdentifiers: ["daily"])
    guard on else { return }
    c.requestAuthorization(options: [.alert, .sound]) { ok, _ in
        guard ok else { return }
        let content = UNMutableNotificationContent()
        content.title = "Spese di oggi"
        content.body = "Hai inserito tutte le spese di oggi?"
        content.sound = .default
        var d = DateComponents(); d.hour = hour; d.minute = 0
        c.add(UNNotificationRequest(identifier: "daily", content: content,
                                    trigger: UNCalendarNotificationTrigger(dateMatching: d, repeats: true)))
    }
}

// MARK: - Interruttore blocco (facoltativo, si conferma prima di attivarlo)

struct LockToggle: View {
    @AppStorage("lockOn") private var lockOn = false
    @State private var msg = ""

    var body: some View {
        Toggle("Proteggi con Face ID o codice", isOn: Binding(
            get: { lockOn },
            set: { want in
                if !want { lockOn = false; msg = ""; return }
                let c = LAContext()
                var err: NSError?
                guard c.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
                    msg = "Prima imposta un codice di sblocco nelle Impostazioni di iPhone."
                    return
                }
                c.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Conferma per attivare il blocco") { ok, _ in
                    DispatchQueue.main.async {
                        if ok { lockOn = true; msg = "" } else { msg = "Blocco non attivato." }
                    }
                }
            }))
        Text(msg.isEmpty ? "Facoltativo. Quando è attivo, l'app si apre solo con Face ID o con il codice del telefono." : msg)
            .font(.footnote).foregroundStyle(.secondary)
    }
}
