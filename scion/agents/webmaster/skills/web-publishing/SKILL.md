---
name: web-publishing
description: >-
  Maintain the project's public-facing index site on GCS. Covers index page structure,
  artifact cataloging, GCS publishing commands, and update conventions. Use when
  building or updating the project site.
---

# Web Publishing

Maintain a navigable project site on Google Cloud Storage.

## Index Page Structure

The index page is a self-contained HTML file at `gs://platform-team-project-work/site/index.html`. It follows the same conventions as the designer template — all CSS inline, no external dependencies, opens in any browser.

### Required Sections

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>[Project Name] — Project Index</title>
  <style>/* All CSS inline */</style>
</head>
<body>
  <header>
    <!-- Project title, one-paragraph summary -->
  </header>

  <nav>
    <!-- Jump links to sections below -->
  </nav>

  <main>
    <section id="overview">
      <!-- What this project is, who it's for, current status -->
    </section>

    <section id="team">
      <!-- Agent roles and capabilities -->
    </section>

    <section id="milestones">
      <!-- Last 5 significant events, newest first -->
    </section>

    <section id="artifacts">
      <!-- Categorized catalog of all published artifacts -->

      <h3>Reports</h3>
      <!-- Incident reports, RCA docs, capability assessments -->

      <h3>Design</h3>
      <!-- Prototypes, design specs -->

      <h3>Infrastructure</h3>
      <!-- Templates, configurations, architecture docs -->

      <h3>Data</h3>
      <!-- Surveys, metrics exports, research -->
    </section>

    <section id="diary">
      <!-- Summary of recent diary entries from chronicler -->
    </section>
  </main>

  <footer>
    <!-- Last updated timestamp, generated-by note -->
  </footer>
</body>
</html>
```

### Design Guidelines

- Clean, readable layout — single column, generous whitespace
- System font stack (`-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`)
- Limited color palette: dark text on white, one accent color for links and headings
- Each artifact entry: title (linked), date, one-line description
- Mobile-friendly (flexbox layout, readable at 320px width)

## Artifact Catalog Entry Format

Each artifact in the catalog follows this pattern:

```html
<article class="artifact">
  <h4><a href="https://storage.googleapis.com/platform-team-project-work/path/to/artifact">Artifact Title</a></h4>
  <time>YYYY-MM-DD</time>
  <p>One-line description of what this artifact is and why it matters.</p>
</article>
```

### Catalog Rules

- **Sort by date** within each category, newest first
- **Keep descriptions to one line** — the artifact itself has the details
- **Use direct GCS URLs** — `https://storage.googleapis.com/BUCKET/PATH`
- **Verify links resolve** before publishing — `gsutil stat gs://BUCKET/PATH`
- **Mark stale artifacts** — if something has been superseded, note it: "(superseded by [newer artifact])"

## GCS Publishing Commands

### Push a file
```bash
gsutil -h "Content-Type:text/html" cp out/index.html gs://platform-team-project-work/site/index.html
```

### Push with cache control (for frequently updated pages)
```bash
gsutil -h "Content-Type:text/html" -h "Cache-Control:no-cache, max-age=0" \
  cp out/index.html gs://platform-team-project-work/site/index.html
```

### List bucket contents
```bash
gsutil ls gs://platform-team-project-work/
gsutil ls -l gs://platform-team-project-work/site/
```

### Check if a file exists
```bash
gsutil stat gs://platform-team-project-work/path/to/file 2>&1
```

### Make a file publicly readable (if bucket isn't already public)
```bash
gsutil acl ch -u AllUsers:R gs://platform-team-project-work/site/index.html
```

## Update Cadence

| Trigger | Action |
|---------|--------|
| New artifact published | Add catalog entry, push updated index |
| Milestone achieved | Update milestones section, push index |
| Stakeholder update sent | Update "Last Updated" timestamp |
| Diary synthesis entry | Update diary summary section |
| Weekly (if no other updates) | Review and refresh the full page |
