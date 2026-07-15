# Cursornahe Verankerung einer Live-Wellenform

Stand: 2026-07-15. Recherche für „Untersuche cursornahe Verankerung und schwebendes Aufnahmefenster“.

## Ergebnis

Die gewünschte Positionierung ist mit der macOS-Bedienungshilfen-API und einem nicht aktivierenden `NSPanel` umsetzbar. Sie darf nicht als garantiert behandelt werden: Nicht jede Ziel-App liefert die erforderliche Textcursor-Geometrie. Deshalb wird beim Start genau einmal eine unveränderliche Ankerposition ermittelt: Textcursor, falls vorhanden, andernfalls Mauszeiger.

## Cursor-Anker

1. `AXUIElementCreateSystemWide()` liefert das System-weite Accessibility-Element; dessen [`kAXFocusedUIElementAttribute`](https://developer.apple.com/documentation/applicationservices/kaxfocuseduielementattribute) bestimmt das fokussierte Eingabeelement.
2. Von diesem Element liest der Adapter [`kAXSelectedTextRangeAttribute`](https://developer.apple.com/documentation/applicationservices/kaxselectedtextrangeattribute) und fragt mit [`AXUIElementCopyParameterizedAttributeValue`](https://developer.apple.com/documentation/applicationservices/1461203-axuielementcopyparameterizedattr) [`kAXBoundsForRangeParameterizedAttribute`](https://developer.apple.com/documentation/applicationservices/kaxboundsforrangeparameterizedattribute) ab.
3. Bei einer Auswahl der Länge null ist deren Rechteck die naheliegende Einfügecursor-Position. Das ist eine technische Schlussfolgerung aus der API-Semantik, keine von Apple garantierte Caret-Zusage.

Die Abfrage kann insbesondere `kAXErrorAttributeUnsupported`, `kAXErrorParameterizedAttributeUnsupported`, `kAXErrorNoValue` oder `kAXErrorCannotComplete` liefern. Außerdem benötigt sie die Bedienungshilfen-Freigabe über [`AXIsProcessTrustedWithOptions`](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions). In jedem dieser Fälle wird `NSEvent.mouseLocation` verwendet. Die vom Accessibility-System gemeldeten Bildschirmkoordinaten müssen zentral in AppKit-Koordinaten übertragen und auf den sichtbaren Bildschirm begrenzt werden; Apples Beschreibung von [`kAXPositionAttribute`](https://developer.apple.com/documentation/applicationservices/kaxpositionattribute) dokumentiert das globale Koordinatensystem.

## Overlay

Ein kleines `NSPanel` mit `.nonactivatingPanel` ist der passende Container: Es kann gezeigt werden, ohne die Ziel-App zu aktivieren. Als Startkonfiguration:

- `isFloatingPanel = true`, Ebene `.floating`;
- randloses, transparentes Panel;
- `hidesOnDeactivate = false`;
- `orderFrontRegardless()` zum Anzeigen ohne Key-/Main-Window-Wechsel;
- für rein informative Flächen `ignoresMouseEvents = true`.

Diese Eigenschaften stützen sich auf Apples Dokumentation zu [`NSPanel`](https://developer.apple.com/documentation/appkit/nspanel), [`.nonactivatingPanel`](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel), [`orderFrontRegardless()`](https://developer.apple.com/documentation/appkit/nswindow/orderfrontregardless%28%29), [`ignoresMouseEvents`](https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents) und [`.floating`](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct/floating). Ein manueller Schließen-Button braucht eine gezielt interaktive Unterfläche; das gesamte Panel darf dann nicht pauschal klickdurchlässig sein. Vollbild, Stage Manager und mehrere Spaces sind vor der endgültigen Konfiguration mit [`NSWindow.CollectionBehavior`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct) real zu prüfen; insbesondere ist [`.fullScreenAuxiliary`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary) nur selektiv mit anderen Space-Verhalten kombinierbar.

## Einhängepunkte in Turbotext

- Der Hold-Shortcut startet den Workflow ohne Popover in [TurbotextMacApp.swift](/Users/mg/Documents/Claude/Projects/turbotext/TurbotextMac/App/TurbotextMacApp.swift:120). Das ist der zentrale Startpunkt für die Anker-Momentaufnahme.
- Die Ziel-App wird bereits beim Start erfasst, aber nur als `PasteTarget` mit Prozess-ID, nicht mit Cursorposition: [AppState.swift](/Users/mg/Documents/Claude/Projects/turbotext/TurbotextMac/App/AppState.swift:433) und [WorkflowOrchestrator.swift](/Users/mg/Documents/Claude/Projects/turbotext/TurbotextMac/Features/Workflows/WorkflowOrchestrator.swift:269).
- Der Workflow liefert bereits `phase`, `isRecording` und `audioLevel`: [WorkflowProtocol.swift](/Users/mg/Documents/Claude/Projects/turbotext/TurbotextMac/Features/Workflows/WorkflowProtocol.swift:38). Der Pegel wird im Recorder alle 50 ms aktualisiert; die bestehende [WaveformView.swift](/Users/mg/Documents/Claude/Projects/turbotext/TurbotextMac/Views/WaveformView.swift:51) enthält bereits einen Verlauf.
- Der zentrale Fensterbesitz liegt im `AppDelegate`: [TurbotextMacApp.swift](/Users/mg/Documents/Claude/Projects/turbotext/TurbotextMac/App/TurbotextMacApp.swift:15). Ein eigener `RecordingOverlayController` sollte dort ausschließlich das Panel besitzen. Er darf nicht den Popover-Pfad wiederverwenden, weil dieser die App aktiviert.

## Empfehlung für die spätere Implementierung

1. Einen testbaren `OverlayAnchorProvider` einführen: AX-Cursorrechteck, sonst Maus-Fallback.
2. Einen `RecordingOverlayController` als alleinigen Besitzer des nicht aktivierenden Panels im `AppDelegate` einführen.
3. Einen expliziten Workflow-/Orchestrator-Event für Aufnahmestart, Verarbeitung und Fehler verwenden. Das ist nötig, weil Hintergrundfehler heute den aktiven Workflow direkt leeren ([WorkflowOrchestrator.swift](/Users/mg/Documents/Claude/Projects/turbotext/TurbotextMac/Features/Workflows/WorkflowOrchestrator.swift:203)).
4. Anker nur beim Start berechnen und danach unverändert lassen. Tests decken AX-Erfolg, AX-Fallback, mehrere Screens, Zustandswechsel sowie manuelles und zeitgesteuertes Schließen ab.

Offen für die spätere Interaktionsentscheidung: ob manuell aus dem Popover gestartete Workflows dieselbe externe Anzeige bekommen sollen und welche Space-/Vollbild-Konfiguration nach einem realen Prototyp angemessen ist.
