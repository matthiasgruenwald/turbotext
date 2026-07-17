# Apple Speech vs. WhisperKit — A/B-Prototyp

**PROTOTYPE für Wayfinder-Ticket „Prototypisiere den A/B-Vergleich Apple Speech gegen WhisperKit“.** Der Code ist Wegwerfcode, keine Turbotext-Produktfunktion, und wird nach der gemeinsamen Entscheidung gelöscht.

Start auf macOS 26 mit Xcode 26:

```zsh
./TurbotextMac/Prototypes/AppleSpeechWhisperKitComparison/run.sh
```

1. Den Status des Apple-`de-DE`-Assets prüfen. Der Prototyp lädt keine Assets herunter; fehlende Assets müssen einmalig sichtbar über macOS installiert werden.
2. Der Prototyp verwendet automatisch Turbotexts installiertes Standardmodell `~/Library/Application Support/Turbotext/models/whisperkit/openai_whisper-small_216MB`. Nur für einen bewussten Vergleich eines anderen Modells „Anderes WhisperKit-Modell wählen“ verwenden und dessen **Modellordner** auswählen, nicht `tokenizer.json`.
3. Eine nicht vertrauliche deutsche Probeaufnahme starten und beenden. Dieselbe WAV-Datei wird zuerst an Apple Speech, danach an WhisperKit übergeben.
4. Laufzeit, Rohtext und Fehler beider Wege nebeneinander begutachten. Der Bereich „Vollständiger Messzustand“ kann als Protokoll kopiert werden.

Für den Offline-Nachweis vor dem Start eine externe Netzsperre für den Prozess setzen und danach die Messung wiederholen. Der Prototyp sperrt das Netz nicht selbst und macht keine Netzwerkbehauptung.
