#!/usr/bin/env zsh
# Notula — turn a recording into meeting notes.
#   pipeline.sh <meeting-folder>   (a folder holding mic.wav and/or system.wav)
#   pipeline.sh <audio-file>       (any file ffmpeg can read)
#
# Four steps, each of which you can run by hand if you want to see it work:
#   1. ffmpeg       cleans up each track and mixes one meeting.wav to listen back to
#   2. whisper-cli  turns each track into text, on this Mac, offline
#   3. merge        interleaves the two tracks by time, so lines are labelled Room / Call
#   4. claude       reads the transcript and writes summary.md
set -eu
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
MODEL="${NOTULA_MODEL:-$ROOT/models/ggml-large-v3-turbo-q5_0.bin}"
VAD_MODEL="${NOTULA_VAD_MODEL:-$ROOT/models/ggml-silero-v5.1.2.bin}"
LANG_OPT="${NOTULA_LANG:-auto}"
QUIET_DB="${NOTULA_QUIET_DB:--55}"   # a track quieter than this is treated as empty

TARGET="${1:?usage: pipeline.sh <meeting-folder|audio-file>}"

if [[ -d "$TARGET" ]]; then
  FOLDER="$TARGET"
else
  NAME="$(basename "${TARGET%.*}" | tr ' ' '-')"
  FOLDER="$HOME/Documents/Meetings/$(date +%Y-%m-%d-%H%M)-$NAME"
  mkdir -p "$FOLDER"
  ffmpeg -y -i "$TARGET" -ac 1 -ar 48000 -c:a pcm_s16le "$FOLDER/mic.wav" -loglevel error
fi
cd "$FOLDER"

log() { print -r -- "$(date +%H:%M:%S)  $*" | tee -a notula.log >&2 }

command -v ffmpeg      >/dev/null || { log "ffmpeg is missing — brew install ffmpeg"; exit 1 }
command -v whisper-cli >/dev/null || { log "whisper-cli is missing — brew install whisper.cpp"; exit 1 }
command -v claude      >/dev/null || { log "the claude command is missing"; exit 1 }
[[ -f "$MODEL" ]]                 || { log "no Whisper model at $MODEL"; exit 1 }

# ------------------------------------------------------------- 1. the audio --
# Each track is levelled and dropped to the 16 kHz mono Whisper wants.
TRACKS=()
for track in mic system; do
  [[ -f "$track.wav" ]] || continue
  DB=$(ffmpeg -i "$track.wav" -af volumedetect -f null - 2>&1 | awk -F': ' '/mean_volume/ {print $2+0}')
  if [[ -z "$DB" ]] || (( DB < QUIET_DB )); then
    log "$track.wav is silent (${DB:-no} dB) — skipping it"
    continue
  fi
  log "preparing $track.wav (${DB} dB average)"
  ffmpeg -y -i "$track.wav" -af "highpass=f=80,dynaudnorm=f=250:g=15" \
    -ac 1 -ar 16000 -c:a pcm_s16le "$track-16k.wav" >>notula.log 2>&1
  TRACKS+=$track
done
(( ${#TRACKS} > 0 )) || { log "no audio with any sound in it — nothing to transcribe"; exit 1 }

if [[ ! -f meeting.wav ]]; then
  if (( ${#TRACKS} == 2 )); then
    ffmpeg -y -i "${TRACKS[1]}-16k.wav" -i "${TRACKS[2]}-16k.wav" \
      -filter_complex "amix=inputs=2:duration=longest:normalize=0" -c:a pcm_s16le meeting.wav >>notula.log 2>&1
  else
    cp "${TRACKS[1]}-16k.wav" meeting.wav
  fi
fi
MINUTES=$(ffprobe -v error -show_entries format=duration -of csv=p=0 meeting.wav | awk '{printf "%d", ($1+59)/60}')
log "about ${MINUTES} minute(s) of meeting"

# -------------------------------------------------------- 2. the transcript --
# Voice activity detection matters more than it sounds: given a near-silent track,
# Whisper will happily invent fluent sentences out of room hiss. VAD hands it only
# the stretches where somebody is actually speaking.
VAD_ARGS=()
if [[ -f "$VAD_MODEL" ]]; then
  VAD_ARGS=(--vad -vm "$VAD_MODEL" -vt "${NOTULA_VAD_THRESHOLD:-0.6}" -vsd 200 -vp 100)
else
  log "warning: no VAD model at $VAD_MODEL — quiet tracks may produce invented text"
fi

for track in $TRACKS; do
  [[ -f "$track.json" ]] && continue
  log "transcribing the ${track} track with Whisper"
  whisper-cli -m "$MODEL" -f "$track-16k.wav" -l "$LANG_OPT" -t 6 -nf \
    -nth "${NOTULA_NO_SPEECH:-0.6}" ${VAD_ARGS[@]} -oj -of "$track" >>notula.log 2>&1
done

python3 "$HERE/merge_tracks.py" "$FOLDER" || { log "nothing was said in the recording"; exit 1 }
[[ -s transcript.txt ]] || { log "the transcript came out empty — check notula.log"; exit 1 }
log "transcript: $(wc -w < transcript.txt | tr -d ' ') words"

# ----------------------------------------------------------- 3. the summary --
log "asking Claude for the notes"
PROMPT='You are reading the transcript of a real meeting, produced by automatic speech
recognition. Read it with these things in mind:

- It may mix Malay and English in the same sentence. Write your notes in English.
- Lines are marked "Room:" (picked up by the microphone — the people physically
  present, including the person whose Mac this is) and "Call:" (the audio the Mac
  was playing — the people dialling in). A transcript with only one of those is
  normal. There are no individual speaker names unless someone says one.
- Some words will be wrong. Read through the errors, and never quote a garbled
  line as though it were certain. Where you can tell what a mangled word was
  meant to be, use the right word.

Write Markdown, using exactly these headings:

## What this meeting was about
Two or three sentences.

## Decisions made
Bullet points, only things actually settled. If nothing was, write "Nothing was decided."

## Action items
A Markdown table with the columns: Task | Who | When. Write "not stated" in a cell
rather than guessing. Leave the table out if nobody was given anything to do.

## Open questions
Things raised and left hanging.

## Notes
Anything else worth keeping: numbers, names, amounts, links, dates.

Rules: invent nothing. If the transcript is too broken or too short to summarise,
say so plainly in one line instead of filling the headings with guesses. No
preamble — start at the first heading.'

claude -p "$PROMPT" < transcript.txt > summary.md 2>>notula.log || {
  log "claude failed — see notula.log"; exit 1
}
[[ -s summary.md ]] || { log "the summary came out empty"; exit 1 }
log "done — $FOLDER/summary.md"

print -r -- "$FOLDER"
