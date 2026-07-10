# Changelog

Alle bemerkenswerten Änderungen an Turbotext werden hier dokumentiert.

Ab v0.9.0 wird der Changelog strukturiert geführt — mit Git-Tags, Conventional Commits und automatisch generiertem Entwurf via [`git-cliff`](https://git-cliff.org).

---

## [0.9.0] — 2026-07-10

Erster öffentlicher Preview-Release. Turbotext ist ein Fork von [turbotext-app](https://github.com/cmagnussen/turbotext-app) von cmagnussen — die folgenden Punkte sind seit dem Fork hinzugekommen.

### 🚀 Transkription

- **Groq als Standard-Backend** — `whisper-large-v3-turbo` statt OpenAI `whisper-1`. Deutlich schneller und günstiger. Eigener Groq-API-Key erforderlich (Free-Tier verfügbar).
- **Groq-Kontingent-Anzeige** — tägliches Audio-Sekunden-Budget sichtbar direkt in den Einstellungen pro Workflow.
- **Automatischer Fallback auf lokales Modell** — bei Netzwerkausfall wechselt die App automatisch auf das On-Device-WhisperKit-Modell, mit hörbarer Warnung beim nächsten Hotkey-Druck.
- **Groq-Fallback auf OpenAI** — bei Groq-Ratenlimit (HTTP 429) schaltet die App dauerhaft auf OpenAI-Transkription um bis zum nächsten Reset-Zeitpunkt, auch nach App-Neustart.

### 🚀 Rewriting-Workflows

- **Groq als Rewriting-Provider** — Rewriting-Workflows (Turbotext+, DampfAblassen, Emoji) können jetzt Groq statt OpenAI nutzen (`gpt-oss-120b`).
- **Provider-Toggle in den Einstellungen** — Umschalten zwischen Groq und OpenAI für Rewriting per Einstellung, ohne Neustart.
- **Sinnvoller Hinweis statt Stille** — fehlt der OpenAI-Key, zeigt die App einen Hinweis statt stillschweigend zu versagen.

### 🚀 Hotkeys

- **Konfigurierbare Hotkeys pro Workflow** — jeder Workflow (Transkription, Rewrite, DampfAblassen, Emoji) bekommt eine eigene, frei belegbare Tastenkombination.
- **Mehrere Hotkeys pro Workflow** — beliebig viele Shortcuts assignierbar (OR-Logik: jeder Shortcut löst den Workflow aus).
- **Hotkey-Badge im Menü** — alle aktiven Shortcuts eines Workflows werden live im Menü angezeigt.
- **F-Tasten-Support** — Shortcuts ohne Modifier-Flags (F1–F12) für externe Tastaturen ohne `fn`-Modifier.
- **Externe USB-Tastaturen** — Hotkeys funktionieren auf Nicht-Apple-Tastaturen via Input-Monitoring-Permission.

### 🚀 Mikrofon

- **Mikrofon-Favoritenliste** — priorisierte Liste bevorzugter Eingabegeräte. App wählt automatisch das höchstpriorisierte verfügbare Gerät; Fallback auf macOS-Standard.
- **„macOS-Standard verwenden"-Option** — explizit abwählbar zugunsten des System-Defaults.

### 🚀 App-Präsenz

- **Dock-Modus** — optionales Hauptfenster mit Dock-Icon und Cmd+Tab-Erreichbarkeit (Standard: aktiv). Abschaltbar für reinen Menüleisten-Betrieb.
- **Menüleisten-Klick-Vorrang** — ist das Hauptfenster offen, bringt ein Klick aufs Menüleisten-Icon das Fenster nach vorne statt einen zweiten Popover zu öffnen.

### 🚀 Netzwerk

- **Netzwerk-Qualitätsindikator** — Ampel-Status (grün/gelb/rot) im Menü basierend auf Live-ICMP-Pings. Hover zeigt exakte Latenz und Paketverlust ohne Tooltip-Delay.
- **Schnelle Recovery** — Status springt sofort auf grün, sobald 2 direkt aufeinanderfolgende Pings erfolgreich waren (~6s statt ~27s).

### 🚀 Einstellungen

- **Sidebar-Navigation** — Einstellungen in einer Sidebar organisiert statt Tabs.
- **Permission-Status sichtbar** — Accessibility- und Input-Monitoring-Status direkt in den Einstellungen, kein Umweg über Systemeinstellungen.

### 🔒 Security

- **Lokale Modell-Artefakte verifiziert** — Checksummen-Prüfung vor Installation eines lokalen WhisperKit-Modells.

### 🐛 Bug Fixes

- Rewrite-Abbruch lässt App korrekt im Idle-Zustand (kein hängender State).
- DampfAblassen-Prompt überarbeitet: Ich-Perspektive, keine Faktenerfindung.
