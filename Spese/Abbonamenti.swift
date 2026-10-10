import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Abbonamenti

/// Quanti giorni prima del rinnovo avvisare (0 = nessun avviso).
let subscriptionRemindDaysKey = "subscriptionRemindDays"

/// Prossimo rinnovo di una spesa ricorrente: il giorno `day` del mese `nextKey` (es. "2026-11"),
/// cioè la prossima data non ancora inserita. Nei mesi più corti vale l'ultimo giorno.
func nextRenewal(nextKey: String, day: Int) -> Date? {
    let p = nextKey.split(separator: "-").compactMap { Int($0) }
    guard p.count == 2 else { return nil }
    let cal = Calendar.current
    guard let first = cal.date(from: DateComponents(year: p[0], month: p[1], day: 1)),
          let n = cal.range(of: .day, in: .month, for: first)?.count else { return nil }
    return cal.date(from: DateComponents(year: p[0], month: p[1], day: min(day, n), hour: 12))
}

/// Ricrea gli avvisi dei rinnovi: uno per abbonamento, `days` giorni prima, alle 9.
@MainActor
func scheduleSubscriptionReminders(_ ctx: ModelContext) async {
    let center = UNUserNotificationCenter.current()
    let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("abbonamento-") }
    center.removePendingNotificationRequests(withIdentifiers: pending)
    let days = UserDefaults.standard.object(forKey: subscriptionRemindDaysKey) as? Int ?? 2
    guard days > 0 else { return }
    let subs = ((try? ctx.fetch(FetchDescriptor<Recurring>())) ?? []).filter(\.isSubscription)
    let cal = Calendar.current
    for (i, r) in subs.enumerated() {
        guard let renew = nextRenewal(nextKey: r.nextKey, day: r.day),
              let when = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: renew)),
              let at = cal.date(bySettingHour: 9, minute: 0, second: 0, of: when), at > Date() else { continue }
        let c = UNMutableNotificationContent()
        c.title = "Rinnovo in arrivo"
        c.body = "\(r.name): \(eur(r.amount)) il \(renew.formatted(.dateTime.day().month(.wide)))"
        c.sound = .default
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
        let req = UNNotificationRequest(identifier: "abbonamento-\(i)-\(r.name)", content: c,
                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        try? await center.add(req)
    }
}

struct SubscriptionsView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var all: [Recurring]
    @Query(sort: \CategoryItem.order) private var cats: [CategoryItem]
    @AppStorage(subscriptionRemindDaysKey) private var remindDays = 2
    @State private var adding = false

    private struct Row: Identifiable {
        let r: Recurring
        let next: Date
        var id: PersistentIdentifier { r.persistentModelID }
    }

    private var subs: [Row] {
        all.filter(\.isSubscription)
            .map { Row(r: $0, next: nextRenewal(nextKey: $0.nextKey, day: $0.day) ?? .distantFuture) }
            .sorted { $0.next < $1.next }
    }
    private var monthly: Double { subs.reduce(0) { $0 + $1.r.amount } }

    private func look(_ name: String) -> (icon: String, color: Color) {
        if let c = cats.first(where: { $0.name == name }) { return (c.icon, Color(hex: c.colorHex)) }
        return ("repeat", .gray)
    }

    private func whenText(_ d: Date) -> String {
        let n = daysLeft(until: d)
        let date = d.formatted(.dateTime.day().month(.abbreviated))
        switch n {
        case 0: return "oggi"
        case 1: return "domani · \(date)"
        case 2...7: return "tra \(n) giorni · \(date)"
        default: return date
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Al mese").font(.caption).opacity(0.8)
                        Text(eur(monthly)).font(.title2.bold())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("All'anno").font(.caption).opacity(0.8)
                        Text(eur(monthly * 12)).font(.title2.bold())
                    }
                }
                .foregroundStyle(.white).padding(16)
                .background(LinearGradient(colors: [HeroStyle.top, HeroStyle.bottom], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 18))
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)

            Section("Prossimi rinnovi") {
                if subs.isEmpty {
                    Text("Nessun abbonamento. Tocca + per aggiungere Netflix, Spotify, palestra… L'importo verrà inserito da solo ogni mese.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(subs) { s in
                    let l = look(s.r.categoryName)
                    HStack(spacing: 12) {
                        Image(systemName: l.icon).foregroundStyle(.white)
                            .frame(width: 36, height: 36).background(l.color, in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.r.name)
                            Text(whenText(s.next)).font(.subheadline)
                                .foregroundStyle(daysLeft(until: s.next) <= remindDays ? Color.orange : Color.secondary)
                        }
                        Spacer()
                        Text(eur(s.r.amount)).bold()
                    }
                }
                .onDelete { idx in
                    idx.map { subs[$0].r }.forEach(ctx.delete)
                    try? ctx.save()
                    Task { await scheduleSubscriptionReminders(ctx) }
                }
            }

            Section {
                Picker("Avvisami prima del rinnovo", selection: $remindDays) {
                    Text("No").tag(0)
                    Text("1 giorno prima").tag(1)
                    Text("2 giorni prima").tag(2)
                    Text("3 giorni prima").tag(3)
                    Text("Una settimana prima").tag(7)
                }
            } footer: {
                Text("Gli abbonamenti sono spese ricorrenti: ogni mese la spesa viene inserita da sola nel giorno indicato.")
            }
        }
        .navigationTitle("Abbonamenti")
        .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $adding) { RecurringEditor(asSubscription: true) }
        .task { await scheduleSubscriptionReminders(ctx) }
        .onChange(of: remindDays) { _, _ in Task { await scheduleSubscriptionReminders(ctx) } }
    }
}
