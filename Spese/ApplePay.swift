import SwiftUI

// MARK: - Registro Apple Pay

/// Una chiamata dell'azione "Aggiungi spesa": cosa è arrivato da Comandi rapidi e com'è finita.
struct ApplePayLogEntry: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var amount: String
    var merchant: String
    var result: String
    var source: String? = nil   // "Email" per le email della banca, nil = Apple Pay
}

/// Ultime chiamate dell'azione "Aggiungi spesa", salvate nelle impostazioni dell'app (le più recenti prima).
enum ApplePayLog {
    static let key = "applePayLog"
    static let maxEntries = 50

    static func all(_ defaults: UserDefaults = .standard) -> [ApplePayLogEntry] {
        guard let d = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ApplePayLogEntry].self, from: d)) ?? []
    }

    private static func save(_ items: [ApplePayLogEntry], _ defaults: UserDefaults) {
        if let d = try? JSONEncoder().encode(Array(items.prefix(maxEntries))) { defaults.set(d, forKey: key) }
    }

    /// Annota l'arrivo di un pagamento. Finché non si chiama `finish` l'esito resta "in corso":
    /// se l'app si chiudesse a metà, nel registro si vedrebbe.
    @discardableResult
    static func begin(amount: String, merchant: String, source: String? = nil, defaults: UserDefaults = .standard) -> UUID {
        let e = ApplePayLogEntry(date: Date(), amount: amount, merchant: merchant, result: "In corso (interrotta?)", source: source)
        save([e] + all(defaults), defaults)
        return e.id
    }

    static func finish(_ id: UUID, _ result: String, defaults: UserDefaults = .standard) {
        var items = all(defaults)
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].result = result
        save(items, defaults)
    }

    static func clear(_ defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }
}

struct ApplePayLogView: View {
    @State private var items = ApplePayLog.all()

    private func show(_ s: String) -> String { s.isEmpty ? "(vuoto)" : "\u{201C}\(s)\u{201D}" }

    var body: some View {
        List {
            Section {
                Text("Ogni volta che Comandi rapidi passa un pagamento all'app (da Apple Pay o da un'email della banca), qui trovi cosa è arrivato esattamente e com'è andata. Serve a capire perché un movimento non è entrato.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if items.isEmpty {
                Section { Text("Nessun pagamento ricevuto finora.").foregroundStyle(.secondary) }
            } else {
                Section("Ultimi pagamenti") {
                    ForEach(items) { e in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(e.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()) + " · " + (e.source ?? "Apple Pay"))
                                .font(.caption).foregroundStyle(.secondary)
                            if e.source == "Email" {
                                Text(show(e.amount)).font(.footnote).foregroundStyle(.secondary).lineLimit(4)
                            } else {
                                Text("Importo: \(show(e.amount))").font(.subheadline)
                                Text("Esercente: \(show(e.merchant))").font(.subheadline)
                            }
                            Text(e.result).font(.subheadline.bold())
                                .foregroundStyle(e.result.contains("registrat") || e.result.hasPrefix("Registrata") ? Theme.accent : Color.orange)
                        }
                        .textSelection(.enabled)
                        .padding(.vertical, 2)
                    }
                }
                Section {
                    Button("Svuota il registro", role: .destructive) { ApplePayLog.clear(); items = [] }
                }
            }
        }
        .navigationTitle("Registro pagamenti")
        .onAppear { items = ApplePayLog.all() }
    }
}
