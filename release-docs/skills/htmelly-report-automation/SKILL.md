---
name: htmelly-report-automation
description: Design and maintain automation-friendly HTTMELY report collections with stable files, archive snapshots, privacy boundaries, regeneration rules, and recurring report prompts.
triggers:
  - HTTMELY reports
  - HTTMELY report automation
  - automated HTML reports
  - daily report collection
  - weekly report collection
  - generated report folder
  - report regeneration
  - report archive
---

# HTTMELY Report Automation

Use this skill when building or reviewing generated report collections that will be opened in HTTMELY.

This skill is about reliable recurring output: daily reports, weekly summaries, project status reports, app inventories, research digests, folder audits, local dashboards, and other generated HTML/Markdown pages.

For beautiful one-off page and collection design, use the companion `htmelly-page-design` skill. Use this skill when cadence, filenames, regeneration, privacy, and automation safety matter.

## Core Contract

HTTMELY reads local files. The automation writes local files.

Keep those roles separate:

- Automation gathers sources and writes pages.
- HTTMELY browses the folder.
- Stable files are for everyday reading.
- Archive files are for history.
- Private/local context stays out of release-safe docs and shared bundles.

## Recommended Folder Shape

```text
Reports/
  index.html
  today.html
  projects.html
  decisions.html
  actions.html
  archive/
    2026-05-16.html
    2026-05-17.html
  assets/
    report.css
```

For daily reports:

```text
Daily Reports/
  index.html
  today.html
  yesterday.html
  weekly.html
  archive/
    2026-05-16.html
    2026-05-17.html
    weekly-2026-W20.html
```

For project reports:

```text
Project Reports/
  index.html
  active.html
  blocked.html
  shipped.html
  archive/
    active-2026-05-16.html
```

## Stable vs Archive Rules

Use stable filenames for the pages people open every day:

- `index.html`
- `today.html`
- `current.html`
- `active.html`
- `projects.html`
- `actions.html`
- `weekly.html`

Use dated filenames for history:

- `archive/2026-05-16.html`
- `archive/weekly-2026-W20.html`
- `archive/projects-2026-05-16.html`

Rules:

- Regeneration may overwrite stable files.
- Regeneration should not overwrite archives unless explicitly asked.
- Stable files should link to the latest useful archive files.
- Archive pages should not be the default HTTMELY entrypoint.
- Do not point a built-in or default Place at dated files unless the user asks for an archive view.

## Automation Safety Rules

Before writing a recurring report workflow:

- Confirm the output folder.
- Confirm which files are stable and which are archives.
- Confirm whether older archives should be retained, pruned, or never touched.
- Avoid deleting source files.
- Avoid deleting archive files unless there is an explicit retention rule.
- Make generated pages reproducible from the source inputs.
- Put generated metadata in the page footer or comments only when it helps.
- Keep secrets, tokens, private account IDs, and raw credentials out of pages.

Prefer this write pattern:

1. Read sources.
2. Generate HTML/Markdown in memory or a temp file.
3. Write stable files atomically when possible.
4. Write dated archive copies.
5. Verify expected files exist.
6. Report what changed.

## Privacy Boundaries

Reports often contain personal or machine-local context.

Default to local/private unless the user explicitly says the report is release-safe.

Keep out of shared/release docs:

- Absolute personal paths.
- Usernames and home directories.
- Private app inventories.
- Internal automation notes.
- Local account identifiers.
- Secrets, tokens, API keys, cookies, auth headers.
- Raw private logs unless the user explicitly asks.

For release-safe examples, use placeholders:

- `~/Reports`
- `Example Project`
- `Your favorite notes app`
- `Your task manager export`

## Report Page Pattern

A good report page answers:

- What changed?
- What matters?
- What needs attention?
- What should happen next?
- Where can the reader inspect the source or archive?

Default structure:

```html
<main>
  <header>
    <p class="eyebrow">Daily Report</p>
    <h1>Today</h1>
    <p class="lead">Short summary of the signal.</p>
  </header>

  <section id="summary">
    <h2>Summary</h2>
  </section>

  <section id="signals">
    <h2>Signals</h2>
  </section>

  <section id="projects">
    <h2>Projects</h2>
  </section>

  <section id="actions">
    <h2>Next Actions</h2>
  </section>
</main>
```

Use compact tables for status, not giant dashboards.

## Useful Report Types

### Daily Operating Report

Sources can include favorite apps, notes, task exports, calendars, local logs, agent summaries, browser captures, or manual notes.

Include:

- Morning or end-of-day summary.
- Project pulse.
- Decisions.
- Open loops.
- Follow-ups.
- Next actions.
- Links to archive copies.

### Weekly Summary

Include:

- What shipped.
- What stalled.
- What changed.
- Themes and repeated patterns.
- Cleanup candidates.
- Next week focus.

### Project Status Report

Include:

- Current state.
- Recent changes.
- Blockers.
- Files or artifacts to inspect.
- Risks.
- Next actions.

### Local Inventory Report

Include:

- What was scanned.
- What changed since last run.
- Keep/remove/review groups.
- Manual review caveats.
- Source and generation timestamp.

### Research Digest

Include:

- Sources reviewed.
- Key findings.
- Contradictions or uncertainty.
- Useful quotes or summaries.
- Follow-up questions.

## Automation Prompt Template

Use this with a recurring automation or agent:

```text
Generate an HTTMELY-ready report collection.

Sources:
[describe files, apps, exports, folders, logs, or notes]

Output folder:
[path]

Stable files:
- index.html
- today.html
- projects.html
- actions.html

Archive rule:
- Write a dated copy to archive/YYYY-MM-DD.html.
- Do not delete previous archive files.

Report rules:
- Local HTML or Markdown only.
- No external scripts, fonts, CDNs, analytics, or remote assets.
- Do not include secrets, tokens, cookies, credentials, or private account IDs.
- Avoid absolute personal paths unless this is explicitly a private local report.
- Use stable h1/h2/h3 headings.
- Include summary, signals, decisions, open loops, and next actions.
- Keep the visual design calm and readable in HTTMELY.
- Verify all stable files exist after writing.

Return:
- Files written.
- Archive file created.
- Any skipped sources or warnings.
```

## Recurring Automation Rules

For recurring jobs:

- Name the automation by cadence and collection: `Daily HTTMELY Report`, `Weekly Project Report`, etc.
- Keep the prompt self-contained.
- Specify output folder, stable filenames, and archive rule.
- Specify whether silence is allowed when no sources changed.
- Prefer future-only generation unless the user asks for backfill.
- Avoid modifying old archive files during normal runs.
- Add a short generated-at timestamp inside the report only if useful.

## Verification Checklist

After generating or changing a report workflow:

- [ ] Stable files exist.
- [ ] Archive copy exists when expected.
- [ ] `index.html` is a useful first page.
- [ ] No private paths or secrets leaked into release-safe output.
- [ ] Links are relative and work from `file://`.
- [ ] Tables are readable.
- [ ] Empty states explain what source was missing.
- [ ] Automation does not delete source data.
- [ ] Automation does not overwrite archives without permission.
- [ ] The folder can be added to HTTMELY as a Place.

## Output Requirements

When using this skill, return one of:

- A report folder plan with stable/archive contracts.
- Complete report HTML/Markdown files.
- A recurring automation prompt.
- A concise review of an existing report workflow with concrete fixes.

Keep reports local-first and automation-safe.
