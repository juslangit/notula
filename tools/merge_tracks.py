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
        out.append((int(seg["offsets"]["from"]), label, text, int(seg["offsets"]["to"])))
    return out


def stamp(ms: int) -> str:
    s = ms // 1000
    return f"{s // 3600:02d}:{(s % 3600) // 60:02d}:{s % 60:02d}"


# A line ends when the other side speaks, when it has run on for this long, or
# when this much silence goes by. Without the last two, a meeting where only one
# side ever speaks comes out as a single unreadable line with one timestamp on it.
MAX_LINE_MS = 45_000
GAP_MS = 3_000


def main() -> int:
    folder = Path(sys.argv[1])
    rows = segments(folder / "mic.json", "Room") + segments(folder / "system.json", "Call")
    if not rows:
        return 1
    rows.sort(key=lambda r: r[0])

    lines: list[str] = []
    buffer: list[str] = []
    label_now, line_start, previous_end = None, 0, 0

    for offset, label, text, end in rows:
        new_line = (
            label != label_now
            or offset - line_start > MAX_LINE_MS
            or offset - previous_end > GAP_MS
        )
        if new_line:
            if buffer:
                lines.append(" ".join(buffer))
            buffer = [f"[{stamp(offset)}] {label}: {text}"]
            label_now, line_start = label, offset
        else:
            buffer.append(text)
        previous_end = end
    if buffer:
        lines.append(" ".join(buffer))

    (folder / "transcript.txt").write_text("\n\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
