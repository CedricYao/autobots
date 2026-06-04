---
name: implement-to-contract
description: >-
  Given an OpenAPI spec and failing contract tests, implement the endpoint.
  Covers spec-to-implementation workflow, Pydantic model generation, CLI-first
  development, and verification against real deployed services.
---

# Implement to Contract

## The Workflow

You receive: an OpenAPI spec and a failing contract test.
You deliver: a passing contract test against the real deployed service and a working CLI command.

```
Input:  openapi.yaml + test_contract.py (RED)
Output: working endpoint + passing test (GREEN) + CLI command
```

### Step 1: Read the Contract

```yaml
# The spec tells you exactly what to build
paths:
  /api/v1/products:
    get:
      parameters:
        - name: category
          in: query
          schema: { type: string }
      responses:
        '200':
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ProductList'
        '400':
          description: Invalid category
```

From this, you know:
- Endpoint: `GET /api/v1/products`
- Input: optional `category` query parameter (string)
- Success: returns `ProductList` schema
- Error: returns 400 for invalid category
- No other behaviors to implement. YAGNI.

### Step 2: Generate Models from Spec

```python
# models.py — Pydantic models matching the OpenAPI schemas
from pydantic import BaseModel

class Product(BaseModel):
    id: str
    name: str
    price: int
    category: str

class ProductList(BaseModel):
    products: list[Product]
    total: int
```

### Step 3: Read the Failing Test

```python
# The test tells you what "pass" looks like
def test_list_products_returns_valid_response(api_url):
    response = httpx.get(f"{api_url}/api/v1/products")
    assert response.status_code == 200
    data = response.json()
    ProductList.model_validate(data)  # Must match Pydantic model
    assert len(data["products"]) > 0  # Must return real data
```

### Step 4: Implement the Minimum to Pass

```python
@app.get("/api/v1/products")
async def list_products(category: str | None = None) -> ProductList:
    products = await db.query_products(category=category)
    return ProductList(products=products, total=len(products))
```

Do not add:
- Pagination (no test demands it)
- Sorting (no test demands it)
- Caching (no test demands it)
- In-memory fallback (defeats the purpose)

### Step 5: Run the Test Against Real Infrastructure

```bash
# Run against local server connected to real DB/APIs
SRE_DISCOVERY_URL=http://localhost:8000 pytest test_contract.py -v

# Then run against the deployed service
SRE_DISCOVERY_URL=https://my-service-xxx.run.app pytest test_contract.py -v
```

Both must pass. If the local test passes but the deployed test fails, you have an environment configuration problem — fix it before moving on.

### Step 6: Build the CLI

```python
# cli.py — thin wrapper over the service layer
import click
import httpx

@click.command()
@click.argument('category', required=False)
@click.option('--format', type=click.Choice(['json', 'text']), default='text')
def products(category, format):
    response = httpx.get(f"{API_URL}/api/v1/products", params={"category": category})
    response.raise_for_status()
    data = response.json()

    if format == 'json':
        click.echo(json.dumps(data, indent=2))
    else:
        click.echo(f"Products: {data['total']}")
        for p in data['products']:
            click.echo(f"  {p['name']} — ${p['price']/100:.2f}")
```

### Step 7: Verify CLI Matches API

```bash
# CLI output must match API output
$ my-tool products --format json | jq '.total'
42

$ curl -s $API_URL/api/v1/products | jq '.total'
42
```

## Real Data Assertions

Every contract test must assert the data is real:

```python
# Bad: accepts stub data
def test_products(api_url):
    response = httpx.get(f"{api_url}/api/v1/products")
    assert response.status_code == 200  # Stubs can return 200 too

# Good: asserts real data
def test_products_returns_real_data(api_url):
    response = httpx.get(f"{api_url}/api/v1/products")
    assert response.status_code == 200
    data = response.json()
    assert len(data["products"]) > 0, "No products — likely stub data"
    assert all(p["id"] for p in data["products"]), "Missing IDs — likely generated data"
```

## Common Mistakes

### Implementing Beyond the Contract

The spec says `GET /products` returns a list. You add filtering, sorting, pagination, and full-text search. None of these have contract tests. None are needed yet. YAGNI.

### Using In-Memory Stores

"I'll use an in-memory store so I can develop without the database." The in-memory store becomes the product. Tests pass against it. It gets deployed. Nobody notices the database is never connected.

### Implementing from a Mockup Instead of a Contract

A visual mockup shows a product grid with images, ratings, and a sale badge. You implement all the UI. The API doesn't have a `rating` field. The mockup implied behavior the contract doesn't specify. Implement to the contract.

### Testing Against Localhost Only

The contract test passes against `localhost:8000`. The deployed service at `my-service.run.app` returns 502 because `DATABASE_URL` isn't set. Run the same test against both environments.
