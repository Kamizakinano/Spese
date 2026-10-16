import Foundation

// MARK: - Emoji per le spese "Altro"

/// Parole che descrivono una spesa "Altro" e l'emoji da mostrare. Si guarda l'inizio delle parole,
/// così "regalo", "regali" e "regalino" danno lo stesso risultato. Le prime della lista vincono.
private let otherEmojiWords: [(String, [String])] = [
    ("🎁", ["regal", "dono", "compleann"]),
    ("💇", ["parrucch", "barbier", "capell", "taglio"]),
    ("💅", ["estetist", "unghi", "manicure", "ceretta"]),
    ("🐶", ["cane", "gatto", "veterinar", "croccantin", "animal", "lettiera"]),
    ("👶", ["bambin", "pannolin", "neonat", "asilo"]),
    ("📚", ["libr", "scuol", "universit", "corso", "quadern", "cancelleri"]),
    ("💊", ["farmac", "medicin"]),
    ("🔧", ["riparaz", "idraulic", "elettricist", "ferrament", "attrezz", "manutenz"]),
    ("🧺", ["lavanderi", "tintori", "stiratur"]),
    ("🧹", ["pulizi", "detersiv"]),
    ("📮", ["posta", "spedizion", "raccomandat", "pacco"]),
    ("🏛️", ["tass", "multa", "bollo", "comune", "agenzia entrate", "f24", "imposta"]),
    ("⛪", ["chiesa", "offert", "beneficenz", "donazion"]),
    ("💐", ["fior", "pianta", "piante", "giardin"]),
    ("🎂", ["torta", "pasticceri"]),
    ("🍷", ["vino", "enotec"]),
    ("🚬", ["sigarett", "tabacc"]),
    ("🎮", ["gioc", "videogioc", "playstation", "xbox", "nintendo"]),
    ("📱", ["telefon", "cellular", "ricaric", "sim"]),
    ("💻", ["computer", "pc", "stampant", "inchiostr", "toner"]),
    ("🖨️", ["stampa", "fotocop"]),
    ("👓", ["occhial", "ottic", "lenti"]),
    ("🦷", ["dentist"]),
    ("🏋️", ["palestr", "piscin", "sport"]),
    ("✂️", ["sartori", "orlo"]),
    ("👕", ["vestit", "maglia", "pantalon", "scarp", "giubbott"]),
    ("🎟️", ["bigliett", "concert", "cinema", "teatro", "museo"]),
    ("🅿️", ["parchegg"]),
    ("🚗", ["auto", "meccanic", "gommist", "lavaggio"]),
    ("⛽", ["benzin", "carburant", "diesel"]),
    ("🧾", ["commission", "spese bancarie", "canone"]),
    ("💸", ["prestit", "restituit", "debit"]),
    ("🖨️", ["3d", "filament"]),
]

/// Emoji per una spesa "Altro" in base a quello che hai scritto. nil se non si riconosce.
func otherEmoji(_ text: String) -> String? {
    let low = text.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "it_IT"))
    let words = low.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    guard !words.isEmpty else { return nil }
    for (emoji, keys) in otherEmojiWords {
        for k in keys {
            if k.contains(" ") { if low.contains(k) { return emoji } }
            else if words.contains(where: { $0.hasPrefix(k) }) { return emoji }
        }
    }
    return nil
}

/// La categoria "Altro": per queste spese l'app chiede a cosa si riferiscono.
let otherCategory = "Altro"
