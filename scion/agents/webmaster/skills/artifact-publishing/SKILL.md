---
name: artifact-publishing
description: >-
  Direct GCS artifact publishing: upload files, convert markdown to styled HTML,
  set correct headers, manage bucket structure. Replaces the former
  artifact-manager coordination pattern with direct webmaster capability.
---

# Artifact Publishing

## GCS Publishing Commands

### Upload HTML

```bash
gsutil -h "Content-Type:text/html" \
  -h "Cache-Control:no-cache, no-store, must-revalidate" \
  cp <local-file> gs://platform-team-project-work/<target-path>
```

### Upload Other Content Types

| Type | Content-Type Header |
|------|-------------------|
| HTML | `text/html` |
| CSS | `text/css` |
| JavaScript | `application/javascript` |
| JSON | `application/json` |
| PNG | `image/png` |
| SVG | `image/svg+xml` |
| Plain text | `text/plain` |
| Markdown (raw) | `text/markdown` |

Always specify Content-Type explicitly. Without it, GCS defaults to `application/octet-stream` and browsers download instead of rendering.

### Cache-Control

Always use:
```
-h "Cache-Control:no-cache, no-store, must-revalidate"
```

Do NOT use `max-age` caching — it causes stale content that users cannot clear without waiting for expiry. The debugging cost is not worth the marginal performance benefit.

## Markdown to Styled HTML Conversion

When you receive a markdown file that should be published as a styled HTML page:

1. Read the markdown source
2. Convert to HTML with inline styling (no external dependencies)
3. Apply the project's visual style (see Style Guide below)
4. Write to a local file
5. Upload to GCS with `Content-Type:text/html`

### Conversion Template

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{document title}</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: 'Google Sans', 'Segoe UI', Roboto, Arial, sans-serif;
      line-height: 1.6;
      color: #202124;
      background: #f8f9fa;
      padding: 2rem;
    }
    .container { max-width: 900px; margin: 0 auto; background: #fff; padding: 2rem; border-radius: 8px; border: 1px solid #dadce0; }
    h1 { color: #1a73e8; margin-bottom: 1rem; font-size: 1.75rem; }
    h2 { color: #202124; margin: 1.5rem 0 0.75rem; font-size: 1.35rem; border-bottom: 2px solid #e8eaed; padding-bottom: 0.5rem; }
    h3 { color: #5f6368; margin: 1.25rem 0 0.5rem; font-size: 1.1rem; }
    p { margin-bottom: 1rem; }
    code { background: #f1f3f4; padding: 0.15rem 0.4rem; border-radius: 4px; font-size: 0.9rem; }
    pre { background: #1e1e1e; color: #d4d4d4; padding: 1rem; border-radius: 8px; overflow-x: auto; margin-bottom: 1rem; }
    pre code { background: none; padding: 0; color: inherit; }
    table { width: 100%; border-collapse: collapse; margin-bottom: 1rem; }
    th, td { padding: 0.5rem 0.75rem; border: 1px solid #dadce0; text-align: left; }
    th { background: #f1f3f4; font-weight: 500; }
    a { color: #1a73e8; text-decoration: none; }
    a:hover { text-decoration: underline; }
    ul, ol { margin: 0 0 1rem 1.5rem; }
    li { margin-bottom: 0.25rem; }
    blockquote { border-left: 4px solid #1a73e8; padding-left: 1rem; color: #5f6368; margin-bottom: 1rem; }
  </style>
</head>
<body>
  <div class="container">
    {converted HTML content}
  </div>
</body>
</html>
```

## Bucket Structure

```
gs://platform-team-project-work/
├── site/
│   └── index.html              # Project hub (main index page)
├── project-diary/
│   └── index.html              # Chronicler's project diary
├── retrospective/
│   └── index.html              # Project retrospective
├── {topic}/
│   └── index.html              # Topic-specific artifact pages
└── {category}/{artifact-name}/
    └── index.html              # Categorized artifacts
```

Conventions:
- Use lowercase, hyphenated directory names
- Each publishable artifact gets its own directory with `index.html`
- Group related artifacts under a shared parent directory
- The `site/` directory is reserved for the project hub

## URL Pattern

All published artifacts are publicly accessible at:
```
https://storage.googleapis.com/platform-team-project-work/{path}
```

## Verification

After every upload, verify the content is served correctly:

```bash
curl -sI "https://storage.googleapis.com/platform-team-project-work/{path}" | grep -E "Content-Type|HTTP"
curl -s "https://storage.googleapis.com/platform-team-project-work/{path}" | head -5
```

Check:
1. HTTP status is 200
2. Content-Type is `text/html` (not `application/octet-stream`)
3. Content matches what you uploaded

## Listing Published Artifacts

```bash
# All artifacts
gsutil ls -r gs://platform-team-project-work/ | grep -v "/$"

# Specific directory
gsutil ls gs://platform-team-project-work/site/

# Find artifacts by name
gsutil ls -r gs://platform-team-project-work/ | grep -i "<search-term>"
```

## Publishing Workflow

When asked to publish an artifact:

1. **Determine source** — local file path or content to generate
2. **Determine target** — GCS path following bucket conventions
3. **Prepare content** — if markdown, convert to styled HTML; if already HTML, use as-is
4. **Write locally** — save to a working directory first
5. **Upload** — `gsutil` with correct Content-Type and Cache-Control
6. **Verify** — `curl` to confirm correct serving
7. **Report** — return the public URL to the requester
8. **Update index** — if significant, add the artifact to the project hub index page
