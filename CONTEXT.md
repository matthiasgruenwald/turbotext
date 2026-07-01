# TurbotextMac — Domain Context

Architekturentscheidungen (ADRs) liegen in `docs/adr/`, nicht in dieser Datei.

## Release-Status

**Turbotext macOS Preview** — Öffentlicher Preview-Stand der macOS-App. Experimentell, quelloffen und für lokale Builds gedacht; kein gehosteter Dienst, keine signierte/notarisierte Release-App und kein Produktivitäts- oder Supportversprechen.

**BYO API Keys** — Nutzer bringen eigene API-Schlüssel mit. Groq ist der Standardpfad für Online-Transkription; OpenAI ist optional für Rewrite-Workflows und als Transkriptions-Fallback.

## Transkriptions-Backend

**CloudTranscriptionRouter** — Logik in `TranscriptionService`, die Groq-first mit OpenAI-Fallback kombiniert. Kein eigener Typ, aber konzeptuell der Router.

**Groq-Kontingent** — Tägliches Free-Tier-Budget bei Groq (Audio-Sekunden). Kommt aus HTTP-Response-Header `x-ratelimit-remaining-audio-seconds`; `x-ratelimit-reset-audio` ist optional und wird von Groq offenbar nur kurz vor Limit-Erreichen mitgeschickt. Wird persistent in `UserDefaults` via `GroqQuotaStore` gespeichert.

**Groq-Fallback** — Zustand, in dem der Router nach Groq-429 dauerhaft auf OpenAI umschaltet. Bleibt aktiv bis `rateLimitResetAt` überschritten ist (auch nach App-Neustart). Gespeichert in `GroqQuotaStore.shared`.

**Paid Mode** — Wenn Online-Transkription aktiv UND (kein Groq-Key konfiguriert ODER Groq-Fallback aktiv). Wird im Menüleisten-Icon als kleiner Punkt angezeigt.

## Shortcut-System

**Shortcut** — eine Tastenkombination bestehend aus `NSEvent.ModifierFlags` + optionalem `keyCode: UInt16`. Repräsentiert einen einzelnen Auslöser für einen Workflow.

**Shortcut-Array** — pro `WorkflowType` eine geordnete Liste von beliebig vielen Shortcuts. Workflow feuert, wenn IRGENDEIN Shortcut in der Liste matcht (OR-Logik).

**fn-Default-Shortcuts** — die aktuellen hardcodierten `fn`-Kombis (z.B. `fn+Shift` = Transkription). Bleiben als Defaults im Shortcut-Array voreingestellt, sind aber löschbar und überschreibbar.

**Key Recorder** — UI-Modus zum Erfassen neuer Shortcuts: Nutzer klickt Button → App lauscht auf nächste Tastenkombination via `NSEvent`-Monitor → Combo wird dem Shortcut-Array des Workflows hinzugefügt. Kein Ersetzen — immer append.

**F-Key-Shortcut** — Shortcut ohne Modifier-Flags, nur `keyCode` (F1–F12). Für non-Apple-Tastaturen (z.B. Perixx), wo `fn` als Modifier-Flag nicht von macOS exponiert wird.

**Shortcut-Badge** — im Hauptmenü zeigt pro Workflow ALLE aktiven Shortcuts nebeneinander (nicht nur den ersten), da Workflows meist nur 1–3 Shortcuts haben.

## Mikrofon-System

**Mikrofon-Favoritenliste** — vom Nutzer priorisierte Liste von Mikro-UIDs, persistiert in `UserDefaults`. Ersetzt NICHT den macOS-Systemstandard, sondern ist eine App-interne Auswahl. Beim App-Start und bei Gerätewechsel (`kAudioHardwarePropertyDevices`-Notification) wählt die App das höchstpriorisierte verfügbare Gerät aus der Liste. Ist kein Favorit verfügbar, fällt die App auf den macOS-Systemstandard zurück. Nutzer kann alternativ explizit "macOS-Standard verwenden" wählen (kein Override).

## App-Präsenz

**Dock-Modus** — Activation Policy `.regular` statt `.accessory`: App zeigt Dock-Icon und ist per Cmd+Tab erreichbar. Standardmäßig aktiv (siehe [ADR 0004](docs/adr/0004-dock-mode-default-on.md)). Per Einstellung abschaltbar (→ zurück zu reinem Menüleisten-Betrieb, kein Dock-Icon).

**Hauptfenster** — Normales, nicht-transientes `NSWindow`, hostet dieselbe `MenuBarView` wie der Menüleisten-Popover (geteilter `AppState`, keine Code-Duplikation). Bleibt offen bis explizit geschlossen — im Gegensatz zum Popover, der bei Außenklick automatisch verschwindet (`behavior = .transient`). Existiert nur im Dock-Modus; wird über Dock-Icon-Klick geöffnet.

**Menüleisten-Klick-Vorrang** — Ist das Hauptfenster offen, holt ein Klick auf das Menüleisten-Icon das Fenster nach vorne, statt einen zweiten Popover zu öffnen. Verhindert zwei gleichzeitig sichtbare UI-Kopien desselben States.

## Netzwerk-Qualität

**Netzwerk-Qualitätsindikator** — Ampel-Status (grün/gelb/rot) im Hauptmenü, basiert auf rollierendem Fenster der letzten 10 ICMP-Pings (alle 3s) gegen einen festen, generischen Host (z.B. 1.1.1.1). Grün: 0% Verlust, <150ms Latenz. Gelb: ≥15% Verlust ODER 150–500ms Latenz. Rot: >30% Verlust ODER keine Antwort. Hover zeigt exakte Latenz/Verlust-Zahlen sofort (kein Standard-Tooltip-Delay).

**Asymmetrische Recovery** — Rot/Gelb-Erkennung (Verschlechterung) bleibt unverändert über das volle 10er-Fenster, um Flackern bei einzelnem Paketverlust zu vermeiden. Für die Erholung gibt es eine schnelle Sonderregel: sobald die letzten 2 Pings direkt hintereinander erfolgreich UND latenzarm waren (<150ms), springt der Status sofort auf grün — unabhängig von älteren Failures im Fenster. So dauert die Recovery nach einem kompletten Ausfall ~6s statt ~27s. `averageLatencyMs`/`packetLossPercent` (Hover-Anzeige) bleiben davon unberührt und werden weiterhin über das volle Fenster berechnet.
