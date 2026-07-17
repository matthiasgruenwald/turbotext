# Benchmark: Apple-Gerätetranskription gegen WhisperKit auf macOS

**Stand:** 16. Juli 2026  
**Wayfinder-Ticket:** [Vergleiche Apple-Gerätetranskription mit WhisperKit auf unterstützten Macs](https://github.com/matthiasgruenwald/turbotext/issues/101)

## Ergebnis

Ein belastbarer Qualitäts- und Geschwindigkeitsvergleich ist auf diesem Ziel-Mac noch **nicht abgeschlossen**: Die Maschine erfüllt die Plattformvoraussetzungen, aber es liegt kein freigegebenes deutsches Sprach-Fixture vor und die Apple-`de-DE`-Assets sind noch nicht installiert. Ein Ergebnis ohne denselben Audioeingang für beide Backends wäre nicht aussagekräftig.

Die technische Eignung für den Test ist dagegen bestätigt: MacBook Air (M1, 16 GB), macOS 26.5.2, Xcode 26.6/SDK 26.5; das lokale `openai_whisper-small_216MB`-WhisperKit-Modell ist installiert. Der isolierte, kompilierbare Apple-Probe liegt in [`TurbotextMac/Prototypes/AppleSpeechBenchmark`](../../TurbotextMac/Prototypes/AppleSpeechBenchmark/). Er lädt keine Assets nach und beendet sich mit Status 69, wenn Apple-Assets fehlen.

Der Probe wurde auf diesem Mac mit einer nicht vertraulichen, synthetisch erzeugten deutschen AIFF-Datei ausgeführt. Ergebnis: `asset-status=supported`, installierte Locales `de_DE,en_US`, aber kein installierter `de-DE`-Assetstand. Das ist ein sauberer Nachweis der aktuellen Blockade; der Probe startet keine Installation. Die TTS-Datei wurde danach gelöscht und ist kein Qualitätsfixture.

**Entscheidung:** WhisperKit nicht anhand dieses Tickets ersetzen. Der Messaufbau ist bereit; der Austausch bleibt von den unten definierten Messergebnissen abhängig.

## Reproduzierbarer Messaufbau

### Fixe Testmatrix

Auf dem M1-Testgerät dieselben drei nicht vertraulichen, von einem Menschen gesprochenen `de-DE`-Fixtures nutzen:

| Fixture | Länge | Zweck |
| --- | ---: | --- |
| `kurz` | 8–15 s | typische einzelne Turbotext-Diktierung |
| `normal` | 30–60 s | Satzzeichen, Eigennamen, Zahlen und Fachbegriffe |
| `lang` | 2–3 min | längere Passage, Pausen und thermische Stabilität |

Jede Datei als PCM-WAV oder M4A/AAC mit dokumentierter Abtastrate aufbewahren; daneben steht eine manuell geprüfte Referenztranskription. Keine realen Kundendiktate committen oder in Issue-Kommentare kopieren.

Für jeden Lauf: fünf Wiederholungen pro Fixture und Backend, zuerst ein ungewerteter Warm-up-Lauf. Apple nutzt `DictationTranscriber(locale: de-DE, preset: .longDictation)`; WhisperKit nutzt den vorhandenen `openai_whisper-small_216MB`-Pfad und dieselben Sprachparameter wie Turbotext. Die Reihenfolge pro Wiederholung abwechseln, damit Cache- und Temperatur-Effekte beide Seiten treffen.

### Messwerte

| Kriterium | Erfassung | Akzeptanzfrage |
| --- | --- | --- |
| Zeit bis finaler Text | monotone Uhr von Start der Analyse bis zum letzten finalen Ergebnis; Median und p95 | Ist Apple auf M1 für kurze Diktate schneller oder mindestens nicht merklich langsamer? |
| Deutsche Qualität | Wortfehlerrate (WER) gegen Referenz; zusätzlich manuelle Liste der Fehler bei Satzzeichen, Namen, Zahlen und Komposita | Ist Apple mindestens gleichwertig für die typische Diktierung? |
| Ressourcen | `powermetrics`/Aktivitätsanzeige: CPU-Auslastung, Speicher, Energieimpact; Peak und Median dokumentieren | Ist Apple ohne unverhältnismäßigen Energie- oder Speicherbedarf nutzbar? |
| Kaltstart | erste Analyse nach App-Start getrennt erfassen | Wird die fehlende Modellinstallation nicht durch eine störende Startlatenz ersetzt? |

Der Apple-Probe misst bereits Asset-Status, installierte Locales, finalen Text und Zeit bis finalem Text. WhisperKit muss für den Vergleich über den existierenden `LocalTranscriptionService` als gleichwertiger separater Probe oder über instrumentierte Debug-Ausgaben laufen; der Produktionscode wird dafür nicht verändert.

## Offline-Nachsweis (Release-Voraussetzung)

Die Apple-Dokumentation belegt, dass SpeechAnalyzer-Transkriptionsmodule keine Stimm-Audiodaten an Apple-Server senden. Das genügt nicht für die im Projekt definierte stärkere Zusage „lokal und offline“: Auch Analyse- oder Telemetriedaten dürfen nicht abfließen.

1. Apple-`de-DE`-Assets einmalig bei vorhandener Verbindung installieren; danach die Asset-Status-Ausgabe festhalten.
2. Vor dem Lauf alle Netzwerkadapter deaktivieren oder eine Firewall-Regel setzen, die dem signierten Turbotext-Bundle sämtlichen ausgehenden Verkehr verbietet. Kein DNS-Ausweichpfad darf bestehen.
3. Apple-Probe und den vollständigen Turbotext-Workflow mit jedem Fixture ausführen; Erfolg, finalen Text und Laufzeit festhalten.
4. Gleichzeitig mit `nettop` oder einem Paketmitschnitt prüfen, dass der Prozess keine Verbindung aufbaut. Den Test nach einem Neustart wiederholen.
5. Scheitert Apple ohne Netz, gilt der Pfad nicht als Offline-Fallback. Meldet der Mitschnitt Verkehr, darf Turbotext ihn nicht als vollständig offline/DSGVO-lokal bewerben, selbst wenn die Transkription weiterläuft.

Die Assets selbst können eine einmalige, sichtbare Installation benötigen; dieser Download ist nicht Teil einer Offline-Transkription und muss im Produkt getrennt erklärt werden.

## Ausführung auf dem Ziel-Mac

```zsh
./TurbotextMac/Prototypes/AppleSpeechBenchmark/run.sh /absoluter/pfad/zu/fixture.m4a
```

Der Lauf benötigt macOS 26 und Xcode 26. Auf älteren macOS-Versionen ist der Probe bewusst nicht lauffähig. Für die Ressourcenmessung kann parallel ein vom Nutzer autorisierter `sudo powermetrics`-Lauf verwendet werden; ohne Administratorrechte reichen Aktivitätsanzeige oder Instruments als Vergleichsprotokoll.

## Offene Übergabe

Sobald ein freigegebenes deutsches Fixture vorliegt und die Apple-Assets einmalig installiert wurden, führt ein einzelner Messdurchgang nach dieser Anleitung die noch offene Entscheidung herbei. Kein Produktcode und keine Produktkonfiguration wurden in diesem Ticket geändert.
