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
    @Query private var payments: [TripPayment]
    @State private var kind = "prelievo"
    @State private var showMove = false
    @State private var editingIncome: Income?
    @State private var showBank = false
    @State private var showCash = false

    private var ledger: Ledger { Ledger(incomes: incomes, expenses: all, moves: moves, cash: cashMoves, account: accounts.first, payments: payments) }
    private var bank: Double { ledger.figures(for: Date()).left }
    private var cash: Double { ledger.cashBalance() }

    /// Riquadro bianco di Banca o Contanti: icona, nome, importo e freccia.
    private func moneyCard(_ icon: String, _ title: String, _ subtitle: String?, _ value: Double, _ color: Color,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: icon).font(.body).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(color, in: Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).font(.body).lineLimit(1).minimumScaleFactor(0.8)
                        if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
                HStack {
                    Text(eur(value)).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
            .padding(14).frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)\(subtitle.map { " \($0)" } ?? ""), \(eur(value))")
        .accessibilityAddTraits(.isButton)
    }

    /// Riga con icona verde, testo e freccia (come le voci di un menu).
    private func menuRow(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(HeroStyle.bottom).frame(width: 28)
            Text(title).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TOTALE ATTIVO").font(.subheadline.weight(.medium)).tracking(0.5).opacity(0.75)
                        Text(eur(bank + cash)).font(.system(size: 40, weight: .bold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("Banca e contanti insieme. Tocca una voce per i dettagli.").font(.subheadline).opacity(0.9)
                            .padding(.top, 14)
                    }
                    .foregroundStyle(.white).padding(22).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [HeroStyle.top, HeroStyle.bottom],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 24))
                    .shadow(color: HeroStyle.bottom.opacity(0.25), radius: 12, y: 6)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)

                Section("Dove sono i tuoi soldi") {
                    HStack(spacing: 12) {
                        moneyCard("creditcard", "Banca (carta)", nil, bank, Color(hex: "2980B9")) { showBank = true }
                        moneyCard("banknote", "Contanti", "(portafoglio)", cash, Color(hex: "E67E22")) { showCash = true }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                let months = salaryMonths(incomes)
                Section {
                    if months.isEmpty {
                        Text("Nessuno stipendio registrato. Si aggiunge da solo ogni mese se l'hai impostato, oppure da Entrate e stipendio.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    SalaryRows(months: Array(months.prefix(6)), editing: $editingIncome)
                    if months.count > 6 {
                        NavigationLink { SalaryHistoryView() } label: { Text("Tutti gli stipendi (\(months.count))") }
                    }
                } header: {
                    HStack {
                        Text("Stipendi ricevuti")
                        Spacer()
                        if !months.isEmpty { Text("media \(eur(salaryAverage(months)))").textCase(nil) }
                    }
                }

                Section("Spostamenti") {
                    Button { kind = "prelievo"; showMove = true } label: { menuRow("Ho prelevato contanti dalla banca", "arrow.down.to.line") }
                    Button { kind = "versamento"; showMove = true } label: { menuRow("Ho versato contanti in banca", "arrow.up.to.line") }
                }

                Section {
                    NavigationLink { IncomesView() } label: {
                        Label { Text("Entrate e stipendio") } icon: { Image(systemName: "arrow.down.circle").foregroundStyle(Theme.accent) }
                    }
                    NavigationLink { InstallmentsView() } label: {
                        Label { Text("Pagamenti a rate") } icon: { Image(systemName: "calendar.badge.clock").foregroundStyle(Theme.accent) }
                    }
                    NavigationLink { CardLinkView() } label: {
                        Label { Text("Collega la carta (Apple Pay)") } icon: { Image(systemName: "creditcard.and.123").foregroundStyle(Theme.accent) }
                    }
                    NavigationLink { ApplePayLogView() } label: {
                        Label { Text("Registro pagamenti") } icon: { Image(systemName: "list.bullet.clipboard").foregroundStyle(Theme.accent) }
                    }
                }
            }
            .navigationTitle("Conti").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showBank) { BankView() }
            .navigationDestination(isPresented: $showCash) { CashView() }
            .sheet(isPresented: $showMove) { CashMoveEditor(kind: kind, maxCash: cash) }
            .sheet(item: $editingIncome) { AddIncomeView(editing: $0) }
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
    @Query private var payments: [TripPayment]
    @State private var editBank = false

    private var ledger: Ledger { Ledger(incomes: incomes, expenses: all, moves: moves, cash: cashMoves, account: accounts.first, payments: payments) }
    private var fig: Figures { ledger.figures(for: Date()) }
    private var cardExpenses: [Expense] {
        all.filter { !$0.isCash && $0.paidByMe && Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }
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
    @Query private var payments: [TripPayment]
    @State private var kind = "prelievo"
    @State private var showMove = false
    @State private var editCash = false

    private var ledger: Ledger { Ledger(incomes: [], expenses: all, moves: [], cash: cashMoves, account: accounts.first, payments: payments) }
    private var cash: Double { ledger.cashBalance() }
    private var cashExpenses: [Expense] { all.filter { $0.isCash && $0.paidByMe } }

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
                }.onDelete { idx in idx.map { cashExpenses[$0] }.forEach { deleteExpense($0, ctx: ctx) } }
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
    @AppStorage(applePayNotifyKey) private var notifyOn = false

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
                Text("Paghi con Apple Pay e la spesa entra da sola nell'app, in silenzio: niente notifiche, niente da confermare. L'azione \"Aggiungi spesa\" è già pronta in Comandi rapidi, devi solo collegarla alla carta una volta (circa un minuto).")
                    .font(.subheadline)
                Link(destination: URL(string: "shortcuts://")!) {
                    Label("Apri Comandi rapidi", systemImage: "arrow.up.forward.app").bold()
                }
            }
            Section("Come si collega (una volta sola)") {
                step(1, "In Comandi rapidi apri la scheda Automazione e tocca + (o Nuova automazione).")
                step(2, "Scegli Transazione, seleziona la tua carta e lascia tutte le categorie.")
                step(3, "Scegli Esegui immediatamente e spegni Notifica quando eseguito. Tocca Avanti.")
                step(4, "Tocca Nuovo comando rapido vuoto, poi Aggiungi azione: cerca Spese e scegli Aggiungi spesa.")
                step(5, "Tocca Importo e scegli Input comando rapido, poi tocca la variabile e scegli Importo. Fai lo stesso con Esercente scegliendo Esercente.")
                step(6, "Tocca Fine. Da ora ogni pagamento con Apple Pay con quella carta viene registrato da solo.")
            }
            Section {
                Toggle("Avvisami quando una spesa arriva da Apple Pay", isOn: $notifyOn)
            } footer: {
                Text("Spento: la spesa viene registrata senza nessun avviso. La trovi nell'elenco quando apri l'app.")
            }
            Section("Dalle email della banca") {
                Text("Se la banca ti manda un'email per ogni movimento, l'app può leggerla da sola: pagamenti con carta (anche online), bonifici ricevuti e prelievi. Serve che l'account email sia aggiunto nell'app Mail di iPhone.")
                    .font(.subheadline)
                step(1, "In Comandi rapidi apri Automazione, tocca + e scegli Email.")
                step(2, "In Mittente scegli l'indirizzo della banca (per Intesa Sanpaolo: comunicazioni@intesasanpaolo.com). Lascia vuoti gli altri campi.")
                step(3, "Scegli Esegui immediatamente e spegni Notifica quando eseguito. Tocca Avanti.")
                step(4, "Tocca Nuovo comando rapido vuoto, poi Aggiungi azione: cerca Spese e scegli Leggi email della banca.")
                step(5, "Tocca Testo e scegli Input comando rapido, poi tocca la variabile e scegli Contenuto (o Corpo). Tocca la freccia, poi Oggetto e scegli allo stesso modo Oggetto.")
                step(6, "Tocca Fine. Le email che non parlano di soldi vengono ignorate.")
            }
            Section("Cosa funziona e cosa no") {
                Text("Funzionano i pagamenti con Apple Pay con la carta scelta. Non vengono registrati i pagamenti con la carta fisica, online con il numero della carta, i bonifici e gli addebiti diretti: per quelli usa le email della banca (sopra) o inseriscili a mano. Com'è andato ogni pagamento lo vedi in Conti → Registro pagamenti.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("La categoria viene scelta dal nome dell'esercente (per esempio Conad diventa Alimentari). Se non è riconosciuto va in Altro e puoi cambiarla toccando la spesa.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Apple non permette alle app di creare da sole l'automazione: per questo il collegamento alla carta va fatto a mano una volta. I nomi delle voci possono cambiare un po' tra le versioni di iOS.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Collega Apple Pay")
    }
}
