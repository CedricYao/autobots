---
name: clean-code
description: >-
  Clean code principles: naming rules, function design, comment philosophy,
  formatting, and error handling. Use when writing or reviewing code for
  readability, maintainability, and clarity.
---

# Clean Code

Code is read far more often than it is written. Optimize for the reader.

## Naming

### Rules

1. **Names reveal intent.** The name should answer: why does this exist, what does it do, how is it used?
2. **Names are searchable.** Single-letter variables and magic numbers are not.
3. **Names match scope.** Short names for small scopes (`i` in a 3-line loop), descriptive names for large scopes.
4. **No encoding.** No Hungarian notation (`strName`), no type prefixes (`IInterface`), no member prefixes (`m_value`).
5. **Pronounceable.** If you can't say it in conversation, rename it.

### Examples

```python
# Bad → Good

d = 7                      → retention_days = 7
lst = get_data()           → active_users = fetch_active_users()
flag = True                → is_verified = True
temp = calculate(x, y)     → monthly_revenue = calculate_revenue(sales, returns)
def proc(r):               → def approve_request(request):
class DataManager:         → class UserRepository:
```

### Class Names

Classes are nouns: `Account`, `OrderProcessor`, `PriceCalculator`. Not verbs, not vague (`Manager`, `Handler`, `Data`, `Info`, `Processor` without context).

### Method Names

Methods are verbs: `save`, `calculate_total`, `validate_address`. Boolean methods are predicates: `is_valid`, `has_items`, `can_withdraw`.

## Function Design

### Small

A function should do one thing. If you can extract a meaningful chunk from it, it's doing more than one thing.

**Guideline:** If a function is longer than 20 lines, look for extraction opportunities. This is a guideline, not a law — a 25-line function that reads clearly is better than five 5-line functions with confusing indirection.

### Single Level of Abstraction

Every line in a function should be at the same level of abstraction.

```python
# Bad: mixes high-level flow with low-level details
def process_signup(form):
    email = form["email"].strip().lower()
    if not re.match(r"^[^@]+@[^@]+\.[^@]+$", email):
        raise ValidationError("Invalid email")
    user = User(email=email)
    db.session.add(user)
    db.session.commit()
    send_welcome_email(user)

# Good: each line is at the same level
def process_signup(form):
    email = parse_email(form)
    user = create_user(email)
    send_welcome_email(user)
```

### No Side Effects

A function named `validate_password` should not also initialize a session. A function named `check_availability` should not also reserve the item.

### Arguments

- **Zero arguments (niladic):** Best
- **One argument (monadic):** Good — asking a question (`is_valid(email)`) or transforming (`parse(json_string)`)
- **Two arguments (dyadic):** Acceptable — natural pairs (`Point(x, y)`, `assert_equal(expected, actual)`)
- **Three or more:** Introduce a parameter object

### Command-Query Separation

A function should either **do something** (command) or **answer something** (query), not both.

```python
# Bad: does it set the attribute AND return success?
if set_attribute("username", "alice"):
    ...

# Good: separate the query from the command
if attribute_exists("username"):
    set_attribute("username", "alice")
```

## Comment Philosophy

### The Goal: No Comments Needed

```python
# Bad: comment explains what the code does
# Check if the user is eligible for a discount
if user.account_age_days > 365 and user.total_purchases > 1000:

# Good: the code explains itself
if user.is_eligible_for_loyalty_discount():
```

### When Comments ARE Appropriate

| Type | Example |
|------|---------|
| **Legal/license** | Copyright headers required by policy |
| **Why, not what** | `# Timezone offset required by legacy billing API` |
| **Warning of consequence** | `# This test takes 30 minutes to run` |
| **TODO** | `# TODO: remove after migration completes (2026-Q3)` — with a deadline |
| **Public API docs** | One-line docstrings for public interfaces |

### Comments That Are Code Smells

| Type | Fix |
|------|-----|
| Restating the code | Delete the comment |
| Explaining a complex expression | Extract to a well-named function |
| Commenting out code | Delete it — git remembers |
| Journal comments ("added X on date") | That's what git log is for |
| Section dividers (`# === HELPERS ===`) | Extract to a separate module |
| Apologetic comments (`# sorry, this is a hack`) | Fix the hack |

## Formatting

### Vertical

- Related code stays together (no blank lines between tightly coupled lines)
- Separate concepts with blank lines
- Caller above callee (read top-down like a newspaper)
- Variables declared close to where they're used

### Horizontal

- Keep lines under 100 characters — if a line is too long, the expression is too complex
- Use whitespace to show association: `total = price * quantity` not `total=price*quantity`
- Consistent indentation — follow the project convention

### File Size

- Prefer small files (under 300 lines)
- A file that's growing past 500 lines probably has multiple responsibilities — consider splitting

## Error Handling

### Use Exceptions, Not Error Codes

```python
# Bad: caller must remember to check
result = withdraw(account, amount)
if result == -1:
    # handle error

# Good: exception is impossible to ignore
try:
    withdraw(account, amount)
except InsufficientFunds:
    # handle error
```

### Don't Return None to Signal Errors

```python
# Bad: caller might forget to check
def find_user(user_id):
    if user_id not in users:
        return None  # Caller gets AttributeError later

# Good: be explicit about the failure case
def find_user(user_id):
    if user_id not in users:
        raise UserNotFound(user_id)
```

### Write the Try-Catch First

When writing code that can fail, start with the error handling test:

```python
# TDD approach to error handling:
# 1. Write a test for the error case
def test_withdraw_from_empty_account_raises_error():
    account = Account(balance=0)
    with pytest.raises(InsufficientFunds):
        account.withdraw(50)

# 2. Then write a test for the success case
def test_withdraw_reduces_balance():
    account = Account(balance=100)
    account.withdraw(50)
    assert account.balance == 50
```

### Don't Catch Generic Exceptions

```python
# Bad: swallows everything, including bugs
try:
    process(data)
except Exception:
    log.error("something went wrong")

# Good: catch what you expect, let bugs propagate
try:
    process(data)
except ValidationError as e:
    log.warning(f"Invalid input: {e}")
```
