---
name: tdd
description: >-
  Spec-first TDD: contract-driven Red/Green/Refactor cycle, OpenAPI as the
  failing test, integration tests against real infrastructure, CLI verification.
  Mocks for unit isolation only, never for system verification.
---

# Spec-First Test-Driven Development

TDD starts at the contract level. The OpenAPI spec is your blueprint. The failing contract test is your first "Red." Implementation is making the contract test pass against real infrastructure.

## The Spec-First TDD Cycle

### Phase 0: Write the Contract (Before Any Code)

```yaml
# openapi.yaml — this IS the requirement
paths:
  /api/v1/products:
    get:
      operationId: listProducts
      parameters:
        - name: category
          in: query
          schema:
            type: string
      responses:
        '200':
          content:
            application/json:
              schema:
                type: object
                required: [products, total]
                properties:
                  products:
                    type: array
                    items:
                      $ref: '#/components/schemas/Product'
                  total:
                    type: integer
```

### Red: Write a Failing Contract Test

```python
import httpx
import jsonschema

def test_list_products_matches_contract(api_url, openapi_spec):
    """Fails because the endpoint doesn't exist yet."""
    response = httpx.get(f"{api_url}/api/v1/products")
    assert response.status_code == 200

    data = response.json()
    schema = openapi_spec["components"]["schemas"]["ProductListResponse"]
    jsonschema.validate(data, schema)

    # Assert data is REAL, not stubbed
    assert len(data["products"]) > 0, "No products — likely stub data"
    assert data["total"] > 0
```

### Green: Implement to Pass the Contract

```python
# Implement the endpoint — the contract test defines what "done" means
@app.get("/api/v1/products")
async def list_products(category: str | None = None) -> ProductListResponse:
    products = await product_repo.list(category=category)
    return ProductListResponse(products=products, total=len(products))
```

### Refactor: Clean Up While Green

Run the contract test after every refactoring step. The contract is your safety net.

## Test Categories

### Contract Tests — "Does the API match the spec?"

```python
def test_response_matches_openapi_schema(api_url, openapi_spec):
    """The response shape must match the OpenAPI spec exactly."""
    response = httpx.get(f"{api_url}/api/v1/products")
    data = response.json()
    schema = openapi_spec["paths"]["/api/v1/products"]["get"]["responses"]["200"]["content"]["application/json"]["schema"]
    jsonschema.validate(data, schema)

def test_error_responses_match_spec(api_url):
    """Error shapes must also match the contract."""
    response = httpx.get(f"{api_url}/api/v1/products/nonexistent")
    assert response.status_code == 404
    data = response.json()
    assert "error" in data
    assert "message" in data
```

### Integration Tests — "Does it work against real infrastructure?"

```python
def test_products_come_from_real_database(api_url):
    """The data must come from real infrastructure, not stubs."""
    response = httpx.get(f"{api_url}/api/v1/products")
    products = response.json()["products"]
    assert len(products) > 0, "No products — is the database seeded?"
    # Real products have real IDs, not placeholder UUIDs
    assert all(p["id"] for p in products)

def test_same_data_from_localhost_and_deployed(api_url, deployed_url):
    """Local and deployed must return equivalent data."""
    local = httpx.get(f"{api_url}/api/v1/products").json()
    deployed = httpx.get(f"{deployed_url}/api/v1/products").json()
    assert local["total"] == deployed["total"]
```

### CLI Tests — "Does the CLI match the API?"

```python
def test_cli_output_matches_api(api_url):
    """CLI and API must return equivalent data."""
    import subprocess, json

    result = subprocess.run(
        ["my-tool", "products", "list", "--format", "json"],
        capture_output=True, text=True
    )
    assert result.returncode == 0
    cli_data = json.loads(result.stdout)

    api_data = httpx.get(f"{api_url}/api/v1/products").json()
    assert cli_data["total"] == api_data["total"]
```

### Unit Tests — "Does the pure logic work?" (Mocks OK here)

```python
def test_discount_calculation():
    """Pure logic — no infrastructure needed."""
    assert calculate_discount(100, percent=10) == 90

def test_product_validation():
    """Validation rules — no infrastructure needed."""
    with pytest.raises(ValidationError):
        Product(name="", price=-1)
```

## FIRST Properties (Updated for Agent-Native)

| Property | Meaning | Agent-Native Twist |
|----------|---------|-------------------|
| **Fast** | Unit tests in ms, contract tests in seconds | Contract tests can take 3-5s — that's fine |
| **Isolated** | Unit tests isolated; contract tests hit real infra | Isolation = unit level only |
| **Repeatable** | Same result every time | Against real infra, seed data must be stable |
| **Self-validating** | Pass or fail, no manual inspection | CLI output is self-validating — no browser needed |
| **Timely** | Written before the code they test | The contract test is written before the endpoint |

## Test Doubles (Restricted Use)

| Double | Permitted For | NOT Permitted For |
|--------|---------------|-------------------|
| Stub | Unit test inputs | API boundary verification |
| Spy | Unit test side effects | Verifying real API calls happened |
| Fake | In-memory repos in unit tests | System-level testing |
| Mock | Isolating pure logic | Contract tests, integration tests, CLI tests |

**The rule:** If a test can pass with in-memory stubs, it proves the stubs work, not the system. At least one test per endpoint must hit real infrastructure.

## Anti-Patterns

### The Stub System

2,600 tests pass. Store tests call `store.loadReport()` directly with hand-crafted data. No test verifies the actual data flow from API to view. The tests verify the agent's assumptions, not reality.

### The Mock Boundary

Tests mock the exact boundary they should be verifying. `mock_gcp_api.return_value = fake_data` — this tests the mock framework, not the GCP integration.

### Activity as Completion

"94/94 stories complete, 2,600 tests pass" — but nobody ran the tests against the deployed service. Test counts are not completion signals. Contract test results against production are.
