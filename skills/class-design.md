# Class/Module Design Skill

Class and module design principles. Language-agnostic, applicable to both OOP and functional paradigms.

---

## Principles

### SOLID Principles

1. **Single Responsibility**
   - One class/module has one responsibility
   - Only one reason to change

2. **Open/Closed**
   - Open for extension
   - Closed for modification

3. **Liskov Substitution**
   - Derived types are substitutable for base types
   - Do not break contracts

4. **Interface Segregation**
   - Prefer multiple small interfaces over one large
   - Do not depend on unused methods

5. **Dependency Inversion**
   - High-level does not depend on low-level
   - Both depend on abstractions

### Additional Principles

6. **Composition over Inheritance**
   - Use inheritance only for is-a relationships
   - Use composition for has-a relationships

7. **Law of Demeter**
   - Talk only to immediate friends
   - Avoid method chaining

---

## Cohesion & Coupling

### Cohesion (higher is better)

| Level | Description | Example |
|-------|-------------|---------|
| Functional | Performs single function | calculate_tax() |
| Sequential | Output feeds next input | parse -> validate -> save |
| Communicational | Operates on same data | User CRUD |
| Coincidental | Unrelated functions grouped | Utils, Helpers |

Target: Functional > Sequential > Communicational

### Coupling (lower is better)

| Level | Description | Problem |
|-------|-------------|---------|
| Data | Pass simple data | Good |
| Stamp | Pass structures | More info than needed |
| Control | Flags change behavior | Knows too much about internals |
| Content | Direct internal reference | Very bad |

Target: Data coupling

---

## Design Patterns

### Creational Patterns

**Factory**

Purpose: Abstract object creation
Use when:
  - Complex creation logic
  - Runtime type determination

Structure:
  Client -> Factory -> Product

**Builder**

Purpose: Stepwise construction of complex objects
Use when:
  - Many optional parameters
  - Immutable objects

### Structural Patterns

**Adapter**

Purpose: Connect incompatible interfaces
Use when:
  - Legacy code with new interface
  - Wrapping third-party libraries

Structure:
  Client -> Adapter -> Adaptee

**Repository**

Purpose: Abstract data access
Use when:
  - Hide data source
  - Improve testability

Structure:
  Domain -> Repository Interface <- Repository Implementation

### Behavioral Patterns

**Strategy**

Purpose: Switch algorithms
Use when:
  - Choose from multiple implementations
  - Reduce conditional branching

Structure:
  Context -> Strategy Interface <- Concrete Strategies

**Observer**

Purpose: Notify state changes
Use when:
  - One-to-many dependencies
  - Event-driven architecture

---

## Module Boundaries

### Public API Design

Principles:
  - Minimal interface
  - Hide implementation details
  - Stable interface

Good:
  save(entity) - exposes only what to save

Bad:
  openConnection(), executeSQL(), closeConnection() - exposes implementation

### Dependency Direction

Depend toward stability:

```
UI -> Application -> Domain -> (Nothing)
           |
           v
    Infrastructure
```

Domain layer has no external dependencies.

---

## Refactoring Indicators

| Indicator | Description | Action |
|-----------|-------------|--------|
| God class | One class with too many responsibilities | Split by responsibility |
| Feature envy | Heavy use of another class's data | Move method |
| Shotgun surgery | One change requires many file edits | Consolidate related functionality |
| Primitive obsession | Overuse of primitive types | Introduce value objects |
| Long parameter list | Too many parameters | Introduce parameter object |

---

## Checklist

### Design phase

- [ ] Each class/module has clear responsibility
- [ ] Dependencies point toward stability
- [ ] Interfaces are minimal
- [ ] Design is testable

### Implementation phase

- [ ] Using only public APIs (no internal dependencies)
- [ ] Appropriate abstraction level
- [ ] No duplication (DRY)

### Review phase

- [ ] No SOLID principle violations
- [ ] No circular dependencies
- [ ] No over-abstraction

---

## Anti-patterns

| Pattern | Problem | Alternative |
|---------|---------|-------------|
| God class | Hard to change, hard to test | Split by single responsibility |
| Anemic domain model | Logic scattered | Add behavior to domain |
| Circular dependency | Change propagation | Organize dependency direction |
| Premature abstraction | Unnecessary complexity | Abstract on third occurrence |
| Deep inheritance | Hard to understand, fragile | Use composition |

---

## Related

- `skills/tdd-protocol.md` - domain model separation
- `skills/api-endpoint.md` - API design
- `skills/testing.md` - testability
