import SwiftUI
import Foundation
import SwiftData
import UserNotifications

// MARK: - Avviso della sera e riepilogo della domenica (si accendono in Altro → Notifiche)

let budgetAlertKey = "budgetAlertOn"
let weeklySummaryKey = "weeklySummaryOn"
private let budgetAlertID = "budget-sera"
private let weeklySummaryID = "riepilogo-domenica"
private let cashCheckID = "controllo-contanti"
let eveningCheckKey = "eveningCheckOn"
let eveningCheckHourKey = "eveningCheckHour"
private let eveningCheckID = "controllo-sera"
/// Indirizzo che apre il "Controllo di stasera".
let eveningCheckURL = URL(string: "spese://sera")!

/// Testo del "Controllo di stasera" con le spese segnate oggi.
func eveningCheckText(_ today: [Expense]) -> String {
    let n = today.count
    guard n > 0 else { return "Oggi non hai segnato spese. Hai pagato qualcosa? Tocca per controllare." }
    let total = today.reduce(0) { $0 + $1.myAmount }
    return "Oggi hai segnato \(n == 1 ? "1 spesa" : "\(n) spese"), \(eur(total)). Manca qualche pagamento? Tocca per controllare."
}

/// Testo dell'avviso delle 21: nil se oggi si è rimasti nel budget.
/// `budget` è il budget giornaliero di stamattina, `tomorrow` quello che resterà da domani.
func budgetAlertText(spentToday: Double, budget: Double, tomorrow: Double?) -> (title: String, body: String)? {
    guard budget > 0, spentToday > budget + 0.005 else { return nil }
    var body = "Hai superato il budget di \(eur(spentToday - budget))."
    if let t = tomorrow { body += " Da domani il budget giornaliero scende a \(eur(t))." }
    return ("Oggi \(eur(spentToday)), budget \(eur(budget))", body)
}

/// La settimana che contiene `now`, da lunedì a domenica.
func weekRange(_ now: Date) -> (start: Date, end: Date) {
    var cal = Calendar(identifier: .gregorian)
    cal.firstWeekday = 2
    let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
    return (start, cal.date(byAdding: .day, value: 7, to: start) ?? now)
}

/// Testo del riepilogo della domenica.
func weeklySummaryText(_ expenses: [Expense], now: Date) -> (title: String, body: String) {
    let w = weekRange(now)
    let prevStart = Calendar.current.date(byAdding: .day, value: -7, to: w.start) ?? w.start
    let this = expenses.filter { $0.date >= w.start && $0.date < w.end }
    let total = this.reduce(0) { $0 + everydaySpend($1) }
    let prev = expenses.filter { $0.date >= prevStart && $0.date < w.start }.reduce(0) { $0 + everydaySpend($1) }
    var parts: [String] = []
    if prev > 0 {
        let d = total - prev
        if abs(d) < 0.5 { parts.append("Come la settimana scorsa.") }
        else { parts.append("\(eur(abs(d))) \(d < 0 ? "meno" : "più") della settimana scorsa.") }
    }
    let byCat = Dictionary(grouping: this, by: \.categoryRaw).mapValues { $0.reduce(0) { $0 + everydaySpend($1) } }
    if let top = byCat.max(by: { $0.value < $1.value }), top.value > 0 {
        parts.append("Categoria più alta: \(top.key), \(eur(top.value)).")
    }
    return ("La tua settimana: \(eur(total))", parts.isEmpty ? "Nessuna spesa questa settimana." : parts.joined(separator: " "))
}

/// Ricrea i due avvisi con i numeri di adesso. Si chiama a ogni modifica (insieme al widget).
@MainActor
func scheduleSmartNotifications(_ ctx: ModelContext, now: Date = Date()) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: [budgetAlertID, weeklySummaryID, cashCheckID, eveningCheckID])
    let defaults = UserDefaults.standard
    let all = (try? ctx.fetch(FetchDescriptor<Expense>())) ?? []
    let trips = (try? ctx.fetch(FetchDescriptor<Trip>())) ?? []
    let cal = Calendar.current

    if defaults.bool(forKey: budgetAlertKey),
       let at = cal.date(bySettingHour: 21, minute: 0, second: 0, of: now), now < at,
       let account = (try? ctx.fetch(FetchDescriptor<Account>()))?.first,
       let p = payPeriod(day: account.salaryDay, customStart: account.periodStart, customEnd: account.periodEnd) {
        let l = Ledger(incomes: (try? ctx.fetch(FetchDescriptor<Income>())) ?? [], expenses: all,
                       moves: (try? ctx.fetch(FetchDescriptor<SavingsMove>())) ?? [],
                       cash: (try? ctx.fetch(FetchDescriptor<CashMove>())) ?? [], account: account,
                       payments: (try? ctx.fetch(FetchDescriptor<TripPayment>())) ?? [])
        let available = l.figures(for: now).left + l.cashBalance()
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let today = all.filter { $0.paidByMe && cal.isDate($0.date, inSameDayAs: now) }
        let upcoming = all.filter { $0.paidByMe && $0.date >= endOfToday && $0.date < p.end }.reduce(0) { $0 + $1.myAmount }
        let days = max(daysLeft(until: p.end, from: now), 1)
        let reserve = defaults.double(forKey: dailySaveKey)   // da parte ogni giorno
        // Budget di stamattina: i soldi di adesso più quelli spesi oggi, divisi per i giorni rimasti.
        let budget = max(available + today.reduce(0) { $0 + $1.amount } - upcoming - reserve * Double(days), 0) / Double(days)
        let spent = statExpenses(today, trips: trips).reduce(0) { $0 + $1.myAmount }
        let tomorrow = days > 1 ? max(available - upcoming - reserve * Double(days - 1), 0) / Double(days - 1) : nil
        if let t = budgetAlertText(spentToday: spent, budget: budget, tomorrow: tomorrow) {
            add(center, id: budgetAlertID, title: t.title, body: t.body, at: at)
        }
    }

    // Controllo di stasera: ogni giorno all'ora scelta (21 se non scelta) con le spese di oggi.
    if defaults.bool(forKey: eveningCheckKey) {
        let hour = defaults.object(forKey: eveningCheckHourKey) as? Int ?? 21
        if let todayAt = cal.date(bySettingHour: hour, minute: 0, second: 0, of: now) {
            if now < todayAt {
                let today = all.filter { $0.paidByMe && cal.isDate($0.date, inSameDayAs: now) }
                add(center, id: eveningCheckID, title: "Controllo di stasera", body: eveningCheckText(today), at: todayAt, open: "sera")
            } else if let at = cal.date(byAdding: .day, value: 1, to: todayAt) {
                // Domani non si sanno ancora le spese: testo generico (si aggiorna appena apri l'app o arriva una spesa).
                add(center, id: eveningCheckID, title: "Controllo di stasera",
                    body: "Hai segnato tutte le spese di oggi? Tocca per controllare.", at: at, open: "sera")
            }
        }
    }

    // Controllo contanti: domenica alle 10, se non è già stato fatto.
    if defaults.object(forKey: cashCheckOnKey) as? Bool ?? true {
        let sunday = cal.date(byAdding: .day, value: 6, to: weekRange(now).start) ?? now
        let last = defaults.object(forKey: cashCheckLastKey) as? Date ?? now
        var at = cal.date(bySettingHour: 10, minute: 0, second: 0, of: sunday) ?? sunday
        if at <= now || last >= cal.startOfDay(for: sunday) { at = cal.date(byAdding: .day, value: 7, to: at) ?? at }
        add(center, id: cashCheckID, title: "Controllo contanti",
            body: "Quanti contanti hai nel portafoglio? Apri Spese e controlla che tornino.", at: at)
    }

    if defaults.bool(forKey: weeklySummaryKey) {
        // Domenica di questa settimana alle 19 (o la prossima, se è già passata).
        var sunday = cal.date(byAdding: .day, value: 6, to: weekRange(now).start) ?? now
        if let at = cal.date(bySettingHour: 19, minute: 0, second: 0, of: sunday), at <= now {
            sunday = cal.date(byAdding: .day, value: 7, to: sunday) ?? sunday
        }
        if let at = cal.date(bySettingHour: 19, minute: 0, second: 0, of: sunday) {
            let t = weeklySummaryText(statExpenses(all, trips: trips).filter { $0.date < at }, now: at)
            add(center, id: weeklySummaryID, title: t.title, body: t.body, at: at)
        }
    }
}

private func add(_ center: UNUserNotificationCenter, id: String, title: String, body: String, at: Date, open: String? = nil) {
    let c = UNMutableNotificationContent()
    c.title = title; c.body = body; c.sound = .default
    if let open { c.userInfo = ["apri": open] }
    let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at)
    center.add(UNNotificationRequest(identifier: id, content: c,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
}

// MARK: - Controllo di stasera (si apre toccando la notifica)

struct EveningCheckView: View {
    /// "Aggiungi quello che manca": chiude e apre la spesa veloce.
    let addMissing: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Expense.date) private var raw: [Expense]
    @Query(sort: \CategoryItem.order) private var cats: [CategoryItem]

    private func look(_ name: String) -> (icon: String, color: Color) {
        if let c = cats.first(where: { $0.name == name }) { return (c.icon, Color(hex: c.colorHex)) }
        return ("questionmark", .gray)
    }

    var body: some View {
        let today = raw.filter { $0.paidByMe && Calendar.current.isDateInToday($0.date) }
        NavigationStack {
            List {
                Section {
                    if today.isEmpty {
                        Text("Oggi non hai segnato spese.").foregroundStyle(.secondary)
                    }
                    ForEach(today) { e in
                        let l = look(e.categoryRaw)
                        HStack(spacing: 12) {
                            Image(systemName: l.icon).foregroundStyle(.white)
                                .frame(width: 32, height: 32).background(l.color, in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.note.isEmpty ? e.categoryRaw : e.note).lineLimit(1)
                                Text(e.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(eur(e.myAmount)).bold()
                        }
                    }
                    if !today.isEmpty {
                        HStack { Text("Totale").bold(); Spacer(); Text(eur(today.reduce(0) { $0 + $1.myAmount })).bold() }
                    }
                } header: {
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                }
                Section {
                    Button { addMissing() } label: {
                        Label("Aggiungi quello che manca", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                    }
                    Button { dismiss() } label: {
                        Label("Tutto a posto", systemImage: "checkmark.circle").frame(maxWidth: .infinity)
                    }
                    .tint(.green)
                } footer: {
                    Text("Controlla l'estratto conto della banca: se un pagamento non è entrato da Wallet o dall'email, aggiungilo qui.")
                }
            }
            .navigationTitle("Controllo di stasera")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
