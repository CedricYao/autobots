---
name: playwright-ci
description: >-
  Running Playwright smoke tests against builds: route-renders-content checks,
  automated CUJ execution against staging, and CI pipeline integration.
  Use when setting up automated UI validation in CI/CD pipelines.
---

# Playwright CI Smoke Tests

## Route-Renders-Content Checks

Lightweight tests that verify every route renders its expected content — the fastest way to catch broken builds before deeper testing.

### Pattern

```typescript
// tests/smoke/routes.spec.ts
import { test, expect } from '@playwright/test';

const routes = [
  { path: '/', expectedText: 'Welcome', title: /Home/ },
  { path: '/login', expectedText: 'Sign In', title: /Login/ },
  { path: '/products', expectedText: 'Products', title: /Products/ },
  { path: '/cart', expectedText: 'Your Cart', title: /Cart/ },
  { path: '/about', expectedText: 'About Us', title: /About/ },
];

for (const route of routes) {
  test(`${route.path} renders content`, async ({ page }) => {
    const response = await page.goto(route.path);

    // Route responds successfully
    expect(response?.status()).toBeLessThan(400);

    // Page has expected title
    await expect(page).toHaveTitle(route.title);

    // Key content is visible (not just in DOM — actually rendered)
    await expect(page.getByText(route.expectedText).first()).toBeVisible();

    // No console errors
    const errors: string[] = [];
    page.on('console', msg => {
      if (msg.type() === 'error') errors.push(msg.text());
    });
    expect(errors).toHaveLength(0);
  });
}
```

### What Smoke Tests Verify

| Check | Why |
|-------|-----|
| HTTP status < 400 | Route exists and server responds |
| Title matches | Correct page component rendered |
| Key text visible | Content loaded, not blank screen |
| No console errors | No runtime crashes on mount |
| No network failures | API calls succeed (or are properly handled) |

### What Smoke Tests Do NOT Verify

- User interactions (clicking, typing, submitting)
- Business logic correctness
- Visual appearance
- Edge cases or error paths

Those belong in full Playwright test suites, not smoke checks.

## Critical User Journey (CUJ) Tests

Automated execution of the most important user workflows against a staging environment.

### CUJ Structure

```typescript
// tests/cuj/purchase-flow.spec.ts
import { test, expect } from '@playwright/test';

test.describe('CUJ: Purchase Flow', () => {
  test.describe.configure({ retries: 2 });

  test('user browses, adds to cart, and checks out', async ({ page }) => {
    // Step 1: Browse products
    await page.goto('/products');
    await expect(page.getByTestId('product-card')).not.toHaveCount(0);

    // Step 2: View product detail
    await page.getByTestId('product-card').first().click();
    await expect(page.getByTestId('product-detail')).toBeVisible();

    // Step 3: Add to cart
    await page.getByRole('button', { name: 'Add to Cart' }).click();
    await expect(page.getByTestId('cart-badge')).toContainText('1');

    // Step 4: View cart
    await page.getByRole('link', { name: 'Cart' }).click();
    await expect(page.getByTestId('cart-item')).toHaveCount(1);

    // Step 5: Proceed to checkout
    await page.getByRole('button', { name: 'Checkout' }).click();
    await expect(page.getByLabel('Email')).toBeVisible();
  });
});
```

### CUJ Inventory

Define your CUJs as the workflows that, if broken, mean the product is unusable:

```typescript
// tests/cuj/index.ts — CUJ registry
export const CRITICAL_USER_JOURNEYS = [
  {
    name: 'Sign Up → First Use',
    file: 'signup-flow.spec.ts',
    priority: 'P0',
    maxDuration: '30s',
  },
  {
    name: 'Login → Dashboard',
    file: 'login-flow.spec.ts',
    priority: 'P0',
    maxDuration: '15s',
  },
  {
    name: 'Browse → Purchase',
    file: 'purchase-flow.spec.ts',
    priority: 'P0',
    maxDuration: '45s',
  },
  {
    name: 'Search → Find Product',
    file: 'search-flow.spec.ts',
    priority: 'P1',
    maxDuration: '20s',
  },
];
```

## CI Integration

### GitHub Actions Workflow

```yaml
# .github/workflows/playwright-smoke.yml
name: Playwright Smoke Tests

on:
  deployment_status:
  workflow_dispatch:
    inputs:
      target_url:
        description: 'URL to test against'
        required: true

jobs:
  smoke:
    if: github.event.deployment_status.state == 'success' || github.event_name == 'workflow_dispatch'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Install Playwright browsers
        run: npx playwright install --with-deps chromium

      - name: Run smoke tests
        env:
          BASE_URL: ${{ github.event.deployment_status.target_url || github.event.inputs.target_url }}
        run: npx playwright test tests/smoke/ --project=chromium

      - name: Run CUJ tests
        if: success()
        env:
          BASE_URL: ${{ github.event.deployment_status.target_url || github.event.inputs.target_url }}
        run: npx playwright test tests/cuj/ --project=chromium

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: playwright-report
          path: playwright-report/
          retention-days: 7
```

### Playwright Config for CI

```typescript
// playwright.config.ts
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  timeout: 30_000,
  expect: { timeout: 10_000 },
  fullyParallel: true,

  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 2 : undefined,
  reporter: process.env.CI
    ? [['github'], ['html', { open: 'never' }]]
    : [['html']],

  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },

  projects: [
    {
      name: 'smoke',
      testDir: './tests/smoke',
      timeout: 15_000,
    },
    {
      name: 'cuj',
      testDir: './tests/cuj',
      timeout: 60_000,
      dependencies: ['smoke'],
    },
  ],
});
```

### Test Ordering in CI

```
1. Smoke tests run first (fast — 10-30 seconds)
   → If smoke fails, skip CUJs (the build is fundamentally broken)

2. CUJ tests run second (slower — 1-3 minutes)
   → If CUJs fail, block promotion to next environment

3. Full Playwright suite runs on staging (slowest — 5-15 minutes)
   → If full suite fails, block production deployment
```

### Targeting Different Environments

```typescript
// Use BASE_URL to target any environment
// Local:    BASE_URL=http://localhost:3000
// Dev:      BASE_URL=https://app-dev-xxx.run.app
// Staging:  BASE_URL=https://app-staging-xxx.run.app
// Prod:     BASE_URL=https://app.example.com

// In CI, BASE_URL comes from deployment_status event or workflow input
```

## Test Data for CI

```typescript
// tests/fixtures/test-data.ts
// Seed data that must exist in the target environment

export const TEST_USER = {
  email: process.env.TEST_USER_EMAIL || 'smoke-test@example.com',
  password: process.env.TEST_USER_PASSWORD || 'test-password-123',
};

// Use API to reset state before CUJ runs
test.beforeAll(async ({ request }) => {
  await request.post(`${process.env.BASE_URL}/api/test/reset`, {
    headers: { 'X-Test-Key': process.env.TEST_API_KEY || '' },
  });
});
```
