# Cursornahe Live-Wellenform — visueller Prototyp

**Frage:** Welche visuelle Sprache macht Aufnahme, Verarbeitung, Stillehinweis und Aufnahmestartfehler am Einfügeort verständlich, ohne abzulenken?

Dies ist ein **Wegwerfprototyp**, keine Produktionsoberfläche. Er vergleicht drei strukturell unterschiedliche Varianten; die Zustände leben ausschließlich im Speicher.

Starten:

```zsh
./TurbotextMac/Prototypes/CursorWaveformVisualPrototype/run.sh
```

Varianten lassen sich mit der schwebenden Leiste, den Pfeiltasten oder den Tasten `1` bis `3` wechseln. Die Zustände lassen sich oben in der Vorschau umschalten.

## Varianten

- **A — Signal-Pille:** Die Wellenform ist das dominierende Feedback, Zustandswechsel bleiben sehr zurückhaltend.
- **B — Statuskarte:** Status, Zeit und Handlung sind explizit gegliedert; gut lesbar, aber präsenter.
- **C — Aufnahmeleiste:** Eine technische, horizontale Transportleiste zeigt den Ablauf als fortlaufenden Prozess.

## Noch offen

Entscheidung vom 17. Juli 2026: Variante A ist die bevorzugte Richtung. Alle Statusbeschriftungen verwenden die kleine, zurückhaltende Fehlerbeschriftung als Referenzgröße; die Wellenform zeigt einen breiten, zeitlich nachvollziehbaren Verlauf. Jede Variante behält über Aufnahme, Verarbeitung, Stillehinweis und Fehler eine feste Außenbreite und -höhe; Farbe, Icon und Inhalt wechseln innerhalb dieser Fläche. Die visuelle Entscheidung wird im Wayfinder-Ticket festgehalten. Danach wird dieser Prototyp gelöscht.
