import SwiftUI
import SwiftData

// MARK: - File Excel (.xlsx)

/// CRC-32 (quello degli archivi ZIP).
func crc32(_ data: Data) -> UInt32 {
    var table = [UInt32](repeating: 0, count: 256)
    for i in 0..<256 {
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        table[i] = c
    }
    var crc: UInt32 = 0xFFFFFFFF
    for b in data { crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
    return crc ^ 0xFFFFFFFF
}

/// Archivio ZIP senza compressione: basta per un file Excel.
func zipStored(_ files: [(name: String, data: Data)]) -> Data {
    var out = Data(), central = Data()
    func u16(_ v: Int, _ d: inout Data) { d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF)) }
    func u32(_ v: UInt32, _ d: inout Data) { for s in [0, 8, 16, 24] { d.append(UInt8((v >> UInt32(s)) & 0xFF)) } }
    for f in files {
        let name = Data(f.name.utf8), crc = crc32(f.data), size = UInt32(f.data.count), offset = UInt32(out.count)
        u32(0x04034b50, &out); u16(20, &out); u16(0, &out); u16(0, &out); u16(0, &out); u16(0x21, &out)
        u32(crc, &out); u32(size, &out); u32(size, &out); u16(name.count, &out); u16(0, &out)
        out.append(name); out.append(f.data)
        u32(0x02014b50, &central); u16(20, &central); u16(20, &central); u16(0, &central); u16(0, &central)
        u16(0, &central); u16(0x21, &central); u32(crc, &central); u32(size, &central); u32(size, &central)
        u16(name.count, &central); u16(0, &central); u16(0, &central); u16(0, &central); u16(0, &central)
        u32(0, &central); u32(offset, &central); central.append(name)
    }
    let cdOffset = UInt32(out.count)
    out.append(central)
    u32(0x06054b50, &out); u16(0, &out); u16(0, &out); u16(files.count, &out); u16(files.count, &out)
    u32(UInt32(central.count), &out); u32(cdOffset, &out); u16(0, &out)
    return out
}

/// Una cella: testo o numero (con lo stile: 0 normale, 1 importo, 2 intestazione, 3 totale).
enum XCell { case text(String, style: Int = 0), number(Double, style: Int = 1) }

/// Crea un file Excel con un solo foglio.
func makeXLSX(sheet: String, rows: [[XCell]], widths: [Double]) -> Data {
    func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    func col(_ i: Int) -> String {
        var n = i + 1, s = ""
        while n > 0 { let r = (n - 1) % 26; s = String(UnicodeScalar(65 + r)!) + s; n = (n - 1) / 26 }
        return s
    }
    var xml = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cols>"#
    for (i, w) in widths.enumerated() { xml += #"<col min="\#(i + 1)" max="\#(i + 1)" width="\#(w)" customWidth="1"/>"# }
    xml += "</cols><sheetData>"
    for (r, row) in rows.enumerated() {
        xml += #"<row r="\#(r + 1)">"#
        for (c, cell) in row.enumerated() {
            let ref = "\(col(c))\(r + 1)"
            switch cell {
            case .text(let s, let st): xml += #"<c r="\#(ref)" t="inlineStr" s="\#(st)"><is><t xml:space="preserve">\#(esc(s))</t></is></c>"#
            case .number(let v, let st): xml += #"<c r="\#(ref)" s="\#(st)"><v>\#(String(format: "%.2f", v))</v></c>"#
            }
        }
        xml += "</row>"
    }
    xml += "</sheetData></worksheet>"
    let styles = ##"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0.00 &quot;€&quot;"/></numFmts><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="164" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/></cellXfs></styleSheet>"##
    let files: [(String, String)] = [
        ("[Content_Types].xml", #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>"#),
        ("_rels/.rels", #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>"#),
        ("xl/workbook.xml", #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="\#(esc(sheet))" sheetId="1" r:id="rId1"/></sheets></workbook>"#),
        ("xl/_rels/workbook.xml.rels", #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>"#),
        ("xl/styles.xml", styles),
        ("xl/worksheets/sheet1.xml", xml)
    ]
    return zipStored(files.map { ($0.0, Data($0.1.utf8)) })
}

/// Righe del foglio: intestazione, una riga per spesa (dalla più vecchia) e il totale.
func exportRows(_ expenses: [Expense]) -> [[XCell]] {
    let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "dd/MM/yyyy"
    var rows: [[XCell]] = [["Data", "Nota", "Categoria", "Importo", "Pagamento", "Tag"].map { .text($0, style: 2) }]
    for e in expenses.sorted(by: { $0.date < $1.date }) {
        rows.append([.text(f.string(from: e.date)), .text(e.note), .text(e.categoryRaw), .number(e.amount),
                     .text(e.isCash ? "Contanti" : "Carta"), .text(e.tag)])
    }
    rows.append([.text("Totale", style: 2), .text(""), .text(""), .number(expenses.reduce(0) { $0 + $1.amount }, style: 3)])
    return rows
}

// MARK: - Pagina "Esporta in Excel"

struct ExportView: View {
    @Query(sort: \Expense.date) private var all: [Expense]
    @Query private var accounts: [Account]
    @State private var mode = 0
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var file: URL?

    private var range: (start: Date, end: Date) {
        let cal = Calendar.current
        switch mode {
        case 1:
            if let a = accounts.first, let p = payPeriod(day: a.salaryDay, customStart: a.periodStart, customEnd: a.periodEnd) { return p }
            fallthrough
        case 0:
            let iv = cal.dateInterval(of: .month, for: Date())
            return (iv?.start ?? Date(), iv?.end ?? Date())
        default:
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: max(from, to))) ?? to
            return (cal.startOfDay(for: min(from, to)), end)
        }
    }
    private var list: [Expense] { all.filter { $0.date >= range.start && $0.date < range.end && $0.date < Ledger.endOfToday } }

    var body: some View {
        List {
            Section {
                Picker("Periodo", selection: $mode) {
                    Text("Questo mese").tag(0); Text("Periodo stipendio").tag(1); Text("Scegli date").tag(2)
                }.pickerStyle(.segmented)
                if mode == 2 {
                    DatePicker("Dal", selection: $from, displayedComponents: .date)
                    DatePicker("Al", selection: $to, displayedComponents: .date)
                }
            } footer: {
                let last = Calendar.current.date(byAdding: .day, value: -1, to: range.end) ?? range.end
                Text("Dal \(range.start.formatted(.dateTime.day().month(.wide).year())) al \(last.formatted(.dateTime.day().month(.wide).year())) · \(list.count) spese, \(eur(list.reduce(0) { $0 + $1.amount }))")
            }
            Section {
                if let file {
                    ShareLink(item: file) { Label("Esporta \(list.count) spese (Excel)", systemImage: "tablecells") }
                }
            } footer: {
                Text("Il file si apre con Excel o Numbers. Puoi salvarlo in File o mandarlo su WhatsApp e per email.")
            }
        }
        .navigationTitle("Esporta in Excel").navigationBarTitleDisplayMode(.inline)
        .task(id: "\(mode)-\(from)-\(to)-\(all.count)") { file = writeFile() }
    }

    private func writeFile() -> URL? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let name = "Spese \(f.string(from: range.start)).xlsx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let data = makeXLSX(sheet: "Spese", rows: exportRows(list), widths: [12, 30, 20, 12, 12, 16])
        do { try data.write(to: url); return url } catch { return nil }
    }
}
