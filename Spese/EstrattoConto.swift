import SwiftUI
import SwiftData
import Compression
import UniformTypeIdentifiers

// MARK: - Controllo estratto conto: si importa il file della banca (Excel o CSV) e si confronta con le spese

/// Un movimento in uscita letto dal file della banca.
struct BankRow: Codable, Equatable, Hashable {
    var date: Date          // giorno vero della spesa (dai dettagli, se c'è), altrimenti quello della banca
    var amount: Double      // positivo: quanto è uscito
    var merchant: String
    var booked: Bool        // false = non ancora contabilizzato
    /// Per ricordare le righe che l'utente ha scelto di non aggiungere.
    var key: String { "\(Int(date.timeIntervalSince1970 / 86400))|\(Int((amount * 100).rounded()))|\(merchant.lowercased())" }
}

/// Una differenza tra file della banca e app.
enum BankDiff: Identifiable, Equatable {
    case missing(BankRow)                       // c'è in banca, non nell'app
    case different(BankRow, PersistentIdentifier, appAmount: Double)
    case duplicate(PersistentIdentifier, amount: Double, merchant: String, date: Date)
    var id: String {
        switch self {
        case .missing(let r): return "m" + r.key
        case .different(let r, _, _): return "d" + r.key
        case .duplicate(let p, _, _, _): return "x\(p.hashValue)"
        }
    }
}

// MARK: Lettura del file

/// Tabella (righe e celle) da un file .xlsx o .csv. nil se il formato non si riconosce.
func readSpreadsheet(_ data: Data) -> [[String]]? {
    if data.starts(with: [0x50, 0x4B]) { return readXLSX(data) }
    guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
    return readCSV(text)
}

/// CSV con ";" o "," (quello più usato nella prima riga lunga), virgolette comprese.
func readCSV(_ text: String) -> [[String]] {
    let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    let sample = lines.max(by: { $0.count < $1.count }) ?? ""
    let sep: Character = sample.filter { $0 == ";" }.count >= sample.filter { $0 == "," }.count ? ";" : ","
    return lines.map { line in
        var cells: [String] = [], cur = "", quoted = false
        for ch in line {
            if ch == "\"" { quoted.toggle() }
            else if ch == sep && !quoted { cells.append(cur); cur = "" }
            else { cur.append(ch) }
        }
        cells.append(cur)
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

/// File di un archivio .zip (come un .xlsx), senza librerie esterne.
private func unzip(_ data: Data) -> [String: Data] {
    let b = [UInt8](data)
    func u16(_ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 }
    func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
    guard b.count > 22, let end = stride(from: b.count - 22, through: max(0, b.count - 65_000), by: -1)
        .first(where: { u32($0) == 0x06054b50 }) else { return [:] }
    var out: [String: Data] = [:]
    var p = u32(end + 16)
    for _ in 0..<u16(end + 10) {
        guard p + 46 <= b.count, u32(p) == 0x02014b50 else { break }
        let method = u16(p + 10), csize = u32(p + 20), usize = u32(p + 24)
        let nlen = u16(p + 28), elen = u16(p + 30), clen = u16(p + 32), local = u32(p + 42)
        let name = String(decoding: b[(p + 46)..<(p + 46 + nlen)], as: UTF8.self)
        p += 46 + nlen + elen + clen
        guard local + 30 <= b.count else { continue }
        let start = local + 30 + u16(local + 26) + u16(local + 28)
        guard start + csize <= b.count else { continue }
        let raw = Array(b[start..<(start + csize)])
        if method == 0 { out[name] = Data(raw); continue }
        guard method == 8, usize > 0 else { continue }
        var dst = [UInt8](repeating: 0, count: usize)
        let n = compression_decode_buffer(&dst, usize, raw, raw.count, nil, COMPRESSION_ZLIB)
        if n > 0 { out[name] = Data(dst.prefix(n)) }
    }
    return out
}

private func xmlUnescape(_ s: String) -> String {
    s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
        .replacingOccurrences(of: "&amp;", with: "&")
}

private func allMatches(_ pattern: String, _ text: String) -> [[String]] {
    guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
    return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
        (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: text).map { String(text[$0]) } ?? "" }
    }
}

/// Primo foglio di un .xlsx come tabella di testi (le date restano numeri seriali di Excel).
private func readXLSX(_ data: Data) -> [[String]]? {
    let files = unzip(data)
    guard let sheet = files["xl/worksheets/sheet1.xml"].map({ String(decoding: $0, as: UTF8.self) }) else { return nil }
    let shared = files["xl/sharedStrings.xml"].map { String(decoding: $0, as: UTF8.self) }.map { xml in
        allMatches("<si>(.*?)</si>", xml).map { si in
            xmlUnescape(allMatches("<t[^>]*>(.*?)</t>", si[1]).map { $0[1] }.joined())
        }
    } ?? []
    func column(_ ref: String) -> Int {
        ref.prefix { $0.isLetter }.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }
    return allMatches("<row[^>]*>(.*?)</row>", sheet).map { row in
        var cells: [String] = []
        for c in allMatches(#"<c ([^>]*?)(?:/>|>(.*?)</c>)"#, row[1]) {
            guard let ref = allMatches(#"r="([A-Z]+)"#, c[1]).first?[1] else { continue }
            let i = column(ref)
            let v = allMatches("<v>(.*?)</v>", c[2]).first?[1] ?? allMatches("<t[^>]*>(.*?)</t>", c[2]).first?[1] ?? ""
            let text = c[1].contains(#"t="s""#) ? (Int(v).flatMap { $0 < shared.count ? shared[$0] : nil } ?? "") : xmlUnescape(v)
            while cells.count < i { cells.append("") }
            if cells.count == i { cells.append(text) } else if i < cells.count { cells[i] = text }
        }
        return cells
    }
}

// MARK: Dalla tabella ai movimenti

private func cellDate(_ s: String) -> Date? {
    let cal = Calendar.current
    if let n = Double(s), n > 30000, n < 80000 {   // numero seriale di Excel
        return cal.date(byAdding: .day, value: Int(n), to: cal.date(from: DateComponents(year: 1899, month: 12, day: 30, hour: 12))!)
    }
    let p = s.split(whereSeparator: { "/-.".contains($0) }).compactMap { Int($0.prefix(4)) }
    guard p.count >= 3 else { return nil }
    let (d, m, y) = p[0] > 31 ? (p[2], p[1], p[0]) : (p[0], p[1], p[2] < 100 ? 2000 + p[2] : p[2])
    return cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))
}

/// "05/110953" o "EFFETTUATO IL 01/11/2026" nei dettagli: giorno vero della spesa, fino a 10 giorni prima della banca.
private func realDay(in text: String, booked: Date) -> Date? {
    let cal = Calendar.current
    for m in allMatches(#"(\d{2})/(\d{2})"#, text) {
        guard let d = Int(m[1]), let mo = Int(m[2]), (1...31).contains(d), (1...12).contains(mo) else { continue }
        var y = cal.component(.year, from: booked)
        if mo > cal.component(.month, from: booked) { y -= 1 }
        if let date = cal.date(from: DateComponents(year: y, month: mo, day: d, hour: 12)),
           date <= booked, booked.timeIntervalSince(date) <= 10 * 86400 { return date }
    }
    return nil
}

/// Nome dell'esercente: l'operazione, o i dettagli se l'operazione è generica ("Pagamento Tramite Pos").
private func merchantName(operation: String, details: String) -> String {
    var op = operation.trimmingCharacters(in: .whitespaces)
    for prefix in ["Addebito diretto disposto a favore di ", "Pagamento a favore di ", "Bonifico a favore di "]
    where op.lowercased().hasPrefix(prefix.lowercased()) { op = String(op.dropFirst(prefix.count)) }
    let generic = ["pagamento tramite pos", "pagamento pos", "pagamento", "pagamento carta", "addebito"]
    if op.isEmpty || generic.contains(op.lowercased()) { return details.trimmingCharacters(in: .whitespaces) }
    return op
}

/// Le uscite del file: cerca da solo la riga dei titoli (Data… Importo) e le colonne.
func bankRows(from table: [[String]]) -> [BankRow] {
    func idx(_ header: [String], _ names: [String]) -> Int? {
        header.firstIndex { h in names.contains { h.lowercased().trimmingCharacters(in: .whitespaces).hasPrefix($0) } }
    }
    guard let h = table.firstIndex(where: { r in idx(r, ["data"]) != nil && idx(r, ["importo", "uscite", "addebiti", "amount"]) != nil })
    else { return [] }
    let header = table[h]
    let dateI = idx(header, ["data contabile", "data operazione", "data"])!
    let amountI = idx(header, ["importo", "amount"])
    let outI = idx(header, ["uscite", "addebiti"])
    let opI = idx(header, ["operazione", "descrizione", "causale", "description"])
    let detI = idx(header, ["dettagli", "descrizione estesa", "details"])
    let bookedI = idx(header, ["contabilizzazione", "stato"])
    func cell(_ r: [String], _ i: Int?) -> String { i.flatMap { $0 < r.count ? r[$0] : nil } ?? "" }
    return table[(h + 1)...].compactMap { r in
        guard let date = cellDate(cell(r, dateI)) else { return nil }
        var value: Double?
        if let i = amountI, let v = parseLooseSigned(cell(r, i)) { value = v }
        else if let v = parseLooseSigned(cell(r, outI)), v != 0 { value = -abs(v) }
        guard let v = value, v < 0 else { return nil }   // solo le uscite
        let details = cell(r, detI)
        let booked = !["no", "non contabilizzato", "in attesa"].contains(cell(r, bookedI).lowercased())
        return BankRow(date: realDay(in: details, booked: date) ?? date, amount: -v,
                       merchant: merchantName(operation: cell(r, opI), details: details), booked: booked)
    }
}

/// Importo con segno: "-16.75", "-1.234,56", "16,75".
func parseLooseSigned(_ s: String) -> Double? {
    let t = s.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty, let v = parseLooseAmount(t) else { return nil }
    return t.contains("-") ? -v : v
}

// MARK: Confronto

private func sameName(_ a: String, _ b: String) -> Bool {
    func words(_ s: String) -> Set<String> {
        Set(s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 3 && Int($0) == nil })
    }
    return !words(a).isDisjoint(with: words(b))
}

/// Confronta le uscite della banca con le spese con carta dell'app negli stessi giorni.
/// Stesso importo entro 3 giorni = a posto. Le righe già scartate dall'utente (`ignored`) non contano.
func compareBank(_ rows: [BankRow], with expenses: [Expense], ignored: Set<String> = []) -> [BankDiff] {
    guard let first = rows.map(\.date).min(), let last = rows.map(\.date).max() else { return [] }
    let cal = Calendar.current
    let from = cal.startOfDay(for: first), to = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: last))!
    var pool = expenses.filter { !$0.isCash && $0.paidByMe && !$0.needsAmount && $0.date >= from.addingTimeInterval(-3 * 86400) && $0.date < to.addingTimeInterval(3 * 86400) }
    var diffs: [BankDiff] = []
    var unmatched: [BankRow] = []
    for r in rows.sorted(by: { $0.date < $1.date }) {
        let near = pool.filter { abs($0.date.timeIntervalSince(r.date)) <= 3.5 * 86400 && abs($0.myAmount - r.amount) < 0.005 }
        if let e = near.min(by: { abs($0.date.timeIntervalSince(r.date)) < abs($1.date.timeIntervalSince(r.date)) }) {
            pool.removeAll { $0 === e }
        } else {
            unmatched.append(r)
        }
    }
    for r in unmatched where !ignored.contains(r.key) {
        // Stesso negozio e stesso giorno ma importo diverso: da correggere.
        if let e = pool.first(where: { abs($0.date.timeIntervalSince(r.date)) <= 1.5 * 86400 && sameName($0.note, r.merchant) }) {
            pool.removeAll { $0 === e }
            diffs.append(.different(r, e.persistentModelID, appAmount: e.myAmount))
        } else {
            diffs.append(.missing(r))
        }
    }
    // Spese rimaste nei giorni del file con una gemella (stesso importo, entro 2 giorni): forse doppie.
    let inRange = expenses.filter { !$0.isCash && $0.paidByMe && $0.date >= from && $0.date < to }
    for e in pool where e.date >= from && e.date < to && e.planID.isEmpty {
        if inRange.contains(where: { $0 !== e && abs($0.myAmount - e.myAmount) < 0.005 && abs($0.date.timeIntervalSince(e.date)) <= 2 * 86400 }) {
            diffs.append(.duplicate(e.persistentModelID, amount: e.myAmount, merchant: e.note, date: e.date))
        }
    }
    return diffs
}

// MARK: Memoria (controlli fatti, righe scartate, differenze in sospeso)

let bankChecksKey = "bankChecks"            // [[from, to, differenze]]
let bankIgnoredKey = "bankIgnoredRows"      // chiavi delle righe "Non aggiungere"
let bankPendingKey = "bankPendingRows"      // righe dell'ultimo file con differenze ancora da vedere

struct BankCheck: Codable, Hashable { var from: Date; var to: Date; var differences: Int; var at: Date }

enum BankStore {
    static var checks: [BankCheck] {
        get { (UserDefaults.standard.data(forKey: bankChecksKey)).flatMap { try? JSONDecoder().decode([BankCheck].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: bankChecksKey) }
    }
    static var ignored: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: bankIgnoredKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: bankIgnoredKey) }
    }
    static var pending: [BankRow] {
        get { (UserDefaults.standard.data(forKey: bankPendingKey)).flatMap { try? JSONDecoder().decode([BankRow].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue), forKey: bankPendingKey) }
    }
}

// MARK: Schermate

/// Conti → Controllo estratto conto.
struct BankCheckView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var expenses: [Expense]
    @State private var importing = false
    @State private var rows: [BankRow] = []
    @State private var showDiffs = false
    @State private var message = ""
    @State private var checks = BankStore.checks

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass").font(.largeTitle).foregroundStyle(Theme.accent)
                    Text("Importa il file della banca").font(.headline)
                    Text("Excel o CSV scaricato dalla tua banca. Puoi importare anche giorni già controllati: i movimenti già presenti non vengono contati due volte.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Scegli file") { importing = true }.buttonStyle(.borderedProminent)
                    if !message.isEmpty { Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            if !checks.isEmpty {
                Section("Controlli fatti") {
                    ForEach(checks.reversed(), id: \.self) { c in
                        HStack {
                            Text(rangeText((c.from, Calendar.current.date(byAdding: .day, value: 1, to: c.to) ?? c.to)))
                            Spacer()
                            Text(c.differences == 0 ? "✓ tutto a posto" : "\(c.differences) differenze")
                                .foregroundStyle(c.differences == 0 ? .green : .orange)
                        }
                    }
                }
            }
        }
        .navigationTitle("Controllo estratto conto").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [UTType(filenameExtension: "xlsx") ?? .data, .commaSeparatedText, .plainText]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let table = readSpreadsheet(data) else {
                message = "Non riesco a leggere questo file. Prova con Excel (.xlsx) o CSV."; return
            }
            let read = bankRows(from: table)
            guard !read.isEmpty else { message = "Nel file non ho trovato uscite (serve una colonna Data e una Importo)."; return }
            let diffs = compareBank(read, with: expenses, ignored: BankStore.ignored)
            var list = BankStore.checks
            list.append(BankCheck(from: read.map(\.date).min()!, to: read.map(\.date).max()!, differences: diffs.count, at: Date()))
            BankStore.checks = list; checks = list
            message = "Letti \(read.count) movimenti in uscita."
            if diffs.isEmpty { BankStore.pending = [] } else { BankStore.pending = read; rows = read; showDiffs = true }
        }
        .sheet(isPresented: $showDiffs) { BankDiffView(rows: rows) }
    }
}

/// Elenco delle differenze: Aggiungi / Non aggiungere, Correggi, Togli.
struct BankDiffView: View {
    let rows: [BankRow]
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var expenses: [Expense]
    @Query(sort: \CategoryItem.order) private var cats: [CategoryItem]
    @State private var ignored = BankStore.ignored

    private var diffs: [BankDiff] { compareBank(rows, with: expenses, ignored: ignored) }

    var body: some View {
        let d = diffs
        NavigationStack {
            List {
                if d.isEmpty {
                    Text("Tutto a posto: le spese tornano con la banca.").foregroundStyle(.secondary)
                }
                let missing = d.compactMap { if case .missing(let r) = $0 { return r } else { return nil } }
                if !missing.isEmpty {
                    Section("Mancano nell'app") {
                        ForEach(missing, id: \.self) { r in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(r.merchant).lineLimit(1); Spacer(); Text(eur(r.amount)).bold() }
                                (Text("Speso il \(day(r.date))") + (r.booked ? Text("") : Text(" · non ancora contabilizzata").foregroundColor(.orange)))
                                    .font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button("Aggiungi il \(day(r.date))") { add(r) }.buttonStyle(.borderedProminent)
                                    Button("Non aggiungere") { ignore(r) }.buttonStyle(.bordered)
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }
                let different = d.compactMap { if case .different(let r, let id, let a) = $0 { return (r, id, a) } else { return nil } }
                if !different.isEmpty {
                    Section("Importo diverso") {
                        ForEach(Array(different.enumerated()), id: \.offset) { _, item in
                            let (r, id, a) = item
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("\(r.merchant) · \(eur(a)) → \(eur(r.amount))").lineLimit(1)
                                    Text("\(day(r.date)) · in app \(eur(a))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Correggi") { correct(id, to: r.amount) }.buttonStyle(.borderedProminent).tint(.orange)
                            }
                        }
                    }
                }
                let doubles = d.compactMap { if case .duplicate(let id, let a, let m, let dt) = $0 { return (id, a, m, dt) } else { return nil } }
                if !doubles.isEmpty {
                    Section {
                        ForEach(Array(doubles.enumerated()), id: \.offset) { _, item in
                            let (id, a, m, dt) = item
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("\(m.isEmpty ? "Spesa" : m) · \(eur(a))").lineLimit(1)
                                    Text("\(day(dt)) · in banca una volta sola").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Togli") { remove(id) }.buttonStyle(.borderedProminent).tint(.red)
                            }
                        }
                    } header: { Text("Forse doppia") }
                }
            }
            .navigationTitle(d.isEmpty ? "Tutto a posto" : "\(d.count) differenze").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Più tardi") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if d.isEmpty { Button("Fine") { BankStore.pending = []; dismiss() } }
                }
            }
            .onDisappear { if diffs.isEmpty { BankStore.pending = [] } }
        }
    }

    private func day(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated)) }

    private func add(_ r: BankRow) {
        let cat = guessCategory(merchant: r.merchant, available: cats.map(\.name))
        let e = Expense(amount: r.amount, categoryName: cat, date: r.date, note: r.merchant)
        e.method = "carta"
        ctx.insert(e)
        try? ctx.save()
        updateWidgetSnapshot(ctx)
    }

    private func ignore(_ r: BankRow) {
        ignored.insert(r.key)
        BankStore.ignored = ignored
    }

    private func correct(_ id: PersistentIdentifier, to amount: Double) {
        guard let e = ctx.model(for: id) as? Expense else { return }
        e.amount = amount
        try? ctx.save()
        updateWidgetSnapshot(ctx)
    }

    private func remove(_ id: PersistentIdentifier) {
        guard let e = ctx.model(for: id) as? Expense else { return }
        ctx.delete(e)
        try? ctx.save()
        updateWidgetSnapshot(ctx)
    }
}

/// Riquadro in Home quando l'ultimo estratto conto ha differenze da vedere.
struct BankPendingSection: View {
    @Environment(\.scenePhase) private var phase
    @Query private var expenses: [Expense]
    @State private var rows = BankStore.pending
    @State private var open = false

    var body: some View {
        let n = rows.isEmpty ? 0 : compareBank(rows, with: expenses, ignored: BankStore.ignored).count
        Group {
            if n > 0 {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Estratto conto: \(n) \(n == 1 ? "differenza" : "differenze")", systemImage: "doc.text.magnifyingglass")
                            .font(.headline).foregroundStyle(.orange)
                        Text("Alcune spese della banca non tornano con l'app.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Controlla") { open = true }.buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.orange.opacity(0.12))
            }
        }
        .sheet(isPresented: $open, onDismiss: { rows = BankStore.pending }) { BankDiffView(rows: rows) }
        .onChange(of: phase) { _, p in if p == .active { rows = BankStore.pending } }
        .onAppear { rows = BankStore.pending }
    }
}
