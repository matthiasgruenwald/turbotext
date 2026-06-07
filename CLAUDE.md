# BlitztextMac — Claude Instructions

## Language

Always respond in **German** (Deutsch). Code, commits, and PR text stay in English.

## Workflow: Every Request

Before implementing any feature or significant change:

1. Run `/grill-with-docs` to build shared terminology and align on approach
2. Then implement

No exceptions — even for small features. Skip only for: typo fixes, single-line hotfixes.

## Project Overview

macOS app (Swift/SwiftUI) for blind-typing training. Speaks text aloud while the user types without looking at the screen. Built as open source preview.

## Tech Stack

- Swift, SwiftUI, SwiftData
- `@Observable` (not `ObservableObject`)
- AVFoundation for audio, CoreML/WhisperKit for transcription
- XcodeGen (`project.yml`) — always regenerate `.xcodeproj` after structural changes

## Build

```bash
./build.sh --install --run
# or
xcodegen generate && xcodebuild build
```

## Architecture

```
BlitztextMac/
  App/          # Entry point, AppDelegate
  Features/     # Feature modules (Settings, Training, …)
  Services/     # Stateless services (AudioRecorder, TranscriptionService, MicrophoneService)
  Views/        # Shared UI components
  Resources/    # Assets, localization
```

## Coding Rules

- Immutable data: always return new values, never mutate in-place
- `@Observable` for state, not `@ObservableObject`
- Files max 800 lines, functions max 50 lines
- No comments except non-obvious WHY

## Git & GitHub

Permissions are pre-approved in `.claude/settings.json`:
- All `git` read/write commands
- All `gh issue`, `gh pr`, `gh label`, `gh api` commands
- Push, pull, fetch, merge — no confirmation needed

Commit style: `type: short description` (imperative, English, lowercase)
Branch style: `feature/short-name`, `fix/short-name`

## Issues & PRs

Create issues and PRs without asking for confirmation. Use `gh` CLI directly.
