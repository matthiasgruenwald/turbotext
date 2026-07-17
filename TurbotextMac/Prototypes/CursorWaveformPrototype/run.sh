#!/bin/zsh
# PROTOTYPE — compile the isolated state machine and start the terminal shell.

set -euo pipefail

directory=${0:A:h}
binary=$(mktemp /tmp/cursor-waveform-prototype.XXXXXX)
trap 'rm -f "$binary"' EXIT

swiftc "$directory/CursorWaveformStateMachine.swift" "$directory/main.swift" -o "$binary"
"$binary"
