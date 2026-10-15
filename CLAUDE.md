# Spese: istruzioni per Claude

App iOS per le spese personali (SwiftUI, SwiftData, iOS 17+). Il proprietario la installa sul suo iPhone con Sideloadly. Non programma: parla di schermate e funzioni, non di codice.

## Come lavorare con l'utente

- Rispondi **in italiano** e **in breve**.
- Ogni proposta o suggerimento di modifica va **con un'immagine**: un'anteprima della schermata (HTML renderizzato in PNG con Playwright e mandato con SendUserFile). Per le correzioni usa "prima / dopo". Le anteprime vanno disegnate come un iPhone vero, con Dynamic Island, barra in basso e linea Home, e senza zone vuote.
- **Accumula le richieste** e non iniziare finché l'utente non scrive **"parti"** o **"procedi"**.
- Quando citi un sito o una pagina, **metti sempre il link**.
- Di' sempre se le schermate sono ricostruite e se i numeri sono di esempio.

## Versioni, build e IPA

- La versione sta in `project.yml`, `MARKETING_VERSION`, **in due punti** (app e widget): aggiornali tutti e due. Ogni modifica è una versione nuova (es. 2.35 → 2.36).
- Lavora su un ramo `claude/<nome>` partito dall'ultimo `origin/main` (fai prima `git fetch origin main`). Il push sul ramo avvia la CI (GitHub Actions, macOS). La CI fa le prove sul simulatore (anche l'aggiornamento dalla 1.0), poi crea l'IPA e la pubblica nella release `ultima-versione`.
- Di' all'utente quanto dura (circa **14 minuti**) e **l'ora di fine in ora italiana** (`TZ=Europe/Rome`). Niente percentuali.
- Aspetta la fine con un ciclo in background su `gh api repos/Kamizakinano/Spese/actions/runs/<id>`, senza sleep in primo piano.
- **Mai mandare un'IPA se le prove sono fallite.**
- Se la CI fallisce, leggi gli errori dalle annotazioni (i log sono bloccati dal proxy): `gh api repos/Kamizakinano/Spese/check-runs/<job_id>/annotations`.
- Se la CI passa, scarica l'IPA dalla release: `gh api repos/Kamizakinano/Spese/releases/tags/ultima-versione` per trovare l'id dell'asset `Spese.ipa`, poi `gh api -H "Accept: application/octet-stream" repos/Kamizakinano/Spese/releases/assets/<id> > "download/Spese vX.Y.ipa"`. Mandala con SendUserFile, nominata **"Spese vX.Y.ipa"**. La release contiene anche `schermata-simulatore.png`, la Home vera dal simulatore: usala per controllare la grafica.
- Quando l'utente conferma che la versione funziona, apri una PR con titolo **"Versione X.Y (già provata, build N) [skip ci]"** (N è il run_number della CI) e uniscila con **squash**. Poi la versione dopo riparte da `origin/main` aggiornato.
- Prima di unire controlla che il ramo parta dall'ultimo `main` (se serve, `git rebase --onto origin/main <vecchia base> <ramo>`).

## Codice

- `Spese/SpeseApp.swift`: modelli SwiftData (`Expense`, `Income`, `Account`, `Trip`, `CategoryItem`, `Recurring`…), `AppColor` (colore "Ardesia" 5D7584 / corallo FF9C88), `eur()`. Le proprietà nuove dei modelli vanno aggiunte **con un valore di default** (migrazione leggera).
- `Spese/NuovaHome.swift`: Home per giorno (`HomeView`, `WeekStrip`, riquadro "Questa settimana"), `MonthPickerView`, `MonthView` (elenco spese per Giorno / Settimana / Mese, Elenco/Categorie), `ExpenseRow`.
- `Spese/ContentView.swift`: le schede (Spese, Conti, Risparmi, Statistiche, Altro).
- `Spese/SettingsView.swift`: la scheda Altro.
- `Spese/Ledger.swift`, `Periodo.swift`: conti, budget e periodo dello stipendio.
- `Spese/EmailBanca.swift`, `PayPal.swift`, `Intents.swift`: spese aggiunte dalle email della banca e da PayPal "Paga a rate", tramite Comandi Rapidi.
- `Spese/Rate.swift`: pagamenti a rate (PayPal, Klarna).
- `Spese/Esporta.swift`: esportazione Excel (.xlsx scritto a mano), CSV e PDF.
- Altre funzioni: `Prossimi30.swift`, `Avvisi.swift` (notifiche), `Bollette.swift` (confronto bollette e foto scontrino), `AnnoMappa.swift` (Il tuo anno, Mappa), `Viaggi*.swift`, `Abbonamenti.swift`, `Debiti.swift`.
- Prove: `SpeseTests/` (unit test, aggiungine per ogni logica nuova) e `SpeseUITests/` (se cambi testi o posizioni di pulsanti usati lì, aggiorna anche le prove).
- Commenti e testi dell'interfaccia in italiano semplice, come nel resto del codice.

## Cose fatte di recente

2.31 PayPal "Paga a rate" dalle email · 2.32 Home per giorno · 2.33 nuova icona e colore Ardesia · 2.34 esportazione CSV e PDF · 2.35 Home più compatta, "Questa settimana", elenco per Giorno/Settimana/Mese, foto scontrino centrata, spese ricorrenti e abbonamenti modificabili, niente doppioni tra ricorrenti e spese inserite a mano (`recurringCovered`), addebito di una ricorrente dall'email della banca spostato al giorno vero (`matchRecurringPayment` in `EmailBanca.swift`, regola generica: stesso importo ±2%, ±6 giorni). · 2.36 ricorrenti modificabili anche toccandole nella Home, trascinare il dito sulla data e sui giorni cambia giorno. · 2.37 le frecce della Home cambiano settimana (stesso giorno), il dito cambia giorno.

## A che punto siamo

- La 2.36 è in `main` (build 60). La **2.37** è sul ramo `claude/eloquent-feynman-wxngiu`: se l'utente conferma che funziona, PR "Versione 2.37 (già provata, build N) [skip ci]" con squash.
- In attesa: un'**email vera dell'addebito del mutuo** (Intesa Sanpaolo). Quando arriva, controlla che `parseBankEmail` la legga come spesa con importo e data giusti e aggiungi una prova in `SpeseTests/EmailBancaTests.swift`.
- Se la CI dice "L'app si è chiusa da sola (crash)", leggi le annotazioni: ora contengono il motivo e le righe del codice. È già successo due volte senza cambiare il codice (2.29 e 2.35): un nuovo tentativo è passato.

Idee rimaste in sospeso: barre per categoria nelle Statistiche; versione Android (andrebbe riscritta); rinnovi PayPal da email (l'utente manderà un esempio).
