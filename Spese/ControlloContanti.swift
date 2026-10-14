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
