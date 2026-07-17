# Vorläufige A/B-Messnotizen

**Status:** Apple Speech ist in diesem Prototypen als deutlich schnellerer lokaler Kandidat bestätigt. Der Netzsperrtest war erfolgreich und `nettop` zeigte für den Prototyp-Prozess keine externe TCP- oder UDP-Verbindung.

## Beobachtungen vom 17. Juli 2026

Dieselbe deutsche Aufnahme wurde nacheinander mit Apple Speech und dem installierten WhisperKit-Modell `openai_whisper-small_216MB` verarbeitet.

| Aufnahme | Apple Speech | WhisperKit | Textqualität |
| --- | ---: | ---: | --- |
| Kurz: „Kurze Testaufnahme“ | 0,51 s | 56,45 s | Beide Texte inhaltlich gleich; WhisperKit setzte einen Punkt. Die WhisperKit-Zeit ist ein Kaltstartwert. |
| Länger: freie deutsche Diktierung mit „UI“ und englischen Wörtern, bei aktiver Netzsperre | 1,66 s | 3,20 s | Beide Texte sind gut verständlich und im Wesentlichen gleichwertig; Apple Speech und WhisperKit blieben funktionsfähig. |

Die Messung zeigt einen sehr deutlichen Apple-Vorteil beim Kaltstart und einen Vorteil auch nach dem Laden von WhisperKit. Die Offline-Funktionalität ist unter aktiver Netzsperre bestätigt. Für eine umfassende Leistungsbewertung fehlen noch Wiederholungen, Warm-up-Läufe und definierte Referenztexte.

## Stolpersteine für die spätere Umsetzung

- Apple Speech steht erst ab macOS 26 zur Verfügung; `de-DE` muss im laufenden App-Bundle über `AssetInventory.status(forModules:)` den Zustand `installed` melden. `supported` bedeutet nur unterstützte Sprache, nicht installierte Assets.
- Fehlende Assets vor jedem `SpeechAnalyzer`-Start abfangen. Der Framework-Aufruf trappt in dieser Konstellation, statt einen zuverlässig behandelbaren Swift-Fehler zu liefern.
- Fehlende Assets nur nach expliziter Nutzeraktion mit `AssetInventory.assetInstallationRequest(supporting:)` und `downloadAndInstall()` laden. Der Download ist Einrichtung und kein Offline-Transkriptionslauf.
- `SpeechAnalyzer(inputAudioFile:modules:)` startet die Analyse bereits. Danach darf für dieselbe Datei nicht erneut `start(inputAudioFile:finishAfterFile:)` aufgerufen werden. Robuster Pfad: `SpeechAnalyzer(modules:)` erzeugen und die Datei genau einmal mit `start` übergeben.
- Den Assetstatus durch den ausliefernden Prozess prüfen. In diesem Versuch meldete ein separat im temporären Verzeichnis gebauter Probe nach der Installation noch `supported`, während der Prototyp `installed` sah.
- Apple und WhisperKit stets mit derselben fertigen Aufnahme vergleichen; keine Kundendiktate in das Repository oder Issue-Kommentare übernehmen.
- WhisperKit-Kaltstart und Warmstart getrennt messen. Der kurze Lauf mit 56,45 s enthält offenbar Laden/Prewarm und ist nicht direkt mit dem 3,20-s-Warmstart vergleichbar.
- Der Netzsperrtest mit der längeren Aufnahme war erfolgreich. Ein anschließender `nettop -n -t external -p AppleSpeechWhisperKitComparison -l 0 -s 1`-Lauf zeigte während der Messung nur Kopfzeilen und keine Verbindung für den Prototyp-Prozess. Das ist ein guter Prozessnachweis, schließt aber Verkehr eines separaten Systemprozesses nicht aus; dafür wäre ein systemweiter Paketmitschnitt erforderlich.
