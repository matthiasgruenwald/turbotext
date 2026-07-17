# Apple Foundation Models Framework für die Rewrite-Workflows

Stand: 17. Juli 2026. Diese Recherche beantwortet GitHub Issue #112 (Child-Ticket der Wayfinder-Map #111 „geräteinterne Textverbesserung als Alternative zu Online-LLM“) und prüft, ob Apples **Foundation Models Framework** (bzw. die Apple-Intelligence-„Writing Tools“) die drei bestehenden Rewrite-Workflows von Turbotext ersetzen könnte:

- **Turbotext+** (`LLMService.improve`): freier System-Prompt, Ton-Auswahl (formell/neutral/locker), Eigennamen-Liste, Kontextfeld — läuft aktuell über `gpt-4o-mini`.
- **Dampf ablassen** (`LLMService.dampfAblassen`): sehr spezifischer, mehrteiliger System-Prompt („EIN kurzer Absatz in Ich-Perspektive, ohne Schimpfwörter/Drohungen/Sarkasmus, NUR der Absatz“) — läuft über `gpt-4o` (`.rageMode`).
- **Emoji-Text** (`LLMService.addEmojis`): System-Prompt mit Dichte-Parameter (wenig/mittel/viel Emojis), Grammatikkorrektur, „NUR den Text mit Emojis zurückgeben“ — läuft über `gpt-4o-mini`.

Alle drei sind reine Text-zu-Text-Transformationen mit freiem, selbstformuliertem System-Prompt (kein festes Preset), moderater Eingabelänge (ein gesprochenes Transkript) und der Anforderung „nur der Ergebnistext, keine Erklärung“.

## 1. Mindest-OS-Version

Das **Foundation Models Framework** ist laut Apples eigener Dokumentation „available with iOS 26, iPadOS 26, and macOS 26“ und funktioniert „on any Apple Intelligence-compatible device when Apple Intelligence is enabled“. Es wurde auf der WWDC 2025 vorgestellt („Meet the Foundation Models framework“, „Deep dive into the Foundation Models framework“) und ist seit dem macOS-26-Release („Tahoe“) für Drittentwickler nutzbar.

Die **Apple-Intelligence-Writing-Tools** (Systemfunktion, keine App-API) sind älter: Sie liefen bereits ab **macOS Sequoia 15.1** (Oktober 2024) auf unterstützter Hardware.

Für Turbotext ist nur das Framework relevant (App-eigene Rewrite-Logik), nicht die System-Writing-Tools — diese sind reine Presets in Fremd-Textfeldern, kein programmatischer Zugriff für eigene Prompts (siehe Punkt 4).

Quellen:

- [Foundation Models framework – Apple Newsroom](https://www.apple.com/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/)
- [Meet the Foundation Models framework – WWDC25](https://developer.apple.com/videos/play/wwdc2025/286/)
- [Deep dive into the Foundation Models framework – WWDC25](https://developer.apple.com/videos/play/wwdc2025/301/)
- [Foundation Models – Apple Developer Documentation](https://developer.apple.com/documentation/FoundationModels)
- [Writing Tools mit Apple Intelligence nutzen – Apple Support](https://support.apple.com/en-us/121582)

## 2. Hardware-Voraussetzungen

Apple Intelligence (und damit auch das Foundation Models Framework) verlangt einen **Mac mit Apple Silicon (M1 oder neuer)** — Intel-Macs werden explizit ausgeschlossen, weil ihnen die notwendige Neural-Engine-Leistung fehlt. Benötigt werden mindestens **8 GB RAM** sowie rund 7 GB freier Speicherplatz für die on-device-Modelle.

Seit dem dritten Modellgenerations-Update (2026) unterscheidet Apple zwischen zwei Stufen:

- **Standard-Erfahrung**: ab 8 GB RAM, jeder Apple-Silicon-Mac (M1+).
- **„Advanced“/leistungsfähigeres on-device Modell**: benötigt **M3 oder neuer mit mindestens 12 GB Unified Memory**.

Für Turbotexts Zielgruppe (Lehrkräfte, vermutlich gemischte Mac-Hardware inkl. älterer M1-Basismodelle mit 8 GB) bedeutet das: Ein Teil der Nutzer bekäme nur das Standardmodell, ältere Intel-Macs fallen komplett raus und benötigen weiterhin den Online-Pfad.

Quellen:

- [How to get Apple Intelligence – Apple Support](https://support.apple.com/en-us/121115)
- [Apple Intelligence system requirements / Hardware-Übersicht – idownloadblog, zusammenfassend mit Verweis auf Apple-Angaben](https://www.idownloadblog.com/2024/06/19/apple-intelligence-system-requirements-device-compatibility-list-iphone-ipad-mac-ios-ipados-18-macos-sequoia/)
- [Apple's Most Powerful On-Device AI Now Requires iPhone 17 Pro/Air (M3/12GB-Analogie für Mac-Advanced-Stufe) – MacRumors](https://www.macrumors.com/2026/06/08/most-powerful-on-device-ai-now-requires-iphone-17-pro-or-air/)

## 3. Sprachunterstützung Deutsch

Apple Intelligence unterstützte **Deutsch von Anfang an nicht** — der Sprach- und EU-Rollout kam verzögert. Deutsch ist erst **ab April 2025** verfügbar geworden, zusammen mit dem EU-weiten Rollout (iOS 18.4 / iPadOS 18.4 / macOS Sequoia 15.4), begründet mit „regulatorischen Unsicherheiten“ (Digital Markets Act).

Für das **Foundation Models Framework** (macOS 26, September/Herbst 2025) listet Apple offiziell neun Sprachen: **Englisch, Französisch, Deutsch, Italienisch, brasilianisches Portugiesisch, Spanisch, vereinfachtes Chinesisch, Japanisch, Koreanisch** — mit dem Zusatz, dass „manche Features nicht in allen Regionen/Sprachen verfügbar“ sind. Mit **iOS/iPadOS/macOS 26.1** kam eine weitere Erweiterung der Regionsverfügbarkeit für bereits unterstützte Sprachen (u. a. Deutsch) sowie neue Sprachen wie Dänisch, Niederländisch, Norwegisch, Schwedisch, Türkisch, Vietnamesisch hinzu.

**Fazit**: Deutsch ist heute (Stand Juli 2026) offiziell unterstützt, war es aber erst seit ca. 15 Monaten (April 2025) und initial nur eingeschränkt regional verfügbar. Die Qualität für Deutsch ist von Apple nicht gesondert ausgewiesen (siehe Punkt 5).

Quellen:

- [Apple Intelligence expands to more languages and regions in April – Apple Newsroom](https://www.apple.com/newsroom/2025/02/apple-intelligence-expands-to-more-languages-and-regions-in-april/)
- [Apple Intelligence speaks German from April and may enter the EU – heise online](https://www.heise.de/en/news/Apple-Intelligence-speaks-German-from-April-and-may-enter-the-EU-10266281.html)
- [Foundation Models framework – Apple Newsroom (Sprachliste)](https://www.apple.com/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/)

## 4. Art der API: freies Prompt-Interface vs. feste Presets

Zwei unterschiedliche Apple-Angebote sind zu trennen:

1. **System-Writing-Tools** (in Textfeldern über den Kontext-Button aufrufbar): feste Presets „Proofread“, „Rewrite“ mit Untervarianten „Friendly“, „Professional“, „Concise“, plus ein Freitextfeld „Describe your change“. Für App-Entwickler gibt es hier nur die `UIWritingToolsCoordinator`/`UIWritingToolsBehavior`-API, um das eigene Textfeld an dieses System-UI anzudocken — **kein programmatischer Zugriff auf einen eigenen System-Prompt**, das System entscheidet über die eigentliche Transformation.

2. **Foundation Models Framework** (`LanguageModelSession`, `@Generable`): Das ist die relevante API für Turbotext. Eine `LanguageModelSession` wird mit **frei formulierten, entwicklerdefinierten Instructions** initialisiert und nimmt beliebige Prompts entgegen — vergleichbar mit einem System-Prompt + User-Prompt bei OpenAI. Zusätzlich bietet das Framework „Guided Generation“ über das `@Generable`-Makro für strukturierte, typsichere Ausgaben sowie Tool-Calling für Rückrufe in die App. Damit lassen sich eigene Stiltransformationen wie „Dampf ablassen“ (Ich-Perspektive, ohne Schimpfwörter, ein Absatz) oder „Emoji-Text“ (Dichte-Parameter, NUR Text mit Emojis) **grundsätzlich 1:1 als Custom-Instructions abbilden** — man ist nicht auf Apples feste Presets beschränkt.

Zusätzlich existiert seit 2026 ein **Private-Cloud-Compute-Zugang für Drittentwickler** über das Framework, aber nur für Teilnehmer des App Store Small Business Program mit unter 2 Millionen Erstinstallationen — und dieser Zugang betrifft explizit das Server-Modell, nicht das garantiert lokale on-device-Modell. Für Turbotexts Anforderung „Text verlässt das Gerät nicht“ ist ausschließlich das Standard-on-device-Modell (`SystemLanguageModel`) relevant, PCC-Zugriff wäre hierfür kontraproduktiv und würde bewusst vermieden werden müssen.

Quellen:

- [Writing Tools API – Blake Crosley (Zusammenfassung von Apples `UIWritingToolsCoordinator`-Doku)](https://blakecrosley.com/blog/writing-tools-api-adoption)
- [Foundation Models – Apple Developer Documentation](https://developer.apple.com/documentation/FoundationModels)
- [Foundation Models framework – Apple Newsroom (Guided Generation, Tool Calling)](https://www.apple.com/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/)
- [Private Cloud Compute – Apple Developer (Small-Business-Programm-Gate)](https://developer.apple.com/private-cloud-compute/)
- [Apple's Private Cloud Compute Is Severely Limited for Third-Party Developers – Daring Fireball](https://daringfireball.net/linked/2026/06/13/pcc-severely-limited-third-party-developers)

## 5. Qualitäts- und Kontextlängen-Grenzen

**Kontextfenster**: Das on-device `SystemLanguageModel` hat ein **fest verdrahtetes Limit von 4096 Token** (Input + Output kombiniert), dokumentiert in Apples technischer Notiz TN3193 „Managing the on-device foundation model's context window“. Bei Überschreitung wirft die Session einen `exceededContextWindowSize`-Fehler; die Session kann danach nicht mehr in derselben Konversation antworten. Erst mit **iOS/macOS 26.4** (März 2026) kam eine `contextSize`-Property sowie `tokenCount(for:)`, um dieses Limit programmatisch zu ermitteln statt es hart zu kodieren — das Limit selbst blieb unverändert bei 4096 Token.

Für Turbotexts Use-Case (ein gesprochenes Transkript + System-Prompt + Ausgabetext) ist das in den meisten Fällen ausreichend, kann aber bei langen Diktaten (z. B. lange „Dampf ablassen“-Tiraden) knapp werden, da System-Prompt, Eingabetranskript und generierte Antwort sich das 4K-Budget teilen.

**Modellgröße/Qualität**: Apples Machine-Learning-Research-Blog beschreibt das aktuelle on-device-Modell (dritte Generation, 2026) als **„AFM 3 Core“, ein rund 3-Milliarden-Parameter dichtes Modell**, sowie optional ein leistungsfähigeres **„AFM 3 Core Advanced“ mit 20 Milliarden Parametern in Sparse-Architektur** (aktiviert je nach Anfrage nur 1–4 Milliarden Parameter, für M3+/12GB-Geräte). Laut Apples eigenem Techreport übertrifft das on-device-Modell Qwen-2.5-3B durchgängig und ist im Englischen konkurrenzfähig mit Qwen-3-4B und Gemma-3-4B. Das separate Server-Modell (Private Cloud Compute) ist Llama-4-Scout vorzuziehen, aber laut Apple **den größeren Cloud-Modellen wie Qwen-3-235B und GPT-4o unterlegen**. Da Turbotext ausschließlich das on-device-Modell nutzen würde (siehe Punkt 6), ist die realistische Qualitätsreferenz das kleine 3B-Modell — spürbar unterhalb des aktuell für „Dampf ablassen“ eingesetzten `gpt-4o`.

Quellen:

- [TN3193: Managing the on-device foundation model's context window – Apple Developer Documentation](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- [Managing the context window – Apple Developer Documentation](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window)
- [Apple Improves Context Window Management for its Foundation Models (26.4-Update) – InfoQ](https://www.infoq.com/news/2026/03/apple-foundation-models-context/)
- [Introducing the Third Generation of Apple's Foundation Models – Apple Machine Learning Research](https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models)
- [Updates to Apple's On-Device and Server Foundation Language Models (2025) – Apple Machine Learning Research](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)
- [Apple Intelligence Foundation Language Models: Tech Report 2025 (arXiv-Spiegel des Apple-Reports)](https://arxiv.org/pdf/2507.13575)

## 6. Offline-/Telemetrie-Garantien und Private Cloud Compute

Apples eigene Privacy-Seite trennt die beiden Betriebsarten klar:

- **On-Device Processing**: „the cornerstone of Apple Intelligence is on-device processing, which gives Apple Intelligence the ability to fulfill many of your requests without leaving your device.“ Für das Foundation-Models-Framework gilt konkret: Das Standard-`SystemLanguageModel` verarbeitet Anfragen vollständig lokal, ohne Netzwerkverbindung — dieser Modus ist gleichzeitig der Default, den ein Entwickler ohne weiteres Zutun bekommt (`LanguageModelSession()` ohne explizite Serverwahl).
- **Private Cloud Compute (PCC)**: „Some requests require more computational power than what fits in your pocket. For these more complex requests, Apple Intelligence can draw on Private Cloud Compute.“ Für PCC gilt: Daten werden nur zur Erfüllung der Anfrage verarbeitet, nicht gespeichert, nicht für Apple zugänglich, unabhängige Sicherheitsforscher können den auf den PCC-Servern laufenden Code prüfen. Nutzer können über „Apple Intelligence Report“ (System Settings > Privacy & Security) eine Transparenz-Protokollierung einschalten.

Für **System-Apple-Intelligence-Features** (Siri, Genmoji, System-Writing-Tools) entscheidet Apple selbst und automatisch, ob eine Anfrage lokal bleibt oder an PCC geht, abhängig von Anfragekomplexität — für die App ist das nicht kontrollierbar.

Für das **Foundation Models Framework**, wie Turbotext es einsetzen würde, ist die Lage klarer und günstiger: Standardmäßig läuft `LanguageModelSession` gegen das lokale `SystemLanguageModel`, ohne Netzwerkzugriff. Ein Wechsel auf PCC ist für Drittentwickler nur über ein separates, gated Programm möglich (App Store Small Business Program, < 2 Mio. Downloads) und müsste explizit angefordert werden — Turbotext würde diesen Pfad schlicht nicht nutzen. Damit lässt sich für den Framework-Einsatz mit vertretbarer Sicherheit die Aussage „Text verlässt das Gerät nicht“ treffen, ähnlich wie bei der bereits recherchierten `SpeechAnalyzer`-Transkription — allerdings ebenfalls ohne eine von Apple explizit zugesicherte Null-Netzwerk-Garantie für Rand- und Metadatenverkehr. Auch hier gilt (analog zur Speech-Recherche vom 16. Juli): Eine belastbare DSGVO-Aussage braucht vor Freigabe einen echten Netzwerktest bei deaktivierter Verbindung.

Quellen:

- [Apple Privacy – Apple Intelligence & Private Cloud Compute](https://www.apple.com/privacy/features/)
- [Private Cloud Compute: A new frontier for AI privacy in the cloud – Apple Security Research](https://security.apple.com/blog/private-cloud-compute/)
- [Apple Intelligence & Privacy (Legal-Seite) – Apple](https://www.apple.com/legal/privacy/data/en/intelligence-engine/)
- [Apple Intelligence and privacy on Mac – Apple Support](https://support.apple.com/guide/mac-help/mchlfc0d4779/mac)
- [Private Cloud Compute Security Guide – Apple Security Documentation](https://security.apple.com/documentation/private-cloud-compute)

## Einschätzung

**Technisch grundsätzlich geeignet, aber mit drei konkreten Blockern, die vor einem Einsatz gelöst sein müssen:**

1. **Hardware-/OS-Ausschluss ist real und aktuell.** Foundation Models läuft erst ab macOS 26 und nur auf Apple Silicon (M1+, 8 GB RAM Minimum). Jeder Intel-Mac und jeder Nutzer unter macOS 26 fällt komplett raus und braucht weiterhin den Online-Pfad — das Framework kann die drei Workflows also nur als **zusätzlichen lokalen Modus neben**, nicht als Ersatz für die bestehende OpenAI-Anbindung dienen (genau wie bei der Speech-Recherche vom 16. Juli).

2. **API passt inhaltlich gut.** `LanguageModelSession` mit frei formulierten Instructions erlaubt es, alle drei bestehenden System-Prompts (Turbotext+, Dampf ablassen, Emoji-Text) im Prinzip unverändert als Custom-Instructions zu übernehmen — man ist nicht auf Apples feste Presets beschränkt. Das ist der entscheidende Unterschied zu den System-Writing-Tools, die für diesen Zweck ungeeignet wären.

3. **Kontextfenster ist ein reales Risiko für „Dampf ablassen“.** 4096 Token für System-Prompt + Transkript + Antwort zusammen ist eng, wenn Nutzer lange, wütende Diktate abladen — genau der Anwendungsfall, für den „Dampf ablassen“ gebaut ist. Hier braucht es entweder Vorab-Kürzung des Transkripts oder eine Fallback-Strategie (z. B. `exceededContextWindowSize` sauber behandeln und auf Online-Pfad zurückfallen).

4. **Qualität ist der größte inhaltliche Blocker.** Das on-device-Modell (~3 Mrd. Parameter, laut Apple vergleichbar mit Qwen-2.5-3B/Gemma-3-4B) liegt spürbar unter `gpt-4o`, das aktuell gezielt für „Dampf ablassen“ gewählt wurde (`.rageMode`), weil die Aufgabe – wütendes Rohtranskript in einen ruhigen, präzisen Ich-Perspektive-Absatz verwandeln – Diskurs- und Umformulierungsfähigkeit jenseits reiner Textkorrektur braucht. Für „Turbotext+“ (Grammatik/Stil, bereits mit `gpt-4o-mini`) und „Emoji-Text“ (einfache Einfügeaufgabe, ebenfalls `gpt-4o-mini`) ist die Qualitätslücke zum kleinen Modell voraussichtlich kleiner und ein lokaler Modus eher vertretbar.

5. **Sprache Deutsch ist unterstützt, aber ohne öffentliche Qualitätsangabe.** Deutsch läuft seit April 2025 offiziell mit, Apple nennt aber keine sprachspezifischen Benchmark-Zahlen — die tatsächliche Qualität für deutsche Lehrkräfte-Texte lässt sich nur durch echten Test auf Zielgeräten klären, nicht aus der Dokumentation ableiten.

6. **Privatsphäre passt zur Anforderung, aber „100 % offline“ ist eine App-seitige Entscheidung, kein API-Fakt.** Das Standard-`SystemLanguageModel` läuft ohne Netzwerkzugriff; PCC ist ein separates, gated Opt-in, das Turbotext schlicht nicht anfordern würde. Die Aussage „Text verlässt das Gerät nicht“ ist plausibel, aber wie bei der Speech-Recherche nur durch einen echten Offline-Test vor Freigabe belastbar zu machen — nicht allein aus der Dokumentation.

**Voraussetzungen für einen Einsatz:**

- macOS-26-Mindestversion und Apple-Silicon-Hardwareprüfung (`SystemLanguageModel.availability`) analog zum bereits geplanten Speech-Pfad.
- Prompt-Portierung + praktischer Qualitätstest aller drei bestehenden System-Prompts gegen das on-device-Modell, insbesondere „Dampf ablassen“ mit langen, emotionalen Eingaben.
- Kontextfenster-Handling (Kürzung/Fallback) für Transkripte, die nahe an 4096 Token herankommen.
- Realer Offline-Netzwerktest vor jeder Produktaussage zu „verlässt das Gerät nicht“.
- Klare Produktentscheidung, dass dies ein **zusätzlicher lokaler Modus** ist (analog zum lokalen Transkriptionsmodus), kein Ersatz der OpenAI-Workflows für Nutzer auf älterer Hardware/OS.
