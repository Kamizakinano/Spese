import SwiftUI
import SwiftData

func cashKindTitle(_ k: String) -> String {
    switch k {
    case "prelievo": return "Prelievo dalla banca"
    case "versamento": return "Versamento in banca"
    case "ricevuti": return "Contanti ricevuti"
    default: return "Correzione contanti"
    }
}

// MARK: - Totale, carta e contanti

struct ContiView: View {
    @Query(sort: \Expense.date, order: .reverse) private var all: [Expense]
    @Query private var incomes: [Income]
    @Query private var moves: [SavingsMove]
    @Query private var cashMoves: [CashMove]
    @Query private var accounts: [Account]
    @State private var kind = "prelievo"
    @State private var showMove = false
    @State private var editBank = false
    @State private var editCash = false

    private var ledger: Ledger { Ledger(incomes: incomes, expenses: all, moves: moves, cash: cashMoves, account: accounts.first) }
    private var bank: Double { ledger.figures(for: Date()).left }
    private var cash: Double { ledger.cashBalance() }

    private func row(_ icon: String, _ title: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.white).frame(width: 34, height: 34).background(color, in: Circle())
            Text(title)
            Spacer()
            Text(eur(value)).bold()
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Totale").font(.subheadline).opacity(0.85)
                        Text(eur(bank + cash)).font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("Banca e contanti insieme. Entra in una delle due voci per il dettaglio.")
                            .font(.footnote).opacity(0.9)
                    }
                    .foregroundStyle(.white).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [Theme.accent, Color(hex: "0F6E56")],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 22))
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)

                Section("Dove sono i tuoi soldi") {
                    NavigationLink { BankView() } label: { row("creditcard", "Banca (carta)", bank, Color(hex: "2980B9")) }
                    NavigationLink { CashView() } label: { row("banknote", "Contanti (portafoglio)", cash, Color(hex: "E67E22")) }
                }

                Section("Modifica i saldi") {
                    Button { editBank = true } label: { Label("Modifica soldi in banca", systemImage: "pencil") }
                    Button { editCash = true } label: { Label("Modifica contanti", systemImage: "pencil") }
                }

                Section("Spostamenti") {
                    Button { kind = "prelievo"; showMove = true } label: {
                        Label("Ho prelevato contanti dalla banca", systemImage: "arrow.down.to.line")
                    }
                    Button { kind = "versamento"; showMove = true } label: {
                        Label("Ho versato contanti in banca", systemImage: "arrow.up.to.line")
                    }
                }

                Section {
                    NavigationLink { IncomesView() } label: { Label("Entrate e stipendio", systemImage: "arrow.down.circle") }
                    NavigationLink { CardLinkView() } label: { Label("Collega la carta (Apple Pay)", systemImage: "creditcard.and.123") }
                }
            }
            .navigationTitle("Conti")
            .sheet(isPresented: $showMove) { CashMoveEditor(kind: kind, maxCash: cash) }
            .sheet(isPresented: $editBank) { BalanceEditor(isCash: false, current: bank) }
            .sheet(isPresented: $editCash) { BalanceEditor(isCash: true, current: cash) }
        }
    }
}

// MARK: - Banca

struct BankView: View {
    @Query(sort: \Expense.date, order: .reverse) private var all: [Expense]
    @Query private var incomes: [Income]
    @Query private var moves: [SavingsMove]
    @Query private var cashMoves: [CashMove]
    @Query private var accounts: [Account]
    @State private var editBank = false

    private var ledger: Ledger { Ledger(incomes: incomes, expenses: all, moves: moves, cash: cashMoves, account: accounts.first) }
    private var fig: Figures { ledger.figures(for: Date()) }
    private var cardExpenses: [Expense] {
        all.filter { !$0.isCash && Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Disponibile in banca").font(.subheadline).opacity(0.85)
                    Text(eur(fig.left)).font(.system(size: 36, weight: .bold, design: .rounded))
                    if fig.budget > 0 {
                        ProgressView(value: min(max(fig.spent + fig.moved, 0), fig.budget), total: fig.budget).tint(.white)
                    }
                    Text("Risparmi separati: \(eur(ledger.savingsTotal))").font(.footnote).opacity(0.9)
                }
                .foregroundStyle(.white).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Color(hex: "2980B9"), Color(hex: "1B4F72")],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 22))
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)

            Section {
                Button { editBank = true } label: { Label("Modifica saldo in banca", systemImage: "pencil") }
            }

            Section("Questo mese") {
                HStack { Text("In banca a inizio mese"); Spacer(); Text(eur(fig.startAvail)).bold() }
                HStack { Text("Entrate"); Spacer(); Text(eur(fig.incomeNet)).bold() }
                HStack { Text("Spese con carta"); Spacer(); Text(eur(fig.spent)).bold() }
                HStack { Text("Spostati in risparmi e contanti"); Spacer(); Text(eur(fig.moved)).bold() }
            }

            Section("Spese con carta") {
                if cardExpenses.isEmpty { Text("Nessuna spesa con carta questo mese").foregroundStyle(.secondary) }
                ForEach(cardExpenses.prefix(30)) { e in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(e.note.isEmpty ? e.categoryRaw : e.note)
                            Text("\(e.date.formatted(.dateTime.day().month(.abbreviated))) · \(e.categoryRaw)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(eur(e.amount)).bold()
                    }
                }
            }

            Section {
                NavigationLink { IncomesView() } label: { Label("Entrate e stipendio", systemImage: "arrow.down.circle") }
            }
        }
        .navigationTitle("Banca (carta)")
        .sheet(isPresented: $editBank) { BalanceEditor(isCash: false, current: fig.left) }
    }
}

// MARK: - Contanti

struct CashView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Expense.date, order: .reverse) private var all: [Expense]
    @Query(sort: \CashMove.date, order: .reverse) private var cashMoves: [CashMove]
    @Query private var accounts: [Account]
    @State private var kind = "prelievo"
    @State private var showMove = false
    @State private var editCash = false

    private var ledger: Ledger { Ledger(incomes: [], expenses: all, moves: [], cash: cashMoves, account: accounts.first) }
    private var cash: Double { ledger.cashBalance() }
    private var cashExpenses: [Expense] { all.filter { $0.isCash } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Contanti nel portafoglio").font(.subheadline).opacity(0.85)
                    Text(eur(cash)).font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("Le spese pagate in contanti scalano da qui, non dalla banca.").font(.footnote).opacity(0.9)
                }
                .foregroundStyle(.white).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Color(hex: "E67E22"), Color(hex: "A04000")],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 22))
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)

            Section("Aggiorna i contanti") {
                Button { kind = "prelievo"; showMove = true } label: { Label("Prelievo dalla banca", systemImage: "arrow.down.to.line") }
                Button { kind = "versamento"; showMove = true } label: { Label("Versamento in banca", systemImage: "arrow.up.to.line") }
                Button { kind = "ricevuti"; showMove = true } label: { Label("Contanti ricevuti", systemImage: "plus.circle") }
                Button { editCash = true } label: { Label("Modifica saldo contanti", systemImage: "pencil") }
            }

            Section("Spostamenti") {
                if cashMoves.isEmpty { Text("Nessuno spostamento").foregroundStyle(.secondary) }
                ForEach(cashMoves) { m in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(m.note.isEmpty ? cashKindTitle(m.kind) : m.note)
                            Text("\(m.date.formatted(.dateTime.day().month(.abbreviated).year())) · \(cashKindTitle(m.kind))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text((m.amount >= 0 ? "+" : "") + eur(m.amount)).bold()
                            .foregroundStyle(m.amount >= 0 ? Color.green : Color.orange)
                    }
                }.onDelete { idx in idx.map { cashMoves[$0] }.forEach(ctx.delete) }
            }

            Section("Spese in contanti") {
                if cashExpenses.isEmpty { Text("Nessuna spesa in contanti").foregroundStyle(.secondary) }
                ForEach(cashExpenses.prefix(30)) { e in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(e.note.isEmpty ? e.categoryRaw : e.note)
                            Text("\(e.date.formatted(.dateTime.day().month(.abbreviated))) · \(e.categoryRaw)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("-" + eur(e.amount)).bold()
                    }
                }.onDelete { idx in idx.map { cashExpenses[$0] }.forEach(ctx.delete) }
            }
        }
        .navigationTitle("Contanti")
        .sheet(isPresented: $showMove) { CashMoveEditor(kind: kind, maxCash: cash) }
        .sheet(isPresented: $editCash) { BalanceEditor(isCash: true, current: cash) }
    }
}

struct CashMoveEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let kind: String
    let maxCash: Double
    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var error = ""

    private var help: String {
        switch kind {
        case "prelievo": return "I soldi escono dalla banca ed entrano nel portafoglio."
        case "versamento": return "I soldi escono dal portafoglio ed entrano in banca."
        case "ricevuti": return "Contanti che ricevi da fuori, per esempio un regalo. Non toccano la banca."
        default: return "Per allineare il saldo ai contanti che hai davvero. Usa il segno meno per toglierne."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Importo (€)", text: $amountText).keyboardType(.numbersAndPunctuation)
                DatePicker("Data", selection: $date, displayedComponents: .date)
                TextField("Nota (facoltativa)", text: $note)
                Text(help).font(.footnote).foregroundStyle(.secondary)
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .navigationTitle(cashKindTitle(kind)).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") { save() } }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let raw = parseAmount(amountText), raw != 0 else { error = "Inserisci un importo."; return }
        let v = abs(raw)
        switch kind {
        case "prelievo":
            ctx.insert(CashMove(amount: v, date: date, note: note, kind: kind, bank: true))
        case "versamento":
            guard v <= maxCash + 0.005 else { error = "Nel portafoglio hai solo \(eur(maxCash))."; return }
            ctx.insert(CashMove(amount: -v, date: date, note: note, kind: kind, bank: true))
        case "ricevuti":
            ctx.insert(CashMove(amount: v, date: date, note: note, kind: kind, bank: false))
        default:
            ctx.insert(CashMove(amount: raw, date: date, note: note, kind: kind, bank: false))
        }
        dismiss()
    }
}

// MARK: - Modifica dei saldi

/// Si scrive quanto si ha davvero adesso: la differenza corregge il saldo di partenza
/// (saldo iniziale in banca o contanti iniziali), senza toccare spese ed entrate.
struct BalanceEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var incomes: [Income]
    @Query private var accounts: [Account]
    let isCash: Bool
    let current: Double
    @State private var amountText = ""
    @State private var error = ""

    private var diff: Double? { parseAmount(amountText).map { $0 - current } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Importo (€)", text: $amountText).keyboardType(.numbersAndPunctuation)
                } header: {
                    Text(isCash ? "Contanti che hai adesso" : "Soldi in banca adesso")
                } footer: {
                    Text("Scrivi l'importo reale: l'app corregge da sola la differenza. Spese ed entrate già inserite restano come sono.")
                }
                HStack { Text("Saldo nell'app"); Spacer(); Text(eur(current)).foregroundStyle(.secondary) }
                if let d = diff, abs(d) >= 0.005 {
                    HStack { Text("Differenza"); Spacer(); Text((d > 0 ? "+" : "") + eur(d)).bold() }
                }
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .navigationTitle(isCash ? "Modifica contanti" : "Modifica saldo banca")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") { save() } }
            }
            .onAppear { amountText = String(format: "%.2f", current).replacingOccurrences(of: ".", with: ",") }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let d = diff else { error = "Inserisci un importo valido."; return }
        guard let a = accounts.first else { dismiss(); return }
        if abs(d) >= 0.005 {
            if isCash {
                a.cashStart += d
            } else if let i = incomes.first(where: { $0.kind == initialKind }) {
                i.amount += d
            } else {
                ctx.insert(Income(amount: d, saved: 0, kind: initialKind, date: a.startDate, note: "Saldo iniziale"))
            }
            try? ctx.save()
        }
        dismiss()
    }
}

// MARK: - Collegamento della carta con Apple Pay

struct CardLinkView: View {
    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.footnote.bold()).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Theme.accent, in: Circle())
            Text(text).font(.subheadline)
        }
    }

    var body: some View {
        List {
            Section {
                Text("Le spese pagate con Apple Pay possono entrare da sole nell'app, senza collegare la banca. Si imposta una volta sola con l'app Comandi rapidi.")
                    .font(.subheadline)
            }
            Section("Come si imposta") {
                step(1, "Apri Comandi rapidi e vai nella scheda Automazione.")
                step(2, "Tocca + e scegli Transazione.")
                step(3, "Seleziona la tua carta (o più carte) e scegli Esegui immediatamente.")
                step(4, "Tocca Nuovo comando rapido e aggiungi l'azione Aggiungi spesa, che trovi sotto Spese.")
                step(5, "Nell'azione, come Importo scegli la variabile Importo e come Esercente la variabile Esercente. Come Pagamento lascia Carta.")
                step(6, "Salva. Da ora, ogni pagamento con Apple Pay con quella carta viene registrato e ricevi una notifica.")
                Link(destination: URL(string: "shortcuts://")!) { Label("Apri Comandi rapidi", systemImage: "arrow.up.forward.app") }
            }
            Section("Cosa funziona e cosa no") {
                Text("Funzionano i pagamenti con Apple Pay con la carta scelta. Non vengono registrati i pagamenti con la carta fisica, online con il numero della carta, i bonifici e gli addebiti diretti: quelli vanno inseriti a mano.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("La categoria viene scelta dal nome dell'esercente (per esempio Conad diventa Alimentari). Se non è riconosciuto va in Altro e puoi cambiarla toccando la spesa.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("I nomi delle voci in Comandi rapidi possono cambiare leggermente a seconda della versione di iOS.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Collega la carta")
    }
}
