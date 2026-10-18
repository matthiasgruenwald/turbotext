# Apple-Speech-Live-Stream-Probe

Wegwerfbarer, isolierter Probe-Harness für Wayfinder-Ticket #143. Speist eine bestehende deutsche Audio-Datei buffer­weise, in Echtzeit-Takt, in `SpeechAnalyzer.start(inputSequence:)` — simuliert damit exakt einen `AVAudioEngine`-Tap, ohne dass jemand ins Mikrofon sprechen muss.

```zsh
swiftc -parse-as-library -framework AVFAudio -framework Speech AppleSpeechLiveStreamProbe.swift -o /tmp/live-stream-probe
/tmp/live-stream-probe /absoluter/pfad/zu/fixture.aiff [--frequent-finalization]
```

`dictation.txt` / `dictation.aiff` sind ein per `say -v Anna -r 150` synthetisiertes, mehrsätziges deutsches Diktat (~65 s), erzeugt mit:

```zsh
say -v Anna -r 150 -f dictation.txt -o dictation.aiff
```

Fehlen die de-DE-Assets für die neue Speech-API (`AssetInventory.status` = `.supported` statt `.installed`), installiert die Probe sie selbst über `AssetInventory.assetInstallationRequest` — das Ergebnis bleibt aber ephemer, da dieses unsignierte CLI-Binary keine stabile Bundle-Identität/Entitlements hat und die Installation nicht über Prozessgrenzen hinweg persistiert.

Ergebnisse siehe `docs/research/2026-07-30-apple-speech-live-stream-macos.md`, Abschnitt 8.
