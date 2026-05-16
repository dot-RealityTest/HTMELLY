# HTTMELY Collection Templates

Copy a single page template or a complete folder template into your local files, edit the content, then add that folder to HTTMELY with `Places > Add Folder...`.

## Page Templates

- `collection-index.html` - a clean landing page for a folder of pages.
- `report-template.html` - a classic structured report page with summary, findings, table, and actions.
- `brief-template.html` - a calmer brief/notes page for writing, planning, reviews, or research.
- `markdown-template.md` - a simple Markdown starter for fast local notes.

## Folder Templates

- `design-md-collection/` - a starter Design.md research packet with notes, screenshots folder, and token files.
- `daily-report-collection/` - a stable current-report folder with daily, weekly, assets, and archive structure.

## Good Folder Shapes

```text
My HTTMELY Collection/
  index.html
  current.html
  notes.md
  archive/
    2026-05-16.html
```

```text
Design Study/
  index.html
  DESIGN.md
  screenshots/
  design-system/
    tokens.css
    tokens.json
  notes/
```

```text
Daily Reports/
  index.html
  today.html
  weekly.html
  assets/
  archive/
    2026-05-16.html
```

## How To Use

1. For a simple collection, copy `collection-index.html` into your folder as `index.html`.
2. For a fuller starter, copy a folder template such as `design-md-collection/` or `daily-report-collection/`.
3. Rename files with clear, stable filenames.
4. Replace the placeholder text.
5. Add the folder in HTTMELY.

## Template Rules

- Keep pages content-only.
- Do not add app chrome, sidebars, nav bars, tabs, search bars, or floating controls.
- Use one `h1`.
- Use stable `id` values on `h2` and important `h3` headings.
- Keep everything local: inline CSS, local images only, no external scripts or CDNs.
- Use the report template only when the content is actually a report.
- For recurring reports, keep stable files like `today.html` and archive dated copies separately.
- For Design.md collections, keep extracted facts, screenshots, and personal interpretation clearly separated.
