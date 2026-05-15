#!/usr/bin/env python3
from __future__ import annotations

import argparse
import html
import json
import os
import plistlib
import subprocess
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from urllib.parse import quote


PROJECT_ROOT = Path(__file__).resolve().parents[2]
REPORTS_DIR = PROJECT_ROOT / "reports"
ARCHIVE_DIR = REPORTS_DIR / "archive"
REPORTS_DIR.mkdir(parents=True, exist_ok=True)


def env_paths(name: str) -> list[Path]:
    value = os.environ.get(name, "")
    return [Path(item).expanduser() for item in value.split(os.pathsep) if item.strip()]


@dataclass
class AppBundle:
    name: str
    location: str
    path: Path
    version: str
    bundle_id: str
    size_bytes: int
    modified: str


@dataclass
class BrewPackage:
    name: str
    versions: str
    description: str
    homepage: str
    kind: str


@dataclass
class LaunchItem:
    label: str
    domain: str
    path: Path
    program: str
    status: str
    note: str


@dataclass
class ProjectItem:
    name: str
    path: Path
    modified: str
    git_status: str
    project_type: str
    run_command: str
    docs: str
    note: str


@dataclass
class FolderWeight:
    name: str
    path: Path
    size_bytes: int
    note: str


def run(command: list[str], timeout: int | None = None) -> str:
    try:
        return subprocess.check_output(command, text=True, stderr=subprocess.DEVNULL, timeout=timeout).strip()
    except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return ""


def run_in(command: list[str], cwd: Path) -> str:
    try:
        return subprocess.check_output(command, cwd=cwd, text=True, stderr=subprocess.DEVNULL).strip()
    except (FileNotFoundError, subprocess.CalledProcessError):
        return ""


def human_size(size_bytes: int) -> str:
    size = float(size_bytes)
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size < 1024 or unit == "TB":
            return f"{size:.1f} {unit}" if unit != "B" else f"{int(size)} B"
        size /= 1024
    return f"{size_bytes} B"


def directory_size(path: Path) -> int:
    total = 0
    for item in path.rglob("*"):
        try:
            if item.is_file() or item.is_symlink():
                total += item.stat().st_size
        except OSError:
            continue
    return total


def modified_date(path: Path) -> str:
    try:
        return datetime.fromtimestamp(path.stat().st_mtime).strftime("%Y-%m-%d")
    except OSError:
        return "Review"


def folder_size(path: Path) -> int:
    raw = run(["/usr/bin/du", "-sk", str(path)], timeout=15)
    if raw:
        try:
            return int(raw.split()[0]) * 1024
        except (ValueError, IndexError):
            pass
    return 0


def batch_directory_sizes(paths: list[Path], timeout: int = 30) -> dict[Path, int]:
    if not paths:
        return {}
    try:
        raw = subprocess.check_output(
            ["/usr/bin/du", "-sk", *[str(path) for path in paths]],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
        )
    except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return {}

    sizes: dict[Path, int] = {}
    for line in raw.splitlines():
        parts = line.split(maxsplit=1)
        if len(parts) != 2:
            continue
        try:
            sizes[Path(parts[1])] = int(parts[0]) * 1024
        except ValueError:
            continue
    return sizes


def app_metadata(app_path: Path, location: str, size_bytes: int | None = None) -> AppBundle:
    plist_path = app_path / "Contents" / "Info.plist"
    version = ""
    bundle_id = ""
    if plist_path.exists():
        try:
            with plist_path.open("rb") as handle:
                plist = plistlib.load(handle)
            version = str(plist.get("CFBundleShortVersionString") or plist.get("CFBundleVersion") or "")
            bundle_id = str(plist.get("CFBundleIdentifier") or "")
        except Exception:
            version = ""
            bundle_id = ""

    try:
        modified = datetime.fromtimestamp(app_path.stat().st_mtime).strftime("%Y-%m-%d")
    except OSError:
        modified = ""

    return AppBundle(
        name=app_path.stem,
        location=location,
        path=app_path,
        version=version or "Review",
        bundle_id=bundle_id or "Review",
        size_bytes=size_bytes if size_bytes is not None else folder_size(app_path),
        modified=modified,
    )


def scan_apps() -> list[AppBundle]:
    roots = [
        (Path("/Applications"), "/Applications"),
        (Path.home() / "Applications", "~/Applications"),
    ]
    apps: list[AppBundle] = []
    for root, label in roots:
        if not root.exists():
            continue
        app_paths = sorted(root.glob("*.app"), key=lambda item: item.name.lower())
        size_map = batch_directory_sizes(app_paths)
        for app_path in app_paths:
            apps.append(app_metadata(app_path, label, size_map.get(app_path)))
    return apps


def brew_info() -> dict[str, dict[str, str]]:
    raw = run(["brew", "info", "--json=v2", "--installed"])
    if not raw:
        return {}
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        return {}

    details: dict[str, dict[str, str]] = {}
    for formula in parsed.get("formulae", []):
        name = formula.get("name", "")
        if name:
            details[name] = {
                "description": formula.get("desc", ""),
                "homepage": formula.get("homepage", ""),
            }
    for cask in parsed.get("casks", []):
        cask_name = cask.get("token", "")
        if cask_name:
            details[cask_name] = {
                "description": cask.get("desc", ""),
                "homepage": cask.get("homepage", ""),
            }
    return details


def parse_brew_list(kind: str, details: dict[str, dict[str, str]]) -> list[BrewPackage]:
    raw = run(["brew", "list", f"--{kind}", "--versions"])
    packages: list[BrewPackage] = []
    for line in raw.splitlines():
        parts = line.split()
        if not parts:
            continue
        name = parts[0]
        meta = details.get(name, {})
        packages.append(
            BrewPackage(
                name=name,
                versions=", ".join(parts[1:]) or "Review",
                description=meta.get("description") or "Review: no description returned by Homebrew.",
                homepage=meta.get("homepage") or "",
                kind=kind,
            )
        )
    return sorted(packages, key=lambda package: package.name.lower())


def slug(text: str) -> str:
    safe = "".join(char.lower() if char.isalnum() else "-" for char in text)
    return "-".join(part for part in safe.split("-") if part)


def link(label: str, href: str) -> str:
    return f'<a href="{html.escape(href, quote=True)}">{html.escape(label)}</a>' if href else html.escape(label)


def link_raw(label_html: str, href: str) -> str:
    return f'<a href="{html.escape(href, quote=True)}">{label_html}</a>' if href else label_html


def file_url(path: Path) -> str:
    return "file://" + quote(str(path))


def table(headers: list[str], rows: list[list[str]], table_class: str = "", widths: list[str] | None = None) -> str:
    head = "".join(f"<th>{html.escape(header)}</th>" for header in headers)
    body = "\n".join("<tr>" + "".join(f"<td>{cell}</td>" for cell in row) + "</tr>" for row in rows)
    class_attr = f' class="{html.escape(table_class, quote=True)}"' if table_class else ""
    colgroup = ""
    if widths:
        colgroup = "<colgroup>" + "".join(f'<col style="width: {html.escape(width, quote=True)}">' for width in widths) + "</colgroup>"
    return f'<div class="table-wrap"><table{class_attr}>{colgroup}<thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>'


def page(title: str, subtitle: str, sections: list[tuple[str, str]]) -> str:
    toc = "\n".join(f'<a href="#{slug(heading)}">{html.escape(heading)}</a>' for heading, _ in sections)
    body = "\n".join(
        f'<section id="{slug(heading)}"><h2>{html.escape(heading)}</h2>{content}</section>'
        for heading, content in sections
    )
    generated = datetime.now().strftime("%Y-%m-%d %H:%M")
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<style>
:root {{
  --ink: #171923;
  --muted: #6b7280;
  --line: #e4e4df;
  --soft: #f7f7f5;
  --accent: #3b6f6a;
}}
* {{ box-sizing: border-box; }}
body {{
  margin: 0;
  color: var(--ink);
  background: #fff;
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
  -webkit-font-smoothing: antialiased;
}}
.shell {{ display: grid; grid-template-columns: 220px minmax(0, 1fr); min-height: 100vh; }}
aside {{
  position: sticky;
  top: 0;
  height: 100vh;
  padding: 22px 18px;
  border-right: 1px solid var(--line);
  background: var(--soft);
  overflow: auto;
}}
main {{ padding: 16px clamp(20px, 4vw, 52px) 48px; }}
h1 {{ font-size: 22px; letter-spacing: 0; margin: 0; }}
h2 {{ font-size: 22px; letter-spacing: 0; margin: 22px 0 10px; }}
section:first-child h2 {{ margin-top: 0; }}
p {{ color: var(--muted); line-height: 1.5; }}
a {{ color: var(--ink); text-decoration: none; }}
a:hover {{ color: var(--accent); text-decoration: underline; text-underline-offset: 2px; }}
.toc-title {{ color: #9ca3af; font-size: 11px; font-weight: 760; letter-spacing: 0; text-transform: uppercase; margin: 0 0 12px; }}
aside a {{ display: block; color: var(--muted); font-size: 13px; line-height: 1.35; margin: 0 0 9px; }}
.page-meta {{
  color: #9ca3af;
  font-size: 11px;
  line-height: 1.35;
  margin-top: 18px;
}}
.page-top {{
  align-items: baseline;
  border-bottom: 1px solid var(--line);
  display: flex;
  gap: 12px;
  justify-content: space-between;
  margin: 0 0 18px;
  padding: 0 0 10px;
}}
.page-top p {{
  color: #9ca3af;
  flex: none;
  font-size: 11px;
  line-height: 1.2;
  margin: 0;
}}
.summary {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: 10px; margin: 18px 0 4px; }}
.metric {{ border: 1px solid var(--line); border-radius: 7px; padding: 13px 14px; background: #fff; }}
.metric strong {{ display: block; font-size: 24px; }}
.metric span {{ color: var(--muted); font-size: 12px; }}
.status {{ display: inline-block; border: 1px solid var(--line); border-radius: 999px; padding: 2px 8px; font-size: 11px; font-weight: 760; white-space: nowrap; }}
.status-keep, .status-your-app {{ background: #edf6ee; color: #24613c; border-color: #cfe7d3; }}
.status-consider, .status-big-file {{ background: #fff7e6; color: #805a15; border-color: #eed99f; }}
.status-duplicate, .status-remove {{ background: #f8e9e9; color: #853535; border-color: #e8c8c8; }}
.status-review {{ background: #f1f4f8; color: #4b5563; border-color: #d8dee8; }}
.column-tools {{ display: none; }}
button {{ border: 1px solid var(--line); background: #fff; color: var(--ink); border-radius: 7px; padding: 7px 10px; font: inherit; }}
.table-wrap {{ border: 1px solid var(--line); border-radius: 7px; overflow: auto; margin: 0 0 16px; }}
table {{ width: 100%; border-collapse: collapse; min-width: 720px; }}
th, td {{ text-align: left; vertical-align: top; border-bottom: 1px solid var(--line); padding: 8px 10px; font-size: 13px; line-height: 1.36; }}
th {{ background: var(--soft); font-weight: 760; position: sticky; top: 0; z-index: 1; }}
tr:last-child td {{ border-bottom: 0; }}
.dense-table {{ table-layout: fixed; min-width: 980px; }}
.dense-table th, .dense-table td {{ overflow-wrap: anywhere; word-break: normal; }}
.dense-table td {{ font-size: 12.5px; line-height: 1.32; }}
.dense-table .status {{ padding-inline: 7px; }}
.compact-text {{ display: inline-block; max-width: 100%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; vertical-align: bottom; }}
.path-text {{ color: #374151; display: inline-block; max-width: 100%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; vertical-align: bottom; font-family: "SF Mono", ui-monospace, Menlo, monospace; font-size: 11.5px; line-height: 1.35; }}
.col-resizer {{ position: absolute; top: 0; right: -4px; width: 8px; height: 100%; cursor: col-resize; }}
.col-resizer::after {{ content: ""; display: block; width: 1px; height: 100%; margin-left: 3px; background: transparent; }}
th:hover .col-resizer::after, .col-resizer.active::after {{ background: var(--accent); }}
body.is-resizing {{ cursor: col-resize; user-select: none; }}
@media (max-width: 900px) {{
  .shell {{ grid-template-columns: 1fr; }}
  aside {{ position: relative; height: auto; border-right: 0; border-bottom: 1px solid var(--line); }}
  main {{ padding: 24px 18px 42px; }}
}}
@media print {{
  aside, .column-tools {{ display: none; }}
  .shell {{ display: block; }}
  main {{ padding: 0; }}
}}
</style>
</head>
<body>
<div class="shell">
<aside>
  <div class="toc-title">Contents</div>
  {toc}
  <p class="page-meta">Generated {generated}</p>
</aside>
<main>
  <div class="page-top">
    <h1>{html.escape(title)}</h1>
    <p>{html.escape(generated)}</p>
  </div>
  <article class="content">
    {body}
  </article>
</main>
</div>
<script>
(() => {{
  function keyFor(table) {{
    const heading = table.closest('section')?.id || 'table';
    return `kika-report-column-widths:${{location.pathname}}:${{heading}}`;
  }}
  function applyWidths(table, widths) {{
    [...table.querySelectorAll('th')].forEach((th, index) => {{
      if (widths[index]) th.style.width = widths[index] + 'px';
    }});
  }}
  function install(table) {{
    const storageKey = keyFor(table);
    try {{ applyWidths(table, JSON.parse(localStorage.getItem(storageKey) || '[]')); }} catch {{}}
    table.querySelectorAll('th').forEach((th, index) => {{
      const handle = document.createElement('span');
      handle.className = 'col-resizer';
      th.appendChild(handle);
      handle.addEventListener('dblclick', () => {{
        th.style.width = '';
        const widths = [...table.querySelectorAll('th')].map(item => item.offsetWidth);
        localStorage.setItem(storageKey, JSON.stringify(widths));
      }});
      handle.addEventListener('pointerdown', (event) => {{
        event.preventDefault();
        handle.setPointerCapture(event.pointerId);
        handle.classList.add('active');
        document.body.classList.add('is-resizing');
        const startX = event.clientX;
        const startWidth = th.offsetWidth;
        const move = (moveEvent) => {{
          const next = Math.max(70, startWidth + moveEvent.clientX - startX);
          th.style.width = next + 'px';
        }};
        const up = () => {{
          handle.classList.remove('active');
          document.body.classList.remove('is-resizing');
          const widths = [...table.querySelectorAll('th')].map(item => item.offsetWidth);
          localStorage.setItem(storageKey, JSON.stringify(widths));
          handle.removeEventListener('pointermove', move);
          handle.removeEventListener('pointerup', up);
          handle.removeEventListener('pointercancel', up);
        }};
        handle.addEventListener('pointermove', move);
        handle.addEventListener('pointerup', up);
        handle.addEventListener('pointercancel', up);
      }});
    }});
  }}
  document.querySelectorAll('table').forEach(install);
}})();
</script>
</body>
</html>
"""


def write_pair(
    stem: str,
    title: str,
    subtitle: str,
    html_sections: list[tuple[str, str]],
    markdown: str,
    archive: bool = False,
) -> None:
    target_dir = ARCHIVE_DIR if archive else REPORTS_DIR
    target_dir.mkdir(parents=True, exist_ok=True)
    rendered = page(title, subtitle, html_sections)
    (target_dir / f"{stem}.html").write_text(rendered, encoding="utf-8")
    (target_dir / f"{stem}.md").write_text(markdown, encoding="utf-8")


def status_badge(status: str) -> str:
    class_name = slug(status)
    return f'<span class="status status-{class_name}">{html.escape(status)}</span>'


def app_lookup(apps: list[AppBundle]) -> dict[str, AppBundle]:
    return {app.name.lower(): app for app in apps}


def matching_apps(apps: list[AppBundle], names: list[str]) -> list[AppBundle]:
    lookup = app_lookup(apps)
    found: list[AppBundle] = []
    for name in names:
        app = lookup.get(name.lower())
        if app:
            found.append(app)
    return found


def package_lookup(packages: list[BrewPackage]) -> dict[str, BrewPackage]:
    return {package.name.lower(): package for package in packages}


def app_matches(app: AppBundle, needles: set[str]) -> bool:
    haystack = f"{app.name} {app.bundle_id}".lower()
    return any(needle.lower() in haystack for needle in needles)


def package_matches(package: BrewPackage, needles: set[str]) -> bool:
    haystack = f"{package.name} {package.description}".lower()
    return any(needle.lower() in haystack for needle in needles)


def markdown_table(headers: list[str], rows: list[list[str]]) -> str:
    clean_rows = [
        [html.unescape(cell).replace("\n", " ").replace("|", "/") for cell in row]
        for row in rows
    ]
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    lines.extend("| " + " | ".join(row) + " |" for row in clean_rows)
    return "\n".join(lines)


def compact_text(text: str, max_length: int = 88) -> str:
    if len(text) <= max_length:
        return text
    keep = max(12, (max_length - 3) // 2)
    tail = max_length - keep - 3
    return f"{text[:keep]}...{text[-tail:]}"


def path_cell(path: str, max_length: int = 92) -> str:
    display = compact_text(path.replace(str(Path.home()), "~"), max_length)
    return f'<span class="path-text" title="{html.escape(path, quote=True)}">{html.escape(display)}</span>'


def compact_cell(text: str, max_length: int = 44) -> str:
    display = compact_text(text, max_length)
    return f'<span class="compact-text" title="{html.escape(text, quote=True)}">{html.escape(display)}</span>'


def recommendation_rows(apps: list[AppBundle]) -> list[list[str]]:
    lookup = app_lookup(apps)
    rules = [
        ("Claude", "AI assistant", "Keep", "Primary assistant candidate."),
        ("Claude Code Agent", "AI dev tool", "Keep", "Development agent workflow."),
        ("ChatGPT", "AI assistant", "Keep", "Official OpenAI desktop app."),
        ("ChatGPT Atlas", "AI assistant", "Duplicate", "Review overlap with ChatGPT before keeping both."),
        ("Gemini", "AI assistant", "Keep", "Keep if it has a distinct Google workflow role."),
        ("Google Gemini", "AI assistant", "Duplicate", "Likely duplicate of Gemini; keep one after confirming data/account needs."),
        ("Perplexity", "AI research", "Keep", "Useful research/search surface if active."),
        ("5ire", "AI assistant", "Consider", "Keep only if MCP/multi-provider features are actively used."),
        ("MindMac", "AI assistant", "Consider", "Review overlap with ChatGPT, Claude, and API clients."),
        ("Noi", "AI browser", "Consider", "Aggregator browser; keep only if it replaces several clients."),
        ("RabbitHolesAI", "AI research", "Consider", "Keep if deep research workflows are active."),
        ("Manus", "AI agent", "Consider", "Review recent use before keeping."),
        ("AI Deck", "AI utility", "Consider", "Review role against existing AI tools."),
        ("Cai", "AI utility", "Review", "Identify role before deciding."),
        ("Ollama", "Local LLM", "Keep", "Core local model runner."),
        ("Ollamac", "Ollama UI", "Keep", "Good primary native Ollama UI candidate."),
        ("Locally AI", "Ollama UI", "Duplicate", "Remove if Ollamac or AnythingLLM covers this workflow."),
        ("Mollama", "Ollama UI", "Duplicate", "Keep only if it has a unique feature."),
        ("MLCChat", "Local LLM", "Duplicate", "Keep only if the MLC engine is specifically needed."),
        ("PocketPal", "Local LLM", "Duplicate", "Likely redundant with main Ollama/GGUF workflow."),
        ("RecurseChat", "Local LLM", "Duplicate", "Likely redundant if Ollamac is primary."),
        ("AnythingLLM", "Local LLM hub", "Consider", "Keep if using RAG, agents, or document chat."),
        ("Codex", "AI dev tool", "Keep", "Active OpenAI Codex workflow."),
        ("CodexShot", "AI dev tool", "Keep", "Screenshot-to-code helper."),
        ("Observer", "AI monitor", "Keep", "AI monitoring/observation surface."),
        ("oMLX", "Local LLM", "Consider", "Keep if you run MLX models directly."),
        ("Goose", "AI dev agent", "Consider", "Review overlap with Codex and Claude Code."),
        ("Prompt Cowboy", "Prompt tool", "Consider", "Review overlap with your active prompt tools."),
        ("Figma", "Design", "Keep", "Core design tool."),
        ("Sketch", "Design", "Keep", "Keep if still used alongside Figma."),
        ("Adobe Photoshop 2026", "Design", "Big File", "Keep only if image editing is active."),
        ("Adobe Creative Cloud", "Design suite", "Big File", "Keep only if required by Adobe apps."),
        ("Eagle", "Asset manager", "Keep", "Primary visual asset/reference manager."),
        ("Eagle Pocket", "Asset manager", "Consider", "Keep if it supports the Eagle capture flow."),
        ("Aseprite", "Pixel art", "Keep", "Useful for icon/sprite work."),
        ("Mochi Diffusion", "AI image", "Keep", "Keep if local image generation is active."),
        ("Gifox", "Screen recording", "Keep", "GIF recorder for demos."),
        ("Gifski", "GIF conversion", "Duplicate", "Review whether Gifox already covers this."),
        ("Xcode", "Apple development", "Keep", "Required for Swift, iOS, and macOS development."),
        ("Cursor", "AI IDE", "Keep", "Keep if active."),
        ("Docker", "Containers", "Keep", "Container runtime."),
        ("GitHub Desktop", "Git GUI", "Keep", "Keep if useful alongside CLI."),
        ("Keyboard Maestro", "Automation", "Keep", "Powerful automation tool."),
        ("Raycast", "Launcher", "Keep", "Primary launcher; can replace some clipboard/snippet tools."),
        ("ForkLift", "File manager", "Keep", "File transfer and SFTP workflows."),
        ("MacDown 3000", "Markdown", "Consider", "Review overlap with Obsidian and other editors."),
        ("OpenCode", "AI dev", "Consider", "Review overlap with Codex, Cursor, and Claude Code."),
        ("Maccy", "Clipboard", "Keep", "Small dedicated clipboard manager."),
        ("CopyClip", "Clipboard", "Duplicate", "Remove if Raycast or Maccy covers clipboard history."),
        ("PasteIQ", "Clipboard AI", "Consider", "Keep only if AI clipboard features are useful."),
        ("Focus", "Focus timer", "Duplicate", "Review whether another focus workflow already covers it."),
        ("Pinterest", "Inspiration", "Consider", "Review whether Eagle covers this role."),
        ("Obsidian", "Notes", "Keep", "Primary knowledge base candidate."),
        ("Notion", "Workspace", "Keep", "Keep if used for collaboration or publishing."),
        ("Logseq", "Notes", "Keep", "Keep if graph/outliner workflow is active."),
        ("Heptabase", "Visual PKM", "Big File", "Keep only if canvas workflow is active."),
        ("Standard Notes", "Encrypted notes", "Keep", "Strong secure notes layer."),
        ("Notesnook", "Encrypted notes", "Duplicate", "Keep either Notesnook or Standard Notes unless roles differ."),
        ("FSNotes", "File notes", "Consider", "Review overlap with Obsidian."),
        ("Notable", "Markdown notes", "Duplicate", "Likely superseded by Obsidian."),
        ("NoteApp", "Notes", "Duplicate", "Likely redundant."),
        ("MyZettel", "Zettelkasten", "Duplicate", "Likely covered by Obsidian."),
        ("Microsoft OneNote", "Notes", "Consider", "Keep if needed for Microsoft collaboration."),
        ("Taio", "Text/Markdown", "Consider", "Review overlap with existing editors."),
        ("MarKie", "Markdown", "Duplicate", "Likely redundant with existing Markdown tools."),
        ("Read.md", "Markdown", "Duplicate", "Likely redundant if another editor previews Markdown."),
        ("CleanMyMac", "Cleaner", "Keep", "Use intentionally; review actions before applying."),
        ("Pearcleaner", "Uninstaller", "Keep", "Preferred uninstaller candidate."),
        ("Uninstaller", "Uninstaller", "Duplicate", "Remove if Pearcleaner covers this workflow."),
        ("DevCleaner", "Xcode cleanup", "Keep", "Useful with large Xcode installs."),
        ("Hidden Bar", "Menu bar", "Keep", "Useful with many menu bar utilities."),
        ("Magnet", "Window manager", "Keep", "Keep if part of daily workflow."),
        ("FileMate", "File manager", "Duplicate", "Likely redundant with ForkLift/Commander One."),
        ("Commander One", "File manager", "Consider", "Review use compared with Finder/ForkLift."),
        ("Termius", "SSH", "Keep", "Keep if used for server access."),
        ("Dropbox", "Cloud sync", "Keep", "Keep if files are synced there."),
        ("LocalSend", "LAN sharing", "Keep", "Useful for local device transfers."),
        ("NordVPN", "VPN", "Keep", "Keep if subscribed and used."),
        ("Tailscale", "VPN mesh", "Keep", "Different role from NordVPN; keep if active."),
    ]

    rows: list[list[str]] = []
    for name, kind, status, note in rules:
        app = lookup.get(name.lower())
        if not app:
            continue
        rows.append([
            link(app.name, file_url(app.path)),
            html.escape(kind),
            status_badge(status),
            html.escape(human_size(app.size_bytes)),
            html.escape(note),
        ])
    return rows


def cleanup_report(apps: list[AppBundle], casks: list[BrewPackage], formulae: list[BrewPackage], today: str) -> tuple[list[tuple[str, str]], str]:
    rows = recommendation_rows(apps)
    duplicate_rows = [row for row in rows if "Duplicate" in row[2]]
    review_rows = [row for row in rows if any(label in row[2] for label in ["Consider", "Big File", "Review"])]
    keep_rows = [row for row in rows if any(label in row[2] for label in ["Keep", "Your App"])]
    largest_rows = [
        [
            link(app.name, file_url(app.path)),
            status_badge("Big File" if app.size_bytes >= 1_000_000_000 else "Review"),
            html.escape(human_size(app.size_bytes)),
            html.escape("Review whether this still earns its disk space."),
        ]
        for app in sorted(apps, key=lambda app: app.size_bytes, reverse=True)[:15]
    ]

    brew_review_names = {"imagemagick", "imagemagick-full", "fdupes", "gifski", "ffmpeg", "yt-dlp", "ollama", "gh", "mas", "node", "python@3.13"}
    brew_rows = [
        [
            link(package.name, package.homepage),
            html.escape("Cask" if package.kind == "cask" else "CLI / formula"),
            status_badge("Review" if package.name in brew_review_names else "Keep"),
            html.escape(package.versions),
            html.escape(package.description),
        ]
        for package in [*casks, *formulae]
        if package.kind == "cask" or package.name in brew_review_names
    ]

    summary = f"""
    <div class="summary">
      <div class="metric"><strong>{len(rows)}</strong><span>matched tools with guidance</span></div>
      <div class="metric"><strong>{len(keep_rows)}</strong><span>keep / core tools</span></div>
      <div class="metric"><strong>{len(duplicate_rows)}</strong><span>duplicate or removal candidates</span></div>
      <div class="metric"><strong>{len(review_rows)}</strong><span>consider / review items</span></div>
    </div>
    <p>This report is guidance, not an uninstall script. Treat duplicate and remove-candidate rows as review-first: open the app once, confirm account/data needs, then remove with Pearcleaner or another uninstaller if appropriate.</p>
    """

    action_rows = [
        ["Consolidate local LLM clients", "Keep Ollama plus one primary UI such as Ollamac. Keep AnythingLLM only if RAG, agents, or document chat are active."],
        ["Consolidate notes apps", "Keep a focused notes stack. Obsidian plus one encrypted notes app is usually enough unless a second app has a clear role."],
        ["Resolve duplicate utilities", "Review duplicate clipboard managers, uninstallers, file managers, Markdown viewers, and local LLM front ends."],
        ["Review largest apps", "Large apps should stay only when they have a current role. Xcode is expected; creative and local-model apps should earn their space."],
        ["Prefer owned workflows", "Where practical, prefer your own active tools over third-party overlap."],
    ]

    sections = [
        ("Overview", summary),
        ("Action Summary", table(["Action", "Details"], [[html.escape(a), html.escape(b)] for a, b in action_rows])),
        ("Keep / Core Tools", table(["App", "Type", "Status", "Size", "Notes"], keep_rows or [["Review", "No matched keep rows found.", "", "", ""]])),
        ("Duplicates / Remove Candidates", table(["App", "Type", "Status", "Size", "Notes"], duplicate_rows or [["Review", "No duplicate rows matched the live scan.", "", "", ""]])),
        ("Consider / Review", table(["App", "Type", "Status", "Size", "Notes"], review_rows or [["Review", "No review rows matched the live scan.", "", "", ""]])),
        ("Largest Apps To Review", table(["App", "Status", "Size", "Notes"], largest_rows)),
        ("Homebrew Tools To Review", table(["Package", "Type", "Status", "Version", "Description"], brew_rows)),
    ]

    md_lines = [
        f"# Cleanup Recommendations ({today})",
        "",
        "Guidance for tools to keep, remove, deduplicate, or review. Confirm usage and data before uninstalling.",
        "",
        "## Action Summary",
        "",
        *[f"- **{action}**: {detail}" for action, detail in action_rows],
        "",
        "## Duplicates / Remove Candidates",
        "",
    ]
    for row in duplicate_rows:
        md_lines.append(f"- {row[0]} | {row[1]} | Duplicate | {row[3]} | {row[4]}")
    md_lines.extend(["", "## Consider / Review", ""])
    for row in review_rows:
        md_lines.append(f"- {row[0]} | {row[1]} | Review | {row[3]} | {row[4]}")
    md_lines.extend(["", "## Keep / Core Tools", ""])
    for row in keep_rows:
        md_lines.append(f"- {row[0]} | {row[1]} | Keep | {row[3]} | {row[4]}")

    return sections, "\n".join(md_lines) + "\n"


def background_report(apps: list[AppBundle], casks: list[BrewPackage], today: str) -> tuple[list[tuple[str, str]], str]:
    categories: list[tuple[str, set[str], str]] = [
        ("Launcher / command center", {"raycast", "alfred", "spotlight"}, "Likely always available; keep if it is the primary command surface."),
        ("Menu bar manager", {"hidden bar", "bartender", "dozer"}, "Menu bar utility; keep if it reduces visual noise."),
        ("Clipboard", {"maccy", "copyclip", "paste", "pasteiq", "clipboard"}, "Review overlap so only one clipboard history tool is active."),
        ("Sync / sharing", {"dropbox", "localsend", "google drive", "onedrive", "syncthing"}, "Background sync or transfer tool; keep only when the folder/data role is clear."),
        ("VPN / network", {"nordvpn", "tailscale", "wireguard", "zerotier"}, "Network background tool; keep when actively used."),
        ("Cleaner / maintenance", {"cleanmymac", "pearcleaner", "devcleaner", "uninstaller"}, "Maintenance tool; use intentionally and avoid overlapping cleaners."),
        ("Automation", {"keyboard maestro", "shortcuts", "hammerspoon", "bettertouchtool"}, "Automation tool; keep if active in daily workflows."),
        ("Window / focus", {"magnet", "rectangle", "focus"}, "Background productivity utility; review duplicate window/focus tools."),
    ]

    rows: list[list[str]] = []
    for app in apps:
        for category, needles, note in categories:
            if app_matches(app, needles):
                status = "Review" if category in {"Clipboard", "Cleaner / maintenance", "Window / focus"} else "Keep"
                rows.append([
                    link(app.name, file_url(app.path)),
                    html.escape(category),
                    status_badge(status),
                    html.escape(human_size(app.size_bytes)),
                    html.escape(note),
                ])
                break

    cask_lookup = package_lookup(casks)
    for name in ["raycast", "hiddenbar", "maccy", "dropbox", "tailscale", "nordvpn", "keyboard-maestro", "magnet", "cleanmymac"]:
        package = cask_lookup.get(name)
        if package and not any(name.replace("-", " ") in row[0].lower() for row in rows):
            rows.append([
                link(package.name, package.homepage),
                "Homebrew cask",
                status_badge("Review"),
                html.escape(package.versions),
                html.escape(package.description),
            ])

    rows = sorted(rows, key=lambda row: (html.unescape(row[1]), html.unescape(row[0]).lower()))
    summary = f"""
    <div class="summary">
      <div class="metric"><strong>{len(rows)}</strong><span>background-style tools found</span></div>
      <div class="metric"><strong>{sum(1 for row in rows if 'Review' in row[2])}</strong><span>review for overlap</span></div>
      <div class="metric"><strong>{sum(1 for row in rows if 'Keep' in row[2])}</strong><span>likely keep if active</span></div>
    </div>
    <p>These are tools that commonly live in the menu bar, run at login, sync files, watch the system, or stay resident in the background. This report only identifies review targets; it does not change login items or running processes.</p>
    """
    sections = [
        ("Overview", summary),
        ("Background Tools", table(["Tool", "Category", "Status", "Size / Version", "Review Note"], rows or [["Review", "No matching background-style tools found.", "", "", ""]])),
    ]
    md = "\n\n".join([
        f"# Background Tools Report ({today})",
        "Read-only review of menu bar, sync, VPN, clipboard, launcher, cleaner, automation, and always-on utilities.",
        markdown_table(["Tool", "Category", "Status", "Size / Version", "Review Note"], rows),
    ]) + "\n"
    return sections, md


def scan_launch_items() -> list[LaunchItem]:
    roots = [
        (Path.home() / "Library" / "LaunchAgents", "User LaunchAgents"),
        (Path("/Library/LaunchAgents"), "System LaunchAgents"),
        (Path("/Library/LaunchDaemons"), "System LaunchDaemons"),
        (Path("/Library/StartupItems"), "Legacy StartupItems"),
    ]
    items: list[LaunchItem] = []
    for root, domain in roots:
        if not root.exists():
            continue
        for path in sorted(root.glob("*.plist"), key=lambda item: item.name.lower()):
            label = path.stem
            program = "Review"
            status = "Installed"
            note = "Review whether this background item still has a current role."
            try:
                with path.open("rb") as handle:
                    plist = plistlib.load(handle)
                label = str(plist.get("Label") or label)
                args = plist.get("ProgramArguments") or []
                program = str(plist.get("Program") or (args[0] if args else "Review"))
                if plist.get("RunAtLoad") or plist.get("KeepAlive"):
                    status = "Auto Starts"
                if plist.get("Disabled") is True:
                    status = "Disabled"
                if plist.get("KeepAlive"):
                    note = "KeepAlive item; review carefully before changing outside HTTMELY."
                elif plist.get("RunAtLoad"):
                    note = "Runs at load; confirm it belongs to an app you still use."
            except Exception:
                note = "Could not parse plist cleanly; inspect before changing anything."
            items.append(LaunchItem(label, domain, path, program, status, note))
    return items


def startup_report(today: str) -> tuple[list[tuple[str, str]], str]:
    items = scan_launch_items()

    def short_domain(domain: str) -> str:
        return {
            "User LaunchAgents": "User Agents",
            "System LaunchAgents": "System Agents",
            "System LaunchDaemons": "System Daemons",
            "Legacy StartupItems": "Legacy Startup",
        }.get(domain, domain)

    def short_note(note: str) -> str:
        replacements = {
            "KeepAlive item; review carefully before changing outside HTTMELY.": "KeepAlive item; review before changing.",
            "Runs at load; confirm it belongs to an app you still use.": "Runs at load; confirm the app is still used.",
            "Review whether this background item still has a current role.": "Review whether this still has a current role.",
            "Could not parse plist cleanly; inspect before changing anything.": "Could not parse cleanly; inspect before changing.",
        }
        return replacements.get(note, note)

    rows = [
        [
            compact_cell(item.label, 38),
            html.escape(short_domain(item.domain)),
            link_raw(compact_cell(item.path.name, 40), file_url(item.path)),
            path_cell(item.program),
            status_badge("Review" if item.status != "Disabled" else "Consider"),
            compact_cell(short_note(item.note), 54),
        ]
        for item in items
    ]
    summary = f"""
    <div class="summary">
      <div class="metric"><strong>{len(items)}</strong><span>launch plist files found</span></div>
      <div class="metric"><strong>{sum(1 for item in items if item.status == 'Auto Starts')}</strong><span>auto-start style items</span></div>
      <div class="metric"><strong>{sum(1 for item in items if item.domain == 'User LaunchAgents')}</strong><span>user launch agents</span></div>
      <div class="metric"><strong>{sum(1 for item in items if item.domain == 'System LaunchDaemons')}</strong><span>system daemons</span></div>
    </div>
    <p>This report only reads launch item metadata. It does not unload, disable, delete, or modify any startup item.</p>
    """
    sections = [
        ("Overview", summary),
        (
            "Launch Items",
            table(
                ["Label", "Domain", "File", "Program", "Status", "Review Note"],
                rows or [["Review", "No launch plist files found.", "", "", "", ""]],
                table_class="dense-table",
                widths=["17%", "11%", "18%", "28%", "7%", "19%"],
            ),
        ),
    ]
    md = "\n\n".join([
        f"# Startup Items Report ({today})",
        "Read-only inventory of LaunchAgents, LaunchDaemons, and legacy StartupItems.",
        markdown_table(["Label", "Domain", "File", "Program", "Status", "Review Note"], rows),
    ]) + "\n"
    return sections, md


def developer_stack_report(apps: list[AppBundle], formulae: list[BrewPackage], casks: list[BrewPackage], today: str) -> tuple[list[tuple[str, str]], str]:
    app_categories: list[tuple[str, set[str], str, str]] = [
        ("Apple development", {"xcode", "tuist"}, "Keep", "Core macOS/iOS development stack."),
        ("AI IDE / editor", {"cursor", "zed", "visual studio code", "sublime text"}, "Keep", "Editor or AI coding surface."),
        ("Containers", {"docker", "orbstack", "podman"}, "Keep", "Container runtime; review duplicates if multiple are installed."),
        ("Git GUI", {"github desktop", "fork"}, "Consider", "Keep if useful alongside CLI git."),
        ("API / database", {"postman", "tableplus", "dbngin", "sequel ace"}, "Consider", "Keep if active for API/database work."),
        ("Terminal / SSH", {"iterm", "warp", "termius"}, "Keep", "Developer shell or remote access tool."),
    ]
    package_categories: list[tuple[str, set[str], str, str]] = [
        ("Package manager", {"node", "npm", "pnpm", "yarn", "bun", "uv", "pipx", "mas", "gh", "git"}, "Keep", "Core package/dev tooling."),
        ("Language runtime", {"python", "ruby", "go", "rust", "swift", "java", "openjdk", "php"}, "Keep", "Runtime or compiler dependency."),
        ("Media/build CLI", {"ffmpeg", "imagemagick", "gifski", "yt-dlp"}, "Review", "Useful but can overlap with GUI tools."),
        ("Database / service", {"postgres", "mysql", "redis", "sqlite", "mongodb"}, "Review", "Keep if local service development is active."),
        ("Cloud / deployment", {"vercel", "cloudflare", "wrangler", "aws", "gcloud", "stripe"}, "Keep", "Deployment or platform CLI."),
    ]

    app_rows: list[list[str]] = []
    for app in apps:
        for category, needles, status, note in app_categories:
            if app_matches(app, needles):
                app_rows.append([
                    link(app.name, file_url(app.path)),
                    html.escape(category),
                    status_badge(status),
                    html.escape(app.version),
                    html.escape(human_size(app.size_bytes)),
                    html.escape(note),
                ])
                break

    package_rows: list[list[str]] = []
    for package in formulae + casks:
        for category, needles, status, note in package_categories:
            if package_matches(package, needles):
                package_rows.append([
                    link(package.name, package.homepage),
                    html.escape("Cask" if package.kind == "cask" else "CLI / formula"),
                    html.escape(category),
                    status_badge(status),
                    html.escape(package.versions),
                    html.escape(note),
                ])
                break

    summary = f"""
    <div class="summary">
      <div class="metric"><strong>{len(app_rows)}</strong><span>developer apps matched</span></div>
      <div class="metric"><strong>{len(package_rows)}</strong><span>developer packages matched</span></div>
      <div class="metric"><strong>{sum(1 for row in package_rows if 'Review' in row[3])}</strong><span>CLI review items</span></div>
    </div>
    """
    sections = [
        ("Overview", summary),
        ("Developer Apps", table(["App", "Category", "Status", "Version", "Size", "Note"], app_rows or [["Review", "No developer apps matched.", "", "", "", ""]])),
        ("Developer CLI and Packages", table(["Package", "Type", "Category", "Status", "Version", "Note"], package_rows or [["Review", "No developer packages matched.", "", "", "", ""]])),
    ]
    md = "\n\n".join([
        f"# Developer Stack Report ({today})",
        markdown_table(["App", "Category", "Status", "Version", "Size", "Note"], app_rows),
        markdown_table(["Package", "Type", "Category", "Status", "Version", "Note"], package_rows),
    ]) + "\n"
    return sections, md


def stale_apps_report(apps: list[AppBundle], today: str, stale_days: int = 180) -> tuple[list[tuple[str, str]], str]:
    cutoff = datetime.now() - timedelta(days=stale_days)
    stale: list[tuple[AppBundle, int]] = []
    for app in apps:
        try:
            modified = datetime.strptime(app.modified, "%Y-%m-%d")
        except ValueError:
            continue
        if modified < cutoff:
            stale.append((app, (datetime.now() - modified).days))

    stale.sort(key=lambda pair: pair[1], reverse=True)
    rows = [
        [
            link(app.name, file_url(app.path)),
            status_badge("Review"),
            html.escape(f"{age} days"),
            html.escape(app.modified),
            html.escape(human_size(app.size_bytes)),
            html.escape("Review whether this app still has a current role before removing it."),
        ]
        for app, age in stale
    ]
    summary = f"""
    <div class="summary">
      <div class="metric"><strong>{len(stale)}</strong><span>apps older than {stale_days} days</span></div>
      <div class="metric"><strong>{human_size(sum(app.size_bytes for app, _ in stale))}</strong><span>combined stale app size</span></div>
      <div class="metric"><strong>{stale_days}</strong><span>day review threshold</span></div>
    </div>
    <p>Modified dates are a cautious proxy, not proof that an app is unused. Treat every row as a review prompt, not an uninstall recommendation.</p>
    """
    sections = [
        ("Overview", summary),
        ("Stale App Review", table(["App", "Status", "Age", "Modified", "Size", "Review Note"], rows or [["Review", "No apps crossed the stale threshold.", "", "", "", ""]])),
    ]
    md = "\n\n".join([
        f"# Stale Apps Report ({today})",
        f"Apps with bundle modified dates older than {stale_days} days. Review only.",
        markdown_table(["App", "Status", "Age", "Modified", "Size", "Review Note"], rows),
    ]) + "\n"
    return sections, md


def ai_tools_report(apps: list[AppBundle], formulae: list[BrewPackage], casks: list[BrewPackage], today: str) -> tuple[list[tuple[str, str]], str]:
    ai_app_needles = {
        "chatgpt", "claude", "gemini", "perplexity", "codex", "cursor", "ollama", "ollamac",
        "anythingllm", "lm studio", "mlx", "goose", "opencode", "prompt", "manus", "recursechat",
        "pocketpal", "mollama", "locally ai", "mindmac", "noi", "observer", "codexshot",
    }
    local_runtime_needles = {"ollama", "mlx", "llama", "gguf", "llm", "torch", "transformers", "huggingface"}
    app_rows: list[list[str]] = []
    for app in apps:
        if not app_matches(app, ai_app_needles):
            continue
        role = "Local model / runtime" if app_matches(app, local_runtime_needles) else "AI app / workflow"
        status = "Review" if app_matches(app, {"locally ai", "mollama", "pocketpal", "recursechat", "mindmac", "noi"}) else "Keep"
        note = "Review overlap with the primary Codex, ChatGPT, Claude, Cursor, and Ollama workflow." if status == "Review" else "Keep if this remains part of the active AI workflow."
        app_rows.append([
            link(app.name, file_url(app.path)),
            html.escape(role),
            status_badge(status),
            html.escape(app.version),
            html.escape(human_size(app.size_bytes)),
            html.escape(note),
        ])

    package_rows: list[list[str]] = []
    for package in formulae + casks:
        if package_matches(package, ai_app_needles | local_runtime_needles):
            package_rows.append([
                link(package.name, package.homepage),
                html.escape("Cask" if package.kind == "cask" else "CLI / formula"),
                status_badge("Keep" if package.name in {"ollama", "llm", "mlx"} else "Review"),
                html.escape(package.versions),
                html.escape(package.description),
            ])

    summary = f"""
    <div class="summary">
      <div class="metric"><strong>{len(app_rows)}</strong><span>AI apps matched</span></div>
      <div class="metric"><strong>{len(package_rows)}</strong><span>AI/local model packages matched</span></div>
      <div class="metric"><strong>{sum(1 for row in app_rows if 'Review' in row[2])}</strong><span>app overlap review items</span></div>
    </div>
    <p>This report separates primary AI tools from overlapping clients and local-model helpers. Use it to decide roles, not to delete tools automatically.</p>
    """
    sections = [
        ("Overview", summary),
        ("AI Apps", table(["App", "Role", "Status", "Version", "Size", "Note"], app_rows or [["Review", "No AI apps matched.", "", "", "", ""]])),
        ("AI CLI / Local Model Packages", table(["Package", "Type", "Status", "Version", "Description"], package_rows or [["Review", "No AI packages matched.", "", "", ""]])),
    ]
    md = "\n\n".join([
        f"# AI Tools Report ({today})",
        markdown_table(["App", "Role", "Status", "Version", "Size", "Note"], app_rows),
        markdown_table(["Package", "Type", "Status", "Version", "Description"], package_rows),
    ]) + "\n"
    return sections, md


def build_folder_weights() -> list[FolderWeight]:
    candidates = [
        ("Downloads", Path.home() / "Downloads", "User downloads and exported assets."),
        ("Desktop", Path.home() / "Desktop", "Desktop screenshots and temporary files."),
        ("Reports", REPORTS_DIR, "HTTMELY generated reports and dated copies."),
        ("HTTMELY project", PROJECT_ROOT, "Current report viewer project."),
        ("Xcode DerivedData", Path.home() / "Library" / "Developer" / "Xcode" / "DerivedData", "Xcode build cache; review with care."),
        ("User Caches", Path.home() / "Library" / "Caches", "User cache folder; inspect before cleaning."),
    ]
    for path in env_paths("HTTMELY_EXTRA_WEIGHT_PATHS"):
        candidates.append((path.name or str(path), path, "Extra folder supplied by HTTMELY_EXTRA_WEIGHT_PATHS."))

    build_roots = env_paths("HTTMELY_BUILD_SCAN_ROOTS") or [Path.home() / "Projects"]
    build_names = {"node_modules", ".build", "dist", "build", "DerivedData"}
    for root in build_roots:
        if not root.exists():
            continue
        for dirpath, dirnames, _ in os.walk(root):
            current = Path(dirpath)
            try:
                depth = len(current.relative_to(root).parts)
            except ValueError:
                continue
            if depth > 2:
                dirnames[:] = []
                continue
            matched = [name for name in dirnames if name in build_names]
            for name in matched:
                child = current / name
                candidates.append((f"Build folder: {name}", child, "Project build/dependency output; review if the project is inactive."))
                if len(candidates) > 45:
                    break
            dirnames[:] = [name for name in dirnames if name not in build_names and not name.startswith(".git")]
            if len(candidates) > 45:
                break

    weights: list[FolderWeight] = []
    seen: set[Path] = set()
    for name, path, note in candidates:
        if path in seen or not path.exists():
            continue
        seen.add(path)
        try:
            size_bytes = folder_size(path)
            if size_bytes > 0:
                weights.append(FolderWeight(name, path, size_bytes, note))
        except Exception:
            continue
    return sorted(weights, key=lambda item: item.size_bytes, reverse=True)


def disk_weight_report(apps: list[AppBundle], today: str) -> tuple[list[tuple[str, str]], str]:
    largest_apps = sorted(apps, key=lambda app: app.size_bytes, reverse=True)[:25]
    app_rows = [
        [
            link(app.name, file_url(app.path)),
            status_badge("Big File" if app.size_bytes >= 1_000_000_000 else "Review"),
            html.escape(human_size(app.size_bytes)),
            html.escape(app.location),
            html.escape("Large app bundle; keep if it has a current role."),
        ]
        for app in largest_apps
    ]
    weights = build_folder_weights()
    folder_rows = [
        [
            link(weight.name, file_url(weight.path)),
            status_badge("Big File" if weight.size_bytes >= 1_000_000_000 else "Review"),
            html.escape(human_size(weight.size_bytes)),
            html.escape(str(weight.path)),
            html.escape(weight.note),
        ]
        for weight in weights
    ]
    summary = f"""
    <div class="summary">
      <div class="metric"><strong>{human_size(sum(app.size_bytes for app in largest_apps))}</strong><span>top app bundle weight</span></div>
      <div class="metric"><strong>{len(weights)}</strong><span>high-signal folders checked</span></div>
      <div class="metric"><strong>{human_size(sum(weight.size_bytes for weight in weights))}</strong><span>checked folder weight</span></div>
    </div>
    <p>This report reads folder sizes only. It skips unreadable paths and does not clean caches, build folders, or downloads.</p>
    """
    sections = [
        ("Overview", summary),
        ("Largest Apps", table(["App", "Status", "Size", "Location", "Review Note"], app_rows)),
        ("High-Signal Folders", table(["Folder", "Status", "Size", "Path", "Review Note"], folder_rows or [["Review", "No folder weights found.", "", "", ""]])),
    ]
    md = "\n\n".join([
        f"# Disk Weight Report ({today})",
        markdown_table(["App", "Status", "Size", "Location", "Review Note"], app_rows),
        markdown_table(["Folder", "Status", "Size", "Path", "Review Note"], folder_rows),
    ]) + "\n"
    return sections, md


def project_roots() -> list[Path]:
    roots = env_paths("HTTMELY_PROJECT_ROOTS") or [Path.home() / "Projects"]
    seen: set[Path] = set()
    output: list[Path] = []
    for root in roots:
        if root.exists() and root not in seen:
            seen.add(root)
            output.append(root)
    return output


def detect_project_type(path: Path) -> tuple[str, str]:
    if (path / "Package.swift").exists():
        return "SwiftPM", "swift run"
    if (path / "Project.swift").exists():
        return "Tuist", "tuist generate"
    if (path / "src-tauri").exists() or (path / "tauri.conf.json").exists():
        return "Tauri", "npm run tauri dev"
    if (path / "package.json").exists():
        package_json = path / "package.json"
        try:
            parsed = json.loads(package_json.read_text(encoding="utf-8"))
            scripts = parsed.get("scripts", {})
            if "dev" in scripts:
                return "Node/Web", "npm run dev"
            if "start" in scripts:
                return "Node/Web", "npm start"
        except Exception:
            pass
        return "Node/Web", "npm install"
    if (path / "pyproject.toml").exists():
        return "Python", "python -m pytest"
    if (path / "Cargo.toml").exists():
        return "Rust", "cargo run"
    if (path / "Makefile").exists():
        return "Makefile", "make"
    return "Folder", "Review"


def discover_projects() -> list[ProjectItem]:
    markers = {"Package.swift", "Project.swift", "package.json", "pyproject.toml", "Cargo.toml", "Makefile", ".git"}
    skip_dirs = {"node_modules", ".build", ".git", "dist", "build", "DerivedData", ".next", ".venv", "__pycache__"}
    candidates: dict[Path, None] = {}
    for root in project_roots():
        if any((root / marker).exists() for marker in markers):
            candidates[root] = None
        for dirpath, dirnames, _ in os.walk(root):
            current = Path(dirpath)
            try:
                rel_parts = current.relative_to(root).parts
            except ValueError:
                continue
            if len(rel_parts) > 4:
                dirnames[:] = []
                continue
            dirnames[:] = [name for name in dirnames if name not in skip_dirs]
            if current != root and any((current / marker).exists() for marker in markers):
                candidates[current] = None
            if len(candidates) >= 180:
                break

    projects: list[ProjectItem] = []
    for path in sorted(candidates, key=lambda item: str(item).lower()):
        project_type, run_command = detect_project_type(path)
        git_status = "Not a git repo"
        if (path / ".git").exists() or run_in(["git", "rev-parse", "--show-toplevel"], path):
            raw_status = run_in(["git", "status", "--short"], path)
            git_status = "Clean" if not raw_status else f"{len(raw_status.splitlines())} changed files"
        docs = ", ".join(name for name in ["README.md", "AGENTS.md"] if (path / name).exists()) or "Review docs"
        note = "Ready to refine in the next Projects output pass." if project_type != "Folder" else "Folder detected; review whether it is an active project."
        projects.append(ProjectItem(path.name, path, modified_date(path), git_status, project_type, run_command, docs, note))
    return projects


def projects_report(today: str) -> tuple[list[tuple[str, str]], str]:
    projects = discover_projects()
    rows = [
        [
            link(project.name, file_url(project.path)),
            html.escape(project.project_type),
            html.escape(project.modified),
            html.escape(project.git_status),
            html.escape(project.run_command),
            html.escape(project.docs),
            html.escape(project.note),
        ]
        for project in projects
    ]
    summary = f"""
    <div class="summary">
      <div class="metric"><strong>{len(projects)}</strong><span>project folders found</span></div>
      <div class="metric"><strong>{sum(1 for project in projects if project.git_status == 'Clean')}</strong><span>clean git worktrees</span></div>
      <div class="metric"><strong>{sum(1 for project in projects if 'changed' in project.git_status)}</strong><span>worktrees with changes</span></div>
      <div class="metric"><strong>{sum(1 for project in projects if project.docs != 'Review docs')}</strong><span>with README or AGENTS</span></div>
    </div>
    <p>This is the first Projects inventory pass. The next step is to refine grouping, priority, and output design after reviewing the real results.</p>
    """
    sections = [
        ("Overview", summary),
        ("Projects", table(["Project", "Type", "Modified", "Git", "Likely Run Command", "Docs", "Review Note"], rows or [["Review", "No projects found.", "", "", "", "", ""]])),
    ]
    md = "\n\n".join([
        f"# Projects Report ({today})",
        "First-pass project inventory for later refinement.",
        markdown_table(["Project", "Type", "Modified", "Git", "Likely Run Command", "Docs", "Review Note"], rows),
    ]) + "\n"
    return sections, md


def main() -> None:
    parser = argparse.ArgumentParser(description="Regenerate HTTMELY local inventory reports.")
    parser.add_argument(
        "--skip-projects",
        action="store_true",
        help="Leave Projects report files untouched; useful when Projects is maintained separately.",
    )
    args = parser.parse_args()

    today = datetime.now().strftime("%Y-%m-%d")
    apps = scan_apps()
    apps_by_location = {
        "/Applications": [app for app in apps if app.location == "/Applications"],
        "~/Applications": [app for app in apps if app.location == "~/Applications"],
    }
    large_apps = sorted(apps, key=lambda app: app.size_bytes, reverse=True)[:20]
    owned_label = os.environ.get("HTTMELY_OWNED_APP_LABEL", "Owned")
    owned_keywords = [
        item.strip().lower()
        for item in os.environ.get("HTTMELY_OWNED_APP_KEYWORDS", "").split(",")
        if item.strip()
    ]
    owned_apps = [
        app for app in apps
        if any(keyword in app.name.lower() or keyword in app.bundle_id.lower() for keyword in owned_keywords)
    ]

    app_summary = f"""
    <div class="summary">
      <div class="metric"><strong>{len(apps_by_location['/Applications'])}</strong><span>apps in /Applications</span></div>
      <div class="metric"><strong>{len(apps_by_location['~/Applications'])}</strong><span>apps in ~/Applications</span></div>
      <div class="metric"><strong>{len(owned_apps)}</strong><span>{html.escape(owned_label)} app bundles found</span></div>
      <div class="metric"><strong>{human_size(sum(app.size_bytes for app in apps))}</strong><span>scanned app bundle size</span></div>
    </div>
    """
    app_rows = [
        [
            link(app.name, file_url(app.path)),
            html.escape(app.location),
            html.escape(app.version),
            html.escape(human_size(app.size_bytes)),
            html.escape(app.modified),
            html.escape(app.bundle_id),
        ]
        for app in apps
    ]
    large_rows = [
        [link(app.name, file_url(app.path)), html.escape(app.location), html.escape(human_size(app.size_bytes)), html.escape(app.version)]
        for app in large_apps
    ]
    owned_rows = [
        [link(app.name, file_url(app.path)), html.escape(app.location), html.escape(app.version), html.escape(human_size(app.size_bytes))]
        for app in owned_apps
    ] or [["Review", f"No {html.escape(owned_label)} app bundles found in the scanned Applications folders.", "", ""]]
    app_sections = [
        ("Overview", app_summary),
        ("Largest Apps", table(["App", "Location", "Size", "Version"], large_rows)),
        (f"{html.escape(owned_label)} Apps", table(["App", "Location", "Version", "Size"], owned_rows)),
        ("All Application Bundles", table(["App", "Location", "Version", "Size", "Modified", "Bundle ID"], app_rows)),
    ]
    app_md = "\n".join(
        [
            f"# Applications Report ({today})",
            "",
            f"- Apps in /Applications: {len(apps_by_location['/Applications'])}",
            f"- Apps in ~/Applications: {len(apps_by_location['~/Applications'])}",
            f"- {owned_label} app bundles found: {len(owned_apps)}",
            f"- Scanned app bundle size: {human_size(sum(app.size_bytes for app in apps))}",
            "",
            "## Largest Apps",
            "",
            *[f"- {app.name}: {human_size(app.size_bytes)} ({app.location})" for app in large_apps],
            "",
            "## All Application Bundles",
            "",
            *[f"- {app.name} | {app.location} | {app.version} | {human_size(app.size_bytes)} | {app.bundle_id}" for app in apps],
            "",
        ]
    )
    write_pair("applications", "Applications", f"Application inventory generated {today}.", app_sections, app_md)
    write_pair(f"local_applications_report_applications_only_{today}", "Applications", f"Application inventory generated {today}.", app_sections, app_md, archive=True)

    details = brew_info()
    casks = parse_brew_list("cask", details)
    formulae = parse_brew_list("formula", details)
    brew_summary = f"""
    <div class="summary">
      <div class="metric"><strong>{len(casks)}</strong><span>Homebrew casks</span></div>
      <div class="metric"><strong>{len(formulae)}</strong><span>formula / CLI packages</span></div>
      <div class="metric"><strong>{len(casks) + len(formulae)}</strong><span>total Homebrew items</span></div>
    </div>
    """

    def brew_rows(packages: list[BrewPackage]) -> list[list[str]]:
        return [
            [
                link(package.name, package.homepage),
                html.escape(package.versions),
                html.escape(package.description),
            ]
            for package in packages
        ]

    brew_sections = [
        ("Overview", brew_summary),
        ("Homebrew Casks", table(["Package", "Version", "Description"], brew_rows(casks))),
        ("Formulae and CLI Tools", table(["Package", "Version", "Description"], brew_rows(formulae))),
    ]
    brew_md = "\n".join(
        [
            f"# Homebrew Report ({today})",
            "",
            f"- Casks: {len(casks)}",
            f"- Formulae / CLI tools: {len(formulae)}",
            "",
            "## Casks",
            "",
            *[f"- {package.name} | {package.versions} | {package.description}" for package in casks],
            "",
            "## Formulae and CLI Tools",
            "",
            *[f"- {package.name} | {package.versions} | {package.description}" for package in formulae],
            "",
        ]
    )
    write_pair("homebrew", "Homebrew", f"Homebrew cask and CLI inventory generated {today}.", brew_sections, brew_md)
    write_pair(f"local_homebrew_report_{today}", "Homebrew", f"Homebrew cask and CLI inventory generated {today}.", brew_sections, brew_md, archive=True)

    cleanup_sections, cleanup_md = cleanup_report(apps, casks, formulae, today)
    write_pair("cleanup", "Cleanup", f"Keep, remove, duplicate, and review guidance generated {today}.", cleanup_sections, cleanup_md)
    write_pair(f"local_cleanup_report_{today}", "Cleanup", f"Keep, remove, duplicate, and review guidance generated {today}.", cleanup_sections, cleanup_md, archive=True)

    background_sections, background_md = background_report(apps, casks, today)
    write_pair("background", "Background", f"Background and menu bar utility review generated {today}.", background_sections, background_md)
    write_pair(f"local_background_report_{today}", "Background", f"Background and menu bar utility review generated {today}.", background_sections, background_md, archive=True)

    startup_sections, startup_md = startup_report(today)
    write_pair("startup", "Startup", f"LaunchAgents and LaunchDaemons inventory generated {today}.", startup_sections, startup_md)
    write_pair(f"local_startup_report_{today}", "Startup", f"LaunchAgents and LaunchDaemons inventory generated {today}.", startup_sections, startup_md, archive=True)

    developer_sections, developer_md = developer_stack_report(apps, formulae, casks, today)
    write_pair("developer_stack", "Developer Stack", f"Developer tools and CLI stack inventory generated {today}.", developer_sections, developer_md)
    write_pair(f"local_developer_stack_report_{today}", "Developer Stack", f"Developer tools and CLI stack inventory generated {today}.", developer_sections, developer_md, archive=True)

    stale_sections, stale_md = stale_apps_report(apps, today)
    write_pair("stale_apps", "Stale Apps", f"180-day app review generated {today}.", stale_sections, stale_md)
    write_pair(f"local_stale_apps_report_{today}", "Stale Apps", f"180-day app review generated {today}.", stale_sections, stale_md, archive=True)

    ai_sections, ai_md = ai_tools_report(apps, formulae, casks, today)
    write_pair("ai_tools", "AI Tools", f"AI tools and local model workflow inventory generated {today}.", ai_sections, ai_md)
    write_pair(f"local_ai_tools_report_{today}", "AI Tools", f"AI tools and local model workflow inventory generated {today}.", ai_sections, ai_md, archive=True)

    disk_sections, disk_md = disk_weight_report(apps, today)
    write_pair("disk_weight", "Disk Weight", f"Disk weight review generated {today}.", disk_sections, disk_md)
    write_pair(f"local_disk_weight_report_{today}", "Disk Weight", f"Disk weight review generated {today}.", disk_sections, disk_md, archive=True)

    report_links = [
        ("Applications", "applications.html", "Weekly application bundle scan."),
        ("Homebrew", "homebrew.html", "Weekly Homebrew cask and formula scan."),
        ("Cleanup", "cleanup.html", "Keep, remove, duplicate, and review guidance."),
        ("Background", "background.html", "Menu bar, sync, VPN, clipboard, launcher, cleaner, automation, and always-on tools."),
        ("Startup", "startup.html", "LaunchAgents, LaunchDaemons, and startup-adjacent review."),
        ("Developer Stack", "developer_stack.html", "Developer apps, runtimes, package managers, and CLIs."),
        ("Stale Apps", "stale_apps.html", "Apps older than the 180-day review threshold."),
        ("AI Tools", "ai_tools.html", "AI assistants, local model tools, agents, and overlap guidance."),
        ("Disk Weight", "disk_weight.html", "Largest apps and high-signal local folders."),
    ]

    if not args.skip_projects:
        project_sections, project_md = projects_report(today)
        write_pair("projects", "Projects", f"Project inventory generated {today}.", project_sections, project_md)
        write_pair(f"local_projects_report_{today}", "Projects", f"Project inventory generated {today}.", project_sections, project_md, archive=True)
        report_links.append(("Projects", "projects.html", "First-pass project inventory for later refinement."))

    project_scan_count = "Skipped" if args.skip_projects else str(len(project_roots()))
    index_sections = [
        (
            "Reports",
            table(
                ["Report", "Stable File", "Notes"],
                [[link(title, file_name), html.escape(file_name), html.escape(note)] for title, file_name, note in report_links],
            ),
        ),
        (
            "Latest Counts",
            table(
                ["Area", "Count"],
                [
                    ["Applications", str(len(apps))],
                    ["Homebrew casks", str(len(casks))],
                    ["Homebrew formulae / CLI tools", str(len(formulae))],
                    ["Cleanup recommendations", str(len(recommendation_rows(apps)))],
                    ["Stable reports", str(len(report_links))],
                    ["New report families", "6" if args.skip_projects else "7"],
                    ["Startup launch items", str(len(scan_launch_items()))],
                    ["Project scan roots", project_scan_count],
                ],
            ),
        ),
    ]
    index_md = f"# Reports Index ({today})\n\n" + "\n".join(f"- [{title}]({file_name})" for title, file_name, _ in report_links) + "\n"
    write_pair("index", "Reports", f"Weekly local inventory reports generated {today}.", index_sections, index_md)
    write_pair(f"local_reports_index_{today}", "Reports", f"Weekly local inventory reports generated {today}.", index_sections, index_md, archive=True)

    print(f"Generated reports in {REPORTS_DIR}")


if __name__ == "__main__":
    main()
