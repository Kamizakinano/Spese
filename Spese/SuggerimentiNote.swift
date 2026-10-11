import SwiftUI

// MARK: - Suggerimenti per la nota

/// Una nota già usata più volte, con la categoria scelta più spesso insieme a lei.
struct NoteSuggestion: Identifiable, Equatable {
    let note: String        // come l'hai scritta l'ultima volta
    let category: String    // la categoria più usata con questa nota
    let count: Int
    var id: String { note }
}

private func folded(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
}

/// Note usate almeno `minUses` volte che iniziano con quello che stai scrivendo
/// (o con una delle loro parole: "lav" trova "Pausa Lavoro"). Le più usate prima.
func noteSuggestions(for typed: String, in expenses: [Expense], minUses: Int = 2, limit: Int = 4) -> [NoteSuggestion] {
    let t = folded(typed)
    guard t.count >= 2 else { return [] }
    let groups = Dictionary(grouping: expenses.filter { !folded($0.note).isEmpty }) { folded($0.note) }
    return groups.compactMap { key, list -> NoteSuggestion? in
        guard list.count >= minUses, key != t else { return nil }
        let words = key.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard key.hasPrefix(t) || words.contains(where: { $0.hasPrefix(t) }) else { return nil }
        let latest = list.max { $0.date < $1.date }!
        let category = Dictionary(grouping: list, by: \.categoryRaw)
            .max { $0.value.count == $1.value.count ? $0.value.map(\.date).max()! < $1.value.map(\.date).max()! : $0.value.count < $1.value.count }!
            .key
        return NoteSuggestion(note: latest.note.trimmingCharacters(in: .whitespacesAndNewlines), category: category, count: list.count)
    }
    .sorted { $0.count != $1.count ? $0.count > $1.count : $0.note < $1.note }
    .prefix(limit).map { $0 }
}

/// Riga di suggerimenti sotto il campo della nota: toccandone uno si inserisce la nota
/// e si sceglie la categoria usata di solito con lei.
struct NoteSuggestionsRow: View {
    let typed: String
    let expenses: [Expense]
    let pick: (NoteSuggestion) -> Void

    var body: some View {
        let list = noteSuggestions(for: typed, in: expenses)
        if !list.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(list) { s in
                        Button { pick(s) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "text.badge.plus").font(.caption)
                                Text(s.note).lineLimit(1)
                            }
                            .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Usa la nota \(s.note)")
                    }
                }
            }
        }
    }
}
