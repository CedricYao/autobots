---
name: cli-verification
description: >-
  Run CLI commands against deployed services, validate output format and content,
  verify CLI matches API responses. Use as the second verification layer after
  contract tests.
---

# CLI Verification

## Purpose

The CLI is the agent's way of verifying the system works end-to-end. It runs in seconds, requires no browser, and produces output an agent can parse and validate.

## Verification Pattern

```bash
# 1. Run the CLI command
$ sre-discover probe boutique-demo-22 --domain logging --format json

# 2. Validate the output structure
$ sre-discover probe boutique-demo-22 --domain logging --format json | jq 'keys'
["domain", "findings", "gaps", "score"]

# 3. Validate specific values
$ sre-discover probe boutique-demo-22 --domain logging --format json | jq '.score'
45  # Must be 0-100

# 4. Validate real data
$ sre-discover probe boutique-demo-22 --domain logging --format json | jq '.findings | length'
5  # Must be > 0

# 5. Validate error handling
$ sre-discover probe INVALID_PROJECT --domain logging 2>&1; echo "exit: $?"
Error: Project "INVALID_PROJECT" not found
exit: 1
```

## CLI Test Script

```bash
#!/usr/bin/env bash
# tests/cli/verify-cli.sh — Run after every merge
set -euo pipefail

PASS=0
FAIL=0

check() {
  local desc="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    echo "  PASS: $desc"
    ((PASS++))
  else
    echo "  FAIL: $desc"
    ((FAIL++))
  fi
}

echo "=== CLI Verification ==="

# Happy path
check "probe returns exit 0" \
  sre-discover probe boutique-demo-22 --domain logging

check "probe JSON is valid" \
  sre-discover probe boutique-demo-22 --domain logging --format json

check "probe score is integer" \
  bash -c 'sre-discover probe boutique-demo-22 --domain logging --format json | jq -e ".score | type == \"number\""'

check "probe has findings" \
  bash -c 'sre-discover probe boutique-demo-22 --domain logging --format json | jq -e ".findings | length > 0"'

# Error handling
check "invalid project returns exit 1" \
  bash -c '! sre-discover probe INVALID --domain logging 2>/dev/null'

check "invalid domain returns exit 1" \
  bash -c '! sre-discover probe boutique-demo-22 --domain fake 2>/dev/null'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

## CLI vs API Consistency

```python
# tests/cli/test_cli_api_match.py
import subprocess
import json
import httpx

def test_cli_output_matches_api(api_url):
    """CLI and API must return equivalent data."""
    # Run CLI
    result = subprocess.run(
        ["sre-discover", "probe", "boutique-demo-22",
         "--domain", "logging", "--format", "json"],
        capture_output=True, text=True
    )
    assert result.returncode == 0
    cli_data = json.loads(result.stdout)

    # Run API
    response = httpx.post(f"{api_url}/api/v1/discovery/probe", json={
        "project_id": "boutique-demo-22", "domain": "logging"
    })
    api_data = response.json()

    # Same structure and data
    assert cli_data["domain"] == api_data["domain"]
    assert abs(cli_data["score"] - api_data["score"]) <= 5
    assert len(cli_data["findings"]) == len(api_data["findings"])
```

## Verification Frequency

| Event | Run What |
|-------|----------|
| Every merge to main | Contract tests + CLI verify script |
| Every deployment | Contract tests + CLI + schemathesis against deployed URL |
| Sprint checkpoint | All above + Playwright smoke (if UI exists) |

The validation loop runs in seconds:
- Contract tests: 3-5 seconds
- CLI verification: 5-10 seconds
- Schemathesis fuzz: 15-30 seconds
- Total: under 60 seconds, fully automated
