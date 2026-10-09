import Foundation

let initialKind = "Saldo iniziale"

/// Quanto mettere a risparmio su un importo ricevuto (percentuale o importo fisso).
func splitSaving(total: Double, mode: Int, value: Double) -> Double {
    min(max(mode == 0 ? total * value / 100 : value, 0), total)
}

/// Mese in cui arriverà il prossimo stipendio.
func nextSalaryKey(day: Int) -> String {
    let cal = Calendar.current
    let today = cal.component(.day, from: Date())
    let d = day > today ? Date() : (cal.date(byAdding: .month, value: 1, to: Date()) ?? Date())
    return monthKey(d)
}

/// Giorno del prossimo stipendio, dopo oggi: se oggi è il giorno dello stipendio è quello del mese dopo.
/// Nei mesi più corti di `day` vale l'ultimo giorno del mese.
func nextPayday(day: Int, from now: Date = Date()) -> Date? {
    let cal = Calendar.current
    let today = cal.startOfDay(for: now)
    for add in 0...2 {
        guard let m = cal.date(byAdding: .month, value: add, to: today),
              let first = cal.date(from: cal.dateComponents([.year, .month], from: m)),
              let n = cal.range(of: .day, in: .month, for: first)?.count,
              let d = cal.date(byAdding: .day, value: min(day, n) - 1, to: first) else { continue }
        if d > today { return d }
    }
    return nil
}

/// Date dovute (fino a oggi) per un evento mensile, a partire dal mese `key`.
func dueDates(from key: String, day: Int) -> (dates: [Date], next: String) {
    let p = key.split(separator: "-").compactMap { Int($0) }
    guard p.count == 2 else { return ([], key) }
    let cal = Calendar.current
    var y = p[0], m = p[1]
    var out: [Date] = []
    while let first = cal.date(from: DateComponents(year: y, month: m, day: 1)),
          let n = cal.range(of: .day, in: .month, for: first)?.count,
          let d = cal.date(from: DateComponents(year: y, month: m, day: min(day, n), hour: 12)),
          d <= Date() {
        out.append(d)
        m += 1
        if m > 12 { m = 1; y += 1 }
    }
    return (out, String(format: "%04d-%02d", y, m))
}

struct Figures {
    var startAvail = 0.0   // disponibile in banca a inizio mese
    var incomeNet = 0.0    // entrate del mese, al netto dei risparmi
    var spent = 0.0        // spese pagate con carta
    var moved = 0.0        // soldi usciti dalla banca verso risparmi e contanti
    var budget: Double { startAvail + incomeNet }
    var left: Double { budget - spent - moved }
}

struct Ledger {
    let incomes: [Income]
    let expenses: [Expense]
    let moves: [SavingsMove]
    var cashMoves: [CashMove] = []
    let start: Date?
    var cashStart: Double = 0

    static var endOfToday: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    /// Situazione della banca (carta) per un mese.
    func figures(for month: Date) -> Figures {
        guard let start, let iv = Calendar.current.dateInterval(of: .month, for: month) else { return Figures() }
        func ex(_ a: Date, _ b: Date) -> Double {
            expenses.filter { !$0.isCash && $0.date >= max(a, start) && $0.date < b }.reduce(0) { $0 + $1.amount }
        }
        func mv(_ a: Date, _ b: Date) -> Double {
            moves.filter { $0.date >= max(a, start) && $0.date < b }.reduce(0) { $0 + $1.amount }
        }
        func tr(_ a: Date, _ b: Date) -> Double {
            cashMoves.filter { $0.bank && $0.date >= max(a, start) && $0.date < b }.reduce(0) { $0 + $1.amount }
        }
        func inc(_ a: Date, _ b: Date) -> Double {
            incomes.filter { $0.date >= a && $0.date < b }.reduce(0) { $0 + $1.amount - $1.saved }
        }
        var f = Figures()
        let past = Date.distantPast
        f.startAvail = inc(past, iv.start) - ex(past, iv.start) - mv(past, iv.start) - tr(past, iv.start)
        f.incomeNet = inc(iv.start, iv.end)
        f.spent = ex(iv.start, iv.end)
        f.moved = mv(iv.start, iv.end) + tr(iv.start, iv.end)
        return f
    }

    /// Contanti nel portafoglio fino alla data indicata.
    func cashBalance(asOf end: Date = Ledger.endOfToday) -> Double {
        guard let start else { return 0 }
        let spent = expenses.filter { $0.isCash && $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.amount }
        let moved = cashMoves.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.amount }
        return cashStart + moved - spent
    }

    var savingsTotal: Double {
        incomes.reduce(0) { $0 + $1.saved } + moves.reduce(0) { $0 + $1.amount }
    }
}

extension Ledger {
    init(incomes: [Income], expenses: [Expense], moves: [SavingsMove], cash: [CashMove], account: Account?) {
        self.init(incomes: incomes, expenses: expenses, moves: moves, cashMoves: cash,
                  start: account?.startDate, cashStart: account?.cashStart ?? 0)
    }
}
