import SwiftUI
import SwiftData

// MARK: - Controllo contanti della domenica

let cashCheckLastKey = "cashCheckLast"   // ultimo controllo fatto (o rimandato)
let cashCheckOnKey = "cashCheckOn"       // promemoria della domenica (acceso di base)

/// La domenica più recente (oggi, se è domenica), a mezzanotte.
func lastSunday(_ now: Date) -> Date {
    Calendar.current.date(byAdding: .day, value: -1, to: weekRange(now).start).map { sunday in
        Calendar.current.isDate(now, inSameDayAs: Calendar.current.date(byAdding: .day, value: 7, to: sunday) ?? sunday)
            ? Calendar.current.startOfDay(for: now) : sunday
    } ?? Calendar.current.startOfDay(for: now)
}

/// Il controllo va fatto se dall'ultima domenica non è ancora stato fatto.
func cashCheckDue(last: Date?, now: Date) -> Bool {
    guard let last else { return false }   // alla prima apertura si comincia dalla prossima domenica
    return last < lastSunday(now)
}

struct CashCheckView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var incomes: [Income]
    @Query private var expenses: [Expense]
    @Query private var moves: [SavingsMove]
    @Query private var cash: [CashMove]
    @Query private var accounts: [Account]
    @Query private var payments: [TripPayment]
    @State private var text = ""
    @FocusState private var focus: Bool

    private var appCash: Double {
        Ledger(incomes: incomes, expenses: expenses, moves: moves, cash: cash, account: accounts.first, payments: payments).cashBalance()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Contanti nel portafoglio (€)", text: $text).keyboardType(.decimalPad).focused($focus)
                        .font(.title2.bold())
                } header: {
                    Text("Quanti contanti hai adesso?")
                } footer: {
                    Text("Per l'app dovresti averne \(eur(appCash)).")
                }
                if let real = parseAmount(text) {
                    let diff = real - appCash
                    Section {
                        if abs(diff) < 0.005 {
                            Label("Tutto torna", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                            Button("Fatto") { done() }
                        } else if diff < 0 {
                            Text("Mancano \(eur(-diff)): forse una spesa non segnata.").foregroundStyle(.orange)
                            Button("Segna \(eur(-diff)) come spesa in contanti") {
                                let e = Expense(amount: -diff, categoryName: "Altro", date: Date(), note: "Contanti non segnati")
                                e.method = "contanti"
                                ctx.insert(e)
                                done()
                            }
                            Button("Correggi solo il saldo") { correct(diff) }
                        } else {
                            Text("Hai \(eur(diff)) in più di quelli che risultano all'app.")
                            Button("Correggi il saldo") { correct(diff) }
                        }
                    }
                }
            }
            .navigationTitle("Controllo contanti").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Più tardi") { done() } } }
            .onAppear { focus = true }
        }
    }

    private func correct(_ diff: Double) {
        ctx.insert(CashMove(amount: diff, date: Date(), note: "Controllo contanti", kind: "correzione", bank: false))
        done()
    }

    private func done() {
        UserDefaults.standard.set(Date(), forKey: cashCheckLastKey)
        dismiss()
    }
}

// MARK: - Conteggio veloce (carta e contanti)

let balanceFixKind = "Correzione saldo"

/// Differenza tra il saldo vero e quello che risulta all'app (positiva = ho più soldi). nil se il testo non è un numero.
func balanceDifference(real text: String, app: Double) -> Double? {
    guard let real = parseAmount(text) else { return nil }
    return ((real - app) * 100).rounded() / 100
}

/// Si scrivono i saldi veri di carta e contanti: l'app trova la differenza e la segna come spesa o corregge il saldo.
struct QuickCountView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var incomes: [Income]
    @Query private var expenses: [Expense]
    @Query private var moves: [SavingsMove]
    @Query private var cash: [CashMove]
    @Query private var accounts: [Account]
    @Query private var payments: [TripPayment]
    @State private var cardText = ""
    @State private var cashText = ""
    @State private var cardDone = ""
    @State private var cashDone = ""

    private var ledger: Ledger {
        Ledger(incomes: incomes, expenses: expenses, moves: moves, cash: cash, account: accounts.first, payments: payments)
    }

    var body: some View {
        NavigationStack {
            Form {
                part(title: "Carta (guarda l'app della banca)", label: "Saldo vero", app: ledger.figures(for: Date()).left,
                     text: $cardText, done: cardDone, cash: false)
                part(title: "Contanti (conta il portafoglio)", label: "Contanti veri", app: ledger.cashBalance(),
                     text: $cashText, done: cashDone, cash: true)
            }
            .navigationTitle("Conteggio veloce").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
    }

    @ViewBuilder private func part(title: String, label: String, app: Double, text: Binding<String>, done: String, cash: Bool) -> some View {
        Section(title) {
            HStack { Text("Per l'app"); Spacer(); Text(eur(app)) }
            HStack {
                Text(label)
                TextField("€", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).bold()
            }
            if !done.isEmpty {
                Label(done, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
            } else if let diff = balanceDifference(real: text.wrappedValue, app: app) {
                if abs(diff) < 0.005 {
                    Label("Tutto torna", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                } else if diff < 0 {
                    Text("Mancano \(eur(-diff))").bold().foregroundStyle(.orange)
                    Button("Segna \(eur(-diff)) come spesa \(cash ? "in contanti" : "con carta")") { addExpense(-diff, cash: cash) }
                    Button("Correggi solo il saldo") { fix(diff, cash: cash) }
                } else {
                    Text("Hai \(eur(diff)) in più").bold()
                    Button("Correggi il saldo") { fix(diff, cash: cash) }
                }
            }
        }
    }

    private func addExpense(_ amount: Double, cash: Bool) {
        let e = Expense(amount: amount, categoryName: otherCategory, date: Date(), note: cash ? "Contanti non segnati" : "Spesa con carta non segnata")
        e.method = cash ? "contanti" : "carta"
        ctx.insert(e)
        mark("Segnata una spesa di \(eur(amount))", cash: cash)
    }

    private func fix(_ diff: Double, cash: Bool) {
        if cash {
            ctx.insert(CashMove(amount: diff, date: Date(), note: "Conteggio veloce", kind: "correzione", bank: false))
        } else {
            ctx.insert(Income(amount: diff, saved: 0, kind: balanceFixKind, date: Date(), note: "Conteggio veloce"))
        }
        mark("Saldo corretto", cash: cash)
    }

    private func mark(_ s: String, cash: Bool) {
        try? ctx.save()
        if cash { cashDone = s; UserDefaults.standard.set(Date(), forKey: cashCheckLastKey) } else { cardDone = s }
    }
}
