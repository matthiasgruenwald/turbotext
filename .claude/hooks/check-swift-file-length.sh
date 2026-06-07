#!/bin/bash
# PostToolUse hook (Edit|Write|MultiEdit): warn when a Swift file exceeds the
# project's 800-line limit (CLAUDE.md "Coding Rules"). Warning only, never blocks.
input=$(cat)
file=$(echo "$input" | jq -r '.tool_input.file_path // empty')

[[ "$file" == *.swift ]] || exit 0
[[ -f "$file" ]] || exit 0

lines=$(wc -l < "$file" | tr -d ' ')
limit=800

if [[ "$lines" -gt "$limit" ]]; then
    echo "Hinweis: $(basename "$file") hat $lines Zeilen (Limit lt. CLAUDE.md: $limit) — Aufteilen erwägen." >&2
fi

exit 0
