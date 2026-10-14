import Foundation
import UIKit
import SwiftUI

// MARK: - Bollette a confronto

/// Categorie in cui ha senso confrontare con le volte precedenti (es. "Casa e bollette").
func isBillCategory(_ c: String) -> Bool { c.localizedCaseInsensitiveContains("bollett") }

/// Le ultime (al massimo 3) bollette con la stessa nota nella stessa categoria, dalla più recente.
func billHistory(note: String, category: String, in all: [Expense], excluding: Expense? = nil) -> [Expense] {
    let key = note.trimmingCharacters(in: .whitespaces).lowercased()
    guard !key.isEmpty, isBillCategory(category) else { return [] }
    return Array(all.filter {
        $0 !== excluding && !$0.needsAmount && $0.categoryRaw == category
            && $0.note.trimmingCharacters(in: .whitespaces).lowercased() == key
    }
    .sorted { $0.date > $1.date }
    .prefix(3))
}

/// Variazione in percentuale rispetto alla bolletta precedente (nil se non c'è).
func billChange(_ amount: Double, previous: Double?) -> Double? {
    guard let p = previous, p > 0 else { return nil }
    return (amount - p) / p * 100
}

// MARK: - Foto dello scontrino

/// Riduce la foto (lato lungo al massimo 1600 punti) e la salva in JPEG, per occupare poco spazio.
func compressReceipt(_ image: UIImage?) -> Data? {
    guard let image else { return nil }
    let side = max(image.size.width, image.size.height)
    let scale = side > 1600 ? 1600 / side : 1
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let format = UIGraphicsImageRendererFormat(); format.scale = 1
    let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    return small.jpegData(compressionQuality: 0.6)
}


/// Foto dello scontrino a tutto schermo, con lo zoom a due dita.
struct ReceiptViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: UIScreen.main.bounds.width * zoom * pinch)
            }
            .gesture(MagnificationGesture().updating($pinch) { v, s, _ in s = v }
                .onEnded { zoom = min(max(zoom * $0, 1), 5) })
            .navigationTitle("Scontrino").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Chiudi") { dismiss() } }
        }
    }
}
