# Issue #202: Mikrofonidentität beim USB-Portwechsel

Messung am 18.10.2026, 11:30–11:34 Uhr (Europe/Berlin), gemeinsam mit dem Nutzer an der laufenden Turbotext-App. Keine Aufnahme, kein Neubau, keine Änderung von Einstellungen oder Favoriten. #201 war ausdrücklich nicht Gegenstand der Untersuchung.

## Ergebnis

Das angeschlossene USB MIC PRO behält bei Port A → Port B → Port A seine CoreAudio-UID. Die automatische Favoritenauswahl funktioniert beim Wechsel, beim Abziehen und nach der Rückkehr. Die geöffnete Favoritenansicht aktualisiert ihre Geräteverfügbarkeit dagegen nicht. Die vorhandenen Fifine-/CMEDIA-Einträge lassen sich mit diesem Mikrofonversuch nicht sicher als physische Duplikate nachweisen.

## Identitätsmerkmale

In allen drei angeschlossenen Zuständen identisch:

- Name: `USB MIC PRO`
- Hersteller: `Generic`
- CoreAudio-UID: `AppleUSBAudioEngine:Generic:USB MIC PRO:20230714100308:1`
- Modell-UID: `USB MIC PRO:8F92:0F9C`
- CoreAudio- und USB-Seriennummer: `20230714100308`
- Transport: `usb `
- USB VID/PID: `0x8F92` / `0x0F9C`; Geräterevision `0x0100`

Veränderliche Verbindungsmerkmale:

- Port A, 11:30:26: AudioDeviceID `117`, locationID `0x01140000`, Registry-ID `4295255249`, USB-sessionID `7399987131278`.
- Port B, 11:31:05: AudioDeviceID `119`, locationID `0x01122000`, Registry-ID `4295326957`, USB-sessionID `8827724934969`.
- Zurück an A, 11:33:58: AudioDeviceID `119`, locationID `0x01140000`, Registry-ID `4295327254`, USB-sessionID `8831982798926`.

USB-Pfad A: `/Root/AppleT8103USBXHCI/USB2.0 Hub/USB MIC PRO`.
USB-Pfad B: `/Root/AppleT8103USBXHCI/USB2.0 Hub/USB2.0 Hub/USB MIC PRO`.
Die USB-Adresse blieb zufällig bei `10`; sie taugt ebenso wenig wie Pfad, locationID oder AudioDeviceID als persistente Geräteidentität. Beide getesteten Anschlüsse liegen in derselben Hub-Topologie; andere Docks/Computer wurden nicht getestet.

## Gespeicherter Ausgangszustand

`turbotext.microphoneUseSystemDefault = false`. Die zehn Favoriten blieben in allen vier Messungen einschließlich Abziehen in exakt derselben Reihenfolge gespeichert:

1. `AppleUSBAudioEngine:Unknown Manufacturer:Fifine Microphone:133000:1`
2. `AppleUSBAudioEngine:Unknown Manufacturer:Fifine Microphone:120000:1`
3. `AppleUSBAudioEngine:Generic:USB MIC PRO:20230714100308:1`
4. `AppleUSBAudioEngine:Unknown Manufacturer:Jabra Speak 710:50C2ED594D02:2`
5. `AppleUSBAudioEngine:CMEDIA:USB PnP Audio Device:143000:1`
6. `AppleUSBAudioEngine:CMEDIA:USB PnP Audio Device:1143000:1`
7. `AppleUSBAudioEngine:Unknown Manufacturer:Fifine Microphone:1133000:1`
8. `BuiltInMicrophoneDevice`
9. `AppleUSBAudioEngine:Unknown Manufacturer:Fifine Microphone:1140000:1`
10. `A4-C1-39-1E-34-55:input`

`selectedMicUID` war an A, B und erneut A die USB-MIC-PRO-UID. Abgezogen (11:31:55) fehlte das Gerät sowohl in CoreAudio als auch im USB-Baum; `selectedMicUID` wechselte auf `BuiltInMicrophoneDevice`, den nächsten verfügbaren Favoriten. Das prüft Auswahlzustand, keine Audioübertragung.

## Reproduktion des Anzeigefehlers

1. Transkriptions-Einstellungen mit Favoriten geöffnet: Zeile zeigt `USB MIC PRO`.
2. Nach Portwechsel A → B: derselbe Text; wegen stabiler Identität allein kein Beleg für oder gegen Aktualisierung.
3. Abziehen, Ansicht offen lassen: CoreAudio meldet kein USB MIC PRO mehr, aber die Zeile zeigt unverändert den Gerätenamen.
4. Einmal auf Workflows und zurück zu Transkription wechseln: Zeile zeigt jetzt die vollständige rohe USB-MIC-PRO-UID als Platzhalter des fehlenden Geräts.
5. Zurück an Port A stecken, Ansicht offen lassen: Favorit wird automatisch ausgewählt, Zeile bleibt bei der rohen UID.
6. Erneuter Ansichtswechsel: Zeile zeigt wieder `USB MIC PRO`. In diesem aufgefrischten Zustand wurde die App hinterlassen.

Der Quelltext passt zur Messung: `TranscriptionSettingsView` befüllt `@State availableDevices` ausschließlich in `.onAppear`. `MicrophoneFavoritesSectionView` löst Namen gegen diesen Snapshot auf und ersetzt fehlende Treffer durch die UID. `MicrophoneAutoSelectionService` verarbeitet Geräteänderungen bereits separat; seine Auswahlaktualisierung ersetzt den Snapshot der Einstellungen nicht.

## Abgeleitete sichere Regel (Vorschlag, nicht implementiert)

1. Ein Favorit repräsentiert ein physisches Gerät beziehungsweise einen bestimmten Audio-Endpunkt. Aktuelle CoreAudio-UIDs sind Routing-Kennungen und können als bekannte Aliase gespeichert werden; UIDs bleiben undurchsichtige Werte, keine allgemein parsebare Identität.
2. Zuerst exakten UID-Alias abgleichen. Bei abweichender UID nur über eine belastbare, nichtleere Seriennummer zusammen mit Hersteller-/Modellkennung (bei USB VID/PID) und eindeutig zugeordnetem Audio-Endpunkt wiedererkennen. Widersprüche und mehrere passende Geräte verhindern eine automatische Zuordnung. Eine Seriennummer ist nicht allein durch ihr Vorhandensein nachweislich weltweit eindeutig.
3. Name, Hersteller, Modell-UID und Transport ohne Seriennummer beschreiben einen Gerätetyp, kein einzelnes Exemplar. Sie dürfen Kandidaten vorschlagen, aber keine automatische Verschmelzung auslösen. Zwei baugleiche Mikrofone müssen getrennt bleiben. Ein kontrollierter Umsteckversuch oder eine explizite Nutzerzuordnung kann einen zusätzlichen Alias bestätigen.
4. Exakt gleiche gespeicherte UIDs können dedupliziert werden. Unterschiedliche alte UIDs nur nach bestätigter physischer Identität samt Endpunkt zusammenführen. Dabei höchste bisherige Priorität behalten, bekannte Aliase vereinigen und vor Migration den Originalzustand sichern. Die vier Fifine- und zwei CMEDIA-Einträge bleiben bis zur Bestätigung erhalten; Portsegmente nicht blind aus den Strings entfernen.
5. Abwesenheit bedeutet nicht Duplikat: getrennte Ansichten für aktuell angeschlossene Geräte und gespeicherte Favoriten. Fehlende Favoriten mit gespeichertem Anzeigenamen und „Nicht verbunden“ darstellen; nicht beim Abziehen löschen. Gerätebestand bei Hardwareänderung als beobachtbaren Snapshot erneuern und Auswahl sowie offene Einstellungen daraus ableiten. Auch dann aktualisieren, wenn die ausgewählte UID gleich bleibt.

Apple unterscheidet Geräte-UID und Modell-UID ausdrücklich. Die ausführliche Semantik wurde im lokal installierten Apple-SDK (`AudioHardwareBase.h`, Abschnitt `kAudioDevicePropertyDeviceUID`/`kAudioDevicePropertyModelUID`) gelesen: Die Geräte-UID ist persistent und undurchsichtig; die Modell-UID bezeichnet gleiche Modelle desselben Herstellers. Öffentliche Referenzen: [DeviceUID](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertydeviceuid), [ModelUID](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertymodeluid).

## Messdaten und Grenzen

Gefilterte Rohmessungen mit Zeitstempeln liegen in [2026-10-18-issue-202-microphone-identity](2026-10-18-issue-202-microphone-identity/). Sie enthalten USB MIC PRO, das interne Mikrofon und die mikrofonbezogenen Einstellungen. Erfasst wurde mit einer temporären, rein lesenden CoreAudio/IORegistry-Abfrage ohne Audiostream; die JSON-Vergleiche bestätigten stabile Identitätsmerkmale, den Portwechsel, unveränderte Favoriten sowie Auswahl-Fallback und Rückkehr.

Der Versuch reproduziert keine UID-Änderung des USB MIC PRO und erzeugt keine neuen Favoriten. Für Fifine/CMEDIA fehlen Live-Metadaten, Seriennummern und ein kontrollierter Portvergleich. Die allgemeine Migration bleibt daher eine Designentscheidung für die spätere Implementierung; #202 ist durch diese Untersuchung nicht behoben.
