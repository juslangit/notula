#!/usr/bin/env python3
"""Interleave the Whisper output of the two tracks into one readable transcript.

Each track is transcribed on its own, so we know which side of the meeting every
line came from: the microphone (the room) or the Mac's own sound (the call).
"""
import json
import sys
from pathlib import Path


def segments(path: Path, label: str):
    if not path.exists():
        return []
    data = json.loads(path.read_text())
    out = []
    for seg in data.get("transcription", []):
        text = seg.get("text", "").strip()
        if not text or text in {"[BLANK_AUDIO]", "(silence)"}:
            continue
        out.append((int(seg["offsets"]["from"]), label, text))
    return out


def stamp(ms: int) -> str:
    s = ms // 1000
    return f"{s // 3600:02d}:{(s % 3600) // 60:02d}:{s % 60:02d}"


def main() -> int:
    folder = Path(sys.argv[1])
    rows = segments(folder / "mic.json", "Room") + segments(folder / "system.json", "Call")
    if not rows:
        return 1
    rows.sort(key=lambda r: r[0])

    lines, last_label, buffer = [], None, []
    for offset, label, text in rows:
        if label != last_label:
            if buffer:
                lines.append(" ".join(buffer))
            buffer = [f"[{stamp(offset)}] {label}: {text}"]
            last_label = label
        else:
            buffer.append(text)
    if buffer:
        lines.append(" ".join(buffer))

    (folder / "transcript.txt").write_text("\n\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
