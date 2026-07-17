#!/bin/zsh
# PROTOTYPE — compile and launch the isolated visual comparison.

set -euo pipefail

directory=${0:A:h}
binary=$(mktemp /tmp/cursor-waveform-visual-prototype.XXXXXX)
trap 'rm -f "$binary"' EXIT

swiftc -parse-as-library -framework SwiftUI -framework AppKit "$directory/CursorWaveformVisualPrototype.swift" -o "$binary"
"$binary"
