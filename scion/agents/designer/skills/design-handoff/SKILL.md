---
name: design-handoff
description: >-
  Creating and pushing structured handoff documents to implementation agents:
  component specs, layout specs, interaction states, and API dependencies.
  Use when handing off designs to developers for implementation.
---

# Design Handoff

## Handoff Document Structure

Every design handoff produces a structured spec that an implementation agent can build from without ambiguity.

```
out/
├── handoff/
│   ├── component-spec.md        # Component inventory with props and states
│   ├── layout-spec.md           # Page layout with responsive breakpoints
│   ├── interaction-spec.md      # User interactions and state transitions
│   ├── api-dependencies.md      # Data requirements and API contracts
│   └── assets/                  # Any reference images or prototypes
│       └── prototype.html       # Working HTML prototype (if created)
```

## Component Spec

Define every component the implementation needs to build.

### Format

```markdown
## Component: ProductCard

**Type:** Presentational
**Location:** Product listing page, search results, recommendations

### Props

| Prop | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| name | string | yes | — | Product display name |
| price | number | yes | — | Price in cents |
| imageUrl | string | yes | — | Product image URL |
| rating | number | no | null | Average rating (0-5) |
| onSale | boolean | no | false | Shows sale badge |
| originalPrice | number | no | null | Pre-sale price (shown struck through) |

### Visual States

| State | Appearance |
|-------|-----------|
| Default | Card with image, name, price |
| Hover | Subtle shadow elevation, cursor pointer |
| On Sale | Red "SALE" badge top-right, original price struck through |
| Out of Stock | Greyed image, "Out of Stock" overlay, no add-to-cart |
| Loading | Skeleton placeholder matching card dimensions |

### Layout

- Card width: fills grid column (min 240px, max 320px)
- Image: 4:3 aspect ratio, object-fit: cover
- Padding: 16px
- Border-radius: 8px
- Font: name is body-md semibold, price is body-lg bold

### Accessibility

- Image has alt text: "{product name} product image"
- Card is a link to product detail page
- Sale badge is aria-label="On sale"
- Rating uses aria-label="{n} out of 5 stars"
```

### Component Inventory Checklist

For each component, specify:
- [ ] Props with types, required/optional, defaults
- [ ] All visual states (default, hover, active, disabled, loading, error, empty)
- [ ] Dimensions and spacing (use design tokens, not magic numbers)
- [ ] Typography (which tokens apply to which text)
- [ ] Responsive behavior (what changes at which breakpoint)
- [ ] Accessibility requirements (alt text, aria labels, keyboard navigation)

## Layout Spec

Define how components arrange on the page across breakpoints.

### Format

```markdown
## Page: Product Listing

### Desktop (≥1024px)

┌─────────────────────────────────────────┐
│ Header (sticky)                         │
├────────┬────────────────────────────────┤
│Filters │ Product Grid                   │
│Sidebar │ 3 columns, 24px gap            │
│240px   │ ┌────┐ ┌────┐ ┌────┐          │
│        │ │Card│ │Card│ │Card│          │
│        │ └────┘ └────┘ └────┘          │
│        │ ┌────┐ ┌────┐ ┌────┐          │
│        │ │Card│ │Card│ │Card│          │
│        │ └────┘ └────┘ └────┘          │
├────────┴────────────────────────────────┤
│ Pagination (centered)                   │
└─────────────────────────────────────────┘

### Tablet (768px–1023px)

- Filters collapse to horizontal chip bar above grid
- Grid becomes 2 columns, 16px gap
- Sidebar hidden, replaced by filter drawer (slide from left)

### Mobile (<768px)

- Grid becomes 1 column, full width with 16px margin
- Filter button fixed bottom-right, opens bottom sheet
- Header scrolls with content (not sticky)
```

### Layout Spec Checklist

- [ ] ASCII wireframe for each breakpoint
- [ ] Container max-width and margins
- [ ] Grid columns and gaps per breakpoint
- [ ] Component placement and ordering
- [ ] Sticky/fixed elements
- [ ] Scroll behavior
- [ ] What hides/shows/reflows at each breakpoint

## Interaction Spec

Define user interactions and the resulting state transitions.

### Format

```markdown
## Interaction: Add to Cart

### Trigger
User clicks "Add to Cart" button on ProductCard or ProductDetail

### States

1. **Idle** → Button shows "Add to Cart"
2. **Loading** → Button shows spinner, disabled (prevents double-click)
3. **Success** → Button briefly shows "Added ✓" (1.5s), cart badge increments
4. **Error** → Toast notification: "Couldn't add item. Try again." Button returns to idle.
5. **Out of Stock** → Button shows "Out of Stock", disabled, grey

### State Machine

```
idle ──[click]──→ loading
loading ──[API success]──→ success ──[1.5s]──→ idle
loading ──[API error]──→ error ──[toast dismiss]──→ idle
```

### Edge Cases

| Scenario | Behavior |
|----------|----------|
| Rapid double-click | Button disabled during loading — second click ignored |
| Network timeout (>5s) | Show error toast, return to idle |
| Item goes out of stock mid-session | Next add-to-cart returns 409 → show "Item no longer available" |
| Cart at max capacity | Show "Cart is full (50 items max)" |
```

### Interaction Spec Checklist

- [ ] Trigger (what user action starts it)
- [ ] All states the UI moves through
- [ ] State transition diagram
- [ ] Timing (animation durations, delays, timeouts)
- [ ] Error states and recovery
- [ ] Edge cases (rapid clicks, concurrent actions, stale state)
- [ ] Feedback mechanism (visual, toast, sound, haptic)

## API Dependencies

Define what data each component needs and where it comes from.

### Format

```markdown
## Page: Product Listing

### Data Requirements

| Component | Data Needed | Source | Loaded When |
|-----------|-------------|--------|-------------|
| ProductCard | name, price, imageUrl, rating, onSale | GET /api/products?page={n} | Page mount |
| FilterSidebar | categories, priceRange, brands | GET /api/products/facets | Page mount |
| Pagination | totalPages, currentPage | Response header from /api/products | After product load |
| CartBadge | itemCount | GET /api/cart/count | App mount (global) |

### API Contracts

**GET /api/products**

Request:
- Query: page (int), category (string[]), minPrice (int), maxPrice (int), sort (string)

Response shape:
```json
{
  "products": [
    {
      "id": "string",
      "name": "string",
      "price": 1999,
      "imageUrl": "string",
      "rating": 4.2,
      "onSale": true,
      "originalPrice": 2499
    }
  ],
  "pagination": {
    "page": 1,
    "totalPages": 12,
    "totalItems": 142
  }
}
```

### Loading States

| Data | Loading Indicator | Empty State |
|------|-------------------|-------------|
| Products | Skeleton cards (6 placeholders) | "No products found. Try different filters." |
| Filters | Skeleton lines (4 placeholders) | Show all filters unchecked |
| Cart count | "—" placeholder | Show "0" |
```

### API Dependencies Checklist

- [ ] Every data field mapped to its API endpoint
- [ ] Request parameters documented
- [ ] Response shape with types
- [ ] Loading states for each data source
- [ ] Empty states when data returns no results
- [ ] Error states when API fails
- [ ] Caching expectations (how fresh must the data be?)

## Pushing Handoff to Implementation Agents

When the handoff is complete, message the implementation agent with:

```
scion message --non-interactive <engineer-agent> "Design handoff ready for <feature name>.

Specs at: out/handoff/
- component-spec.md: <N> components defined with props, states, and layout
- layout-spec.md: responsive layouts for desktop/tablet/mobile
- interaction-spec.md: <N> interactions with state machines
- api-dependencies.md: data requirements and API contracts

Prototype at: out/handoff/assets/prototype.html (if applicable)

Key implementation notes:
- <any non-obvious design decisions>
- <any constraints or gotchas>"
```

## Handoff Quality Checklist

Before sending the handoff:

- [ ] Every component has props, states, and layout defined
- [ ] Every page has responsive wireframes for all breakpoints
- [ ] Every interaction has a state machine and edge cases
- [ ] Every data dependency has an API contract and loading/empty/error states
- [ ] No ambiguous language ("appropriate", "nice", "good") — everything is specific
- [ ] An implementation agent could build this without asking clarifying questions
