---
name: design-specs
description: >-
  Convert HTML/CSS prototypes into structured design specifications for engineering
  handoff. Produces component inventories, layout specs, spacing tokens, color palettes,
  interaction states, and accessibility notes in both markdown and JSON formats.
---

# Design Specifications

Convert visual prototypes into precise, structured specifications that engineers can implement from.

## When to Generate

Generate a design spec when:
- The prototype has been reviewed and approved
- The design is being handed off to an engineer who wasn't involved in the design process
- The project needs a permanent record of design decisions
- Multiple engineers will implement different parts of the same design

## Spec Structure

### Markdown Format (`out/design-spec.md`)

```markdown
# Design Specification: [Feature/Screen Name]

**Version:** 1.0
**Date:** YYYY-MM-DD
**Prototype:** [path to HTML file]

## Overview

[1-2 sentences describing what this screen/feature does and who it's for]

## Layout

### Page Structure
[Describe the overall layout: grid columns, sidebar width, content max-width, breakpoints]

### Sections
[List each major section of the page with its layout rules]

## Components

### [Component Name]
- **Purpose:** [What it does]
- **HTML element:** [Semantic element used]
- **Variants:** [List visual variants]
- **States:** [Default, hover, focus, active, disabled, loading, error]
- **Sizing:** [Width, height, padding, margin]
- **Typography:** [Font size, weight, line-height, color]
- **Borders:** [Width, color, radius]
- **Background:** [Color or pattern]

[Repeat for each component]

## Design Tokens

### Colors
| Token | Value | Usage |
|-------|-------|-------|
| --color-primary | #2563eb | Buttons, links, active states |
| --color-text | #111827 | Body text, headings |
| ... | ... | ... |

### Spacing
| Token | Value | Usage |
|-------|-------|-------|
| --space-2 | 8px | Inline element gaps |
| --space-4 | 16px | Component internal padding |
| ... | ... | ... |

### Typography
| Style | Size | Weight | Line-height | Usage |
|-------|------|--------|-------------|-------|
| Heading 1 | 30px | 700 | 1.2 | Page titles |
| Body | 16px | 400 | 1.5 | Default text |
| ... | ... | ... | ... | ... |

## Interaction States

### [Component/Element]
| State | Visual Change |
|-------|--------------|
| Default | [description] |
| Hover | [description] |
| Focus | [description] |
| Active | [description] |
| Disabled | [description] |

## Responsive Behavior

| Breakpoint | Layout Change |
|------------|--------------|
| < 768px | [what changes on mobile] |
| 768px - 1024px | [what changes on tablet] |
| > 1024px | [desktop layout — default] |

## Accessibility

- **Color contrast:** [List any contrast ratios that are close to limits]
- **Keyboard navigation:** [Tab order, focus management notes]
- **Screen reader:** [ARIA labels, live regions, landmark notes]
- **Motion:** [Any animations and prefers-reduced-motion handling]
```

### JSON Format (`out/design-spec.json`)

```json
{
  "name": "Feature Name",
  "version": "1.0",
  "date": "YYYY-MM-DD",
  "tokens": {
    "colors": {
      "primary": { "value": "#2563eb", "usage": "Buttons, links, active states" },
      "text": { "value": "#111827", "usage": "Body text, headings" }
    },
    "spacing": {
      "2": { "value": "8px", "usage": "Inline element gaps" },
      "4": { "value": "16px", "usage": "Component internal padding" }
    },
    "typography": {
      "heading-1": { "size": "30px", "weight": 700, "lineHeight": 1.2 },
      "body": { "size": "16px", "weight": 400, "lineHeight": 1.5 }
    },
    "radii": {
      "sm": "4px",
      "md": "6px",
      "lg": "8px"
    }
  },
  "components": [
    {
      "name": "Component Name",
      "element": "button",
      "variants": ["primary", "secondary", "danger"],
      "states": ["default", "hover", "focus", "active", "disabled"],
      "styles": {
        "padding": "8px 16px",
        "fontSize": "14px",
        "fontWeight": 500,
        "borderRadius": "6px"
      }
    }
  ],
  "layout": {
    "type": "grid",
    "columns": "240px 1fr",
    "maxWidth": "1200px",
    "breakpoints": {
      "mobile": "< 768px",
      "tablet": "768px - 1024px",
      "desktop": "> 1024px"
    }
  }
}
```

## Extraction Process

To generate a spec from an existing HTML prototype:

1. **Read the HTML file** — parse the `<style>` block for all CSS custom properties and component classes
2. **Extract tokens** — pull all `--color-*`, `--space-*`, `--text-*`, `--radius-*`, `--shadow-*` variables
3. **Inventory components** — identify each distinct UI component by its class name and visual role
4. **Document states** — for each interactive component, list all CSS pseudo-class states (`:hover`, `:focus`, `:active`, `:disabled`)
5. **Describe layout** — document the grid/flexbox structure, breakpoints, and responsive rules
6. **Note accessibility** — check contrast ratios, ARIA usage, semantic elements, focus management

## Quality Checklist

- [ ] Every component in the prototype is listed in the spec
- [ ] Every color used is defined as a token with its semantic purpose
- [ ] Every interactive element has all its states documented
- [ ] Spacing values are consistent and drawn from the token scale
- [ ] Responsive behavior is described for at least mobile and desktop
- [ ] Accessibility requirements are specific, not generic
