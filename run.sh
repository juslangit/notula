#!/usr/bin/env bash
# Build Notula and start it. The icon appears at the top right of the screen.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
pkill -x Notula 2>/dev/null || true
open build/Notula.app
echo "→ Notula is running — look for the waveform icon in the menu bar"
