#!/bin/zsh
# PROTOTYPE — compile and launch the isolated waveform-scroll comparison.

set -euo pipefail

directory=${0:A:h}
binary=$(mktemp /tmp/waveform-scroll-prototype.XXXXXX)
trap 'rm -f "$binary"' EXIT

swiftc -parse-as-library -framework SwiftUI -framework AppKit "$directory/WaveformScrollPrototype.swift" -o "$binary"
"$binary"
