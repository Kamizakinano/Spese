import SwiftUI
import SwiftData
import UIKit

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

// MARK: - File CSV

/// CSV all'italiana: separatore ";", virgola nei decimali, BOM per Excel.
func makeCSV(_ expenses: [Expense]) -> Data {
    let f = DateFormatter(); f.locale = Locale(identifier: "it_IT"); f.dateFormat = "dd/MM/yyyy"
    func field(_ s: String) -> String {
        s.contains(";") || s.contains("\"") || s.contains("\n") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }
    func num(_ v: Double) -> String { String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",") }
    var lines = ["Data;Nota;Categoria;Importo;Pagamento;Tag"]
    for e in expenses.sorted(by: { $0.date < $1.date }) {
        lines.append([f.string(from: e.date), field(e.note), field(e.categoryRaw), num(e.amount),
                      e.isCash ? "Contanti" : "Carta", field(e.tag)].joined(separator: ";"))
    }
    lines.append("Totale;;;\(num(expenses.reduce(0) { $0 + $1.amount }));;")
    return Data([0xEF, 0xBB, 0xBF]) + Data(lines.joined(separator: "\r\n").utf8)
}

// MARK: - Riepilogo PDF

/// Riepilogo stampabile (A4): totali, categorie e l'elenco delle spese.
func makePDF(_ expenses: [Expense], title: String, subtitle: String) -> Data {
    let page = CGRect(x: 0, y: 0, width: 595, height: 842), m: CGFloat = 40
    let list = expenses.sorted { $0.date < $1.date }
    let total = list.reduce(0) { $0 + $1.amount }
    let cash = list.filter(\.isCash).reduce(0) { $0 + $1.amount }
    let cats = Dictionary(grouping: list, by: \.categoryRaw).mapValues { $0.reduce(0) { $0 + $1.amount } }
        .sorted { $0.value > $1.value }
    let df = DateFormatter(); df.locale = Locale(identifier: "it_IT"); df.dateFormat = "dd/MM"
    let accent = UIColor(red: 0x5D / 255, green: 0x75 / 255, blue: 0x84 / 255, alpha: 1)
    func font(_ s: CGFloat, _ w: UIFont.Weight = .regular) -> UIFont { .systemFont(ofSize: s, weight: w) }
    func draw(_ t: String, _ x: CGFloat, _ y: CGFloat, _ f: UIFont, _ c: UIColor = .black, width: CGFloat = 300, right: Bool = false) {
        let p = NSMutableParagraphStyle(); p.alignment = right ? .right : .left; p.lineBreakMode = .byTruncatingTail
        (t as NSString).draw(in: CGRect(x: right ? x - width : x, y: y, width: width, height: f.lineHeight + 2),
                             withAttributes: [.font: f, .foregroundColor: c, .paragraphStyle: p])
    }
    let cols: [CGFloat] = [m, m + 50, m + 250, m + 390]   // data, nota, categoria, pagamento; importo a destra
    let right = page.width - m

    return UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
        var y: CGFloat = 0
        func header() {
            draw("Data", cols[0], y, font(9, .semibold), .gray); draw("Nota", cols[1], y, font(9, .semibold), .gray)
            draw("Categoria", cols[2], y, font(9, .semibold), .gray); draw("Pagamento", cols[3], y, font(9, .semibold), .gray)
            draw("Importo", right, y, font(9, .semibold), .gray, width: 80, right: true)
            y += 16
        }
        func newPage() { ctx.beginPage(); y = m; header() }

        ctx.beginPage()
        accent.setFill(); UIBezierPath(roundedRect: CGRect(x: m, y: m, width: page.width - 2 * m, height: 90), cornerRadius: 12).fill()
        draw(title, m + 18, m + 14, font(20, .bold), .white, width: 400)
        draw(subtitle, m + 18, m + 42, font(10), .white.withAlphaComponent(0.85), width: 400)
        draw(eur(total), right - 18, m + 14, font(22, .bold), .white, width: 200, right: true)
        draw("\(list.count) spese · carta \(eur(total - cash)) · contanti \(eur(cash))", right - 18, m + 46, font(9),
             .white.withAlphaComponent(0.85), width: 300, right: true)
        y = m + 110

        if !cats.isEmpty {
            draw("Categorie", m, y, font(12, .semibold)); y += 20
            let maxV = cats.first?.value ?? 1
            for (name, v) in cats {
                draw(name, m, y, font(10), width: 150)
                UIColor(white: 0.92, alpha: 1).setFill()
                UIBezierPath(roundedRect: CGRect(x: m + 150, y: y + 3, width: 250, height: 8), cornerRadius: 4).fill()
                accent.setFill()
                UIBezierPath(roundedRect: CGRect(x: m + 150, y: y + 3, width: max(250 * v / maxV, 4), height: 8), cornerRadius: 4).fill()
                draw(eur(v), right, y, font(10, .medium), width: 90, right: true)
                draw(total > 0 ? "\(Int((v / total * 100).rounded()))%" : "", m + 410, y, font(9), .gray, width: 30)
                y += 17
                if y > page.height - m - 40 { newPage() }
            }
            y += 14
        }

        draw("Spese", m, y, font(12, .semibold)); y += 20
        header()
        for (i, e) in list.enumerated() {
            if y > page.height - m - 20 { newPage() }
            if i % 2 == 0 {
                UIColor(white: 0.965, alpha: 1).setFill(); UIRectFill(CGRect(x: m - 4, y: y - 2, width: page.width - 2 * m + 8, height: 16))
            }
            draw(df.string(from: e.date), cols[0], y, font(9))
            draw(e.note.isEmpty ? e.categoryRaw : e.note, cols[1], y, font(9), width: 190)
            draw(e.categoryRaw, cols[2], y, font(9), .darkGray, width: 130)
            draw(e.isCash ? "Contanti" : "Carta", cols[3], y, font(9), .darkGray, width: 70)
            draw(eur(e.amount), right, y, font(9, .medium), width: 80, right: true)
            y += 16
        }
        if y > page.height - m - 30 { newPage() }
        y += 6
        UIColor.lightGray.setFill(); UIRectFill(CGRect(x: m, y: y, width: page.width - 2 * m, height: 0.5))
        draw("Totale", cols[0], y + 6, font(10, .bold))
        draw(eur(total), right, y + 6, font(10, .bold), width: 120, right: true)
        draw("Creato con Spese", m, page.height - m + 10, font(8), .gray)
    }
}

// MARK: - Pagina "Esporta"

enum ExportFormat: Int, CaseIterable {
    case excel, csv, pdf
    var name: String { ["Excel", "CSV", "PDF"][rawValue] }
    var ext: String { ["xlsx", "csv", "pdf"][rawValue] }
    var icon: String { ["tablecells", "doc.plaintext", "doc.richtext"][rawValue] }
    var hint: String {
        switch self {
        case .excel: "Il file si apre con Excel o Numbers. Puoi salvarlo in File o mandarlo su WhatsApp e per email."
        case .csv: "Testo semplice, una riga per spesa: si apre con qualsiasi foglio di calcolo o programma."
        case .pdf: "Un riepilogo da leggere o stampare: totali, categorie e l'elenco delle spese."
        }
    }
}

struct ExportView: View {
    @Query(sort: \Expense.date) private var all: [Expense]
    @Query private var accounts: [Account]
    @State private var mode = 0
    @State private var format = ExportFormat.excel
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
    private var lastDay: Date { Calendar.current.date(byAdding: .day, value: -1, to: range.end) ?? range.end }

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
                Text("Dal \(range.start.formatted(.dateTime.day().month(.wide).year())) al \(lastDay.formatted(.dateTime.day().month(.wide).year())) · \(list.count) spese, \(eur(list.reduce(0) { $0 + $1.amount }))")
            }
            Section("Formato") {
                Picker("Formato", selection: $format) {
                    ForEach(ExportFormat.allCases, id: \.self) { Text($0.name).tag($0) }
                }.pickerStyle(.segmented)
            }
            Section {
                if let file {
                    ShareLink(item: file) { Label("Esporta \(list.count) spese (\(format.name))", systemImage: format.icon) }
                }
            } footer: {
                Text(format.hint)
            }
        }
        .navigationTitle("Esporta").navigationBarTitleDisplayMode(.inline)
        .task(id: "\(mode)-\(format.rawValue)-\(from)-\(to)-\(all.count)") { file = writeFile() }
    }

    private func writeFile() -> URL? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Spese \(f.string(from: range.start)).\(format.ext)")
        let data: Data
        switch format {
        case .excel: data = makeXLSX(sheet: "Spese", rows: exportRows(list), widths: [12, 30, 20, 12, 12, 16])
        case .csv: data = makeCSV(list)
        case .pdf:
            let day = Date.FormatStyle().day().month(.wide).year()
            let title = mode == 0 ? "Spese di " + range.start.formatted(.dateTime.month(.wide).year()) : "Spese"
            data = makePDF(list, title: title, subtitle: "Dal \(range.start.formatted(day)) al \(lastDay.formatted(day))")
        }
        do { try data.write(to: url); return url } catch { return nil }
    }
}
