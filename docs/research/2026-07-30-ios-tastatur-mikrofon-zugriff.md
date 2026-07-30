# Mikrofon- und Speech-Zugriff in einer iOS-Tastaturerweiterung

Stand: 30. Juli 2026. Diese Recherche beantwortet GitHub Issue #139 (Child-Ticket der Wayfinder-Map #137 „Live-Diktat mit Apple Speech und gemeinsamer Kern für eine iOS-Tastatur") und klärt, ob eine iOS-Custom-Keyboard-Extension selbst diktieren kann.

## 1. Die kurze Antwort: nein

Eine iOS-Tastaturerweiterung hat **keinen Zugriff auf das Mikrofon**. Das ist keine Berechtigungsfrage, die sich mit „Vollzugriff erlauben" lösen ließe, sondern eine Plattformgrenze. Berichte aus dem Apple-Entwicklerforum zeigen, dass der Start einer `AVAudioEngine` in der Extension auch dann fehlschlägt (Fehler 561145187), wenn Vollzugriff *und* Mikrofonberechtigung erteilt wurden.

Damit fällt die naheliegende Vorstellung — eine Turbotext-Tastatur mit eigenem Diktat-Knopf, die überall diktiert — als Bauform aus. Was in der Tastatur bleibt, ist Apples eigener Mikrofonknopf in der Systemleiste: Das ist Apples Systemdiktat, nicht Turbotext, also ohne Eigennamen-Liste, ohne Korrekturstufen, ohne Rewrite-Workflows.

## 2. Die Referenz bestätigt das

[QuickTextMobile](https://github.com/simplyniels/quicktext-app) — die vom Auftraggeber benannte Vorlage und Geschwisterprojekt von Turbotext — hat dieselbe Grenze dokumentiert und sich danach gerichtet. Aus deren `docs/setup-ios.md`:

> „iOS third-party keyboard extensions cannot access the microphone, draw outside their keyboard view, or show a floating overlay above another app."

> „The current design keeps microphone capture in the containing app and uses the keyboard only for explicit insertion. This is the closest reliable system-wide flow available through public iOS APIs."

Deren tatsächlicher Ablauf pro Diktat:

1. Nutzerin öffnet die Quick-Text-App und tippt dort das Mikrofon an.
2. Sprechen, Stopp antippen. Aufnahmen enden automatisch nach 60 Sekunden.
3. Die App transkribiert (`whisper-1`), führt optional den Rewrite-Workflow aus und legt das Ergebnis **in die Zwischenablage**.
4. Zurück in die Ziel-App, per Globus-Taste auf die Quick-Text-Tastatur wechseln, „Letztes Diktat einfügen" antippen.

Die Extension liest die Zwischenablage ausschließlich bei diesem ausdrücklichen Tippen und fügt über `textDocumentProxy` am Cursor ein. „Allow Full Access" wird genau dafür gebraucht — für den Zwischenablage-Zugriff, nicht fürs Mikrofon.

Weitere Grenzen aus derselben Quelle: Sichere Textfelder, Telefonfeld-Eingaben und Apps, die Fremdtastaturen ablehnen, bekommen die Systemtastatur; eine App kann jede Drittanbieter-Tastatur pauschal ablehnen, und die Tastatur kann das nicht überstimmen.

## 3. Bauformen und ihre Kosten

Aus der Grenze folgen genau zwei tragfähige Formen, plus eine, die ausscheidet:

**A — Container-App diktiert, Tastatur fügt ein** (Quick-Text-Modell, funktioniert nachweislich)
Vier Interaktionen pro Diktat: App wechseln, diktieren, zurückwechseln, Tastatur wechseln und einfügen. Der App-Wechsel ist der Preis. Dafür läuft in der App alles, was Turbotext kann — Apple Speech lokal, Live-Text während des Sprechens, Korrekturstufen, Rewrite-Workflows.

**B — Nur App, ohne Tastatur** (Teilen/Zwischenablage)
Diktieren in der App, Ergebnis manuell einfügen. Spart die Tastatur-Einrichtung samt Vollzugriff, kostet dafür bei jedem Einfügen einen Handgriff mehr.

**C — Tastatur diktiert selbst** — scheidet aus, siehe Abschnitt 1.

Der Übergabekanal zwischen App und Extension ist offen: Quick Text nimmt die Zwischenablage; eine App Group oder Keychain Access Group wäre die Alternative, die die Zwischenablage der Nutzerin nicht überschreibt. Das gehört in die Bauform-Entscheidung, nicht in diese Recherche.

## 4. Was das für Turbotext bedeutet

Der Unterschied zur Referenz bleibt trotz der Plattformgrenze erhalten, und zwar genau dort, wo er erwartet wurde: Quick Text schickt Audio an `whisper-1`, braucht also einen OpenAI-Schlüssel und eine Netzverbindung. Turbotext hat mit `AppleSpeechTranscriptionService` bereits den geräteinternen Weg gebaut, und `SpeechAnalyzer`/`DictationTranscriber` sind ab **iOS 26** ebenso verfügbar wie ab macOS 26. Eine Turbotext-iOS-App könnte also lokal diktieren, ohne Schlüssel und ohne Netz — und mit sichtbarem Live-Text während des Sprechens, weil die Container-App im Gegensatz zur Extension eine normale App mit Mikrofonzugriff ist.

Die Plattformgrenze kostet den Komfort des systemweiten Diktats, nicht die Substanz der Funktion.

Was zu prüfen bleibt, wenn die Bauform entschieden ist: Sprachassets und Speicherbudget auf dem iPhone (auf macOS mussten die de-DE-Assets erst installiert werden, siehe #133), sowie ob Apple Foundation Models für die Korrekturstufen auf der Zielhardware verfügbar sind.

## Quellen

- [Quick Text – Setup on iOS](https://github.com/simplyniels/quicktext-app/blob/main/docs/setup-ios.md)
- [QuickTextMobile README](https://github.com/simplyniels/quicktext-app/blob/main/QuickTextMobile/README.md)
- [Quick Text README](https://github.com/simplyniels/quicktext-app/blob/main/README.md)
- [Error 561145187 – Recording audio from keyboard extension – Apple Developer Forums](https://developer.apple.com/forums/thread/775077)
- [Custom Keyboard Audio Recording – Apple Developer Forums](https://developer.apple.com/forums/thread/23355)
- [Record microphone in a Keyboard app (in the background) – Apple Developer Forums](https://developer.apple.com/forums/thread/800500)
- [Limitations of custom iOS keyboards – inFullMobile](https://medium.com/@inFullMobile/limitations-of-custom-ios-keyboards-3be88dfb694)
- [DictationTranscriber – Apple Developer Documentation](https://developer.apple.com/documentation/speech/dictationtranscriber) (iOS 26.0+)
