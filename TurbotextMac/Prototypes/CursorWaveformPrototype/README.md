# Cursornahe Live-Wellenform — Terminal-Prototyp

**Frage:** Haben Aufnahme, Stillehinweis, Verarbeitung, Einfügen und Fehler der cursornahen Live-Wellenform klare, wiederherstellbare Zustandsübergänge?

Starten:

```zsh
./TurbotextMac/Prototypes/CursorWaveformPrototype/run.sh
```

Der Prototyp hält alle Daten nur im Speicher. `CursorWaveformStateMachine.swift` enthält die pure Zustandsmaschine; `main.swift` ist ausschließlich die wegwerfbare Terminal-Oberfläche.

## Beobachtungen

Bestätigt am 16. Juli 2026: Die Zustände und Übergänge sind nachvollziehbar und vollständig genug für die spätere Überführung. Das erneute Auslösen ist ausschließlich als Reaktion auf einen Aufnahmestartfehler vorgesehen; im Terminal repräsentiert `[r]` das gewohnte globale Turbotext-Tastenkürzel.

Bei der Umsetzung die bestätigte Zustandsmaschine in den Produktionscode überführen und diesen Prototyp anschließend löschen.
