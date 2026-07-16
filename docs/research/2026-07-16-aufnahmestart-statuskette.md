# Aufnahmestart: Fehler- und Statuskette

Stand: 2026-07-16. Recherche für „Ermittle Ursache und Statuskette für ausbleibende Aufnahmestarts“.

## Ergebnis

Der gemeldete Ausfall ließ sich ohne die konkrete Hardware-/TCC-Konstellation nicht reproduzieren. Der vorhandene Code verhindert jedoch doppelte Starts während eines gehaltenen Shortcuts und transportiert bekannte Startfehler bis zum Workflow- und Menüleistenstatus. Ein deterministischer, agentenfähiger Test für die echte `AVAudioEngine`-Startfolge existiert noch nicht, weil deren Ergebnis vom Mikrofon, TCC und Core Audio abhängt und diese Abhängigkeiten nicht injiziert werden können.

## Relevante Kette

1. `HotkeyEngine` übersetzt ein passendes Ereignis einmalig in `.down(type)` und merkt sich den aktiven Shortcut. Weitere `flagsChanged`-Ereignisse, solange derselbe Shortcut gehalten wird, lösen keinen weiteren Start aus.
2. `TurbotextMacApp.handleHotkeyDown` startet über `AppState.startWorkflow` einen Workflow.
3. `WorkflowOrchestrator.start` beendet einen gegebenenfalls aktiven Workflow, erzeugt den neuen und ruft `start()` auf.
4. `AudioRecorder.startRecording` setzt `isRecording` erst nach erfolgreichem `AVAudioEngine.start()` auf `true`.
5. `SpokenWorkflowPipeline.startRecording` wandelt `AudioRecorder.errorMessage` in einen Fehler um. `TranscriptionWorkflow` und `SpokenRewriteWorkflow` setzen daraus `WorkflowPhase.error`.
6. `WorkflowOrchestrator` bildet den Fehler auf `MenuBarStatus.error` ab und setzt ihn nach 1,6 Sekunden zurück.

## Heute unterscheidbare Zustände

| Ebene | Zustände / Daten |
| --- | --- |
| Recorder | kein Eingabegerät; Fehler beim Anlegen der Audiodatei; Fehler beim Start der Audio-Engine; `isRecording`; Pegel; Aufnahmedauer |
| Workflow | `idle`, `running("Aufnahme läuft ...")`, laufende Verarbeitungsphasen, `done`, `error(String)` |
| Menüleiste | `idle`, `recording`, `processing`, `success`, `error` |

Der Fehlertext ist bei Startfehlern bereits nutzerverständlich: „Kein Mikrofon verfügbar.“ oder „Aufnahme konnte nicht gestartet werden: …“. Eine eigene, persistente Anzeige am Einfügeort existiert noch nicht.

## Beobachtungsloop und Grenze

Der vorgesehene Loop ist:

```sh
xcodebuild -project TurbotextMac.xcodeproj -scheme TurbotextMac \
  -destination 'platform=macOS' \
  -derivedDataPath ../.derivedData-turbotextmac-test \
  -only-testing:TurbotextMacTests/HotkeyEngineTests \
  -only-testing:TurbotextMacTests/SpokenWorkflowPipelineTests test
```

Er deckt die Entprellung des Shortcuts und die Weitergabe eines Recorder-Fehlers in der Pipeline ab. Die Ausführung am 2026-07-16 baute wegen erneuter Paketkompilierung nicht bis zu Tests durch; der erzeugte Ergebnis-Bundle meldet deshalb `totalTestCount: 0`. Der Loop ist für diese beiden logischen Grenzen geeignet, aber nicht red-fähig für den tatsächlichen Core-Audio-Fehler.

Für einen echten Reproduktionsloop fehlt ein enger Seam, der einen Startfehler oder eine doppelte Tap-Installation am `AVAudioEngine`-Grenzübergang deterministisch einspeisen kann. Die spätere Umsetzung sollte diese Abhängigkeit injizierbar machen und dann zwei Tests ergänzen: Startfehler → sichtbarer Fehlerzustand, sowie Start/Stop/Start über den realen Workflow-Orchestrator.
