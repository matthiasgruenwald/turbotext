#!/bin/zsh
# PROTOTYPE — run this disposable A/B comparison locally on macOS 26.

set -euo pipefail

cd "${0:A:h}"
swift run AppleSpeechWhisperKitComparison
