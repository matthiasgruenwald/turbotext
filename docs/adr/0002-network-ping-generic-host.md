# Netzwerk-Ping gegen generischen Host statt Groq/OpenAI-Endpunkte

**Kontext:** Nutzer arbeitet im Alltag mit unzuverlässigem WLAN und braucht ständige Sichtbarkeit der Verbindungsqualität (Latenz, Paketverlust), nicht nur ein binäres "online/offline".

**Entscheidung:** ICMP-Ping (via `/sbin/ping`-Prozessaufruf, App-Sandbox ist deaktiviert) gegen einen festen generischen Host (z.B. 1.1.1.1), nicht gegen die tatsächlichen Groq/OpenAI-API-Endpunkte.

**Begründung:** Groq/OpenAI fallen selten aus — das eigentliche Problem ist die lokale Verbindung. Pingen der echten API-Hosts wäre präziser, birgt aber Risiko (Endpunkte antworten ggf. nicht auf ICMP, oder häufiges Pingen könnte als Abuse gewertet werden / zu Rate-Limiting führen).

**Konsequenz:** Der Indikator zeigt allgemeine Netzqualität, nicht zwingend Erreichbarkeit von Groq/OpenAI selbst. Akzeptiert, da beide selten ausfallen.
