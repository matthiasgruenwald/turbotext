# Dock-Modus ist standardmäßig aktiv

**Kontext:** App lief bisher ausschließlich als `.accessory` (LSUIElement) — kein Dock-Icon, nur Menüleisten-Popover. Das erschwert zwei Dinge: (1) Auffindbarkeit für neue User, die eine "richtige" App im Dock erwarten (Vorbild: AlDente), (2) automatisiertes UI-Testing per Computer-Use, da der Popover `behavior = .transient` bei jedem Außenklick schließt und damit kein stabiles Klick-/Screenshot-Ziel ist.

**Entscheidung:** App wechselt standardmäßig zu `.regular` (Dock-Modus an). Ein zusätzliches `NSWindow` hostet dieselbe `MenuBarView` wie der Popover, bleibt aber offen statt transient zu schließen. Der Menüleisten-Popover bleibt parallel bestehen (schneller Zugriff ohne Fenster-Fokuswechsel). In den Einstellungen lässt sich der Dock-Modus abschalten — App fällt zurück auf reinen `.accessory`-Betrieb.

**Konsequenz:** Bestehende User sehen ab Update ein neues Dock-Icon, ohne das aktiv gewählt zu haben — Verhaltensänderung ohne Opt-in. Dafür: bessere Auffindbarkeit, und Computer-Use-Tests bekommen ein stabiles Fenster statt eines sich schließenden Popovers. Abschaltbar für User, die den minimalen Menüleisten-Fußabdruck bevorzugen.
