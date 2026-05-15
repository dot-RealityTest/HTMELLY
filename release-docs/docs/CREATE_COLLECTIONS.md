# Create Your Own Page Collections

HTTMELY is more than a viewer when paired with scripts or AI agents.

Anything you can turn into local HTML or Markdown can become a polished HTTMELY folder.

## The Pattern

1. Choose a source.
2. Generate local HTML or Markdown pages.
3. Save them in a normal folder.
4. Add the folder to HTTMELY with `Places > Add Folder...`.
5. Browse the result in the native reader.

Sources can include:

- Apps
- Folders
- Project files
- Logs
- Notes
- CSV or JSON exports
- Screenshots
- Browser exports
- Research material
- Local AI outputs
- Documentation

## Why This Matters

HTTMELY stays simple: it reads local pages.

The generation layer can be anything: Codex, a shell script, a Python script, an app export, or a manual folder of pages.

That separation makes HTTMELY flexible. It can become a local presentation layer for many workflows without becoming a complex app.

## Recommended Structure

```text
My Collection/
  index.html
  current.html
  notes.md
  archive/
    2026-05-16.html
```

Stable files are for everyday browsing.

Archive files are for history.

## Ready-To-Use Templates

Starter files are included in `release-docs/templates/`:

- `collection-index.html`
- `report-template.html`
- `brief-template.html`
- `markdown-template.md`

Copy one into your folder, rename it, replace the sample content, then add the folder to HTTMELY.

## Page Design Rules

- Make the page content-first.
- Do not include app chrome, sidebars, nav bars, tabs, search bars, or floating controls.
- Use one clear `h1`.
- Use `h2` and `h3` headings with stable IDs.
- Use inline CSS only.
- Avoid external scripts, fonts, CDNs, analytics, or cloud assets.
- Keep the page readable as a standalone local file.
- Do not force a report structure unless the page is actually a report.

## Prompt For Codex

```text
Create an HTTMELY-ready local page collection from this source:

[describe source]

Goal:
[describe what I want to understand or browse]

Output:
- Create a local folder containing standalone HTML or Markdown pages.
- Include an index page if there is more than one page.
- Use semantic h1/h2/h3 headings with stable IDs.
- Use inline CSS only.
- Do not add app chrome, nav bars, sidebars, tabs, search bars, floating controls, external scripts, CDNs, analytics, or remote assets.
- Keep filenames clear and stable.
- Tell me the folder path to add in HTTMELY with Places > Add Folder...

Use the HTTMELY page design skill if it is available in your agent environment.
```
