#!/bin/zsh
# PROTOTYPE — issue #178: watches AssetInventory.status flips overnight.
# Usage: ./run.sh [duration-seconds]  (no arg = run until killed)

set -euo pipefail

directory=${0:A:h}
binary=$(mktemp /tmp/asset-status-monitor.XXXXXX)
trap 'rm -f "$binary"' EXIT

swiftc -parse-as-library -framework Speech "$directory/AssetStatusMonitor.swift" -o "$binary"
exec "$binary" "$@"
