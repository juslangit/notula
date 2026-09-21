# Notula

A menu bar app that listens to a meeting and writes the minutes.

*Notula* is the Malay word for the written record of a meeting.

## What it does

Click the waveform icon in the menu bar → **Start Recording**. Notula records two
things at once:

| Track | What it hears | Where it comes from |
|---|---|---|
| `mic.wav` | you and anyone in the room | the Mac's microphone |
| `system.wav` | anyone on a Zoom / Meet / Teams call | the sound the Mac itself is playing |

Click **Stop and Summarise** and it transcribes both tracks, interleaves them by
time so every line is labelled `Room:` or `Call:`, and asks Claude to write the
notes. The summary opens by itself when it is ready.

Everything lands in `~/Documents/Meetings/`, in a folder named after the meeting
itself — `2026-09-21-1755-game-jam-format-and-pitching`. The title comes from the
summary, so the Finder is readable a month later without opening anything.

```
summary.html           the notes as a page — this is the one that opens
summary.md             the same notes as plain text, for pasting elsewhere
transcript.txt         what was said, with timestamps and Room / Call labels
meeting.wav            both tracks mixed, for listening back
mic.wav  system.wav    the raw recording
notula.log             what each step did, when something goes wrong
```

## Running it

```sh
./run.sh        # builds the app and starts it
```

The first recording asks for two permissions, once:

- **Microphone** — for the people in the room.
- **Screen & System Audio Recording** — this is the one that lets it hear a call.
  macOS files system audio under screen recording; Notula captures a 2×2 pixel
  video it throws away, and keeps only the sound.

If a permission was refused, it is in System Settings → Privacy & Security.

## The privacy line

The audio never leaves the Mac — Whisper transcribes it here. The **transcript
text** is sent to Anthropic when Claude writes the summary, the same as anything
typed into Claude. For a meeting too sensitive for that, stop after the
transcript: `transcript.txt` is complete on its own.

## The parts

- `Sources/Notula/` — the Swift app: the menu bar icon and the recording.
  `Recorder.swift` is the part that captures audio; `AppDelegate.swift` is the menu.
- `tools/pipeline.sh` — **the brain, and the part worth reading.** Mix → transcribe
  → merge → summarise, as four plain shell steps. The wording of the summary
  prompt lives at the bottom of this file. Editing it changes the next summary
  straight away, with no rebuild.
- `tools/merge_tracks.py` — interleaves the two transcripts by timestamp.
- `tools/render_html.py` — turns `summary.md` into the page, and reports the title
  the folder gets named after. All the styling lives in this one file.
- `models/` — the Whisper model, 547 MB, not in git.

Run the brain by itself on any recording, no app needed:

```sh
./tools/pipeline.sh ~/Documents/Meetings/2026-09-21-1430
./tools/pipeline.sh ~/Downloads/some-recording.m4a
```

It skips any step already done, so if a summary comes out badly you can delete
`summary.md`, edit the prompt and run it again without transcribing afresh — the
page and the folder name are rebuilt from whatever the new summary says.

## Knobs

| Variable | Default | What it does |
|---|---|---|
| `NOTULA_LANG` | `auto` | Force a language: `NOTULA_LANG=en` or `ms`. Useful when a mixed-language meeting gets detected wrongly. |
| `NOTULA_MODEL` | `models/ggml-large-v3-turbo-q5_0.bin` | A different Whisper model. Bigger is more accurate and slower. |
| `NOTULA_QUIET_DB` | `-55` | Below this average volume a track counts as silent and is skipped — that's what stops a silent call track from inventing text. |

## What it needs

`ffmpeg` and `whisper.cpp` from Homebrew, `python3`, and the `claude` command.
macOS 15 or newer, Apple silicon.

## Known limits

- **No speaker names.** It knows room from call, not Ali from Fikri.
- The folder is renamed only after the summary exists, so a run that fails partway
  leaves the plain `<date>-<time>` name behind. Running it again finishes the job.
- Roughly one minute of processing per ten minutes of meeting, on an M2.
- Heavy Malay–English code-switching still trips Whisper. It gets the meaning;
  it mangles the occasional word. The summary prompt tells Claude to expect that.
- A meeting held entirely on headphones with nobody in the room gives a silent
  mic track — that is fine, Notula skips it.
