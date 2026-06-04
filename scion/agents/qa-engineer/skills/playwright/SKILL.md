---
name: playwright
description: >-
  Playwright test structure, page object model, happy path and error path coverage,
  async handling, CI integration, and test data management. Use when writing or
  reviewing Playwright E2E tests.
---

# Playwright Testing

Every story ships with Playwright tests covering happy path AND error path. Non-negotiable.

## Test Structure

```typescript
import { test, expect } from '@playwright/test';

test.describe('Feature: Checkout', () => {

  test('happy path: user completes purchase', async ({ page }) => {
    // Given: user has items in cart
    await page.goto('/cart');
    await expect(page.getByTestId('cart-item')).toHaveCount(2);

    // When: user completes checkout
    await page.getByRole('button', { name: 'Checkout' }).click();
    await page.getByLabel('Card number').fill('4242424242424242');
    await page.getByLabel('Expiry').fill('12/28');
    await page.getByLabel('CVC').fill('123');
    await page.getByRole('button', { name: 'Pay' }).click();

    // Then: confirmation appears
    await expect(page.getByText('Order confirmed')).toBeVisible();
    await expect(page.getByTestId('order-number')).toBeVisible();
  });

  test('error path: payment with declined card', async ({ page }) => {
    await page.goto('/cart');
    await page.getByRole('button', { name: 'Checkout' }).click();
    await page.getByLabel('Card number').fill('4000000000000002');
    await page.getByLabel('Expiry').fill('12/28');
    await page.getByLabel('CVC').fill('123');
    await page.getByRole('button', { name: 'Pay' }).click();

    await expect(page.getByText('Your card was declined')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Pay' })).toBeEnabled();
  });

});
```

### Naming Convention

```typescript
// Pattern: describe what the user experiences
test('happy path: user completes purchase')
test('error path: payment with declined card')
test('error path: checkout with empty cart shows message')
test('edge case: removing last item returns to shop')
```

## Page Object Model

Encapsulate page interaction in page objects to reduce duplication and improve maintainability.

```typescript
// pages/login.page.ts
export class LoginPage {
  constructor(private page: Page) {}

  async goto() {
    await this.page.goto('/login');
  }

  async login(email: string, password: string) {
    await this.page.getByLabel('Email').fill(email);
    await this.page.getByLabel('Password').fill(password);
    await this.page.getByRole('button', { name: 'Sign In' }).click();
  }

  async expectError(message: string) {
    await expect(this.page.getByRole('alert')).toContainText(message);
  }

  async expectLoggedIn() {
    await expect(this.page).toHaveURL('/dashboard');
  }
}

// tests/login.spec.ts
test('happy path: valid credentials', async ({ page }) => {
  const login = new LoginPage(page);
  await login.goto();
  await login.login('alice@example.com', 'validpass');
  await login.expectLoggedIn();
});

test('error path: wrong password', async ({ page }) => {
  const login = new LoginPage(page);
  await login.goto();
  await login.login('alice@example.com', 'wrongpass');
  await login.expectError('Invalid email or password');
});
```

### Page Object Rules

- Page objects expose **actions** (`login`, `addToCart`, `search`), not raw selectors
- Assertions live in the **test**, not the page object — except for convenience methods like `expectError`
- One page object per page/component — don't create god objects
- Page objects never contain test logic (no `if`, no loops for test flow)

## Locator Strategy

Prefer locators in this order (most resilient to least):

| Priority | Locator | Example | Why |
|----------|---------|---------|-----|
| 1st | Role | `getByRole('button', { name: 'Submit' })` | Accessible, user-facing |
| 2nd | Label | `getByLabel('Email')` | Tied to visible label text |
| 3rd | Text | `getByText('Welcome back')` | What the user sees |
| 4th | Test ID | `getByTestId('cart-count')` | Stable, decoupled from UI |
| Last | CSS/XPath | `page.locator('.btn-primary')` | Brittle, breaks on refactor |

```typescript
// Good: resilient locators
await page.getByRole('button', { name: 'Add to Cart' }).click();
await page.getByLabel('Search').fill('headphones');
await expect(page.getByText('No results found')).toBeVisible();

// Bad: brittle locators
await page.locator('#add-btn').click();
await page.locator('input.search-field').fill('headphones');
await expect(page.locator('.empty-state > p:first-child')).toBeVisible();
```

## Happy Path + Error Path Checklist

For every story, write Playwright tests covering:

### Happy Path (Required)

- [ ] User completes the primary workflow successfully
- [ ] Correct success feedback is shown (message, redirect, updated state)
- [ ] Data is persisted (page reload shows the change)

### Error Paths (Required)

- [ ] Form validation errors are shown inline with clear messages
- [ ] Server errors show user-friendly feedback (not stack traces)
- [ ] The UI recovers — user can retry without refreshing
- [ ] Unauthorized actions show appropriate error (not a blank page)

### Edge Cases (When Applicable)

- [ ] Empty state: what does the page look like with no data?
- [ ] Loading state: does a spinner/skeleton appear during async operations?
- [ ] Maximum values: long text, many items, large numbers
- [ ] Concurrent actions: double-click submit, rapid navigation

## Async Handling

### Wait for Conditions, Not Time

```typescript
// Bad: arbitrary sleep
await page.click('#submit');
await page.waitForTimeout(3000);  // NEVER DO THIS
await expect(page.locator('.result')).toBeVisible();

// Good: wait for the condition
await page.getByRole('button', { name: 'Submit' }).click();
await expect(page.getByText('Saved successfully')).toBeVisible();
```

### Common Async Patterns

```typescript
// Wait for navigation
await Promise.all([
  page.waitForURL('/dashboard'),
  page.getByRole('button', { name: 'Sign In' }).click(),
]);

// Wait for network request to complete
const responsePromise = page.waitForResponse('**/api/orders');
await page.getByRole('button', { name: 'Place Order' }).click();
const response = await responsePromise;
expect(response.status()).toBe(201);

// Wait for element to disappear (loading spinner)
await expect(page.getByTestId('loading-spinner')).toBeHidden();

// Wait for element count
await expect(page.getByTestId('search-result')).toHaveCount(5);
```

## CI Integration

### Playwright Config for CI

```typescript
// playwright.config.ts
export default defineConfig({
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: process.env.CI ? 'github' : 'html',
  use: {
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
});
```

### CI Best Practices

- **Retries:** Allow 1-2 retries in CI to absorb transient failures, but investigate any test that needs them regularly
- **Traces:** Capture traces on failure — they show every action, network request, and screenshot
- **Parallelism:** Run tests in parallel locally, serial in CI if resource-constrained
- **Artifacts:** Upload screenshots and traces as CI artifacts for debugging failures

## Test Data Management

### Principles

1. **Each test creates its own data.** Never depend on pre-existing database state.
2. **Tests clean up after themselves.** Or use transaction rollback / container reset.
3. **Use factories, not fixtures.** Factories make intent clear; fixtures hide it.

### Patterns

```typescript
// API-based setup (preferred for speed)
test.beforeEach(async ({ request }) => {
  await request.post('/api/test/reset');
  await request.post('/api/test/seed', {
    data: { users: [{ email: 'test@example.com', password: 'pass123' }] }
  });
});

// UI-based setup (when no API is available)
test.beforeEach(async ({ page }) => {
  await page.goto('/signup');
  await page.getByLabel('Email').fill('test@example.com');
  await page.getByLabel('Password').fill('pass123');
  await page.getByRole('button', { name: 'Create Account' }).click();
  await expect(page).toHaveURL('/dashboard');
});
```

### What NOT to Do

```typescript
// Bad: depends on other tests having run
test('edit user profile', async ({ page }) => {
  // Assumes "create user" test already ran — FRAGILE
  await page.goto('/profile');
  // ...
});

// Bad: depends on production data
test('search for products', async ({ page }) => {
  await page.goto('/search?q=widget');
  // Assumes "widget" exists in the database — FRAGILE
});
```
