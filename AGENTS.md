# AGENTS.md

This project is the dedicated home for HTTMELY, a native local HTML/Markdown folder reader, plus the internal KIKA generated reports workflow.

## Project Purpose

Maintain a local-first macOS app that:

- Opens local HTML/Markdown folders from anywhere on the Mac.
- Presents them in a quiet native AppKit/WKWebView reader.
- Keeps saved folders and UI state in local user defaults only.
- Includes the generated KIKA reports as one bundled/internal workflow.
- Keeps public user docs separate from private workflow and maintenance notes.

## Layout

- `viewer/` - SwiftPM AppKit/WKWebView macOS app.
- `viewer/Resources/Welcome/` - bundled release-safe onboarding pages shown on first launch.
- `viewer/script/build_and_run.sh` - canonical build and launch path.
- `viewer/script/regenerate_reports.py` - canonical KIKA reports refresh path.
- `reports/` - generated stable reports.
- `reports/archive/` - dated generated report snapshots and old preview images.
- `chat/` - local notes and session summaries.
- `docs/user/` - release/user-facing docs. Keep these generic and free of private paths.
- `docs/internal/` - KIKA/Codex workflow and maintenance context.
- `docs/MAINTENANCE.md` and `docs/CREATING_REPORTS.md` - older continuity notes; keep unless explicitly asked to remove.
- `release-docs/` - release-safe docs, screenshots, and the bundled HTTMELY page-design skill.

## Commands

From the project root:

```bash
make run
make refresh
make verify
```

From `viewer/` directly:

```bash
./script/build_and_run.sh --verify
./script/regenerate_reports.py
```

## Built-In Reports Place Contract

The built-in Reports place reads these stable files:

- `reports/applications.html`
- `reports/homebrew.html`
- `reports/cleanup.html`
- `reports/background.html`
- `reports/startup.html`
- `reports/developer_stack.html`
- `reports/stale_apps.html`
- `reports/ai_tools.html`
- `reports/disk_weight.html`
- `reports/projects.html`
- `reports/index.html`

The refresh script also writes dated archive copies in `reports/archive/`. Do not point the built-in Reports place at dated filenames unless the user explicitly asks for an archive view.

## Editing Rules

- Keep the viewer native, quiet, and minimal.
- Keep bundled welcome/onboarding pages release-safe and generic.
- Keep HTTMELY local-first; do not add upload, cloud sync, analytics, accounts, or external services.
- Do not describe the app as only a reports app. It is a general local HTML/Markdown folder reader.
- Keep user-facing docs in `docs/user/` generic enough for release.
- Keep `release-docs/` free of private paths, internal automation, generated archives, and local-only context.
- Keep KIKA-specific workflow, private paths, and maintenance context in `docs/internal/`, `docs/MAINTENANCE.md`, `docs/CREATING_REPORTS.md`, or `chat/`.
- Prefer changing `viewer/script/regenerate_reports.py` for report content/structure changes.
- Prefer changing `viewer/Sources/HTTMELY/main.swift` for native viewer behavior.
- Folder-backed modes should scan local HTML/Markdown files and keep selected folders in local user defaults only.
- Do not manually edit generated stable reports as the long-term fix; regenerate them from the script.
- Do not delete or flatten context docs unless the user explicitly asks; they preserve the project history.
- If SwiftPM build errors mention stale module caches after a move, remove `viewer/.build` and rebuild.

## Verification

After viewer code changes:

```bash
cd viewer
./script/build_and_run.sh --verify
```

After report-generation changes:

```bash
cd viewer
./script/regenerate_reports.py
```

Then confirm the stable report files exist in `reports/`.
