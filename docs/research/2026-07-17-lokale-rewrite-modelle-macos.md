# Lokale Rewrite-Modelle für macOS (Ticket #117)

Stand: 17. Juli 2026. Umfang: Turbotext+, Emoji-Text und Dampf ablassen. Dieses Dokument bewertet nur Inferenz auf dem Gerät; es ist keine Behauptung, dass ein Modell die bestehende OpenAI-Qualität erreicht.

## Kurzentscheidung

Für einen optionalen, herunterladbaren lokalen Modus ist **Qwen3-4B-Instruct, 4-bit, über llama.cpp/GGUF** der belastbarste erste Prototyp. Es bietet ein für die Workflows weit überdimensioniertes natives Kontextfenster (32K Token), keine OS-Sperre auf Apple Silicon und einen reifen, klein integrierbaren C/C++-Unterbau. Der Download sollte statt eines App-Bundles gewählt werden: rund 2,3–2,8 GB Gewichte sind für eine Preview zumutbar, aber nicht für jede App-Installation.

**MLX Swift** ist die bessere Apple-native Alternative, sobald Turbotext Apple-Silicon-only werden darf: Swift-Integration, Metal und lokale Modellgewichte passen gut. Gegenüber llama.cpp ist es aber Apple-Silicon-exklusiv und das App-Team besitzt mehr Downloader-/Tokenizer-/Gewichts-Integration selbst. Beide Pfade brauchen einen eigenen Qualitäts- und Safety-Gate; ein lokales Modell ist kein Guardrail-Service.

Die bereits erhobenen Ergebnisse zu Apple Foundation Models aus #112/#113 bleiben eine dritte, systemseitig vorhandene Option, aber kein Ersatz: macOS 26, 4.096 Token und ein für `Dampf ablassen` relevanter Guardrail-False-Positive machen es nur zum separaten Fallback/Kandidaten.

## Vergleich der Runtimes

| Kriterium | MLX Swift + MLX-Gewichte | llama.cpp + GGUF |
| --- | --- | --- |
| Plattform | MLX ist ein Apple-Silicon-Framework; die Swift-API nutzt auf macOS standardmäßig Metal. [MLX](https://github.com/ml-explore/mlx) / [Swift](https://github.com/ml-explore/mlx-swift) | Metal ist auf Apple Silicon unterstützt; CPU-/weitere Backends erlauben zudem Intel-Macs, praktisch mit deutlich schwächerer Leistung. [Backends](https://github.com/ggml-org/llama.cpp#supported-backends) |
| Einbettung | SwiftPM-/Xcode-Pakete; `mlx-swift-lm` bietet LLM-API sowie Downloader-/Tokenizer-Integrationen, aber diese sind ausdrücklich austauschbar. [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm) | C/C++-Bibliothek, GGUF als erforderliches Modellformat; Download und lokale Ausführung sind offizieller Standardpfad. [README](https://github.com/ggml-org/llama.cpp#obtaining-and-quantizing-models) |
| Modellformat | MLX-spezifische Gewichte plus Tokenizer; für einen reproduzierbaren Release eigenes manifestiertes Artefakt/Hash nötig. | GGUF, gut für versionierte, quantisierte Ein-Datei-Downloads; Conversion/Quantisierung ist ein zusätzlicher Lieferketten-Schritt. [GGUF-Hinweis](https://github.com/ggml-org/llama.cpp#obtaining-and-quantizing-models) |
| Lizenz Runtime | MIT. [LICENSE](https://github.com/ml-explore/mlx-swift/blob/main/LICENSE) und [MLX Swift LM](https://github.com/ml-explore/mlx-swift-lm) | MIT. [LICENSE](https://github.com/ggml-org/llama.cpp/blob/master/LICENSE) |
| Wartung | Versionierte Swift-Abhängigkeiten, API-Änderungen und Xcode-Build der Metal-Shader nachziehen; keine fremde Prozess-/Server-Schicht nötig. | C/C++-/Metal-Build und GGUF-Kompatibilität nachziehen; dafür ist Modellformat, Download und Quantisierung explizit Kernumfang. |
| Empfehlung | Zweiter Spike auf Apple Silicon, wenn native Swift-API wichtiger als Intel-Kompatibilität ist. | Erster Produkt-Spike: klare Artefaktgrenze, breiterer Mac-Support und leicht zu aktualisierender Modell-Download. |

Beide Runtimes führen nach erfolgreichem Download ohne Netzwerkanfrage aus. Das ist ein Implementierungsziel, kein automatisch nachgewiesenes Datenschutzversprechen: Turbotext muss Download, Telemetrie und Fehlerberichte strikt vom Inferenzpfad trennen und im Offline-Test verifizieren.

## Modellkandidaten

| Kandidat | Warum realistisch | Kontext / Qualitätssignal | Größe und RAM (Planungswert) | Lizenz / Safety |
| --- | --- | --- | --- | --- |
| **Qwen3-4B-Instruct, Q4** (Startkandidat) | 4,0 Mrd. Parameter; das offizielle Modell nennt llama.cpp ausdrücklich als lokalen Quantisierungsweg. [Modellkarte](https://huggingface.co/Qwen/Qwen3-4B) | 32.768 Token nativ; YaRN bis 131.072, wobei Qwen selbst für kürzere typische Kontexte von YaRN abrät. Für Rewrite `enable_thinking=false`, sonst ist es standardmäßig aktiv. [Kontext](https://huggingface.co/Qwen/Qwen3-4B#processing-long-texts), [Modus](https://huggingface.co/Qwen/Qwen3-4B#quickstart) | Q4-Gewichte rechnerisch etwa 2,25 GB vor Container-/Metadaten; **2,3–2,8 GB Download** reservieren. Für kurze Rewrite-Prompts 8 GB Unified Memory als Untergrenze, **16 GB empfehlen**; 32K Kontext erhöht KV-Cache/Peak spürbar. Vor Release auf M1/8, M1/16, M2/16 messen. | Apache-2.0 laut offizieller Modellkarte. Kein Runtime-Filter; Prompt, Ausgabebegrenzung und produktbezogener Safety-Test liegen bei Turbotext. [Lizenz/Modell](https://huggingface.co/Qwen/Qwen3-4B) |
| **Gemma 3 4B IT, Q4** (Gegenprobe) | 4B-Modell, ausdrücklich für Laptops/Desktops mit begrenzten Ressourcen beschrieben; kompatible GGUF-Downloads sind im llama.cpp-Ökosystem vorgesehen. [Karte](https://ai.google.dev/gemma/docs/core/model_card_3), [llama.cpp](https://github.com/ggml-org/llama.cpp#obtaining-and-quantizing-models) | 128K Gesamtkontext für 4B und mehrsprachig (über 140 Sprachen). Das ist ein Kapazitäts-, kein deutscher Rewrite-Qualitätsbeleg. [Karte](https://ai.google.dev/gemma/docs/core/model_card_3) | Ebenfalls grob 2,3–2,8 GB bei Q4 plus KV-Cache; dieselbe 8-GB-Untergrenze/16-GB-Empfehlung, jedoch zwingend auf dem finalen GGUF messen. | Gemma Terms, nicht Apache/MIT. Die Modellkarte fordert anwendungsbezogene Safety-Mechanismen; ihre Safety-Auswertung war nur englischsprachig. [Terms](https://ai.google.dev/gemma/docs/core/model_card_3), [Safety-Limit](https://ai.google.dev/gemma/docs/core/model_card_3#ethics-and-safety) |
| **Apple Foundation Models** (bereits untersucht) | Kein Modell-Download und kein Dritt-Runtime-Bundle. | 4.096 Token Input+Output; #113 zeigte ein `guardrailViolation` bei einer harmlosen wütenden Beschwerde und eine Fidelity-Abweichung im Emoji-Workflow. | App-Download klein, Modell vom System; nur macOS 26, Apple Silicon M1+ und 8 GB. | System-Guardrails sind nicht konfigurierbar genug für den emotionalen Rewrite-Fall. Interne Evidenz: [#112](https://github.com/matthiasgruenwald/turbotext/issues/112), [#113](https://github.com/matthiasgruenwald/turbotext/issues/113). |

Die Größen sind bewusst Planungswerte, keine Herstellerangabe für ein bestimmtes Artefakt: Quantisierungstyp, Container und Tokenizer ändern die tatsächliche Downloadgröße. Die RAM-Werte enthalten einen Sicherheitsabstand für App, Gewichte, Aktivierungen und KV-Cache; sie müssen durch einen Release-artigen Build auf den drei Zielklassen ersetzt werden.

## Konsequenzen je Rewrite-Workflow

| Workflow | Lokaler Kandidat | Nicht verhandelbarer Abnahmetest |
| --- | --- | --- |
| Turbotext+ | Qwen3-4B Q4 zuerst; Gemma-3-4B-Q4 als Blindvergleich. | Deutscher Korpus: Füllwörter entfernen, Inhalt/Ton erhalten, Satzzeichen; keine Halluzinationen oder ungewollte Verkürzung. |
| Emoji-Text | Beide Kandidaten, niedrige Temperatur und strikt begrenzte Ausgabe. | Charakter- und Bedeutungs-Fidelity gegen Eingabe; insbesondere keine Perspektiv- oder Inhaltsumschreibung wie im #113-Fund. |
| Dampf ablassen | Beide nur als **optional lokaler** Modus, mit klarer Fehlermeldung und bestehendem Online-Alternativpfad. | Deutsche emotionale/beleidigende, aber harmlose Diktate: keine unnötige Verweigerung, Ich-Perspektive/ruhiger Ton, keine neue Eskalation. Kein Modell darf aufgrund einer bloßen Modellkarte als sicher gelten. |

## Versand, Updates und Betrieb

1. **Download statt Bundling.** App liefert nur Runtime und signiertes Modell-Manifest (Modell-ID, Revision, SHA-256, Lizenz/Notices, Größe). Der Nutzer startet einen sichtbaren WLAN-tauglichen Download und kann ihn löschen. Bundling würde den App-Download um den vollständigen Modellwert vergrößern und jedes Update der App mit den Gewichten koppeln.
2. **Ein exakt unterstütztes Artefakt pro Release.** Nicht beliebige Hub-Modelle laden. Für llama.cpp eine geprüfte GGUF-Revision; für MLX eine geprüfte Gewichts-/Tokenizer-Revision. So bleiben Prompt-Template, Sampling, Kontextobergrenze und Regressionstests reproduzierbar.
3. **Konservatives Betriebsprofil.** Maximaler Kontext zunächst 8K statt des Modellmaximums, Ausgabe auf Rewrite-Länge begrenzen, Qwen ohne Thinking. Das senkt RAM/Antwortzeit und verhindert, dass das lange Herstellerlimit ungetestet zum Produktversprechen wird.
4. **Qualitäts- und Safety-Release-Gate.** Für jeden Runtime-/Modell-/Quantisierungswechsel den deutschen Golden-Korpus erneut bewerten, einschließlich `Dampf ablassen`; kein automatischer Modell-Update-Kanal ohne diese Freigabe.

## Empfohlener nächster Spike

In einem separaten, nicht nutzerwirksamen Spike Qwen3-4B-Instruct Q4 als fixiertes GGUF über llama.cpp integrieren und Gemma 3 4B IT Q4 dagegen messen: M1/8 GB, M1/16 GB, M2/16 GB; Offline nach Download; Peak-RAM, Latenz, Energie und den deutschen 3-Workflow-Korpus erfassen. Erst wenn Qwen beim `Dampf ablassen` keine unvertretbaren Verweigerungen/Verfälschungen zeigt, die Runtime-Abhängigkeit productisieren. Parallel kann ein kleiner MLX-Swift-Prototyp auf M1/16 klären, ob dessen native Integration die Apple-Silicon-Beschränkung aufwiegt.
