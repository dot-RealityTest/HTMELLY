---
name: htmelly-page-design
description: Design or generate local HTML pages that fit HTTMELY's native macOS reader, folder sidebar, and contents navigation.
triggers:
  - HTTMELY page
  - htmelly-ready
  - design for HTTMELY
  - local HTML page
  - folder-backed HTML
  - page for HTTMELY
---

# HTTMELY Page Design

Use this skill when creating, rewriting, or reviewing HTML pages that will be opened inside HTTMELY.

HTTMELY is the native app shell. The HTML file is the page content.

## Purpose

Create calm, readable, local-first HTML pages that feel natural inside HTTMELY's native macOS reader.

Good outputs can be:

- Blog previews
- Briefs
- Notes
- Guides
- Local references
- Inventories
- Archives
- Overviews
- Project pages
- Documentation pages

## When To Use

Use this skill when the user asks for:

- A page that will go into HTTMELY
- A local HTML page for a folder-backed collection
- A blog preview or content preview for HTTMELY
- A guide, brief, notes page, archive, or overview opened in HTTMELY
- A redesign of an existing HTML page so it fits the HTTMELY reader

## When Not To Use

Do not use this skill for:

- Marketing landing pages meant for the public web
- Full web apps with their own navigation system
- Pages that need remote APIs, analytics, cloud scripts, or external assets
- App chrome, dashboards, sidebars, tab bars, or search interfaces
- Generated stable HTTMELY app code or native AppKit changes

## Core Rule

```
HTTMELY provides the app navigation.
The HTML provides only the page content.
```

Do not duplicate HTTMELY's sidebar, folder picker, contents panel, top controls, or file navigation inside the page.

## Default Page Pattern

Use this structure unless the content clearly needs something else:

1. One `h1` page title.
2. A short opening summary or orientation paragraph.
3. Clear `h2` sections with stable IDs.
4. Optional `h3` subsections for dense material.
5. Scannable blocks: lists, compact tables, examples, quotes, or notes.
6. A closing section only when it adds useful next action or context.

## HTML Rules

- Output a complete single HTML file.
- Use inline CSS in a `<style>` tag.
- Use semantic HTML: `main`, `section`, `header`, `table`, `ul`, `ol`, `blockquote`, `figure` where useful.
- Use logical heading order: `h1`, then `h2`, then `h3`.
- Add stable section IDs to `h2` and important `h3` headings.
- Keep the page readable as a standalone local file.
- Keep content width around `900px` to `1100px`.
- Use system fonts.
- Use neutral, quiet colors.
- Make links visible but calm.
- Make tables readable and horizontally scrollable when wide.
- Use local images only when explicitly provided.

## Design Rules

Do:

- Make the page content-first.
- Keep spacing calm and consistent.
- Use strong typographic hierarchy.
- Use simple dividers and subtle grouping.
- Match the content type instead of forcing one template.
- Let HTTMELY generate or expose contents navigation from headings.

Do not:

- Add nav bars, sidebars, breadcrumbs, tabs, search bars, floating controls, or app headers.
- Add hero sections unless the user explicitly asks for a public-facing page.
- Add decorative gradients, blobs, heavy shadows, animations, or oversized cards.
- Add nested card layouts.
- Add external scripts, analytics, fonts, CDNs, or remote dependencies.
- Rely on hover-only meaning.
- Use JavaScript unless absolutely needed for local table usability.
- Use the word "report" as the default content model unless the user specifically asks for a report.

## Content-Type Guidance

For blog previews:

- Make the title and excerpt the first useful signal.
- Include status, audience, angle, outline, and notable excerpts when useful.
- Keep it editorial, not dashboard-like.

For notes or briefs:

- Use summary, context, details, decisions, and next actions when useful.
- Keep paragraphs short and scan-friendly.

For guides:

- Use steps, prerequisites, examples, and pitfalls.
- Keep instructions direct.

For inventories or archives:

- Use compact tables and grouped sections.
- Avoid making the page feel like a spreadsheet dump.

For project or reference pages:

- Use sections for identity, purpose, files, links, decisions, and open questions.
- Make dense information easy to jump through with headings.

## HTTMELY Fit Checklist

Before final output, check:

- [ ] No app chrome or duplicate navigation.
- [ ] One clear `h1`.
- [ ] `h2` sections have stable IDs.
- [ ] Page works from a local file.
- [ ] No external dependencies.
- [ ] Width and line length are comfortable.
- [ ] Tables wrap or scroll cleanly.
- [ ] Visual style is calm and native-reader friendly.
- [ ] The page type fits the content, not a generic report template.

## Copy-Paste Prompt

Use this with another AI agent:

```text
Design this as an HTTMELY-ready local HTML page.

The page will be opened inside HTTMELY, a native macOS reader for local HTML and Markdown pages. HTTMELY already provides the app shell: left folder/page sidebar, optional in-page contents navigation, local file controls, and reader chrome.

Rules:
- Do not build app chrome, nav bars, sidebars, breadcrumbs, tabs, search bars, or floating controls.
- The HTML should be page content only, not an app shell.
- Use one clear page title and a calm reading flow.
- Use semantic headings in a logical order: h1, then h2/h3.
- Add stable section IDs so HTTMELY contents navigation can link to them.
- Match the content type: blog preview, reference page, brief, inventory, notes, archive, guide, overview, or project page.
- Use scanning structure when useful: summaries, sections, lists, pull quotes, compact tables, examples, notes, or next actions.
- Keep spacing calm and readable without making it feel like a marketing landing page.
- Avoid hero sections, decorative gradients, large nested cards, animations, and busy visual effects.
- Keep max content width around 900-1100px.
- Use system fonts and neutral colors.
- Make links obvious but quiet.
- Tables must be readable, scrollable if wide, and not rely on hover-only meaning.
- Do not include external scripts, analytics, fonts, CDNs, cloud assets, or remote dependencies.
- Local images are allowed only when explicitly provided.
- The page must work as a standalone local HTML file.
- Do not use "report" as the default structure unless I specifically ask for a report.

Output:
- A complete single HTML file.
- Inline CSS only.
- No JavaScript unless absolutely necessary for local table usability.
- No external dependencies.
```

## Output Requirements

When using this skill, return either:

- The complete HTML file content, or
- A concise review with concrete fixes for making an existing page HTTMELY-ready.

If editing a repo file, keep changes local-first and avoid adding dependencies.
