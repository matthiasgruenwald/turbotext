# Apple Speech für lokale macOS-Transkription

Stand: 16. Juli 2026. Diese Recherche verwendet ausschließlich Apple-Quellen und beantwortet Wayfinder-Ticket „Prüfe Apple Speech auf vollständig lokale macOS-Transkription“.

## Ergebnis

**Ja, auf macOS 26 gibt es einen geeigneten Apple-Pfad:** `SpeechAnalyzer` mit `DictationTranscriber` (bei fehlender leistungsfähiger Hardware) beziehungsweise `SpeechTranscriber`. Apple dokumentiert ausdrücklich, dass die Transkriptionsmodule von `SpeechAnalyzer` keine Audiodaten der Stimme an Apple-Server senden. `DictationTranscriber` verwendet dieselben Modelle wie die Systemdiktierfunktion beziehungsweise wie die lokale Konfiguration von `SFSpeechRecognizer` und unterstützt keine Sprachen, die nur über das Netz funktionieren.

Für Turbotext ist deshalb `DictationTranscriber` der robuste Ausgangspunkt: Er ist ausdrücklich für Diktat geeignet und als Kompatibilitätsvariante für ältere Hardware vorgesehen. `SpeechTranscriber` kann ergänzend bevorzugt werden, wenn `isAvailable` für das konkrete Gerät `true` liefert.

## Betriebssystem und API-Wahl

Die modernen Klassen `SpeechAnalyzer`, `DictationTranscriber`, `SpeechTranscriber` und `AssetInventory` sind laut dem mit Xcode 26.6 gelieferten macOS-SDK ab **macOS 26.0** verfügbar. Sie sind nicht rückwärts auf macOS 15 oder früher einsetzbar.

Die ältere `SFSpeechRecognizer`-API ist keine gleichwertige Alternative für diesen Zweck. Zwar gibt es auf macOS 10.15+ `requiresOnDeviceRecognition`; Apple sagt dazu, dass damit Audiodaten nicht über das Netz gesendet werden. Die erforderliche Abfrage `supportsOnDeviceRecognition` ist im aktuellen SDK jedoch nur für iOS markiert. Für ein verlässliches macOS-Fallback ist das daher nicht die passende Grundlage.

Quellen:

- [SpeechAnalyzer und Transkriptionsmodule](https://developer.apple.com/documentation/speech/speechanalyzer)
- [DictationTranscriber](https://developer.apple.com/documentation/speech/dictationtranscriber)
- [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
- [Lokale Erkennung der alten API](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)

## Datenschutz- und Offline-Grenze

Apple trennt zwei Aussagen, die Turbotext ebenfalls trennen muss:

1. **Transkriptionsaudio:** Für `SpeechAnalyzer`-Transkriptionsmodule sagt Apple ausdrücklich, dass die Audiodaten der Stimme nicht an Apple-Server gehen. Das erfüllt die technische Kernanforderung an die lokale Transkription.
2. **Absolute Netz- beziehungsweise Telemetriegarantie:** Die API-Dokumentation verspricht nicht, dass das Betriebssystem bei der Nutzung keinerlei Metadaten oder andere Signale austauscht. Apples allgemeine Siri-/Diktat-Datenschutzhinweise nennen für die Systemfunktion optionale Audiofreigaben sowie „related request data“. Daraus lässt sich weder eine Übertragung für `SpeechAnalyzer` ableiten noch eine absolute Null-Telemetrie-Garantie.

Folgerung: Im Produkt darf der Modus als „lokale Transkription – Audio bleibt auf diesem Mac“ bezeichnet werden. Eine weitergehende Aussage wie „vollständig offline, keinerlei Datenverkehr“ braucht vor Freigabe einen Test mit gesperrter Netzverbindung und aktivierter Systemoption „Siri & Diktat verbessern“; sie darf nicht allein aus der API-Dokumentation abgeleitet werden. Die spätere Online-Nachbearbeitung bleibt davon getrennt und muss weiterhin sichtbar als online gekennzeichnet werden.

Quellen:

- [Apple: Berechtigung für Spracherkennung](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition)
- [Apple: Siri, Diktat und Datenschutz](https://www.apple.com/legal/privacy/data/en/ask-siri-dictation/)
- [Apple: On-device processing](https://www.apple.com/privacy/features/)

## Sprache, Modelle und Laufzeitverhalten

Die konkrete Sprachunterstützung ist nicht global garantiert. Die neue API bietet `supportedLocale(equivalentTo:)`, `supportedLocales` und `installedLocales`; erst damit kann Turbotext für `de-DE` die tatsächliche Unterstützung und die lokal installierten Assets feststellen. Fehlende Assets können über `AssetInventory` heruntergeladen und installiert werden. Das ist einmaliger Einrichtungsdatenverkehr, nicht Teil einer Transkription, muss aber in der Produktkommunikation und im Offline-Fall sauber behandelt werden.

Vor dem Ersatz von WhisperKit ist daher ein echter Test auf den Ziel-Macs erforderlich: `de-DE` auflösen, installierte Assets und Offline-Transkription prüfen sowie Qualität und Durchsatz messen. Das ist bewusst ein Folge-Ticket, nicht Ergebnis dieser API-Recherche.

Quellen:

- [Unterstützte und installierte Locales von DictationTranscriber](https://developer.apple.com/documentation/speech/dictationtranscriber/installedlocales)
- [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory)
- [Prüfung der Geräteunterstützung von SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber/isavailable)

## Berechtigungen und Deployment-Risiken

- Die vorhandene Mikrofonberechtigung bleibt notwendig, weil Turbotext weiterhin selbst aufnimmt.
- Für `SpeechAnalyzer` sagt Apple, dass seine Transkriptionsmodule keine Audiodaten an Apple-Server senden; Apples `NSSpeechRecognitionUsageDescription` ist dagegen für APIs vorgesehen, die Nutzerdaten an Apples Spracherkennungsserver senden. Die Umsetzung muss vor dem Release im signierten App-Bundle getestet werden, damit keine unnötige Spracherkennungsfreigabe erscheint.
- Fehlen Geräteunterstützung, `de-DE` oder die lokalen Assets, muss der lokale Schalter einen verständlichen nicht-online Fehler liefern. Ein stiller Wechsel auf Online-Transkription wäre mit dem Modusversprechen unvereinbar.
- Das neue Streaming-Zubehör der API ist teilweise als Beta markiert. Turbotext kann das bestehende Aufnahmeende-zu-Endtranskript-Verhalten beibehalten und die vorhandenen Audiopuffer über `AnalyzerInputConverter` zuführen; Live-Text ist nicht erforderlich.

## Entscheidung für die weitere Planung

Die Apple-Speech-Integration ist technisch als **macOS-26+-lokaler Ersatz für WhisperKit** tragfähig. Die Route sollte auf `SpeechAnalyzer` plus `DictationTranscriber` aufbauen, mit Laufzeitprüfungen für Locale, Assets und Hardware. Die offene Produktfrage ist keine API-Frage mehr, sondern die praktische Eignung: Deutschqualität, Tempo auf M1 und eine nachweislich netzfreie Ausführung nach der Modellersteinrichtung.
