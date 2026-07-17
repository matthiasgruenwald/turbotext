#!/bin/zsh
# PROTOTYPE — run only with a pre-existing, non-sensitive German audio fixture.

set -euo pipefail

directory=${0:A:h}
binary=$(mktemp /tmp/apple-speech-probe.XXXXXX)
trap 'rm -f "$binary"' EXIT

swiftc -parse-as-library -framework AVFAudio -framework Speech "$directory/AppleSpeechProbe.swift" -o "$binary"
"$binary" "$@"
