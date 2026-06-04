---
name: view-integration-tests
description: >-
  Writing view-level integration tests: mounting components, verifying onMounted
  lifecycle calls to stores/services, verifying data loads and renders correctly.
  Use when testing component behavior beyond unit-level isolation.
---

# View Integration Tests

View integration tests verify that a component, when mounted, correctly integrates with its dependencies — stores, services, composables — and renders the expected result. They sit between unit tests and E2E tests in the pyramid.

## What View Integration Tests Verify

| Check | Unit Test? | View Integration? | E2E? |
|-------|-----------|-------------------|------|
| Pure function returns correct value | Yes | — | — |
| Component calls store on mount | — | **Yes** | — |
| Store data renders in component template | — | **Yes** | — |
| API data flows from service → store → component | — | **Yes** | — |
| User clicks button → store action dispatched | — | **Yes** | — |
| Full user journey through multiple pages | — | — | Yes |

## Pattern: Mount and Verify

### Basic Structure

```typescript
import { mount } from '@vue/test-utils';
import { createTestingPinia } from '@pinia/testing';
import { describe, it, expect, vi } from 'vitest';
import ProductList from '@/views/ProductList.vue';
import { useProductStore } from '@/stores/product';

describe('ProductList', () => {
  it('fetches products on mount', async () => {
    const wrapper = mount(ProductList, {
      global: {
        plugins: [createTestingPinia({ createSpy: vi.fn })],
      },
    });

    const store = useProductStore();

    // Verify the component called the store's fetch action on mount
    expect(store.fetchProducts).toHaveBeenCalledOnce();
  });

  it('renders products from store', async () => {
    const wrapper = mount(ProductList, {
      global: {
        plugins: [
          createTestingPinia({
            createSpy: vi.fn,
            initialState: {
              product: {
                products: [
                  { id: '1', name: 'Widget', price: 999 },
                  { id: '2', name: 'Gadget', price: 1499 },
                ],
              },
            },
          }),
        ],
      },
    });

    // Verify store data renders in the template
    expect(wrapper.text()).toContain('Widget');
    expect(wrapper.text()).toContain('Gadget');
    expect(wrapper.findAll('[data-testid="product-card"]')).toHaveLength(2);
  });
});
```

### React Equivalent

```typescript
import { render, screen, waitFor } from '@testing-library/react';
import { describe, it, expect, vi } from 'vitest';
import ProductList from '@/components/ProductList';
import * as productApi from '@/api/products';

describe('ProductList', () => {
  it('fetches and renders products on mount', async () => {
    const mockProducts = [
      { id: '1', name: 'Widget', price: 999 },
      { id: '2', name: 'Gadget', price: 1499 },
    ];

    vi.spyOn(productApi, 'fetchProducts').mockResolvedValue(mockProducts);

    render(<ProductList />);

    // Verify fetch was called
    expect(productApi.fetchProducts).toHaveBeenCalledOnce();

    // Verify data renders after async load
    await waitFor(() => {
      expect(screen.getByText('Widget')).toBeInTheDocument();
      expect(screen.getByText('Gadget')).toBeInTheDocument();
    });
  });
});
```

## Testing onMounted / useEffect Behavior

### Verify Store Methods Called on Mount

```typescript
it('loads user profile and preferences on mount', async () => {
  const wrapper = mount(DashboardView, {
    global: {
      plugins: [createTestingPinia({ createSpy: vi.fn })],
    },
  });

  const userStore = useUserStore();
  const prefStore = usePreferencesStore();

  // Both stores should be called during mount
  expect(userStore.fetchProfile).toHaveBeenCalledOnce();
  expect(prefStore.loadPreferences).toHaveBeenCalledOnce();
});
```

### Verify Conditional Fetching

```typescript
it('fetches order details only when orderId route param exists', async () => {
  const wrapper = mount(OrderView, {
    global: {
      plugins: [createTestingPinia({ createSpy: vi.fn })],
      mocks: {
        $route: { params: { orderId: '42' } },
      },
    },
  });

  const store = useOrderStore();
  expect(store.fetchOrder).toHaveBeenCalledWith('42');
});

it('does not fetch when orderId is missing', async () => {
  const wrapper = mount(OrderView, {
    global: {
      plugins: [createTestingPinia({ createSpy: vi.fn })],
      mocks: {
        $route: { params: {} },
      },
    },
  });

  const store = useOrderStore();
  expect(store.fetchOrder).not.toHaveBeenCalled();
});
```

## Testing Data Flow: Service → Store → Component

```typescript
it('displays loading state while data fetches', async () => {
  // Store starts in loading state
  const wrapper = mount(ProductList, {
    global: {
      plugins: [
        createTestingPinia({
          createSpy: vi.fn,
          initialState: {
            product: { products: [], loading: true },
          },
        }),
      ],
    },
  });

  expect(wrapper.find('[data-testid="loading-skeleton"]').exists()).toBe(true);
  expect(wrapper.find('[data-testid="product-card"]').exists()).toBe(false);
});

it('displays empty state when no products exist', async () => {
  const wrapper = mount(ProductList, {
    global: {
      plugins: [
        createTestingPinia({
          createSpy: vi.fn,
          initialState: {
            product: { products: [], loading: false },
          },
        }),
      ],
    },
  });

  expect(wrapper.text()).toContain('No products found');
});

it('displays error state when fetch fails', async () => {
  const wrapper = mount(ProductList, {
    global: {
      plugins: [
        createTestingPinia({
          createSpy: vi.fn,
          initialState: {
            product: { products: [], loading: false, error: 'Network error' },
          },
        }),
      ],
    },
  });

  expect(wrapper.text()).toContain('Network error');
  expect(wrapper.find('[data-testid="retry-button"]').exists()).toBe(true);
});
```

## Testing User Interactions → Store Dispatches

```typescript
it('dispatches addToCart when user clicks add button', async () => {
  const wrapper = mount(ProductCard, {
    props: { product: { id: '1', name: 'Widget', price: 999 } },
    global: {
      plugins: [createTestingPinia({ createSpy: vi.fn })],
    },
  });

  const cartStore = useCartStore();

  await wrapper.find('[data-testid="add-to-cart"]').trigger('click');

  expect(cartStore.addItem).toHaveBeenCalledWith('1');
});

it('dispatches filter update and refetches products', async () => {
  const wrapper = mount(FilterSidebar, {
    global: {
      plugins: [createTestingPinia({ createSpy: vi.fn })],
    },
  });

  const store = useProductStore();

  await wrapper.find('[data-testid="category-electronics"]').trigger('click');

  expect(store.setFilter).toHaveBeenCalledWith('category', 'electronics');
  expect(store.fetchProducts).toHaveBeenCalled();
});
```

## Test Setup Helpers

```typescript
// tests/helpers/mount-with-store.ts
import { mount, VueWrapper } from '@vue/test-utils';
import { createTestingPinia } from '@pinia/testing';
import { vi } from 'vitest';
import { createRouter, createMemoryHistory } from 'vue-router';
import { routes } from '@/router';

interface MountOptions {
  initialState?: Record<string, unknown>;
  routePath?: string;
  props?: Record<string, unknown>;
}

export function mountWithStore(
  component: any,
  options: MountOptions = {}
): VueWrapper {
  const router = createRouter({
    history: createMemoryHistory(),
    routes,
  });

  if (options.routePath) {
    router.push(options.routePath);
  }

  return mount(component, {
    props: options.props,
    global: {
      plugins: [
        createTestingPinia({
          createSpy: vi.fn,
          initialState: options.initialState,
        }),
        router,
      ],
    },
  });
}

// Usage:
const wrapper = mountWithStore(ProductList, {
  initialState: { product: { products: mockProducts } },
  routePath: '/products?category=electronics',
});
```

## When to Write View Integration Tests

| Scenario | Test Type |
|----------|-----------|
| Component has `onMounted` that calls a store action | View integration |
| Component renders data from a store | View integration |
| User interaction triggers a store dispatch | View integration |
| Component shows loading/empty/error states based on store | View integration |
| Pure computed value or utility function | Unit test |
| Full multi-page user workflow | Playwright E2E |

## Anti-Patterns

### Testing Implementation, Not Behavior

```typescript
// Bad: testing that a specific internal method exists
expect(wrapper.vm.loadData).toBeDefined();

// Good: testing that the observable effect happened
expect(store.fetchProducts).toHaveBeenCalled();
expect(wrapper.text()).toContain('Widget');
```

### Mounting Without Dependencies

```typescript
// Bad: component crashes because store/router isn't provided
const wrapper = mount(ProductList); // Error: store not found

// Good: provide all required dependencies
const wrapper = mount(ProductList, {
  global: {
    plugins: [createTestingPinia({ createSpy: vi.fn }), router],
  },
});
```

### Testing Too Deep

```typescript
// Bad: testing child component internals from parent test
expect(wrapper.findComponent(ProductCard).vm.isHovered).toBe(false);

// Good: test parent's integration with its own store; test child separately
expect(wrapper.findAll('[data-testid="product-card"]')).toHaveLength(3);
```
