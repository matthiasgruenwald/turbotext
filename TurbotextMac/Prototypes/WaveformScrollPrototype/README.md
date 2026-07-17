# Wellenform-Scroll — Mechanismus-Prototyp

**Frage:** Welcher Rendering-Mechanismus liefert dünne Balken, volle Pillenbreite, deutlich sichtbare pegelabhängige Höhe und ein flüssiges Durchlaufen von rechts nach links — ohne die Layout-Regression aus dem Produktionsversuch (pro Frame neu berechneter Abstand in einem GeometryReader/HStack)?

Wegwerfprototyp, keine Produktionsoberfläche. Alle drei Varianten zeigen denselben simulierten Live-Pegel (Random Walk auf einem Timer), damit der Vergleich fair ist.

Starten:

```zsh
./TurbotextMac/Prototypes/WaveformScrollPrototype/run.sh
```

Varianten mit der schwebenden Leiste, den Pfeiltasten oder `1`–`3` wechseln.

## Varianten

- **A — Feste Zellen:** Balkenzahl einmalig aus der verfügbaren Breite berechnet; jeder Tick verschiebt die FIFO-Historie und die immer gleichen Zellen bekommen neue Höhen. Entspricht dem Mechanismus der ursprünglichen (Vor-Regressions-)Produktionsversion — dort war nur die Balkenbreite zu groß.
- **B — Verschobener Streifen:** Mehr Balken als sichtbar vorgehalten, der gesamte Streifen wird animiert nach links verschoben (`.animation(.linear)`), neuestes Sample erscheint rechtsbündig, ältestes läuft links aus dem sichtbaren Fenster.
- **C — Canvas-Zeichnung:** Kein Balken pro View — ein `Canvas`-Zeichenaufruf pro Frame, Balkenbreite/-abstand aus der festen Historienlänge abgeleitet. Unempfindlich gegenüber SwiftUI-Layout-Timing (genau das Problem, das die Produktionsregression verursacht hat).

## Noch offen

Entscheidung steht noch aus — Rückmeldung nach dem Durchklicken hier ergänzen, dann Ergebnis in `RecordingOverlaySignalPillView.swift` übernehmen und diesen Prototyp löschen.
