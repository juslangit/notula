#!/usr/bin/env bash
# One-time setup: the tools and the two models Notula needs.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v brew >/dev/null || { echo "Homebrew is needed first: https://brew.sh"; exit 1; }
for f in ffmpeg whisper.cpp; do
  brew list --formula "$f" >/dev/null 2>&1 || brew install "$f"
done

mkdir -p models
[[ -f models/ggml-large-v3-turbo-q5_0.bin ]] || {
  echo "→ downloading the Whisper model (547 MB)"
  curl -L --fail -o models/ggml-large-v3-turbo-q5_0.bin \
    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin
}
[[ -f models/ggml-silero-v5.1.2.bin ]] || {
  echo "→ downloading the voice detection model (864 KB)"
  curl -L --fail -o models/ggml-silero-v5.1.2.bin \
    https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin
}
# Stops macOS asking for the microphone and screen permissions after every rebuild.
./tools/make-signing-cert.sh

echo "→ ready. Now run ./run.sh"
