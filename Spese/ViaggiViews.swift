import SwiftUI
import SwiftData

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
    @State private var countInStats = false
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
                Section("Per categoria (la tua parte)") {
                    ForEach(byCategory) { c in
                        HStack { Text(c.name); Spacer(); Text(eur(c.total)).bold() }
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
                if !error.isEmpty { Text(error).font(.footnote).foregroundStyle(.red) }
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
        participants = Set(trip.everyone)
        inLocal = trip.isForeign
        catName = cats.first?.name ?? "Altro"
        date = trip.contains(Date()) ? Date() : trip.startDate
        if trip.lastRate > 0 { rateText = String(format: "%.4f", trip.lastRate).replacingOccurrences(of: ".", with: ",") }
        guard let e = editing else { return }
        catName = e.categoryRaw; date = e.date; note = e.note; method = e.method; payer = e.payer
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
