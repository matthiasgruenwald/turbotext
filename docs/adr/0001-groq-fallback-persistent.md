# Groq-Fallback ist persistent, nicht session-basiert

**Kontext:** Quota wird täglich zurückgesetzt. Bei App-Neustart während laufendem Training würde ein session-basierter Fallback erneut Groq versuchen, obwohl das Kontingent noch nicht zurückgesetzt ist.

**Entscheidung:** `GroqQuotaStore` persistiert `fallbackActive` + `rateLimitResetAt` in `UserDefaults`. Beim App-Start prüft `clearIfExpired()` ob das Reset-Datum überschritten ist.

**Konsequenz:** Ein paar Anfragen die direkt nach Reset kommen könnten theoretisch nochmal 429 bekommen — kein Problem, der Fallback aktiviert sich einfach erneut bis zum nächsten Reset.
