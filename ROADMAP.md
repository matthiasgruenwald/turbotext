# Roadmap

This is an interest list for the Turbotext macOS Preview, not a release promise.

## Current Scope

- macOS menubar app
- developer preview for people who build and inspect the app locally
- personal-first tool with contribution-friendly boundaries
- local recording and hotkeys
- direct Groq API calls for online transcription with a user-provided API key
- optional direct OpenAI API calls for rewrite workflows and transcription fallback
- transcription, rewriting, calmer-message, and emoji workflows
- no hosted backend
- no packaged public release

## Possible Next Work

### Everyday Reliability

- Make first-run setup clearer.
- Improve credential setup, validation, and recovery UX.
- Improve recording/transcription failure states so users understand what happened and what can be retried.
- Add recording recovery so failed recordings can be transcribed later instead of being lost.

### Dictation And Workflows

- Keep Turbotext centered on dictation.
- Keep the current fixed rewrite workflows, but evaluate user-defined prompt workflows before adding more hardcoded modes.
- Treat local transcription as a loss-prevention fallback, not as the primary path or a performance promise.

### Technical Guardrails

- Add a small automated test layer around prompt construction and text quality filters.
- Keep provider boundaries clear as Groq, OpenAI, and local transcription paths evolve.
- Reduce the Accessibility blast radius, ideally by moving synthetic paste into a smaller helper with narrower responsibilities.
- Add stronger supply-chain checks around downloaded local speech models.
- Review external contributions especially carefully when they touch dependencies, network calls, permissions, Keychain access, or Accessibility behavior.

## Not In Scope Yet

- Production support.
- Commercial product, paid support, or hosted service operation.
- Community roadmap ownership or accepting unreviewed third-party code.
- Accounts, sync, teams, or hosted infrastructure.
- Claims that the app is offline or privacy-complete.
- App Store distribution.
- Signed and notarized public builds unless the annual Apple Developer Program cost is externally covered.
- iOS keyboard or mobile companion app work; interesting as a separate dictation direction, but not part of the macOS preview focus.
