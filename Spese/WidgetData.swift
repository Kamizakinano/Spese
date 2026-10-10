import SwiftData
import WidgetKit

/// Ricalcola i numeri del widget dai dati dell'app e chiede a iOS di aggiornarlo.
@MainActor
func updateWidgetSnapshot(_ ctx: ModelContext) {
    let all = (try? ctx.fetch(FetchDescriptor<Expense>())) ?? []
    let account = (try? ctx.fetch(FetchDescriptor<Account>()))?.first
    guard let account else { return }
    let l = Ledger(incomes: (try? ctx.fetch(FetchDescriptor<Income>())) ?? [], expenses: all,
                   moves: (try? ctx.fetch(FetchDescriptor<SavingsMove>())) ?? [],
                   cash: (try? ctx.fetch(FetchDescriptor<CashMove>())) ?? [], account: account,
                   payments: (try? ctx.fetch(FetchDescriptor<TripPayment>())) ?? [])
    let trips = (try? ctx.fetch(FetchDescriptor<Trip>())) ?? []
    let p = payPeriod(day: account.salaryDay, customStart: account.periodStart, customEnd: account.periodEnd)
    let spent = p.map { p in
        statExpenses(all, trips: trips).filter { $0.date >= p.start && $0.date < p.end }.reduce(0) { $0 + $1.myAmount }
    } ?? 0
    WidgetSnapshot(available: l.figures(for: Date()).left + l.cashBalance(), periodStart: p?.start, periodEnd: p?.end,
                   spentSincePay: spent, updated: Date()).save()
    WidgetCenter.shared.reloadAllTimelines()
}
