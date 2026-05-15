# HTTMELY

Small native macOS reader for local HTML and Markdown folders.

HTTMELY can open saved folders from anywhere on the Mac and present their pages in a calm native shell. The built-in Reports place is one local workflow, not the limit of what the viewer can open.

## Default Reports Place

- `../reports/applications.html`
- `../reports/homebrew.html`
- `../reports/cleanup.html`
- `../reports/background.html`
- `../reports/startup.html`
- `../reports/developer_stack.html`
- `../reports/stale_apps.html`
- `../reports/ai_tools.html`
- `../reports/disk_weight.html`
- `../reports/projects.html`
- `../reports/index.html`

## Run

```bash
./script/build_and_run.sh
```

The script builds the SwiftPM app, stages `dist/HTTMELY.app`, and launches it as a real macOS app bundle.

## Export

- `File > Open Selected Page`: open the selected page externally.
- `File > Reveal Selected Page`: reveal the selected page in Finder.
- `File > Reveal Current Folder`: reveal the active source folder.
- `File > Export Current Folder...`: copy the complete current folder to a chosen destination.
- `File > Write Archive Copy`: write a timestamped local archive copy beside the source folder.

## Refresh Reports

```bash
./script/regenerate_reports.py
```

The refresh script rescans `/Applications`, `~/Applications`, and Homebrew, then updates the stable HTML/Markdown reports in `../reports`.

This script belongs to the local reports layer. The viewer itself can also open arbitrary local HTML/Markdown folders added through `Places > Add Folder...`.

## Keyboard

- Use the sidebar place picker to switch between Reports and saved folders.
- Use the sidebar page list to open a page.
- Use the bottom sidebar icons for previous page, next page, contents, and reload.
- Right-click a page to open it externally or reveal it in Finder.
- `Command-Option-S`: toggle the page sidebar.
- `Command-Option-C`: toggle the in-page contents panel.
- `Command-[`: move to the previous page.
- `Command-]`: move to the next page.
- `Command-R`: reload the current page.
- `Command-Option-1`: switch to Reports.
- `Command-Option-2` through `Command-Option-9`: switch to saved folders.
- `Command-Option-Left` / `Command-Option-Right`: move through saved folders.
- `Command-Option-,`: open Manage Places.
- `Command-Option-N`: rename the current folder mode.
- `Command-Option-Up` / `Command-Option-Down`: reorder the current folder mode.
- `Command-Option-Shift-Up` / `Command-Option-Shift-Down`: move it to the top or bottom.
- `Command-Option-E`: export the full current folder.
- `Command-Option-A`: write a dated archive copy.
- `Command-Option-Delete`: remove the current folder mode.

## Menus

- `File`: local file actions and archive/export commands.
- `View`: page navigation, reload, sidebar, contents, and optional title bar.
- `Places`: switch places, add folders, manage folders, rename/reorder/remove the current place.
- `Help`: HTTMELY Help, Keyboard Shortcuts, and About.

## HTTMELY-Ready Pages

The page should be content-only: no app chrome, no duplicate sidebar/navigation, semantic headings with stable IDs, inline CSS, no external dependencies, and no forced report structure unless the page is specifically a report.

For custom generated page collections, see `../docs/user/CREATE_COLLECTIONS.md`. The core pattern is: generate local HTML/Markdown from any source, save it in a folder, then add that folder to HTTMELY with `Places > Add Folder...`.
