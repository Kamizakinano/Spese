import WidgetKit
import SwiftUI

// MARK: - Dati

struct SpeseEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
}

struct SpeseProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpeseEntry { SpeseEntry(date: Date(), snap: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (SpeseEntry) -> Void) {
        completion(SpeseEntry(date: Date(), snap: context.isPreview ? (WidgetSnapshot.load() ?? .sample) : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpeseEntry>) -> Void) {
        // Il budget al giorno cambia a mezzanotte (un giorno in meno): si aggiorna da solo a quell'ora.
        let now = Date()
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        let snap = WidgetSnapshot.load()
        completion(Timeline(entries: [SpeseEntry(date: now, snap: snap), SpeseEntry(date: midnight, snap: snap)],
                            policy: .after(midnight)))
    }
}

private let green1 = Color(red: 0x1A / 255, green: 0x5E / 255, blue: 0x44 / 255)
private let green2 = Color(red: 0x0E / 255, green: 0x46 / 255, blue: 0x32 / 255)
private let mint = Color(red: 0x4C / 255, green: 0xC3 / 255, blue: 0x8A / 255)

private struct GreenBackground: View {
    var body: some View { LinearGradient(colors: [green1, green2], startPoint: .topLeading, endPoint: .bottomTrailing) }
}

/// Mostrato quando il widget non trova ancora i dati dell'app.
private struct OpenAppHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "eurosign.circle.fill").font(.title2)
            Spacer()
            Text("Apri Spese").font(.headline)
            Text("per vedere qui i tuoi numeri").font(.caption2).opacity(0.8)
        }
        .foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Budget di oggi

struct BudgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SpeseEntry

    var body: some View {
        if let s = entry.snap {
            let days = s.remainingDays(now: entry.date)
            switch family {
            case .accessoryInline:
                Text("\(widgetEuro(s.perDay(now: entry.date))) oggi · \(days) gg")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Oggi puoi spendere").font(.caption2)
                    Text(widgetEuro(s.perDay(now: entry.date))).font(.headline).widgetAccentable()
                    Text("ancora \(days) giorni").font(.caption2)
                }
            default:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Oggi puoi spendere").font(.caption2).opacity(0.8)
                    Spacer(minLength: 0)
                    Text(widgetEuro(s.perDay(now: entry.date)))
                        .font(.system(size: 26, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                    Text("ancora \(days) \(days == 1 ? "giorno" : "giorni")").font(.caption2).opacity(0.8)
                    if let end = s.periodEnd {
                        Text("fino al \(end.formatted(.dateTime.day().month(.abbreviated)))").font(.caption2).opacity(0.8)
                    }
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else if family == .systemSmall {
            OpenAppHint()
        } else {
            Text("Apri Spese")
        }
    }
}

struct BudgetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "budget", provider: SpeseProvider()) { entry in
            BudgetView(entry: entry).containerBackground(for: .widget) { GreenBackground() }
        }
        .configurationDisplayName("Budget di oggi")
        .description("Quanto puoi spendere oggi fino al prossimo stipendio.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Speso dallo stipendio

struct SpentView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SpeseEntry

    var body: some View {
        if let s = entry.snap {
            let since = s.periodStart.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? ""
            if family == .accessoryRectangular {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Speso dal \(since)").font(.caption2)
                    Text(widgetEuro(s.spentSincePay)).font(.headline).widgetAccentable()
                    Text("restano \(widgetEuro(s.available))").font(.caption2)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speso dal \(since)").font(.caption2).opacity(0.8)
                    Spacer(minLength: 0)
                    Text(widgetEuro(s.spentSincePay))
                        .font(.system(size: 26, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                    Text("restano \(widgetEuro(s.available))").font(.caption2).opacity(0.8)
                }
                .foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else if family == .systemSmall {
            OpenAppHint()
        } else {
            Text("Apri Spese")
        }
    }
}

struct SpentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "speso", provider: SpeseProvider()) { entry in
            SpentView(entry: entry).containerBackground(for: .widget) { GreenBackground() }
        }
        .configurationDisplayName("Speso dallo stipendio")
        .description("Quanto hai speso dall'ultimo stipendio e quanto ti resta.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

// MARK: - Spesa veloce

struct QuickAddWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "plus").font(.title2.bold())
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 30, weight: .bold))
                    .frame(width: 58, height: 58).background(mint.opacity(0.35), in: Circle())
                Text("Spesa veloce").font(.footnote.bold())
            }
            .foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct QuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "veloce", provider: SpeseProvider()) { _ in
            QuickAddWidgetView()
                .containerBackground(for: .widget) { GreenBackground() }
                .widgetURL(URL(string: "spese://nuova"))
        }
        .configurationDisplayName("Spesa veloce")
        .description("Un tocco per inserire una spesa.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

@main
struct SpeseWidgets: WidgetBundle {
    var body: some Widget {
        BudgetWidget()
        SpentWidget()
        QuickAddWidget()
    }
}
