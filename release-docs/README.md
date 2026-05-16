# HTTMELY Release Docs

This folder is the clean release packet for HTTMELY.

It contains user-facing docs, app positioning, screenshot planning, and the HTTMELY collection-design skill. It does not include private maintenance notes, internal workflow context, generated archives, or local automation details.

## Contents

- `docs/GETTING_STARTED.md` - user guide.
- `docs/CREATE_COLLECTIONS.md` - how users can create local HTML/Markdown page collections.
- `docs/LOCAL_FIRST_PRIVACY.md` - local-first privacy notes.
- `docs/APP_DESCRIPTION.md` - short/medium app copy and feature bullets.
- `skills/htmelly-page-design/SKILL.md` - reusable agent skill for creating local page collections that fit HTTMELY.
- `skills/htmelly-report-automation/SKILL.md` - reusable agent skill for generated report collections, archive rules, and recurring automation prompts.
- `templates/` - ready-to-use HTML and Markdown starter pages.
- `screenshots/` - place final release screenshots here.
- `SCREENSHOTS.md` - screenshot checklist and naming guide.
- `NOTARIZATION.md` - signing and notarization notes.

## Build Artifact

The release app and DMG are created from the project with:

```bash
cd viewer
./script/package_release.sh
```

After notarization, use the DMG from `viewer/release/` as the shareable installer.

## Release Positioning

HTTMELY is a local-first macOS reader for folders of HTML and Markdown pages.

Its standout workflow is simple: any user, script, or AI agent can generate local page collections from almost any source, then browse them in HTTMELY as a calm native library.

## What Not To Include Here

- Private paths.
- Internal maintenance notes.
- Agent session notes.
- Generated report archives.
- Build output.
- `.DS_Store` files.
