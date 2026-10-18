import SwiftUI
import SwiftData
import PhotosUI

private func money(_ v: Double, _ code: String) -> String { v.formatted(.currency(code: code)) }
private func dayText(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated)) }

// MARK: - Elenco dei viaggi

struct TripsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @Query private var all: [Expense]
    @State private var adding = false
    @State private var toDelete: Trip?

    private func myTotal(_ t: Trip) -> Double { all.filter { $0.tripID == t.uid }.reduce(0) { $0 + $1.myAmount } }

    var body: some View {
        List {
            if trips.isEmpty {
                Text("Nessun viaggio. Tocca + per crearne uno: scegli la valuta del paese, le date e con chi viaggi.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(trips) { t in
                NavigationLink { TripDetailView(trip: t) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: t.contains(Date()) ? "airplane.departure" : "airplane")
                            .foregroundStyle(.white).frame(width: 34, height: 34).background(Theme.accent, in: Circle())
                        VStack(alignment: .leading) {
                            Text(t.name)
                            Text("\(dayText(t.startDate)) – \(dayText(t.endDate)) · \(t.currency)" + (t.people.isEmpty ? "" : " · \(t.people.count + 1) persone"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(eur(myTotal(t))).bold()
                    }
                }
            }
            .onDelete { idx in toDelete = idx.map { trips[$0] }.first }
        }
        .navigationTitle("Viaggi")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nuovo viaggio") }
        .sheet(isPresented: $adding) { TripEditor(trip: nil) }
        .confirmationDialog("Eliminare il viaggio? Le spese restano nell'elenco come spese normali.",
                            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Elimina viaggio", role: .destructive) {
                if let t = toDelete {
                    for e in all where e.tripID == t.uid { e.tripID = "" }
                    ctx.delete(t)
                    try? ctx.save()
                }
                toDelete = nil
            }
        }
    }
}

// MARK: - Nuovo viaggio / modifica

struct TripEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let trip: Trip?
    @State private var name = ""
    @State private var currency = "EUR"
    @State private var otherCode = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(6 * 86400)
    @State private var budgetText = ""
    @State private var countInStats = true   // le spese del viaggio si pagano con lo stipendio: contano nel periodo
    @State private var people: [String] = []
    @State private var newPerson = ""

    private var code: String {
        currency == "ALTRA" ? otherCode.uppercased().filter(\.isLetter).prefix(3).description : currency
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome (es. Londra 2026)", text: $name)
                    Picker("Valuta del paese", selection: $currency) {
                        ForEach(Rates.currencies, id: \.self) { c in Text(c == "EUR" ? "EUR (euro)" : c).tag(c) }
                        Text("Altra").tag("ALTRA")
                    }
                    if currency == "ALTRA" {
                        TextField("Codice valuta (es. MAD)", text: $otherCode).textInputAutocapitalization(.characters)
                        Text("Per questa valuta il cambio va scritto a mano quando inserisci una spesa.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    DatePicker("Dal", selection: $start, displayedComponents: .date)
                    DatePicker("Al", selection: $end, in: start..., displayedComponents: .date)
                    TextField("Budget del viaggio in € (facoltativo)", text: $budgetText).keyboardType(.decimalPad)
                }
                Section {
                    ForEach(people, id: \.self) { p in Label(p, systemImage: "person") }
                        .onDelete { people.remove(atOffsets: $0) }
                    HStack {
                        TextField("Nome di chi viaggia con te", text: $newPerson)
                        Button("Aggiungi") { addPerson() }.disabled(newPerson.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Compagni di viaggio")
                } footer: {
                    Text("Servono per dividere le spese. Se viaggi da solo lascia vuoto.")
                }
                Section {
                    Toggle("Conta nelle statistiche e nei limiti", isOn: $countInStats)
                } footer: {
                    Text("Le spese che paghi tu scalano sempre dal saldo. Spento: non entrano in grafici, limiti per categoria e riepiloghi, così il viaggio resta a parte.")
                }
            }
            .navigationTitle(trip == nil ? "Nuovo viaggio" : "Modifica viaggio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") { save() } }
            }
            .onAppear {
                guard let t = trip else { return }
                name = t.name; start = t.startDate; end = t.endDate
                if Rates.currencies.contains(t.currency) { currency = t.currency } else { currency = "ALTRA"; otherCode = t.currency }
                budgetText = t.budget > 0 ? String(t.budget) : ""
                countInStats = t.countInStats; people = t.people
            }
        }
    }

    private func addPerson() {
        let n = newPerson.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != me, !people.contains(n) else { newPerson = ""; return }
        people.append(n); newPerson = ""
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, code.count == 3 else { return }
        addPerson()
        let t = trip ?? Trip(name: n, currency: code, startDate: start, endDate: end)
        t.name = n; t.currency = code; t.startDate = Calendar.current.startOfDay(for: start)
        t.endDate = Calendar.current.startOfDay(for: max(end, start))
        t.budget = parseAmount(budgetText) ?? 0
        t.countInStats = countInStats
        t.people = people
        if trip == nil { ctx.insert(t) }
        try? ctx.save()
        dismiss()
    }
}

// MARK: - Dettaglio del viaggio

struct TripDetailView: View {
    @Environment(\.modelContext) private var ctx
    let trip: Trip
    @Query(sort: \Expense.date, order: .reverse) private var all: [Expense]
    @Query(sort: \TripPayment.date, order: .reverse) private var allPayments: [TripPayment]
    @Query(sort: \CategoryItem.order) private var cats: [CategoryItem]
    @State private var adding = false
    @State private var editingTrip = false
    @State private var editing: Expense?
    @State private var settling: Transfer?
    @State private var viewing: UIImage?

    private var expenses: [Expense] { all.filter { $0.tripID == trip.uid } }
    private var payments: [TripPayment] { allPayments.filter { $0.tripID == trip.uid } }
    private var groupTotal: Double { expenses.reduce(0) { $0 + $1.amount } }
    private var myTotal: Double { expenses.reduce(0) { $0 + $1.myAmount } }
    private var transfers: [Transfer] { settleUp(tripBalances(expenses: expenses, payments: payments)) }
    private var days: Int {
        let cal = Calendar.current
        let last = min(cal.startOfDay(for: Date()), cal.startOfDay(for: trip.endDate))
        return max((cal.dateComponents([.day], from: cal.startOfDay(for: trip.startDate), to: last).day ?? 0) + 1, 1)
    }
    private var byCategory: [CategoryAmount] {
        Dictionary(grouping: expenses, by: \.categoryRaw)
            .map { CategoryAmount(name: $0.key, total: $0.value.reduce(0) { $0 + $1.myAmount }) }
            .filter { $0.total > 0 }.sorted { $0.total > $1.total }
    }
    private func label(_ n: String) -> String { n == me ? "Tu" : n }
    private func catColor(_ n: String) -> Color { cats.first { $0.name == n }.map { Color(hex: $0.colorHex) } ?? tripBlue }
    /// La mia parte nella valuta locale (con il cambio di ogni spesa).
    private var localTotal: Double {
        var sum = 0.0
        for e in expenses {
            let r = e.originalCurrency == trip.currency && e.rate > 0 ? e.rate : trip.lastRate
            sum += e.myAmount * r
        }
        return sum
    }

    private var shareText: String {
        var lines = ["✈︎ \(trip.name) – conti del viaggio", "Totale: \(eur(groupTotal))"]
        if transfers.isEmpty { lines.append("Siamo pari!") }
        for t in transfers { lines.append("\(t.from == me ? "Io" : t.from) deve \(eur(t.amount)) a \(t.to == me ? "me" : t.to)") }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(dayText(trip.startDate)) – \(dayText(trip.endDate))").font(.subheadline).opacity(0.85)
                    Text(eur(myTotal)).font(.system(size: 36, weight: .bold, design: .rounded))
                    Text(trip.people.isEmpty ? "spesi in \(expenses.count) spese" : "la tua parte · totale del gruppo \(eur(groupTotal))")
                        .font(.footnote).opacity(0.9)
                    if trip.isForeign && localTotal > 0 {
                        Text("≈ \(money(localTotal, trip.currency)) nella valuta locale").font(.footnote).opacity(0.9)
                    }
                    Text("Media \(eur(myTotal / Double(days))) al giorno").font(.footnote).opacity(0.9)
                    if trip.budget > 0 {
                        ProgressView(value: min(myTotal, trip.budget), total: trip.budget).tint(.white)
                        Text(myTotal <= trip.budget ? "Restano \(eur(trip.budget - myTotal)) del budget di \(eur(trip.budget))"
                                                    : "Budget superato di \(eur(myTotal - trip.budget))").font(.footnote).bold()
                    }
                }
                .foregroundStyle(.white).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Color(hex: "2980B9"), Color(hex: "1B4F72")], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 22))
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)

            if !trip.people.isEmpty {
                Section {
                    if transfers.isEmpty { Text("Siete pari: nessuno deve soldi.").foregroundStyle(.secondary) }
                    // In grande quello che riguarda me, con le spese da cui viene.
                    ForEach(transfers.filter { $0.from == me || $0.to == me }) { t in
                        let other = t.from == me ? t.to : t.from
                        VStack(alignment: .leading, spacing: 6) {
                            Text(t.from == me ? "Devi \(eur(t.amount)) a \(other)" : "\(other) ti deve \(eur(t.amount))")
                                .font(.title3.bold()).foregroundStyle(t.from == me ? Color.orange : Theme.accent)
                            DisclosureGroup("Da dove viene") {
                                ForEach(tripDebtLines(expenses, with: other), id: \.expense.persistentModelID) { l in
                                    HStack {
                                        Text(l.expense.note.isEmpty ? l.expense.categoryRaw : l.expense.note).lineLimit(1)
                                        Spacer()
                                        Text(l.amount > 0 ? "devi \(eur(l.amount))" : "ti deve \(eur(-l.amount))")
                                            .foregroundStyle(l.amount > 0 ? Color.orange : Theme.accent)
                                    }
                                    .font(.footnote)
                                }
                            }
                            .font(.footnote)
                        }
                        .padding(.vertical, 4)
                    }
                    ForEach(transfers) { t in
                        HStack {
                            Text("\(label(t.from)) → \(label(t.to))")
                            Spacer()
                            Text(eur(t.amount)).bold()
                            Button("Saldato") { settling = t }.buttonStyle(.bordered).font(.caption)
                        }
                    }
                    ShareLink(item: shareText) { Label("Manda il riepilogo (WhatsApp…)", systemImage: "square.and.arrow.up") }
                } header: {
                    Text("Chi deve a chi")
                } footer: {
                    Text("\"Saldato\" registra il rimborso: se riguarda te, i soldi entrano o escono dal tuo saldo.")
                }
            }

            if !byCategory.isEmpty {
                Section("Dove sono andati i soldi (la tua parte)") {
                    let top = byCategory.first?.total ?? 1
                    ForEach(byCategory) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(c.name); Spacer(); Text(eur(c.total)).bold() }
                            ProgressView(value: c.total, total: max(top, 0.01)).tint(catColor(c.name))
                        }
                    }
                    if let big = expenses.max(by: { $0.myAmount < $1.myAmount }) {
                        LabeledContent("La spesa più cara", value: "\(big.note.isEmpty ? big.categoryRaw : big.note) · \(eur(big.myAmount))")
                            .font(.footnote)
                    }
                }
            }

            let photos = expenses.filter { $0.receipt != nil }
            if !photos.isEmpty {
                Section("Scontrini e foto") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(photos) { e in
                                if let d = e.receipt, let img = UIImage(data: d) {
                                    Button { viewing = img } label: {
                                        Image(uiImage: img).resizable().scaledToFill().frame(width: 70, height: 90)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .accessibilityLabel("Foto di \(e.note.isEmpty ? e.categoryRaw : e.note)")
                                }
                            }
                        }
                    }
                }
            }

            Section("Spese del viaggio") {
                if expenses.isEmpty { Text("Ancora nessuna spesa. Tocca + per aggiungerne una.").foregroundStyle(.secondary) }
                ForEach(expenses) { e in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(e.note.isEmpty ? e.categoryRaw : e.note)
                            Text("\(dayText(e.date)) · \(e.categoryRaw)" + (e.paidByMe ? "" : " · pagato da \(e.paidBy)")
                                 + (e.shares.count > 1 ? " · divisa in \(e.shares.count)" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(eur(e.amount)).bold()
                            if !e.originalCurrency.isEmpty {
                                Text(money(e.originalAmount, e.originalCurrency)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = e }
                }
                .onDelete { idx in idx.map { expenses[$0] }.forEach(ctx.delete); try? ctx.save() }
            }

            if !payments.isEmpty {
                Section("Rimborsi registrati") {
                    ForEach(payments) { p in
                        HStack {
                            Text("\(label(p.from)) → \(label(p.to))")
                            Spacer()
                            Text(eur(p.amount))
                        }
                    }
                    .onDelete { idx in idx.map { payments[$0] }.forEach(ctx.delete); try? ctx.save() }
                }
            }
        }
        .navigationTitle(trip.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Modifica") { editingTrip = true } }
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Aggiungi spesa")
            }
        }
        .sheet(isPresented: $adding) { TripExpenseEditor(trip: trip, editing: nil) }
        .sheet(item: $editing) { TripExpenseEditor(trip: trip, editing: $0) }
        .sheet(isPresented: $editingTrip) { TripEditor(trip: trip) }
        .sheet(isPresented: Binding(get: { viewing != nil }, set: { if !$0 { viewing = nil } })) {
            if let viewing { ReceiptViewer(image: viewing) }
        }
        .confirmationDialog(settling.map { "\(label($0.from)) ha dato \(eur($0.amount)) a \(label($0.to))?" } ?? "",
                            isPresented: Binding(get: { settling != nil }, set: { if !$0 { settling = nil } }),
                            titleVisibility: .visible) {
            if let t = settling {
                if t.from == me || t.to == me {
                    Button("Sì, con carta / bonifico") { settle(t, method: "carta") }
                    Button("Sì, in contanti") { settle(t, method: "contanti") }
                } else {
                    Button("Sì, segna come saldato") { settle(t, method: "carta") }
                }
            }
            Button("Annulla", role: .cancel) { settling = nil }
        }
    }

    private func settle(_ t: Transfer, method: String) {
        let p = TripPayment(tripID: trip.uid, from: t.from, to: t.to, amount: t.amount, date: Date())
        p.method = method
        ctx.insert(p)
        try? ctx.save()
        settling = nil
    }
}

// MARK: - Spesa del viaggio (valuta locale e divisione)

struct TripExpenseEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryItem.order) private var cats: [CategoryItem]
    let trip: Trip
    let editing: Expense?

    @State private var amountText = ""
    @State private var inLocal = true
    @State private var rateText = ""
    @State private var rateInfo = ""
    @State private var catName = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var payer = me
    @State private var method = "carta"
    @State private var participants: Set<String> = []
    @State private var custom = false
    @State private var customTexts: [String: String] = [:]
    @State private var error = ""
    @State private var receipt: Data?            // foto dello scontrino (o del locale)
    @State private var photoItem: PhotosPickerItem?
    @State private var showScanner = false
    @State private var showReceipt = false

    private var rate: Double? { parseAmount(rateText).flatMap { $0 > 0 ? $0 : nil } }
    private var entered: Double? { parseAmount(amountText).flatMap { $0 > 0 ? $0 : nil } }
    /// Importo in euro.
    private var euro: Double? {
        guard let a = entered else { return nil }
        if inLocal && trip.isForeign { return rate.map { (a / $0 * 100).rounded() / 100 } }
        return a
    }
    private var chosen: [String] { trip.everyone.filter { participants.contains($0) } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if trip.isForeign {
                        Picker("Valuta", selection: $inLocal) {
                            Text(trip.currency).tag(true)
                            Text("EUR").tag(false)
                        }.pickerStyle(.segmented)
                    }
                    TextField("Importo (\(inLocal && trip.isForeign ? trip.currency : "€"))", text: $amountText).keyboardType(.decimalPad)
                    if inLocal && trip.isForeign {
                        HStack {
                            Text("1 € =")
                            TextField("cambio", text: $rateText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            Text(trip.currency)
                        }
                        if !rateInfo.isEmpty { Text(rateInfo).font(.footnote).foregroundStyle(.secondary) }
                        if let e = euro { HStack { Text("In euro"); Spacer(); Text(eur(e)).bold() } }
                    }
                    Picker("Categoria", selection: $catName) {
                        ForEach(cats) { c in Label(c.name, systemImage: c.icon).tag(c.name) }
                    }
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                    TextField("Nota (facoltativa)", text: $note)
                }

                if !trip.people.isEmpty {
                    Section {
                        Picker("Ha pagato", selection: $payer) {
                            ForEach(trip.everyone, id: \.self) { p in Text(p == me ? "Io" : p).tag(p) }
                        }
                        ForEach(trip.everyone, id: \.self) { p in
                            Toggle(p == me ? "Io" : p, isOn: Binding(
                                get: { participants.contains(p) },
                                set: { on in if on { participants.insert(p) } else { participants.remove(p) } }))
                        }
                        Toggle("Importi diversi", isOn: $custom)
                        if custom {
                            ForEach(chosen, id: \.self) { p in
                                HStack {
                                    Text(p == me ? "Io" : p)
                                    TextField("€", text: Binding(get: { customTexts[p] ?? "" }, set: { customTexts[p] = $0 }))
                                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                }
                            }
                        } else if let e = euro, !chosen.isEmpty {
                            Text("\(eur(e / Double(chosen.count))) a testa").font(.footnote).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Chi ha pagato e tra chi dividere")
                    } footer: {
                        Text("Gli importi diversi sono in euro e devono sommare il totale.")
                    }
                }

                if payer == me {
                    Section("Pagato con") {
                        Picker("Pagato con", selection: $method) {
                            Text("Carta").tag("carta"); Text("Contanti").tag("contanti")
                        }.pickerStyle(.segmented)
                    }
                }
                Section("Scontrino") {
                    if let receipt, let img = UIImage(data: receipt) {
                        Button { showReceipt = true } label: {
                            Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 8)).frame(maxWidth: .infinity)
                        }
                        .accessibilityLabel("Foto dello scontrino, tocca per ingrandire")
                        Button("Rimuovi la foto", role: .destructive) { self.receipt = nil }
                    }
                    Button { showScanner = true } label: {
                        Label(receipt == nil ? "Scatta foto" : "Rifai la foto", systemImage: "camera")
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Scegli dalla galleria", systemImage: "photo")
                    }
                }
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                        receipt = await Task.detached { compressReceipt(img) }.value
                    }
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScanner { imgs in
                    let first = imgs.first
                    Task { receipt = await Task.detached { compressReceipt(first) }.value }
                }.ignoresSafeArea()
            }
            .sheet(isPresented: $showReceipt) {
                if let receipt, let img = UIImage(data: receipt) { ReceiptViewer(image: img) }
            }
            .navigationTitle(editing == nil ? "Spesa del viaggio" : "Modifica spesa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salva") { save() } }
            }
            .onAppear(perform: load)
            .task { await loadRate() }
        }
    }

    private func load() {
        // Spesa nuova: di partenza è solo mia; chi la divide accende gli altri.
        participants = [me]
        inLocal = trip.isForeign
        catName = cats.first?.name ?? "Altro"
        date = trip.contains(Date()) ? Date() : trip.startDate
        if trip.lastRate > 0 { rateText = String(format: "%.4f", trip.lastRate).replacingOccurrences(of: ".", with: ",") }
        guard let e = editing else { return }
        catName = e.categoryRaw; date = e.date; note = e.note; method = e.method; payer = e.payer
        receipt = e.receipt
        if !e.originalCurrency.isEmpty {
            inLocal = true
            amountText = String(e.originalAmount).replacingOccurrences(of: ".", with: ",")
            rateText = String(format: "%.4f", e.rate).replacingOccurrences(of: ".", with: ",")
        } else {
            inLocal = false
            amountText = String(e.amount).replacingOccurrences(of: ".", with: ",")
        }
        let s = e.shares
        if !s.isEmpty {
            participants = Set(s.keys)
            let eq = equalShares(e.amount, among: trip.everyone.filter { s[$0] != nil })
            custom = eq != s
            customTexts = s.mapValues { String(format: "%.2f", $0).replacingOccurrences(of: ".", with: ",") }
        } else {
            participants = [me]
        }
    }

    /// Cambio automatico (BCE), solo per una spesa nuova: il campo resta modificabile a mano.
    private func loadRate() async {
        guard trip.isForeign, editing == nil else { return }
        if let r = await Rates.rate(for: trip.currency) {
            rateText = String(format: "%.4f", r).replacingOccurrences(of: ".", with: ",")
            let d = (UserDefaults.standard.object(forKey: Rates.cacheDateKey) as? Date).map { $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
            rateInfo = "Cambio della Banca Centrale Europea\(d.isEmpty ? "" : " (\(d))"). Puoi correggerlo."
        } else if trip.lastRate > 0 {
            rateInfo = "Senza connessione: uso l'ultimo cambio salvato. Puoi correggerlo."
        } else {
            rateInfo = "Cambio non disponibile: scrivilo a mano (quanti \(trip.currency) vale 1 €)."
        }
    }

    private func save() {
        guard let e = euro, e > 0 else {
            error = inLocal && trip.isForeign && rate == nil ? "Scrivi il cambio." : "Inserisci un importo."
            return
        }
        var shares: [String: Double] = [:]
        if !trip.people.isEmpty {
            guard !chosen.isEmpty else { error = "Scegli almeno una persona tra cui dividere."; return }
            if custom {
                for p in chosen { shares[p] = parseAmount(customTexts[p] ?? "") ?? 0 }
                let sum = shares.values.reduce(0, +)
                guard abs(sum - e) < 0.011 else { error = "Gli importi sommano \(eur(sum)), ma la spesa è \(eur(e))."; return }
            } else {
                shares = equalShares(e, among: chosen)
            }
            if payer == me && shares.keys.sorted() == [me] { shares = [:] }   // solo mia: nessuna divisione
        }
        let x = editing ?? Expense(amount: e, categoryName: catName, date: date, note: note)
        x.amount = e; x.categoryRaw = catName; x.date = date; x.note = note
        x.tripID = trip.uid
        if x.receipt != receipt { x.receipt = receipt }
        x.paidBy = payer == me ? "" : payer
        x.method = payer == me ? method : "carta"
        if inLocal && trip.isForeign, let a = entered, let r = rate {
            x.originalAmount = a; x.originalCurrency = trip.currency; x.rate = r
            trip.lastRate = r
        } else {
            x.originalAmount = 0; x.originalCurrency = ""; x.rate = 0
        }
        x.shares = shares
        if editing == nil { ctx.insert(x) }
        try? ctx.save()
        dismiss()
    }
}

// MARK: - Viaggio in Home

let tripBlue = Color(hex: "2D7FB8")
let tripBlueDark = Color(hex: "1B5C8C")

/// Etichetta azzurra delle spese di un viaggio nell'elenco della Home.
struct TripBadge: View {
    let name: String
    var body: some View {
        Label(name, systemImage: "airplane")
            .font(.caption).foregroundStyle(tripBlue).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(tripBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Quanto ho speso per un viaggio: nei giorni del viaggio e in tutto (voli, hotel e prenotazioni pagati prima compresi).
func tripTotals(_ trip: Trip, _ expenses: [Expense]) -> (here: Double, total: Double) {
    let mine = expenses.filter { $0.tripID == trip.uid }
    return (mine.filter { trip.contains($0.date) }.reduce(0) { $0 + $1.myAmount }, mine.reduce(0) { $0 + $1.myAmount })
}

/// Riquadro del viaggio in corso: giorno, speso, cambio di oggi e totale della vacanza.
struct TripHomeCard: View {
    let trip: Trip
    let expenses: [Expense]
    @State private var rate: Double = 0

    var body: some View {
        let t = tripTotals(trip, expenses)
        let cal = Calendar.current
        let days = (cal.dateComponents([.day], from: cal.startOfDay(for: trip.startDate), to: cal.startOfDay(for: trip.endDate)).day ?? 0) + 1
        let today = min((cal.dateComponents([.day], from: cal.startOfDay(for: trip.startDate), to: cal.startOfDay(for: Date())).day ?? 0) + 1, days)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(trip.name, systemImage: "airplane").font(.headline).lineLimit(1)
                    Text("\(dayText(trip.startDate)) – \(dayText(trip.endDate)) · giorno \(today) di \(days)").font(.caption).opacity(0.85)
                    Text("Speso **\(eur(t.here))**").font(.caption)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    if trip.isForeign && rate > 0 {
                        Text("1 € = \(rate.formatted(.number.precision(.fractionLength(2)))) \(trip.currency)")
                            .font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 2)
                            .background(.white.opacity(0.2), in: Capsule())
                    }
                    Text("Totale vacanza").font(.caption2).opacity(0.85)
                    Text(eur(t.total)).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            if trip.budget > 0 {
                ProgressView(value: min(t.total, trip.budget), total: trip.budget).tint(.white)
                Text(t.total <= trip.budget ? "Restano \(eur(trip.budget - t.total)) del budget" : "Budget superato di \(eur(t.total - trip.budget))")
                    .font(.caption)
            }
        }
        .foregroundStyle(.white).padding(.vertical, 4)
        .task(id: trip.currency) {
            // Cambio di oggi della BCE; senza rete resta l'ultimo usato nel viaggio.
            rate = trip.lastRate
            if trip.isForeign, let r = await Rates.rate(for: trip.currency) { rate = r }
        }
    }
}

/// Prova prezzi: scrivi un prezzo nella moneta del viaggio e vedi subito quanto costa in euro. Non registra nulla.
struct TripPriceCheck: View {
    let trip: Trip
    @State private var text = ""
    @State private var rate: Double = 0
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "dollarsign.arrow.circlepath").foregroundStyle(tripBlue)
            HStack(spacing: 4) {
                TextField("Prezzo", text: $text).keyboardType(.decimalPad).focused($focused)
                Text(trip.currency).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tripBlue.opacity(0.6)))
            Text("=").foregroundStyle(.secondary)
            Text(priceInEuro(text, rate: rate).map(eur) ?? "– €")
                .font(.headline).foregroundStyle(tripBlue).lineLimit(1).minimumScaleFactor(0.7)
                .frame(minWidth: 80, alignment: .trailing)
        }
        .accessibilityElement(children: .contain)
        .toolbar {
            if focused { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Fine") { focused = false } } }
        }
        .task(id: trip.currency) {
            rate = trip.lastRate
            if let r = await Rates.rate(for: trip.currency) { rate = r }
        }
    }
}

/// Quanto vale in euro un prezzo scritto nella moneta del viaggio (1 € = rate). nil se manca qualcosa.
func priceInEuro(_ text: String, rate: Double) -> Double? {
    guard rate > 0, let a = parseAmount(text), a > 0 else { return nil }
    return (a / rate * 100).rounded() / 100
}


/// Una spesa del viaggio e quanto pesa nel conto con un'altra persona (+ = io le devo, − = lei mi deve).
struct TripDebtLine { let expense: Expense; let amount: Double }

/// Le spese da cui viene il debito tra me e `other`: quelle pagate da lei con una mia parte,
/// e quelle pagate da me con una sua parte.
func tripDebtLines(_ expenses: [Expense], with other: String) -> [TripDebtLine] {
    expenses.compactMap { e in
        if e.paidBy == other, e.myAmount > 0.004 { return TripDebtLine(expense: e, amount: e.myAmount) }
        if e.paidByMe, let s = e.shares[other], s > 0.004 { return TripDebtLine(expense: e, amount: -s) }
        return nil
    }
    .sorted { $0.expense.date < $1.expense.date }
}
