# HTTMELY

Local-first macOS reader for HTML and Markdown folders.

HTTMELY lets you choose folders from anywhere on your Mac and browse local pages in a quiet native AppKit/WKWebView shell. It is useful for generated reports, exported notes, project briefs, research packets, documentation folders, and any workflow that ends as local `.html` or `.md` files.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111827)](#build-and-run)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-6.0-f05138)](#build-and-run)
[![Local First](https://img.shields.io/badge/local--first-no%20cloud-2f615c)](docs/user/LOCAL_FIRST_PRIVACY.md)

## Download

The macOS DMG is published on the [GitHub Releases page](https://github.com/dot-RealityTest/HTMELLY/releases).

For a local build:

```bash
make verify
```

## Features

- Opens folders containing `.html`, `.htm`, `.md`, and `.markdown` files.
- Opens a bundled Welcome guide on first launch so new users have a starting point.
- Saves multiple local folder shortcuts as Places.
- Shows a native sidebar with place switching and page selection.
- Adds optional in-page contents navigation from headings.
- Opens or reveals source files in Finder.
- Renames, reorders, and removes folder shortcuts without changing files on disk.
- Exports or archives the current local folder.
- Remembers window size, selected place, sidebar state, contents state, and title-bar state in local user defaults.

## Privacy

HTTMELY is local-first. It does not add cloud sync, analytics, uploads, accounts, remote databases, or external services. Folder shortcuts and UI state stay in local user defaults.

Generated reports are intentionally ignored by this public repo because they can contain machine-local paths and app inventories. See [reports/README.md](reports/README.md).

## Build And Run

```bash
make run
make verify
```

From the viewer folder directly:

```bash
cd viewer
./script/build_and_run.sh --verify
```

## Package

```bash
cd viewer
./script/package_release.sh
```

For Developer ID signing, pass `SIGN_IDENTITY` in the environment. For notarization, store a notarytool keychain profile and run with `NOTARIZE=1`.

## Docs

- [User Guide](docs/user/GETTING_STARTED.md)
- [Create Page Collections](docs/user/CREATE_COLLECTIONS.md)
- [Local-First Privacy](docs/user/LOCAL_FIRST_PRIVACY.md)
- [Release Docs](release-docs/README.md)
- [Answer-engine summary](llms.txt)
- [Public overview](docs/overview.md)
- [Landing page](https://dot-realitytest.github.io/HTMELLY/)

## HTTMELY-Ready Pages

Good HTTMELY folders are content-first: semantic headings, readable local HTML or Markdown, no hosted dependencies required, and an `index.html` or `index.md` when you want a clear starting page.

```text
My Pages/
  index.html
  overview.md
  notes/
    research.html
```

## Local Report Workflow

This repo includes a report-generation script as one example workflow:

```bash
make refresh
```

The generated files stay local by default. You can customize scan roots with:

- `HTTMELY_REPORTS_DIR`
- `HTTMELY_PROJECT_ROOTS`
- `HTTMELY_BUILD_SCAN_ROOTS`
- `HTTMELY_EXTRA_WEIGHT_PATHS`
- `HTTMELY_OWNED_APP_KEYWORDS`

## License

MIT
