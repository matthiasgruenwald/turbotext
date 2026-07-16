# Apple-Gerätetranskription: Routing und Einrichtung

Stand: 2026-07-16. Recherche für „Kartiere die Umstellung des Transkriptions-Routings und der lokalen Einrichtung“.

## Entscheidungskontext

Apple-Gerätetranskription soll nach erfolgreicher API-/Offline-Prüfung WhisperKit als automatischen lokalen Fallback ersetzen. Ein Schalter erzwingt lokale Transkription. Sprach-Workflows behalten ihre zwei Stufen: Rohtext entsteht mit dem gewählten Transkriptions-Backend; optionale Nachbearbeitung bleibt ein klar erkennbarer Online-Schritt. Ohne genutzte Online-Stufe darf weder Onboarding noch Bedienoberfläche zur Hinterlegung eines API-Keys drängen.

Diese Recherche bewertet keine Apple-API und implementiert nichts.

## Heutiger Ablauf

### Backend- und Workflow-Routing

- `AppState.makeWorkflow` erzeugt für `Turbotext` entweder `.remote` oder `.local`; die Wahl ist aktuell allein `secureLocalModeEnabled` beziehungsweise einem Hotkey-Override geschuldet ([AppState.swift](../../TurbotextMac/App/AppState.swift)).
- `transcriber(for:)` verbindet `.remote` mit `GroqTranscriptionProvider` und `.local` mit `LocalTranscriptionService`/WhisperKit. Der lokale Pfad ignoriert derzeit eigene Begriffe, weil sein Closure die `terms` verwirft.
- `Turbotext Lokal` ist ein separater `WorkflowType` und immer lokal. Er erscheint nicht im Hauptmenü (`mainMenuCases` filtert ihn heraus), kann aber per Shortcut existieren ([WorkflowType+UI.swift](../../TurbotextMac/Features/Workflows/WorkflowType+UI.swift)).
- Alle drei Verbesserer (`Turbotext+`, `Dampf ablassen`, `Emoji-Text`) rufen fest `transcriber(for: .remote)` auf. Zudem sperrt `isWorkflowAvailable` sie im lokalen Modus. Damit gibt es aktuell keinen lokalen Rohtext mit anschließender Online-Nachbearbeitung.
- `GroqTranscriptionProvider` ist kein allgemeiner Backend-Router: Er bevorzugt Groq und wechselt bei Groq-429 zu OpenAI. Dieser Quota-Fallback darf unabhängig von dem geplanten Apple-Lokalfallback bleiben ([GroqTranscriptionProvider.swift](../../TurbotextMac/Services/GroqTranscriptionProvider.swift)).

### Automatischer Fallback und Status

- Beim Hotkey entscheidet `TurbotextMacApp.handleHotkeyDown` mit `TranscriptionFallbackResolver` anhand des Ping-Status über einen Override ([TurbotextMacApp.swift](../../TurbotextMac/App/TurbotextMacApp.swift), [OfflineWarningSoundPlayer.swift](../../TurbotextMac/Services/OfflineWarningSoundPlayer.swift)).
- Dieser Resolver betrifft nur `WorkflowType.transcription`; Verbesserer erhalten bei rotem Netzstatus nur einen Warnsound. Er prüft zusätzlich das installierte WhisperKit-Modell und `autoFallbackToLocalOnOffline`.
- `TranscriptionModeStatus` und die Menüleistenansicht sprechen binär von „Lokal · kein Server“ (WhisperKit) oder „Online“ (Groq/OpenAI). Groq-Quota und -Fallback sind dort sichtbar ([TranscriptionModeStatus.swift](../../TurbotextMac/Services/TranscriptionModeStatus.swift)).

### Einstellungen, lokale Installation und Onboarding

- `AppSettings` persistiert `secureLocalModeEnabled`, das gewählte WhisperKit-Modell, dessen automatische Schnellmodell-Auswahl und `autoFallbackToLocalOnOffline` ([WorkflowSettings.swift](../../TurbotextMac/Features/Workflows/WorkflowSettings.swift)).
- `TranscriptionSettingsView` koppelt den lokalen Modus an Modell-Auswahl, Download, Verifikation und Prewarm. Das Aktivieren des Schalters startet nötigenfalls einen Modell-Download. Die Fallback-Option ist nur bei installiertem Modell aktiv ([TranscriptionSettingsView.swift](../../TurbotextMac/Features/Settings/TranscriptionSettingsView.swift), [LocalModelState.swift](../../TurbotextMac/App/LocalModelState.swift)).
- Als eingerichtet gilt die App derzeit mit einem OpenAI-Key **oder** mindestens einem installierten WhisperKit-Modell; ein bloßer Groq-Key genügt paradoxerweise nicht, weil `KeychainService.isConfigured` nur OpenAI prüft ([AppState.swift](../../TurbotextMac/App/AppState.swift), [KeychainService.swift](../../TurbotextMac/Services/KeychainService.swift)).
- Das Onboarding ist Groq-zentriert und fordert immer zur Schlüssel-Einrichtung auf. Die Zugangsdaten-Seite fokussiert beim Öffnen ohne OpenAI-Key automatisch dessen Feld. Der Banner „Kein API Key hinterlegt“ verschwindet nur im globalen lokalen Modus, nicht workflowbezogen ([MenuBarOnboardingPage.swift](../../TurbotextMac/Features/MenuBar/MenuBarOnboardingPage.swift), [CredentialsSettingsView.swift](../../TurbotextMac/Features/Settings/CredentialsSettingsView.swift), [OnlineKeyHintBanner.swift](../../TurbotextMac/Services/OnlineKeyHintBanner.swift)).

## Minimale Zielzustands-Skizze

1. Einen expliziten, persistenten Transkriptionsmodus modellieren: `online` und `immer lokal`. Ein fachlicher Resolver liefert pro Aufnahme ein Backend; bei `online` und nicht verfügbarem Onlinepfad fällt er automatisch auf Apple-Gerätetranskription zurück. Das Ergebnis muss nicht länger an `WorkflowType.transcription` gebunden sein.
2. Apple als verfügbaren lokalen Backend-Kandidaten hinter derselben Transcriber-Naht einführen. WhisperKit-Modellverwaltung, Download, Prewarm und dessen Einstellungen bleiben aus dem Standardpfad heraus; erst eine separate spätere Kompatibilitätsentscheidung könnte sie wieder als bewusst gewählte Option ergänzen.
3. Jeden Sprach-Workflow zuerst durch denselben Resolver transkribieren lassen. Danach entscheidet allein der Workflow, ob ein Online-Nachbearbeitungsschritt folgt. Ist er gewählt, bleibt der Raw-Text lokal, aber der Workflow-Status und die UI kennzeichnen die Nachbearbeitung deutlich als „online“.
4. Die Verfügbarkeit aufteilen: Reine Transkription ist mit verfügbarer Apple-Gerätetranskription ohne Key startbar. Verbesserer benötigen ausschließlich einen für ihre Nachbearbeitung passenden Key; ein lokaler Rohtext darf sie nicht pauschal deaktivieren.
5. Onboarding, Key-Hinweis, Credentials-Autofokus und Menüleistenstatus aus der tatsächlich aktiven/gewählten Stufe ableiten. Bei ausschließlich lokaler reiner Transkription: keine Key-Aufforderung. Bei Verbesserern ohne passenden Key: gezielter Hinweis auf die Online-Nachbearbeitung, nicht auf die lokale Transkription.
6. Status begrifflich trennen: „Transkription: lokal auf diesem Mac“ und gegebenenfalls „Nachbearbeitung: online“. Der Offline-/Datenschutzhinweis zur Apple-Integration bleibt von der noch offenen API-Prüfung abhängig und darf erst danach die behauptete Garantie präzisieren.

## Eng begrenzte Folgeschritte für die Umsetzung

- Den Backend-Resolver mit Tests isoliert einführen, bevor AppState/Hotkeys umgehängt werden. Testfälle: erzwungen lokal, online verfügbar, online nicht verfügbar → Apple lokal, Verbesserer mit lokalem Rohtext plus online Rewriting.
- Die inzwischen vermischten Bedeutungen von `secureLocalModeEnabled` in einen Transkriptionsmodus und workflowbezogene Online-Anforderungen zerlegen. Dabei die bestehende Groq-429→OpenAI-Logik nicht verändern.
- Erst wenn die Apple-API-Recherche die Laufzeit- und Offline-Garantien festlegt, Availability/Fehlertexte und den genauen macOS-Support in den Resolver aufnehmen.

## Risiken, die kein Routing allein klärt

- Ob Apple Speech die gewünschte Audio-Datei-/Finalisierungsform unterstützt, welche Sprachen offline vorhanden sind und welche macOS-Version nötig ist, entscheidet die parallele Apple-API-Recherche.
- Eigennamen/Hinweise werden beim heutigen WhisperKit-Pfad nicht übergeben. Ob und wie Apple Speech Äquivalente anbietet, ist eine Produkt- und API-Frage; der gemeinsame Resolver sollte sie nicht wegabstrahieren.
- Der aktuelle Ping ist nur eine Vorabentscheidung. Ein Netzfehler während einer bereits gestarteten Online-Transkription fällt derzeit nicht auf WhisperKit zurück. Die Zielentscheidung sollte ausdrücklich festlegen, ob Apple auch für diesen Laufzeitfehler erneut versucht wird.
