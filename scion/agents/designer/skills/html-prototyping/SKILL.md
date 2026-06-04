---
name: html-prototyping
description: >-
  Create self-contained HTML/CSS prototype files for UI screens. Use when you need to
  produce a functional, styled mockup that can be opened in a browser with no build step
  or external dependencies. Covers layout patterns, component recipes, and output conventions.
---

# HTML/CSS Prototyping

Build realistic, self-contained HTML prototypes that communicate design intent.

## File Structure

Every prototype is a single `.html` file with all CSS inlined in a `<style>` block. No external stylesheets, no JavaScript frameworks, no CDN links. The file must open correctly from the filesystem via `file://`.

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>[Screen Name] — [Project Name]</title>
  <style>
    /* Reset + Design tokens + Component styles + Layout */
  </style>
</head>
<body>
  <!-- Semantic HTML structure -->
</body>
</html>
```

## CSS Foundation

Start every prototype with these defaults:

```css
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

:root {
  /* Spacing scale (4px base) */
  --space-1: 4px;
  --space-2: 8px;
  --space-3: 12px;
  --space-4: 16px;
  --space-5: 20px;
  --space-6: 24px;
  --space-8: 32px;
  --space-10: 40px;
  --space-12: 48px;
  --space-16: 64px;

  /* Typography */
  --font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  --font-mono: "SF Mono", SFMono-Regular, Consolas, "Liberation Mono", Menlo, monospace;

  --text-xs: 0.75rem;    /* 12px */
  --text-sm: 0.875rem;   /* 14px */
  --text-base: 1rem;     /* 16px */
  --text-lg: 1.125rem;   /* 18px */
  --text-xl: 1.25rem;    /* 20px */
  --text-2xl: 1.5rem;    /* 24px */
  --text-3xl: 1.875rem;  /* 30px */

  /* Colors — define a limited palette, then assign semantic names */
  --gray-50: #f9fafb;
  --gray-100: #f3f4f6;
  --gray-200: #e5e7eb;
  --gray-300: #d1d5db;
  --gray-400: #9ca3af;
  --gray-500: #6b7280;
  --gray-600: #4b5563;
  --gray-700: #374151;
  --gray-800: #1f2937;
  --gray-900: #111827;

  --blue-500: #3b82f6;
  --blue-600: #2563eb;
  --blue-700: #1d4ed8;
  --green-500: #22c55e;
  --green-600: #16a34a;
  --red-500: #ef4444;
  --red-600: #dc2626;
  --yellow-500: #eab308;

  /* Semantic tokens */
  --color-bg: #ffffff;
  --color-bg-subtle: var(--gray-50);
  --color-bg-muted: var(--gray-100);
  --color-text: var(--gray-900);
  --color-text-secondary: var(--gray-500);
  --color-text-muted: var(--gray-400);
  --color-border: var(--gray-200);
  --color-primary: var(--blue-600);
  --color-primary-hover: var(--blue-700);
  --color-success: var(--green-600);
  --color-danger: var(--red-600);

  /* Radii */
  --radius-sm: 4px;
  --radius-md: 6px;
  --radius-lg: 8px;
  --radius-xl: 12px;

  /* Shadows */
  --shadow-sm: 0 1px 2px rgba(0,0,0,0.05);
  --shadow-md: 0 4px 6px -1px rgba(0,0,0,0.1), 0 2px 4px -2px rgba(0,0,0,0.1);
  --shadow-lg: 0 10px 15px -3px rgba(0,0,0,0.1), 0 4px 6px -4px rgba(0,0,0,0.1);
}

body {
  font-family: var(--font-sans);
  font-size: var(--text-base);
  line-height: 1.5;
  color: var(--color-text);
  background: var(--color-bg);
  -webkit-font-smoothing: antialiased;
}
```

## Layout Patterns

### App Shell (sidebar + main content)
```css
.app-shell { display: grid; grid-template-columns: 240px 1fr; min-height: 100vh; }
.sidebar { background: var(--color-bg-subtle); border-right: 1px solid var(--color-border); padding: var(--space-6); }
.main { padding: var(--space-8); max-width: 1200px; }
```

### Page Header + Content
```css
.page-header { padding: var(--space-6) var(--space-8); border-bottom: 1px solid var(--color-border); display: flex; justify-content: space-between; align-items: center; }
.page-content { padding: var(--space-8); }
```

### Card Grid
```css
.card-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: var(--space-6); }
.card { background: var(--color-bg); border: 1px solid var(--color-border); border-radius: var(--radius-lg); padding: var(--space-6); }
```

## Component Recipes

### Button
```css
.btn { display: inline-flex; align-items: center; gap: var(--space-2); padding: var(--space-2) var(--space-4); font-size: var(--text-sm); font-weight: 500; border-radius: var(--radius-md); border: 1px solid transparent; cursor: pointer; transition: all 0.15s ease; }
.btn-primary { background: var(--color-primary); color: white; }
.btn-primary:hover { background: var(--color-primary-hover); }
.btn-secondary { background: white; color: var(--color-text); border-color: var(--color-border); }
.btn-secondary:hover { background: var(--color-bg-subtle); }
.btn-danger { background: var(--color-danger); color: white; }
```

### Form Input
```css
.form-group { display: flex; flex-direction: column; gap: var(--space-1); }
.form-label { font-size: var(--text-sm); font-weight: 500; color: var(--color-text); }
.form-input { padding: var(--space-2) var(--space-3); font-size: var(--text-sm); border: 1px solid var(--color-border); border-radius: var(--radius-md); outline: none; transition: border-color 0.15s; }
.form-input:focus { border-color: var(--color-primary); box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.1); }
.form-hint { font-size: var(--text-xs); color: var(--color-text-secondary); }
```

### Table
```css
.table { width: 100%; border-collapse: collapse; font-size: var(--text-sm); }
.table th { text-align: left; padding: var(--space-3) var(--space-4); font-weight: 500; color: var(--color-text-secondary); border-bottom: 2px solid var(--color-border); }
.table td { padding: var(--space-3) var(--space-4); border-bottom: 1px solid var(--color-border); }
.table tr:hover td { background: var(--color-bg-subtle); }
```

### Badge / Status Pill
```css
.badge { display: inline-flex; align-items: center; padding: 2px var(--space-2); font-size: var(--text-xs); font-weight: 500; border-radius: 9999px; }
.badge-success { background: #dcfce7; color: #166534; }
.badge-warning { background: #fef9c3; color: #854d0e; }
.badge-danger { background: #fee2e2; color: #991b1b; }
.badge-neutral { background: var(--color-bg-muted); color: var(--color-text-secondary); }
```

## Content Guidelines

- Use realistic names, numbers, and dates — never Lorem Ipsum
- For user names, use diverse names: "Sarah Chen", "James Okafor", "Maria Garcia"
- For metrics, use plausible numbers with appropriate units
- For dates, use relative terms in the UI ("2 hours ago", "Yesterday") and absolute dates in tooltips/details
- For empty states, show the actual empty state message, not a populated example

## Accessibility Checklist

- [ ] All text meets WCAG AA contrast ratio (4.5:1 for body text, 3:1 for large text)
- [ ] Interactive elements have visible focus styles (`:focus-visible`)
- [ ] Form inputs have associated `<label>` elements
- [ ] Images have `alt` attributes
- [ ] Semantic HTML used (`<nav>`, `<main>`, `<section>`, `<article>`, `<header>`, `<footer>`)
- [ ] Color is not the only means of conveying information

## Output Convention

Save files to `out/` directory:
```
out/
├── index.html         # Primary screen
├── detail.html        # Detail/drill-down view
├── form.html          # Create/edit form
├── settings.html      # Settings/configuration
└── empty-state.html   # Empty/zero-data state
```

Name files by their screen purpose, not component name. Use kebab-case.
