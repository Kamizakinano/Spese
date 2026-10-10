import SwiftUI
import SwiftData
import AppIntents

// MARK: - Spesa veloce (dal widget o dal tasto Azione)

/// Apre la finestra della spesa veloce quando l'app viene aperta dal widget o dall'azione.
final class QuickAddRouter: ObservableObject {
    static let shared = QuickAddRouter()
    @Published var show = false
}

/// Indirizzo usato dal widget "Spesa veloce".
let quickAddURL = URL(string: "spese://nuova")!

/// Azione per il tasto Azione o per Comandi rapidi: apre l'app sulla spesa veloce.
struct QuickAddIntent: AppIntent {
    static let title: LocalizedStringResource = "Spesa veloce"
    static let description = IntentDescription("Apre Spese per inserire subito una spesa: importo, categoria, salva.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickAddRouter.shared.show = true
        return .result()
    }
}

struct QuickAddView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CategoryItem.order) private var cats: [CategoryItem]
    @AppStorage("lastMethod") private var lastMethod = "carta"
    @State private var amountText = ""
    @State private var catName = ""
    @State private var method = "carta"
    @State private var note = ""
    @FocusState private var focused: Bool

    private var amount: Double? { parseAmount(amountText).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    TextField("0,00", text: $amountText)
                        .keyboardType(.decimalPad).focused($focused)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .overlay(alignment: .trailing) { Text("€").font(.title.bold()).foregroundStyle(.secondary) }
                        .padding(.horizontal, 24)
                        .accessibilityLabel("Importo")

                    Picker("Pagamento", selection: $method) {
                        Text("Carta").tag("carta")
                        Text("Contanti").tag("contanti")
                    }
                    .pickerStyle(.segmented)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                        ForEach(cats) { c in
                            let color = Color(hex: c.colorHex)
                            let on = catName == c.name
                            Button { catName = c.name } label: {
                                Label(c.name, systemImage: c.icon).font(.footnote.weight(.medium)).lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity)
                                    .foregroundStyle(on ? .white : color)
                                    .background(on ? color : color.opacity(0.12), in: Capsule())
                                    .overlay(Capsule().strokeBorder(color, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    TextField("Nota (facoltativa)", text: $note)
                        .padding(12).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                    Button(action: save) {
                        Text("Salva").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .foregroundStyle(.white)
                            .background(amount == nil ? Color.gray : Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(amount == nil)
                }
                .padding(20)
            }
            .navigationTitle("Spesa veloce").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } } }
            .onAppear {
                method = lastMethod
                if catName.isEmpty { catName = cats.first?.name ?? "Altro" }
                focused = true
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        guard let a = amount else { return }
        let e = Expense(amount: a, categoryName: catName, date: Date(), note: note.trimmingCharacters(in: .whitespaces))
        e.method = method
        applyActiveTrip(e, raw: "€", trips: (try? ctx.fetch(FetchDescriptor<Trip>())) ?? []) { _ in nil }
        ctx.insert(e)
        try? ctx.save()
        lastMethod = method
        updateWidgetSnapshot(ctx)
        dismiss()
    }
}
