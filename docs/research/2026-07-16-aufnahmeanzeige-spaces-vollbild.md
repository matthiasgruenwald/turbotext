# Space- und Vollbildverhalten der Aufnahmeanzeige

## Frage

Welche `NSWindow.CollectionBehavior`-Kombination hält die cursornahen
Live-Wellenform sichtbar, ohne der Ziel-App den Fokus zu nehmen?

## Empfehlung

Die Aufnahmeanzeige wird als nicht aktivierendes `NSPanel` mit folgender
Konfiguration erstellt:

```swift
panel.collectionBehavior = [
    .auxiliary,
    .fullScreenAuxiliary,
    .canJoinAllSpaces,
    .ignoresCycle
]
panel.level = .floating
panel.hidesOnDeactivate = false
```

`auxiliary` ist die einzige der drei für Stage Manager und Vollbild
gegenseitig ausschließlichen Rollen, die für ein Hilfsfenster passt.
`fullScreenAuxiliary` bringt es auf denselben Space wie das Vollbildfenster
der Ziel-App. `canJoinAllSpaces` verhindert ein Verschwinden beim
Space-Wechsel; `ignoresCycle` hält die kurzlebige Anzeige aus Cmd-` heraus.
`moveToActiveSpace` wird bewusst nicht gesetzt: Die Anzeige darf nie aktiv
werden und damit weder einen Space-Wechsel auslösen noch den Fokus der
Ziel-App übernehmen.

## Machbarkeitsnachweis

Am 16. Juli 2026 auf macOS 26.5.2 (Xcode 26.6) lief ein minimaler
AppKit-Probe mit genau dieser Konfiguration. Er erzeugte ein borderless
`NSPanel` mit `.nonactivatingPanel`, zeigte es mit `orderFrontRegardless()`
an und prüfte nach einer Sekunde über `CGWindowListCopyWindowInfo` seine
Sichtbarkeit sowie den Fokuszustand.

```text
visible=true key=false main=false frontmostIsProbe=false behavior=131393
```

Damit ist für den realen AppKit-Pfad bestätigt: Das Panel erscheint, wird
weder Key- noch Main-Window und macht Turbotext nicht zur Vordergrund-App.
Die Bitmaske `131393` entspricht genau `.canJoinAllSpaces` (1),
`.auxiliary` (64), `.fullScreenAuxiliary` (256) und `.ignoresCycle` (131072).

## Grenzen und Abnahme

Die öffentlichen APIs erlauben keine automatisierte Abfrage, ob ein Fenster
auf einem anderen Space oder in einer fremden Stage-Manager-Gruppe sichtbar
ist. Die Kombination ist daher die durch Apple dokumentierte technische
Empfehlung; die endgültige UI-Abnahme muss auf echter Hardware folgende
manuelle Matrix ausführen:

| Umgebung | Erwartung |
| --- | --- |
| Zwei Displays, Ziel-App auf jedem Display | Anzeige liegt auf dem Bildschirm der festgehaltenen Ziel-App; Fokus bleibt dort. |
| Mehrere Spaces | Anzeige bleibt beim Wechsel sichtbar, ohne Turbotext oder einen anderen Space zu aktivieren. |
| Ziel-App im macOS-Vollbild | Anzeige erscheint über der Ziel-App im selben Vollbild-Space. |
| Stage Manager an | Anzeige bleibt als Hilfsfenster bei der Ziel-App, nicht als eigene Gruppe. |

Ein Fehlschlag dieser Matrix ist kein Anlass für `.canJoinAllApplications`:
Apple dokumentiert diese Rolle als zu `.auxiliary` gegenseitig ausschließend;
sie würde die Bindung an die Ziel-App aufgeben.

## Quellen

- Apple, [NSWindow.CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct): Rollen für Stage Manager/Vollbild sind gegenseitig ausschließend; `canJoinAllSpaces`, `moveToActiveSpace` und `ignoresCycle` sind getrennte Optionen.
- Apple, [auxiliary](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/auxiliary): Hilfsfenster werden neben primären Fenstern bevorzugt angezeigt.
- Apple, [fullScreenAuxiliary](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary): Das Fenster erscheint im selben Space wie das Vollbildfenster.
- Apple, [canJoinAllSpaces](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces): Das Fenster kann in allen Spaces erscheinen.
