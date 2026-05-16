---
name: htmelly-page-design
description: Design beautiful local HTML/Markdown collections for HTTMELY, including welcome guides, blog queues, daily reports, saved-site libraries, Design.md research folders, and project packets.
triggers:
  - HTTMELY collection
  - HTTMELY page
  - htmelly-ready
  - design for HTTMELY
  - local HTML collection
  - local page library
  - folder-backed HTML
  - Design.md collection
  - daily report collection
  - saved website collection
---

# HTTMELY Collection Design

Use this skill when creating, rewriting, or reviewing local HTML/Markdown folders meant to be opened in HTTMELY.

HTTMELY is a native macOS reader for local page collections. The app provides the shell: Places, sidebar page list, local file controls, optional contents navigation, export, and archive actions. Your job is to make the folder feel like a useful local library.

## Core Idea

Design a collection, not just a single file.

A good HTTMELY folder feels like a small private website:

- It has a clear purpose.
- It opens with a helpful first page.
- It contains readable local pages.
- It can be browsed, exported, archived, and revisited.
- It does not need a server, account, analytics, or cloud workflow.

## Great Collection Types

Use these as strong defaults when the user has not specified a structure:

- **Blog Queue**: polished draft posts, editorial notes, publish decisions, topic clusters.
- **Daily Reports**: daily HTML summaries from favorite apps, notes, calendars, task managers, agent outputs, local logs, or manual journaling.
- **Saved Sites**: SingleFile or similar local website captures organized by topic.
- **Design.md Collections**: design-system research folders with `DESIGN.md`, screenshots, token files, color notes, typography notes, and component observations.
- **Research Vaults**: source captures, summaries, decisions, quotes, and next questions.
- **Project Packets**: specs, audits, screenshots, changelogs, release notes, handoff docs, and open questions.
- **Product Manuals**: getting started, troubleshooting, examples, privacy notes, and reference pages.
- **Personal Knowledge Shelves**: local notes, exported docs, briefs, checklists, maps, and timelines.

## When To Use

Use this skill when the user asks for:

- An HTTMELY-ready local folder or page collection.
- A beautiful local HTML page that will live inside a folder.
- A welcome/onboarding collection for an app or product.
- A blog preview folder or publishing queue.
- A daily report format.
- A saved website/archive collection.
- A Design.md or design-system research packet.
- A folder index page.
- A redesign of existing local HTML so it feels good inside HTTMELY.

## When Not To Use

Do not use this skill for:

- Public marketing landing pages that need hosted site navigation.
- Full web apps with client-side routing, remote APIs, accounts, analytics, or cloud scripts.
- Native AppKit/Swift changes to HTTMELY itself.
- Pixel-perfect cloning of a third-party website.
- Extracting a whole design system from a website. Use an extraction workflow first, then use this skill to turn the artifacts into a readable collection.

For recurring generated reports, archive contracts, stable filenames, and automation prompts, use the companion `htmelly-report-automation` skill.

## Collection Shape

Prefer this structure:

```text
My Collection/
  index.html
  README.md              optional
  assets/                local CSS/images only
  pages/
    overview.html
    details.md
  archive/               optional snapshots
```

For design research:

```text
Design Research/
  index.html
  DESIGN.md
  screenshots/
    homepage.png
    detail-page.png
  design-system/
    tokens.json
    tokens.css
  notes/
    typography.md
    color-system.md
    component-observations.md
```

For daily reports:

```text
Daily Reports/
  index.html
  2026-05-16.html
  2026-05-17.html
  weekly/
    2026-week-20.html
```

For saved websites:

```text
Saved Sites/
  index.html
  AI Tools/
    local-model-comparison.html
  Design References/
    beautiful-docs-page.html
```

## First Page Pattern

Every collection should have a natural opening page, usually `index.html`.

Use the first page to answer:

- What is this collection?
- Why would someone open it?
- What are the 3-6 most useful pages?
- What workflow produced it?
- What should the reader do next?

The first page can be more editorial than technical. It may use a restrained hero, a compact shelf of collection types, section markers, quotes, tables, and examples.

## Page Design Language

Default style:

- Editorial, calm, local-first.
- Muted neutral background or white page, depending on the content.
- Strong title, short lead paragraph, useful section markers.
- Smaller body type than a landing page.
- Compact shelves or tables for scanning.
- Subtle accent color, not a loud theme.
- Local CSS only. No remote fonts or CDN.

Good pages can feel beautiful. They do not need to feel like developer docs.

Avoid:

- Big SaaS landing-page heroes.
- Marketing claims without useful content.
- App chrome duplicated inside the page.
- Sidebars, tab bars, folder pickers, fake window controls, or search UI.
- Giant cards everywhere.
- Heavy gradients, blobs, noisy shadows, or animation for its own sake.
- Remote dependencies.

Small CSS-only motion is okay when it stays quiet and respects `prefers-reduced-motion`.

## HTTMELY App Boundary

```
HTTMELY provides the app navigation.
The folder provides the local library.
Each HTML/Markdown file provides page content.
```

Do not build a second app inside the page. Let HTTMELY handle the sidebar and local file actions.

## HTML Rules

For generated HTML pages:

- Output complete standalone HTML.
- Use inline CSS for one-off pages, or a local `assets/*.css` file for a multi-page collection.
- Use semantic HTML: `main`, `article`, `section`, `header`, `table`, `ul`, `ol`, `blockquote`, `figure`.
- Use one clear `h1`.
- Use logical headings: `h2`, then `h3`.
- Add stable IDs to important headings when useful.
- Use system fonts unless a local font file is explicitly provided.
- Keep readable line length: usually 680-780px for article content.
- Make wide tables scroll or stay compact.
- Keep links visible.
- Use local images only when provided or generated.
- The page must work from `file://`.

## Content Patterns

### Blog Queue

Include:

- Draft title and short excerpt.
- Audience and angle.
- Status: idea, draft, ready, published.
- Strong sections or outline.
- Pull quote or notable excerpt.
- Publish decision notes when useful.

### Daily Reports

Use generic wording. Do not assume a specific app.

Include:

- Date and short daily summary.
- Signals from favorite tools, notes, task managers, app exports, logs, agents, or manual input.
- Project pulse.
- Decisions made.
- Open loops.
- Next actions.
- Optional weekly rollup links.

### Saved Sites

Include:

- Topic index.
- Why each page was saved.
- Source URL if available.
- Date saved.
- Tags or category notes.
- Local capture caveats when useful.

### Design.md Collections

Treat design extraction as a starter, not truth.

Include:

- `DESIGN.md` overview.
- Source URL and date.
- Screenshots.
- Likely colors and typography.
- Spacing/radius/shadow observations.
- Component observations.
- Token files if available.
- Manual review notes.
- A clear distinction between extracted facts and interpretation.

Example `DESIGN.md` starter:

```md
# Design Study

Source: https://example.com
Date: YYYY-MM-DD

## First Impression
- Calm editorial layout
- Muted neutral background
- Small uppercase labels

## Extracted Primitives
- Primary color:
- Accent color:
- Body font:
- Heading font:
- Radius scale:
- Shadow style:

## Screenshots
- screenshots/homepage.png
- screenshots/detail-page.png

## Notes
- What should inspire this project?
- What should not be copied?
- What needs manual review?
```

### Project Packets

Include:

- Project purpose.
- Current state.
- Important files or links.
- Screenshots or artifacts.
- Decisions.
- Risks.
- Next actions.
- Archive/history only when useful.

## Visual Examples

### Editorial Home Page

Use for welcome pages, blog queues, design studies, and polished collection indexes:

- Fixed or simple top label only when the page is viewed outside HTTMELY too.
- Small uppercase tag.
- Large but not huge title.
- Short lead with left accent line.
- Compact shelf of collection highlights.
- Section markers.
- Quotes and tables used sparingly.

### Operating Report

Use for daily/weekly reports:

- Date-forward title.
- Compact signal shelf.
- Project pulse table.
- Decisions and next actions.
- Quiet archive links.

### Design Research Packet

Use for `DESIGN.md` collections:

- Source and extraction date.
- Color and typography summary.
- Screenshot links.
- Token file links.
- Component observations.
- Manual review caveats.

## HTTMELY Fit Checklist

Before final output, check:

- [ ] The folder has a clear use case.
- [ ] There is a useful first page, preferably `index.html`.
- [ ] Pages work from local files.
- [ ] No cloud, analytics, external scripts, or remote dependencies.
- [ ] No duplicate app chrome or navigation.
- [ ] Typography is readable and not oversized.
- [ ] Visual style fits the collection type.
- [ ] Tables and code blocks are readable.
- [ ] Local assets use relative paths.
- [ ] Report structure is used only when the content is actually a report.
- [ ] Design-system extraction output is described as starter material, not complete truth.

## Copy-Paste Prompt

Use this with another AI agent:

```text
Design this as an HTTMELY-ready local page collection.

HTTMELY is a native macOS reader for local HTML and Markdown folders. It already provides the app shell: Places, sidebar page list, optional contents navigation, local file controls, export, and archive actions.

Goal:
- Create a beautiful local folder of standalone pages, not a web app.
- Make the folder feel like a small private website or local library.
- Include a useful first page, preferably index.html.

Possible collection types:
- blog queue
- daily reports from favorite tools, notes, exports, logs, or agents
- saved websites / SingleFile archives
- Design.md design-system research packet
- research vault
- project packet
- product manual
- personal knowledge shelf

Rules:
- Do not build app chrome, sidebars, tabs, search bars, folder pickers, fake window controls, or hosted navigation.
- Use semantic HTML and local Markdown.
- Use local CSS only: inline CSS for one-off pages, or assets/*.css for a multi-page collection.
- No remote fonts, CDNs, analytics, hosted scripts, cloud assets, or remote APIs.
- Use one clear h1 per page and useful h2/h3 headings.
- Add stable IDs to important headings when useful.
- Keep typography smaller and editorial, not oversized landing-page style.
- Use calm visual hierarchy: muted neutrals, subtle accent, section markers, compact tables, quotes, notes, and examples.
- Use report structure only if the content is truly a report.
- For Design.md collections, clearly separate extracted facts from interpretation and manual review notes.
- The output must work from file://.

Output:
- A suggested folder tree.
- The complete HTML/Markdown content for the key files.
- Any local CSS file content if using shared styling.
- A short note explaining how to add the folder in HTTMELY.
```

## Output Requirements

When using this skill, return one of:

- A folder plan plus complete key file contents.
- A complete single HTML file.
- A concise review with concrete fixes for making an existing folder HTTMELY-ready.

If editing files in a repo, keep changes local-first and avoid adding dependencies.
