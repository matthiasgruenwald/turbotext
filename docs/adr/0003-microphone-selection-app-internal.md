# Mikrofon-Auswahl bleibt App-intern, ändert nicht den macOS-Systemstandard

**Kontext:** Nutzer wechselt häufig zwischen Dockingstationen mit unterschiedlichen Mikrofonen und möchte automatische Auswahl nach Priorität — aber andere Nutzer (z.B. mit Kopfhörer-Mikros schlechter Qualität) wollen nicht, dass die App den System-weiten Standard verändert.

**Entscheidung:** `MicrophoneService` setzt den ausgewählten Favoriten nur für die App-interne Aufnahme (`AudioRecorder`), NICHT via `setDefaultInputDevice` für macOS systemweit. Nutzer kann optional explizit "macOS-Standard verwenden" wählen, um auf bisheriges Verhalten zurückzufallen.

**Konsequenz:** Andere Apps sind von der Favoritenliste nicht betroffen — nur Blitztext selbst nutzt das priorisierte Mikro.
