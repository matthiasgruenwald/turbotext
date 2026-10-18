# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | --------------------- | ----------------------------------------- |
| `needs-triage`             | `needs-triage`        | Maintainer needs to evaluate this issue   |
| `needs-info`               | `needs-info`          | Waiting on reporter for more information  |
| `ready-for-agent`          | `ready-for-agent`     | Fully specified, ready for an AFK agent   |
| `ready-for-human`          | `ready-for-human`     | Requires human implementation             |
| `wontfix`                  | `wontfix`             | Will not be actioned (already exists)     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table. All five labels exist on the repo.

## When to apply `needs-triage`

Every new issue gets a type label (`bug`, `enhancement`, …). Add `needs-triage` only when it is still open what needs to be clarified (e.g. a raw idea or report). Issues that are already fully specified (e.g. produced by `/to-tickets`) skip it and go straight to `ready-for-agent` / `ready-for-human`.
