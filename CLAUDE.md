# Spese: istruzioni per Claude

App iOS per le spese personali (SwiftUI, SwiftData, iOS 17+). Il proprietario la installa sul suo iPhone con Sideloadly. Non programma: parla di schermate e funzioni, non di codice.

## Come lavorare con l'utente

- Rispondi **in italiano** e **in breve**.
- Ogni proposta o suggerimento di modifica va **con un'immagine**: un'anteprima della schermata (HTML renderizzato in PNG con Playwright e mandato con SendUserFile). Per le correzioni usa "prima / dopo". Le anteprime vanno disegnate come un iPhone vero, con Dynamic Island, barra in basso e linea Home, e senza zone vuote.
- Le anteprime si possono mandare sempre, anche quando l'utente non può aggiornare l'app (es. in viaggio).
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

2.31 PayPal "Paga a rate" dalle email · 2.32 Home per giorno · 2.33 nuova icona e colore Ardesia · 2.34 esportazione CSV e PDF · 2.35 Home più compatta, "Questa settimana", elenco per Giorno/Settimana/Mese, foto scontrino centrata, spese ricorrenti e abbonamenti modificabili, niente doppioni tra ricorrenti e spese inserite a mano (`recurringCovered`), addebito di una ricorrente dall'email della banca spostato al giorno vero (`matchRecurringPayment` in `EmailBanca.swift`, regola generica: stesso importo ±2%, ±6 giorni). · 2.36 ricorrenti modificabili anche toccandole nella Home, trascinare il dito sulla data e sui giorni cambia giorno. · 2.37 le frecce della Home cambiano settimana (stesso giorno), il dito cambia giorno. · 2.38 nei giorni del viaggio il riquadro del viaggio sta in alto, sotto Disponibile/Carta/Contanti.

## A che punto siamo

- La 2.36 è in `main` (build 60). La 2.37 (build 61) e la **2.38** sono sul ramo `claude/eloquent-feynman-wxngiu`: se l'utente conferma che funziona, PR "Versione 2.38 (già provata, build N) [skip ci]" con squash.
- In attesa: un'**email vera dell'addebito del mutuo** (Intesa Sanpaolo). Quando arriva, controlla che `parseBankEmail` la legga come spesa con importo e data giusti e aggiungi una prova in `SpeseTests/EmailBancaTests.swift`.
- In attesa: **email Klarna "Prossimo pagamento programmato"** (Gmail). Testo intero arrivato: `esempi/klarna-prossimo-pagamento.txt` (usalo per la prova in `SpeseTests/`). Contiene importo, carta, data ("26,28 € saranno addebitati dalla tua carta **** 4833 il 17 ottobre 2026"), negozio, riferimento ordine Klarna (PLS6MMBG, utile per riconoscere lo stesso acquisto), "Paga in 12 mesi", totale 314,96 € e la tabella con le prossime rate (17 nov 25,88 €: l'ultima rata può differire). Dalla notifica: "Il pagamento di 26,28 € per 3DJake sarà addebitato il 17 ottobre 2026" / "Assicurati di avere 26,28 € disponibili sulla tua carta prima del 17 ottobre 2026". Idea approvata: leggerla col Comando Rapido come PayPal; se la rata Klarna c'è già spostarla al giorno giusto, altrimenti aggiungerla come spesa in arrivo (categoria rate, Klarna). La notifica dell'app Klarna non è leggibile dai Comandi Rapidi. Da fare al ritorno dal viaggio, insieme ai rinnovi PayPal.
- In attesa: **preavviso di addebito diretto Intesa** (`esempi/intesa-preavviso-addebito.txt`, arrivato come notifica dell'app, non leggibile dai Comandi Rapidi). Chiesto all'utente se arriva anche per email/SMS. Oggi `parseBankEmail` lo leggerebbe come spesa da 170,63 € al 26.10 ma senza esercente ("da parte di" non è tra le parole cercate) e con il "+" davanti; andrebbe trattato come spesa in arrivo, non come spesa fatta, e l'addebito vero dopo non deve fare doppione.
- Richiesta accumulata (anteprima approvata da mandare): in "Spesa del viaggio" (`TripExpenseEditor` in `ViaggiViews.swift`) per una **spesa nuova** solo "Io" acceso, i compagni di viaggio spenti; le spese già salvate restano come sono.
- Richiesta accumulata (scelta la versione **A**): nel riquadro blu del viaggio in Home (`TripHomeCard` in `ViaggiViews.swift`), a destra, una pastiglia col cambio di oggi ("1 € = 4,37 PLN", solo se la valuta del viaggio non è EUR) e sotto "Totale vacanza" in grande (tutte le spese del viaggio, prenotazioni comprese); a sinistra resta "Speso". Il totale deve includere tutto ciò che riguarda il viaggio (hotel, voli, spese varie, anche pagati prima). In più (anteprima mandata): in "Modifica spesa" di una spesa normale (`AddExpenseView`) una riga "Fa parte del viaggio" per collegarla a un viaggio (imposta `tripID`).
- Se la CI dice "L'app si è chiusa da sola (crash)", leggi le annotazioni: ora contengono il motivo e le righe del codice. È già successo due volte senza cambiare il codice (2.29 e 2.35): un nuovo tentativo è passato.

Idee rimaste in sospeso: barre per categoria nelle Statistiche; versione Android (andrebbe riscritta); rinnovi PayPal da email (l'utente manderà un esempio).
