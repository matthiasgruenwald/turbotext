# BlitztextMac — Domain Context

## Transkriptions-Backend

**CloudTranscriptionRouter** — Logik in `TranscriptionService`, die Groq-first mit OpenAI-Fallback kombiniert. Kein eigener Typ, aber konzeptuell der Router.

**Groq-Kontingent** — Tägliches Free-Tier-Budget bei Groq (Audio-Sekunden). Kommt aus HTTP-Response-Headern `x-ratelimit-remaining-audio-seconds` und `x-ratelimit-reset-audio`. Wird persistent in `UserDefaults` via `GroqQuotaStore` gespeichert.

**Groq-Fallback** — Zustand, in dem der Router nach Groq-429 dauerhaft auf OpenAI umschaltet. Bleibt aktiv bis `rateLimitResetAt` überschritten ist (auch nach App-Neustart). Gespeichert in `GroqQuotaStore.shared`.

**Paid Mode** — Wenn Online-Transkription aktiv UND (kein Groq-Key konfiguriert ODER Groq-Fallback aktiv). Wird im Menüleisten-Icon als kleiner Punkt angezeigt.

## Shortcut-System

**Shortcut** — eine Tastenkombination bestehend aus `NSEvent.ModifierFlags` + optionalem `keyCode: UInt16`. Repräsentiert einen einzelnen Auslöser für einen Workflow.

**Shortcut-Array** — pro `WorkflowType` eine geordnete Liste von beliebig vielen Shortcuts. Workflow feuert, wenn IRGENDEIN Shortcut in der Liste matcht (OR-Logik).

**fn-Default-Shortcuts** — die aktuellen hardcodierten `fn`-Kombis (z.B. `fn+Shift` = Transkription). Bleiben als Defaults im Shortcut-Array voreingestellt, sind aber löschbar und überschreibbar.

**Key Recorder** — UI-Modus zum Erfassen neuer Shortcuts: Nutzer klickt Button → App lauscht auf nächste Tastenkombination via `NSEvent`-Monitor → Combo wird dem Shortcut-Array des Workflows hinzugefügt. Kein Ersetzen — immer append.

**F-Key-Shortcut** — Shortcut ohne Modifier-Flags, nur `keyCode` (F1–F12). Für non-Apple-Tastaturen (z.B. Perixx), wo `fn` als Modifier-Flag nicht von macOS exponiert wird.

## ADR-0001: Groq-Fallback ist persistent, nicht session-basiert

**Kontext:** Quota wird täglich zurückgesetzt. Bei App-Neustart während laufendem Training würde ein session-basierter Fallback erneut Groq versuchen, obwohl das Kontingent noch nicht zurückgesetzt ist.

**Entscheidung:** `GroqQuotaStore` persistiert `fallbackActive` + `rateLimitResetAt` in `UserDefaults`. Beim App-Start prüft `clearIfExpired()` ob das Reset-Datum überschritten ist.

**Konsequenz:** Ein paar Anfragen die direkt nach Reset kommen könnten theoretisch nochmal 429 bekommen — kein Problem, der Fallback aktiviert sich einfach erneut bis zum nächsten Reset.
