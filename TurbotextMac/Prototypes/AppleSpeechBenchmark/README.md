# Apple-Speech-Benchmark-Probe

Wegwerfbarer, isolierter Probe-Harness für Wayfinder-Ticket #101. Er verarbeitet eine bestehende deutsche Audio-Datei mit `DictationTranscriber`, schreibt ausschließlich Messausgabe auf Standardausgabe und lädt keine Assets nach.

```zsh
./TurbotextMac/Prototypes/AppleSpeechBenchmark/run.sh /absoluter/pfad/zu/fixture.m4a
```

Vor einem Offline-Lauf müssen die Sprach-Assets bereits installiert sein. Der Probe bricht sonst mit Status 69 ab. Für einen vollständigen Vergleich siehe `docs/research/2026-07-16-apple-speech-benchmark-macos.md`.
