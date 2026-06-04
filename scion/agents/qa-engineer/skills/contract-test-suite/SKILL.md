---
name: contract-test-suite
description: >-
  Generate and run contract tests against deployed APIs using pytest, schemathesis,
  and jsonschema. Validates API responses match OpenAPI specs with real data
  assertions. Use as the primary verification layer.
---

# Contract Test Suite

## What Contract Tests Verify

Contract tests are the base of the verification pyramid. They answer: "Does the API response match the OpenAPI spec, with real data, from the real deployed service?"

```python
# The canonical contract test
def test_endpoint_matches_contract(api_url, openapi_spec):
    # 1. Call the REAL deployed API
    response = httpx.post(f"{api_url}/api/v1/discovery/probe", json={
        "project_id": "boutique-demo-22",
        "domain": "logging"
    })

    # 2. Verify HTTP status matches spec
    assert response.status_code == 200

    # 3. Verify response shape matches OpenAPI schema
    data = response.json()
    schema = openapi_spec["components"]["schemas"]["ProbeResult"]
    jsonschema.validate(data, schema)

    # 4. Verify this is REAL data, not stubs
    assert data["score"] > 0, "Score is 0 — likely stub data"
    assert len(data["findings"]) > 0, "No findings — likely stub data"
```

## Test Structure

```python
# tests/contracts/conftest.py
import os
import pytest
import yaml

@pytest.fixture
def api_url():
    url = os.environ.get("API_URL")
    assert url, "API_URL must be set. Use deployed service URL, not localhost."
    return url.rstrip("/")

@pytest.fixture
def openapi_spec():
    with open("openapi.yaml") as f:
        return yaml.safe_load(f)
```

```python
# tests/contracts/test_probe_endpoint.py
import httpx
import jsonschema
import pytest

class TestProbeEndpoint:
    """Contract tests for POST /api/v1/discovery/probe"""

    def test_returns_200_for_valid_request(self, api_url):
        response = httpx.post(f"{api_url}/api/v1/discovery/probe", json={
            "project_id": "boutique-demo-22", "domain": "logging"
        })
        assert response.status_code == 200

    def test_response_matches_schema(self, api_url, openapi_spec):
        response = httpx.post(f"{api_url}/api/v1/discovery/probe", json={
            "project_id": "boutique-demo-22", "domain": "logging"
        })
        schema = openapi_spec["components"]["schemas"]["ProbeResult"]
        jsonschema.validate(response.json(), schema)

    def test_returns_real_data(self, api_url):
        response = httpx.post(f"{api_url}/api/v1/discovery/probe", json={
            "project_id": "boutique-demo-22", "domain": "logging"
        })
        data = response.json()
        assert data["score"] > 0, "Score is 0 — likely stub"
        assert len(data["findings"]) > 0, "No findings — likely stub"

    def test_returns_400_for_invalid_domain(self, api_url):
        response = httpx.post(f"{api_url}/api/v1/discovery/probe", json={
            "project_id": "boutique-demo-22", "domain": "nonexistent"
        })
        assert response.status_code == 400

    def test_returns_403_for_no_permissions(self, api_url):
        response = httpx.post(f"{api_url}/api/v1/discovery/probe", json={
            "project_id": "inaccessible-project", "domain": "logging"
        })
        assert response.status_code == 403
```

## Schemathesis (Automated Fuzz Testing)

```bash
# Run schemathesis against the deployed API
# Generates requests from the OpenAPI spec and validates responses
schemathesis run openapi.yaml \
  --base-url $API_URL \
  --checks all \
  --hypothesis-max-examples 50
```

```yaml
# CI integration
- name: Contract fuzz testing
  run: |
    pip install schemathesis
    schemathesis run openapi.yaml \
      --base-url ${{ vars.API_URL }} \
      --checks all \
      --report
```

## Real Data Assertions

Every contract test must distinguish real data from stubs:

| Assertion | Why |
|-----------|-----|
| `assert len(findings) > 0` | Stubs often return empty arrays |
| `assert score > 0` | Stubs return 0 or hardcoded values |
| `assert "Default" in sink_names` | Real GCP projects have a _Default sink |
| `assert all(f["id"] for f in findings)` | Real data has real IDs |
| `assert data != KNOWN_STUB_RESPONSE` | Detect if stubs are deployed |

## CI Integration

```yaml
# .github/workflows/contract-tests.yml
name: Contract Tests

on:
  push:
    branches: [main]
  deployment_status:

jobs:
  contracts:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - run: pip install httpx pytest jsonschema pyyaml schemathesis

      - name: Run contract tests against deployed service
        env:
          API_URL: ${{ vars.API_URL }}
        run: pytest tests/contracts/ -v --tb=short

      - name: Run schemathesis fuzz tests
        env:
          API_URL: ${{ vars.API_URL }}
        run: schemathesis run openapi.yaml --base-url $API_URL --checks all
```

## What "Verified" Means

| Signal | Meaningful? |
|--------|-------------|
| "94/94 stories complete" | No — measures activity |
| "2,600 tests pass" | No — could be testing stubs |
| "Contract tests pass against localhost" | Partially — proves code works locally |
| **"48/48 contract tests pass against production URL"** | **Yes — proves the deployed system works** |
| **"CLI produces correct output against production"** | **Yes — proves end-to-end flow** |
