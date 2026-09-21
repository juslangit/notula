#!/usr/bin/env python3
"""Turn summary.md into summary.html — a page that is pleasant to read and to print.

Deliberately small: the summary only ever uses headings, paragraphs, bullet lists,
one table and bold text, so this handles that subset and nothing else. No
dependencies, so it keeps working on a fresh Mac with only the system python.
"""
import html
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path


def inline(text: str) -> str:
    """Bold, code and bare links, after escaping everything else."""
    out = html.escape(text.strip())
    out = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"`(.+?)`", r"<code>\1</code>", out)
    out = re.sub(r"(https?://[^\s<)]+)", r'<a href="\1">\1</a>', out)
    return out


def render_table(rows: list[str]) -> str:
    cells = [[c.strip() for c in r.strip().strip("|").split("|")] for r in rows]
    cells = [c for c in cells if not all(re.fullmatch(r":?-{2,}:?", x or "-") for x in c)]
    if not cells:
        return ""
    head, *body = cells
    out = ["<table>", "<thead><tr>"]
    out += [f"<th>{inline(c)}</th>" for c in head]
    out.append("</tr></thead><tbody>")
    for row in body:
        out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in row) + "</tr>")
    out.append("</tbody></table>")
    return "\n".join(out)


def to_html(markdown: str) -> tuple[str, str]:
    title, body, lines = "", [], markdown.splitlines()
    buffer: list[str] = []
    mode = None  # None | "ul" | "table" | "p"

    def flush():
        nonlocal buffer, mode
        if not buffer:
            mode = None
            return
        if mode == "ul":
            body.append("<ul>" + "".join(f"<li>{inline(x)}</li>" for x in buffer) + "</ul>")
        elif mode == "table":
            body.append(render_table(buffer))
        elif mode == "p":
            body.append(f"<p>{inline(' '.join(buffer))}</p>")
        buffer, mode = [], None

    for line in lines:
        stripped = line.strip()
        if not stripped:
            flush()
        elif stripped.startswith("## "):
            flush()
            body.append(f"<h2>{inline(stripped[3:])}</h2>")
        elif stripped.startswith("# "):
            flush()
            if title:
                body.append(f"<h2>{inline(stripped[2:])}</h2>")
            else:
                title = stripped[2:].strip()
        elif stripped.startswith(("- ", "* ")):
            if mode != "ul":
                flush()
            mode = "ul"
            buffer.append(stripped[2:])
        elif stripped.startswith("|"):
            if mode != "table":
                flush()
            mode = "table"
            buffer.append(stripped)
        else:
            if mode != "p":
                flush()
            mode = "p"
            buffer.append(stripped)
    flush()
    return title, "\n".join(body)


PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
  :root {{
    --ink: #1b1b1f; --soft: #5d5d6b; --line: #e2e2e8;
    --bg: #fbfbfd; --card: #ffffff; --accent: #8a5a2b; --mark: #fdf3e7;
  }}
  @media (prefers-color-scheme: dark) {{
    :root {{
      --ink: #e9e9ef; --soft: #9a9aa8; --line: #2c2c34;
      --bg: #121215; --card: #1a1a1f; --accent: #d9a066; --mark: #26201a;
    }}
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; background: var(--bg); color: var(--ink);
    font: 16px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
    -webkit-font-smoothing: antialiased;
  }}
  main {{ max-width: 44rem; margin: 0 auto; padding: 4rem 1.5rem 6rem; }}
  header {{ border-bottom: 2px solid var(--line); padding-bottom: 1.5rem; margin-bottom: 2.5rem; }}
  .eyebrow {{
    font-size: .72rem; letter-spacing: .14em; text-transform: uppercase;
    color: var(--accent); font-weight: 600; margin: 0 0 .6rem;
  }}
  h1 {{ font-size: 2rem; line-height: 1.2; margin: 0 0 .75rem; letter-spacing: -.02em; }}
  .meta {{ color: var(--soft); font-size: .9rem; margin: 0; }}
  .meta span + span::before {{ content: "·"; margin: 0 .5rem; }}
  h2 {{
    font-size: 1.1rem; margin: 2.75rem 0 .9rem; letter-spacing: -.01em;
    padding-left: .75rem; border-left: 3px solid var(--accent);
  }}
  p {{ margin: 0 0 1rem; }}
  ul {{ margin: 0 0 1rem; padding-left: 1.2rem; }}
  li {{ margin-bottom: .45rem; }}
  table {{
    width: 100%; border-collapse: collapse; margin: 0 0 1.25rem;
    background: var(--card); border: 1px solid var(--line); border-radius: 10px;
    overflow: hidden; font-size: .93rem;
  }}
  th {{
    text-align: left; font-size: .72rem; letter-spacing: .1em; text-transform: uppercase;
    color: var(--soft); padding: .75rem 1rem; border-bottom: 1px solid var(--line);
  }}
  td {{ padding: .8rem 1rem; border-bottom: 1px solid var(--line); vertical-align: top; }}
  tr:last-child td {{ border-bottom: none; }}
  td:first-child {{ font-weight: 500; }}
  th:first-child, td:first-child {{ width: 58%; }}
  td:last-child {{ white-space: nowrap; }}
  @media (max-width: 34rem) {{
    th:first-child, td:first-child {{ width: auto; }}
    td:last-child {{ white-space: normal; }}
  }}
  code {{ background: var(--mark); padding: .1em .35em; border-radius: 4px; font-size: .9em; }}
  a {{ color: var(--accent); }}
  footer {{
    margin-top: 4rem; padding-top: 1.25rem; border-top: 1px solid var(--line);
    color: var(--soft); font-size: .8rem;
  }}
  @media print {{
    body {{ background: #fff; color: #000; }}
    main {{ padding: 0; max-width: none; }}
    h2 {{ page-break-after: avoid; }}
    table, ul {{ page-break-inside: avoid; }}
  }}
</style>
</head>
<body>
<main>
  <header>
    <p class="eyebrow">Meeting notes</p>
    <h1>{title}</h1>
    <p class="meta">{meta}</p>
  </header>
  {body}
  <footer>Recorded and transcribed on this Mac by Notula · transcript in <code>transcript.txt</code> · audio in <code>meeting.wav</code></footer>
</main>
</body>
</html>
"""


def duration_of(path: Path) -> str:
    try:
        seconds = float(subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "csv=p=0", str(path)],
            capture_output=True, text=True, check=True).stdout.strip())
    except Exception:
        return ""
    minutes = int(seconds // 60)
    return f"{minutes} min" if minutes else f"{int(seconds)} sec"


def main() -> int:
    folder = Path(sys.argv[1])
    source = folder / "summary.md"
    if not source.exists():
        return 1

    title, body = to_html(source.read_text())
    title = title or "Meeting notes"

    meta = []
    stamp = re.match(r"(\d{4}-\d{2}-\d{2})-(\d{2})(\d{2})", folder.name)
    if stamp:
        when = datetime.strptime(f"{stamp.group(1)} {stamp.group(2)}:{stamp.group(3)}", "%Y-%m-%d %H:%M")
        meta.append(f"<span>{when.strftime('%A, %-d %B %Y')}</span>")
        meta.append(f"<span>{when.strftime('%H:%M')}</span>")
    length = duration_of(folder / "meeting.wav")
    if length:
        meta.append(f"<span>{length}</span>")

    (folder / "summary.html").write_text(PAGE.format(
        title=html.escape(title), meta="".join(meta), body=body))
    print(title)
    return 0


if __name__ == "__main__":
    sys.exit(main())
