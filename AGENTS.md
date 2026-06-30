# TurbotextMac — Codex Instructions

## Language

Always respond in **German** (Deutsch). Code, commits, and PR text stay in English.

## Workflow: Every Feature/Change

1. Run `/grill-with-docs` to build shared terminology and align on approach. Skip only for typo fixes / single-line hotfixes.
2. Implement.
3. If the change is UI-relevant (default assumption — only skip if explicitly told otherwise): rebuild and test in the real app.
   - `./build.sh --install --run`
   - If `Turbotext` is already running: ask for confirmation before `killall Turbotext`, then install + start the new build
   - Verify the change in the running app before reporting done

## Coding Rules

- Immutable data: always return new values, never mutate in-place
- `@Observable` for state, not `@ObservableObject` (exception: `WaveformView.swift` — legacy, not yet migrated)
- Files max 800 lines, functions max 50 lines
- No comments except non-obvious WHY
- XcodeGen: regenerate `.xcodeproj` (`xcodegen generate`) after adding/removing/moving files

## Git & GitHub

Commit style: `type: short description` (imperative, English, lowercase)
Branch style: `feature/short-name`, `fix/short-name`

Create issues and PRs without asking for confirmation — use `gh` CLI directly.

## Agent skills

### Issue tracker

GitHub Issues (`matthiasgruenwald/turbotext`), via `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at repo root. See `docs/agents/domain.md`.
