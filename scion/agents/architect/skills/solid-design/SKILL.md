---
name: solid-design
description: >-
  SOLID principles with concrete examples, design smell identification, and refactoring
  guidance. Use when reviewing code for design quality, identifying anti-patterns, or
  recommending refactoring strategies. Also covers DRY, YAGNI, KISS, 12-factor, and
  hexagonal architecture.
---

# SOLID Design Principles

Apply design principles pragmatically — they are guidelines for managing complexity, not laws to follow blindly.

## The SOLID Principles

### S — Single Responsibility Principle
A module should have one, and only one, reason to change.

**Smell:** A class/service that changes whenever ANY of several unrelated requirements change.

```
# Bad: UserService handles auth, profile, notifications, and billing
class UserService:
    def authenticate(self, credentials): ...
    def update_profile(self, data): ...
    def send_notification(self, message): ...
    def process_payment(self, amount): ...

# Good: Each concern is a separate module
class AuthService: ...
class ProfileService: ...
class NotificationService: ...
class BillingService: ...
```

**At the service level:** A microservice that owns "users" should not also own "payments." But a service that handles user registration AND user profile is fine — those change for the same reason (user management).

### O — Open/Closed Principle
Software entities should be open for extension but closed for modification.

**Smell:** Adding a new feature requires modifying existing, tested code.

```
# Bad: Adding a new report type requires editing this function
def generate_report(report_type, data):
    if report_type == "pdf":
        return generate_pdf(data)
    elif report_type == "csv":
        return generate_csv(data)
    elif report_type == "html":  # Had to modify this function
        return generate_html(data)

# Good: New report types are added without modifying existing code
report_generators = {
    "pdf": PdfGenerator,
    "csv": CsvGenerator,
}
# Adding HTML just requires: report_generators["html"] = HtmlGenerator
```

**Practical limit:** Don't create extension points speculatively. Apply O/C when you've seen the axis of change at least twice.

### L — Liskov Substitution Principle
Subtypes must be substitutable for their base types without altering correctness.

**Smell:** Code that checks `isinstance()` or uses type-specific branching on a polymorphic type.

```
# Bad: Square violates LSP as a subtype of Rectangle
class Rectangle:
    def set_width(self, w): self.width = w
    def set_height(self, h): self.height = h

class Square(Rectangle):
    def set_width(self, w): self.width = self.height = w  # Surprise!
    def set_height(self, h): self.width = self.height = h  # Surprise!

# Good: Model the actual relationship
class Shape:
    def area(self): ...

class Rectangle(Shape): ...
class Square(Shape): ...
```

### I — Interface Segregation Principle
Clients should not be forced to depend on interfaces they don't use.

**Smell:** A consumer imports a large interface but only uses 2 of its 15 methods.

```
# Bad: All consumers get the full interface
class DataStore:
    def read(self, key): ...
    def write(self, key, value): ...
    def delete(self, key): ...
    def list_keys(self): ...
    def backup(self): ...
    def restore(self): ...

# Good: Split by consumer need
class ReadableStore:
    def read(self, key): ...
    def list_keys(self): ...

class WritableStore(ReadableStore):
    def write(self, key, value): ...
    def delete(self, key): ...
```

**At the API level:** A service should offer focused endpoints, not a single god-endpoint that does everything.

### D — Dependency Inversion Principle
High-level modules should not depend on low-level modules. Both should depend on abstractions.

**Smell:** A business logic module imports a specific database library, HTTP client, or cloud SDK directly.

```
# Bad: Business logic depends on specific infrastructure
from google.cloud import storage

class ReportService:
    def save_report(self, report):
        client = storage.Client()
        bucket = client.bucket("reports")
        bucket.blob(report.name).upload_from_string(report.content)

# Good: Business logic depends on an abstraction
class ReportService:
    def __init__(self, storage: FileStorage):
        self.storage = storage

    def save_report(self, report):
        self.storage.save(report.name, report.content)

# Infrastructure implements the abstraction
class GcsStorage(FileStorage):
    def save(self, name, content):
        client = storage.Client()
        ...
```

## Complementary Principles

### DRY (Don't Repeat Yourself)
Every piece of knowledge should have a single, authoritative representation.

**But:** Three similar lines is better than a premature abstraction. Wait until you've duplicated something three times before extracting it. "A little copying is better than a little dependency."

### YAGNI (You Aren't Gonna Need It)
Don't build it until you need it.

**Applies to:** Feature flags for features that don't exist, extension points for changes that haven't happened, abstractions over things that aren't varying.

**Does NOT mean:** Skip error handling, ignore security, or skip tests.

### KISS (Keep It Simple, Stupid)
The simplest solution that solves the problem is the best one.

**Test:** Can a new team member understand this code in 15 minutes? If not, simplify.

## 12-Factor App Checklist

| Factor | Principle | GCP Implementation |
|--------|-----------|-------------------|
| 1. Codebase | One codebase, many deploys | Cloud Source Repos / GitHub |
| 2. Dependencies | Explicitly declare and isolate | Container image, requirements.txt |
| 3. Config | Store config in the environment | Secret Manager, env vars via Cloud Run/GKE |
| 4. Backing services | Treat as attached resources | Cloud SQL, Memorystore, Pub/Sub via connection strings |
| 5. Build, release, run | Strictly separate stages | Cloud Build → Artifact Registry → Cloud Deploy |
| 6. Processes | Execute as stateless processes | Cloud Run (stateless), GKE (stateless pods) |
| 7. Port binding | Export services via port binding | Cloud Run auto-binds PORT, GKE via Service |
| 8. Concurrency | Scale out via process model | Cloud Run autoscaling, GKE HPA |
| 9. Disposability | Fast startup, graceful shutdown | Health checks, SIGTERM handling, preStop hooks |
| 10. Dev/prod parity | Keep environments similar | Cloud Deploy: dev → stage → prod pipeline |
| 11. Logs | Treat as event streams | Cloud Logging (stdout → automatic collection) |
| 12. Admin processes | Run as one-off processes | Cloud Run Jobs, kubectl exec |

## Modular Monolith Architecture

A single deployable unit with clear internal module boundaries — the complexity benefits of a monolith with the organizational clarity of services.

### Vertical Slice Architecture

Organize code by feature, not by technical layer. Each slice owns its full stack: API → logic → data access.

```
# Bad: Horizontal layers (changes cut across all layers)
controllers/
  user_controller.py
  order_controller.py
services/
  user_service.py
  order_service.py
repositories/
  user_repository.py
  order_repository.py

# Good: Vertical slices (changes stay within one module)
modules/
  users/
    api.py
    service.py
    repository.py
    models.py
  orders/
    api.py
    service.py
    repository.py
    models.py
  catalog/
    api.py
    service.py
    repository.py
    models.py
```

**Why it matters:** Adding a new feature touches one directory, not every layer. Teams can own modules without stepping on each other.

### Feature-Based Module Decomposition

Each module is a bounded context — it owns a business capability end-to-end.

**Module boundary rules:**
- Modules communicate through **public interfaces only** (explicit API contracts, shared events)
- No module reaches into another's database tables or internal classes
- Shared kernel (common types, utilities) is minimal and versioned
- Each module can have its own data schema (separate tables, or even separate databases later)

```
# Module public interface — this is the ONLY way other modules interact
# modules/orders/public.py

class OrderService:
    def place_order(self, customer_id: str, items: list[OrderItem]) -> OrderId: ...
    def get_order(self, order_id: OrderId) -> Order: ...
    def cancel_order(self, order_id: OrderId) -> None: ...

# Internal implementation — other modules CANNOT import from here
# modules/orders/internal/
#   fulfillment.py
#   pricing.py
#   validation.py
```

### Bounded Contexts Within a Monolith

Apply Domain-Driven Design boundaries without distributed systems overhead.

| Concept | In Microservices | In Modular Monolith |
|---------|-----------------|-------------------|
| Boundary enforcement | Network/process isolation | Module visibility rules, linting |
| Communication | HTTP/gRPC/events | In-process method calls via public API |
| Data isolation | Separate databases | Separate schemas or table prefixes |
| Deployment | Independent | Single deployable unit |
| Transaction boundaries | Saga/eventual consistency | Can use local transactions across modules (but avoid it) |

**Smell:** If two modules share database tables directly, they are not properly bounded — they're just folders.

### Decomposition Readiness

Design module seams so extraction to a separate service is straightforward when (and if) it becomes necessary.

**Readiness checklist for a module:**
- [ ] All inter-module communication goes through the public interface (no internal imports)
- [ ] Module has its own data schema (no shared tables)
- [ ] No in-process transactions spanning multiple modules
- [ ] Module dependencies are explicit and injected
- [ ] Async communication uses events/messages, not direct calls, where possible

**When to extract a module into a service:**
- The module needs to scale independently (different resource profile)
- The module needs a different deployment cadence (team autonomy)
- The module has genuinely different availability requirements
- A separate team will own it long-term

**When NOT to extract:**
- "It feels too big" — size alone is not a reason
- "Microservices are best practice" — they are a trade-off, not a goal
- You only have one team — Conway's Law says you'll get a distributed monolith
- You haven't proven the module boundary is correct yet (extract too early → wrong cuts → painful rewiring)

### Avoiding Premature Distribution

> "If you can't build a well-structured monolith, what makes you think microservices will help?" — Simon Brown

**Costs of premature distribution:**
- Network latency replaces function calls
- Distributed transactions and eventual consistency complexity
- Operational overhead: more deployments, more monitoring, more failure modes
- Testing complexity: integration tests across services are slow and brittle
- Data consistency challenges multiply

**The modular monolith path:**
1. Start with a well-structured monolith with clear module boundaries
2. Enforce boundaries with linting, architecture tests, and code review
3. Monitor which modules actually need independent scaling or deployment
4. Extract only when there is a concrete, demonstrated need
5. The module's public interface becomes the service's API — minimal refactoring

## Design Smell Checklist

| Smell | Symptom | Likely Violation | Refactoring |
|-------|---------|-----------------|-------------|
| God class/service | One module does everything | SRP | Extract classes/services by responsibility |
| Shotgun surgery | One change requires editing many files | SRP (inverted) | Move related code together |
| Feature envy | A method uses more data from another class than its own | SRP | Move method to the class it envies |
| Primitive obsession | Business concepts represented as raw strings/ints | Missing domain model | Introduce value objects |
| Long parameter list | Function takes 5+ parameters | Missing abstraction | Introduce parameter object |
| Refused bequest | Subclass ignores most of parent's behavior | LSP | Use composition instead of inheritance |
| Speculative generality | Abstractions/hooks for changes that haven't happened | YAGNI | Remove until needed |
