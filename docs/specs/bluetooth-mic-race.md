# Spec: Bluetooth-Mikrofon liefert Stille nach Geräte-Switch (abgeschlossen)

## Ursprüngliche Annahme (falsifiziert)

Vermutet wurde ein Race in `AudioRecorder.startRecording()`: Format wird
gelesen, bevor CoreAudio den Geräte-Switch abgeschlossen hat. Zwei Versuche,
das per Warten/Polling im `AudioRecorder` zu fixen, wurden verworfen:

- Polling von `kAudioOutputUnitProperty_CurrentDevice` vor
  `engine.prepare()`/Initialize legte die komplette Aufnahme lahm (auch
  eingebautes Mic).
- Festes `Thread.sleep` im Hotkey-Pfad blockierte den Main-Thread — fiel
  zeitlich mit einem SwiftUI-Absturz zusammen, der sich als unabhängiger Bug
  in `RecordingOverlayController` herausstellte (siehe unten).

Beide Versuche wurden revertiert. `AudioRecorder.swift` ist unverändert.

## Tatsächlicher Befund

Kein Software-Bug. Bluetooth-Headsets brauchen beim Umschalten von
A2DP (Musik/Output) auf HFP (Mikro-Betrieb) real 2-4 Sekunden Handoff-Zeit
auf Hardware-/Treiberebene. Bestätigt durch Beobachtung: Pegelanzeige bleibt
sichtbar niedrig und springt nach 2-4s hoch, sobald das Headset-Mikro aktiv
wird. Eine Aufnahme, die komplett in dieses Zeitfenster fällt, ist zurecht
stumm — es gibt in der Zeit schlicht kein Audiosignal vom Gerät.

Nicht app-seitig fixbar (Hardware-Latenz). Lösung ist UX, nicht Timing-Code:
bereits vorhandene Live-Pegelanzeige (`RecordingOverlaySignalPillView`,
Waveform-Balken) zeigt an, wann das Mikro aktiv ist; `showsSilenceHint`
(5s-Schwelle) deckt längere Aussetzer ab.

## Separater, tatsächlich gefixter Bug

`RecordingOverlayController.updateContent(of:)` erzeugte bei jedem Poll-Tick
(10x/s während Aufnahme) eine neue `NSHostingView` statt die bestehende
wiederzuverwenden — riss SwiftUIs AttributeGraph mitten in Transaktionen ab,
Crash `EXC_BAD_ACCESS` bei jeder zweiten Aufnahme (kurz nach Mikro-Freigabe).
Fix: `NSHostingView` einmalig erzeugen, danach nur `rootView` aktualisieren.
Committed in `RecordingOverlayController.swift`.

## Separater, tatsächlich gefixter Bug 2

Favoriten-Reorder/-Änderungen in den Settings (`MicrophoneFavoritesSectionView`)
griffen direkt auf `MicrophoneFavoritesStore` zu und lösten nie eine
Neuauflösung der aktiven Mikro-Auswahl aus — Anzeige blieb auf altem Gerät
stehen, bis ein Hardware-Event (Geräte an/abstecken) sie zufällig neu
auflöste. Fix: View nutzt jetzt `MicrophoneState`, dessen
Favoriten-Methoden `autoSelectionService.applySelection()` nach jeder
Änderung erneut anstoßen.
