# SpeechAnalyzer am Live-Mikrofonstrom auf macOS 26

Stand: 30. Juli 2026. Diese Recherche beantwortet GitHub Issue #138 (Child-Ticket der Wayfinder-Map #137 „Live-Diktat mit Apple Speech und gemeinsamer Kern für eine iOS-Tastatur") und klärt, wie `SpeechAnalyzer` mit laufendem Mikrofonaudio statt mit einer fertigen Datei betrieben wird.

Ausgangslage im Code auf `dev`: `AppleSpeechTranscriptionService.transcribe` erzeugt einen `DictationTranscriber(locale: de-DE, preset: .progressiveLongDictation)`, baut einen `SpeechAnalyzer(modules:)` und startet ihn mit `analyzer.start(inputAudioFile:finishAfterFile:)`. Die Datei entsteht vorher in `AudioRecorder` über einen `AVAudioEngine`-Tap. Der vorhandene `partialTranscriptHandler` feuert deshalb erst *nach* dem Sprechen — er sieht Teilergebnisse aus der Dateianalyse, nicht aus dem Live-Strom.

## 1. Der Streambetrieb: `start(inputSequence:)`

`SpeechAnalyzer` hat neben der Datei-Variante eine Sequenz-Variante:

```swift
final func start<InputSequence>(inputSequence: InputSequence) async throws
  where InputSequence: Sendable, InputSequence: AsyncSequence,
        InputSequence.Element == AnalyzerInput
```

Das Element ist `AnalyzerInput`, erzeugbar aus einem Audiopuffer über `init(buffer:)` bzw. `init(buffer:bufferStartTime:)`. Apple beschreibt in der WWDC25-Session das übliche Muster mit einem `AsyncStream`:

```swift
(inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
try await analyzer?.start(inputSequence: inputSequence)

// pro Audiopuffer, aus dem Tap heraus:
let converted = try converter.convertBuffer(buffer, to: analyzerFormat)
inputBuilder.yield(AnalyzerInput(buffer: converted))
```

Ein- und Ausgabe sind dabei bewusst entkoppelt: „Your application can add audio as it becomes available in one task and display or further process the results independently in another task. Swift's async sequences buffer and decouple the input and results."

Das Format ist nicht frei wählbar. `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` liefert das erwartete Format; die Puffer aus dem Tap müssen per `AVAudioConverter` **exakt** darauf konvertiert werden, sonst nimmt der Analyzer sie nicht an.

## 2. Volatile und finalisierte Ergebnisse

Der entscheidende Unterschied zum heutigen Dateipfad. Apple in derselben Session:

> „We call the immediate rough results 'volatile results'. They're delivered almost as soon as they're spoken but they are less accurate guesses."

> „However, the model improves its transcription as it gets more audio with more context. Eventually, the result will be as good as it can be, and the transcriber delivers one last finalized result. Once it does that, the transcriber won't deliver any more results for this range of audio, and it moves on to the next range."

> „Note how the timecodes show that later, improved results replace earlier results. This only happens when you enable volatile results. Normally, the transcriber only delivers finalized results, and none of them replace earlier results."

Volatile Ergebnisse müssen über `ReportingOption` eingeschaltet werden. Verfügbar sind `.volatileResults`, `.frequentFinalization` und `.alternativeTranscriptions`. Die „progressiven" Presets (`progressiveShortDictation`, `progressiveLongDictation`) sind genau die Vorkonfigurationen mit volatilen Ergebnissen — das heute genutzte `.progressiveLongDictation` ist für Live-Diktat also bereits die richtige Wahl.

Zusätzlich exponiert der Analyzer `volatileRange: CMTimeRange?` und `setVolatileRangeChangedHandler(_:)`. Damit ist jederzeit bekannt, welcher Zeitbereich noch instabil ist — das ist die belastbare Grenze zwischen „darf schon korrigiert werden" und „ändert sich noch".

**Für Ticket #141 (Live-Korrektur) folgt daraus:** Ein finalisiertes Ergebnis ist das saubere Signal für „dieser Textbereich steht fest". `.frequentFinalization` verkürzt die volatile Phase und liefert früher finalisierte Abschnitte — der Hebel, um satzweise Korrektur überhaupt früh genug ansetzen zu lassen. Ob die Finalisierungsgrenzen im Deutschen mit Satzgrenzen zusammenfallen, ist nicht dokumentiert und muss auf dem Gerät nachgemessen werden.

## 3. Fallstrick: finalisierte Ergebnisse sind Segmente, nicht der Gesamttext

Der bestehende Code sammelt so:

```swift
if result.isFinal {
    finalText = text   // überschreiben
}
```

mit dem Kommentar, jedes finale Ergebnis trage bereits den laufenden Gesamttext — empirisch validiert im Datei-Modus über `AppleSpeechProbe.swift` (Wayfinder #101/#104).

Apples eigenes Streaming-Beispiel macht das Gegenteil:

```swift
if result.isFinal {
    finalizedTranscript += text   // anhängen
    volatileTranscript = ""
} else {
    volatileTranscript = text
}
```

Das passt zur Beschreibung „the transcriber won't deliver any more results for this range of audio, and it moves on to the next range": im volatilen Betrieb sind finale Ergebnisse **Abschnitte**, die angehängt gehören.

**Das ist der wichtigste Punkt dieser Recherche.** Wird die Sammellogik aus dem Dateipfad unverändert in den Streambetrieb übernommen, bleibt am Ende nur der letzte Abschnitt übrig statt des ganzen Diktats — ein stiller Datenverlust, der in kurzen Tests nicht auffällt. Das Verhalten muss auf dem M1 mit macOS 26 an einem mehrsätzigen deutschen Diktat gemessen werden, bevor Code darauf gebaut wird.

## 4. Ein Tap für beides

`AVAudioEngine` erlaubt pro Bus genau einen Tap; ein zweiter `installTap(onBus: 0, ...)` ersetzt den ersten. Der bestehende Tap in `AudioRecorder` muss also beides bedienen: den Puffer wie bisher in die `.m4a`-Datei schreiben **und** ihn konvertiert in den `AnalyzerInput`-Stream geben. Ein separater Analyzer-Tap ist keine Option.

Das ist zugleich der Fallback-Mechanismus: Die Datei entsteht weiterhin vollständig. Bricht der Streambetrieb ab, kann der Lauf über den bestehenden Dateipfad zu Ende geführt werden, ohne das Diktat zu verlieren. Groq, OpenAI und WhisperKit bleiben davon ohnehin unberührt.

## 5. Beenden, Abbrechen, Vorwärmen

- `finalizeAndFinishThroughEndOfInput()` — regulärer Abschluss: alles noch Volatile wird finalisiert, dann endet die Analyse.
- `finalize(through:)` — erzwingt Finalisierung bis zu einem Zeitpunkt; nützlich, wenn ein Abschnitt früher feststehen soll als der Transcriber ihn von selbst finalisiert.
- `cancelAndFinishNow()` / `cancelAnalysis(before:)` — Abbruch.
- `prepareToAnalyze(in:)` bzw. `prepareToAnalyze(in:withProgressReadyHandler:)` — Vorwärmen für schnellere erste Ergebnisse. Turbotext hat mit `PrewarmObserver` bereits eine Stelle, an die das gehört.

## 6. Offenes Risiko: Bluetooth-Mikrofone und `installTap`

Aus Apples Entwicklerforum zu macOS 26 gibt es Berichte, dass der `installTap`-Callback bei Bluetooth-Eingabegeräten nicht feuert, während er mit eingebauten Mikrofonen zuverlässig läuft; als Ausweichweg wird `AVCaptureSession` genannt, deren Delegate-Callback geräteunabhängig feuert.

Das trifft Turbotext an einer bekannten Stelle: `AudioRecorder` heftet das bevorzugte Gerät per CoreAudio direkt an die Engine (ADR-0003), und es gab bereits Bluetooth-Befunde (#129, sowie das offene #132 „confirm real microphone signal after device changes"). Ist der Bericht zutreffend, verliert Live-Diktat auf Bluetooth-Headsets nicht nur den Live-Text, sondern die Aufnahme selbst — heute schon, unabhängig vom Streaming. Das gehört auf einem echten Bluetooth-Headset überprüft.

## 7. Was gemessen werden muss, bevor Code entsteht

Dokumentation trägt bis hierhin; der Rest ist unbelegt und braucht den M1 mit macOS 26:

1. Liefern finale Ergebnisse im Streambetrieb Abschnitte (anhängen) oder den Gesamttext (überschreiben)? — siehe Abschnitt 3.
2. Wie lange dauert es vom gesprochenen Wort bis zum ersten sichtbaren volatilen Text?
3. Fallen Finalisierungsgrenzen im Deutschen mit Satzgrenzen zusammen, und wie verschiebt `.frequentFinalization` das?
4. Gibt es praktische Längen- oder Speichergrenzen bei mehrminütigen Diktaten?
5. Feuert der `installTap`-Callback auf einem Bluetooth-Mikrofon?

## 8. Messung auf dem M1 (macOS 26.5.2, Nachtrag zu Issue #143)

Gemessen mit einem Wegwerf-Probe (`TurbotextMac/Prototypes/AppleSpeechLiveStreamProbe/`), der eine bestehende deutsche Audiodatei buffer­weise in Echtzeit-Takt (100-ms-Chunks, mit Schlaf zwischen den Chunks) in `analyzer.start(inputSequence:)` einspeist — das reproduziert exakt den Fall eines `AVAudioEngine`-Tap, ohne dass jemand tatsächlich ins Mikrofon sprechen muss. Als Diktat diente ein per `say -v Anna` synthetisiertes, mehrsätziges deutsches Sprachsignal (~65 s bzw. ~195 s für den Langlauf); die de-DE-Assets mussten für dieses unsignierte CLI-Binary bei jedem Prozessstart neu über `AssetInventory.assetInstallationRequest` angefordert werden, da eine Installation ohne stabile Bundle-Identität/Entitlements nicht über Prozessgrenzen hinweg persistiert.

1. **Sammelverhalten — bestätigt: anhängen, nicht überschreiben.** Bei einem 65-Sekunden-Diktat kamen genau zwei finale Ergebnisse: eines nach 60,9 s mit 884 Zeichen (praktisch das gesamte bisherige Diktat als ein Abschnitt), eines nach 64,9 s mit den restlichen 75 Zeichen. Angehängt ergibt das die vollen 959 Zeichen des Originaltexts. Nimmt man stattdessen nur das letzte finale Ergebnis (Überschreiben-Annahme aus dem Dateipfad), bleiben 75 von 959 Zeichen übrig — **über 90 % des Diktats gingen verloren.** Damit ist Abschnitt 3 empirisch bestätigt: Die Sammellogik aus dem Dateipfad (`finalText = text`) darf nicht unverändert in den Streambetrieb übernommen werden.
2. **Latenz.** Erster sichtbarer volatiler Text nach ~1,0 s ab Sprechbeginn (vier Messläufe: 1,035–1,048 s, sehr stabil). Bis zur Finalisierung desselben ersten Abschnitts vergingen dagegen **~60 Sekunden** — mit reinem `.volatileResults` blieb praktisch das komplette einminütige Diktat ein einziger, fortlaufend wachsender volatiler Abschnitt, bis der reguläre Stream-Abschluss (`finalizeAndFinishThroughEndOfInput()`) die Finalisierung erzwang.
3. **Satzgrenzen und `.frequentFinalization`.** Der eine erzwungene Finalisierungs-Schnitt (bei ~60,9 s) fiel zufällig mit einem Satzende zusammen. `.frequentFinalization` zusätzlich gesetzt lieferte in einem identisch aufgebauten Lauf **exakt dieselben zwei Finalisierungszeitpunkte** (60,86 s / 64,91 s) und nahezu denselben Text — kein messbarer Unterschied. Bei durchgehend gesprochenem Text ohne echte Sprechpausen (wie bei synthetischer TTS-Sprache) triggert die Option offenbar keine zusätzliche Finalisierung; sie scheint an erkannte Pausen bzw. Stille gekoppelt zu sein, nicht an eine feste Zeit- oder Wortgrenze. **Für #141 heißt das: Ohne echte Sprechpausen ist mit `.frequentFinalization` allein keine satzweise Korrektur binnen Sekunden zu erwarten** — das widerspricht der ursprünglichen Erwartung aus Abschnitt 2 dieses Dokuments.
4. **Lange Diktate.** Ein Lauf über ~3:15 Minuten (dreifach verkettetes Diktat) lief fehlerfrei durch: vier finale Abschnitte, Speicherverbrauch (`peak resident memory`) blieb bei ~20 MB — praktisch identisch zum 65-Sekunden-Lauf (~19–20 MB). Keine Anzeichen für Speicher- oder Längenprobleme im getesteten Bereich.
5. **Bluetooth.** Auf diesem M1 war zum Testzeitpunkt kein Bluetooth-Mikrofon verbunden (zwei gekoppelte, aber nicht verbundene Headsets in den Bluetooth-Einstellungen). Dieser Punkt bleibt unbeantwortet und braucht einen erneuten Test mit angeschlossenem Bluetooth-Headset.

**Nebenbefund (Probe-Implementierung, kein Speech-API-Verhalten):** Beim letzten, kürzeren Audio-Chunk am Dateiende wirft sowohl `AVAudioFile.read(into:frameCount:)` als auch der `AVAudioConverterInputHandler` gelegentlich einen Fehler statt sauber ans Ende zu kommen — vermutlich weil der Rest-Chunk die Resampling-Ratio nicht mehr exakt erfüllt. Das ist ein reines Artefakt der Buffer-Chunking-Probe (in beiden Fällen abgefangen und als Ende-der-Datei behandelt), keine Eigenschaft von `SpeechAnalyzer` selbst.

## Quellen

- [SpeechAnalyzer – Apple Developer Documentation](https://developer.apple.com/documentation/speech/speechanalyzer)
- [SpeechAnalyzer.start(inputSequence:) – Apple Developer Documentation](https://developer.apple.com/documentation/speech/speechanalyzer/start(inputsequence:))
- [AnalyzerInput – Apple Developer Documentation](https://developer.apple.com/documentation/speech/analyzerinput)
- [DictationTranscriber – Apple Developer Documentation](https://developer.apple.com/documentation/speech/dictationtranscriber)
- [DictationTranscriber.ReportingOption – Apple Developer Documentation](https://developer.apple.com/documentation/speech/dictationtranscriber/reportingoption)
- [DictationTranscriber.Preset – Apple Developer Documentation](https://developer.apple.com/documentation/speech/dictationtranscriber/preset)
- [Bring advanced speech-to-text to your app with SpeechAnalyzer – WWDC25](https://developer.apple.com/videos/play/wwdc2025/277/)
- [Implementing advanced speech-to-text in your SwiftUI app – Create with Swift](https://www.createwithswift.com/implementing-advanced-speech-to-text-in-your-swiftui-app/)
- [Building Real-Time Voice Input on macOS 26 with SpeechAnalyzer + ScreenCaptureKit – Apple Developer Forums](https://developer.apple.com/forums/thread/819555)
