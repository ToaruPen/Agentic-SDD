# Class/Module Design Skill

Class and module design principles. Language-agnostic, applicable to both OOP and functional paradigms.

---

## Principles

### SOLID Principles

**Single Responsibility**
- One class/module has one responsibility
- Only one reason to change

**Open/Closed**
- Open for extension
- Closed for modification

**Liskov Substitution**
- Derived types are substitutable for base types
- Do not break contracts

**Interface Segregation**
- Prefer multiple small interfaces over one large
- Do not depend on unused methods

**Dependency Inversion**
- High-level does not depend on low-level
- Both depend on abstractions

### Additional Principles

**Composition over Inheritance**
- Use inheritance only for is-a relationships
- Use composition for has-a relationships

**Law of Demeter**
- Talk only to immediate friends
- Avoid method chaining

---

## Cohesion and Coupling

### Cohesion (higher is better)

**Functional cohesion**
- Description: Performs single function
- Example: calculate_tax()
- Rating: Best

**Sequential cohesion**
- Description: Output feeds next input
- Example: parse then validate then save
- Rating: Good

**Communicational cohesion**
- Description: Operates on same data
- Example: User CRUD operations
- Rating: Acceptable

**Coincidental cohesion**
- Description: Unrelated functions grouped
- Example: Utils, Helpers
- Rating: Avoid

### Coupling (lower is better)

**Data coupling**
- Description: Pass simple data
- Rating: Best

**Stamp coupling**
- Description: Pass structures
- Problem: More info than needed

**Control coupling**
- Description: Flags change behavior
- Problem: Knows too much about internals

**Content coupling**
- Description: Direct internal reference
- Rating: Worst - avoid

---

## Design Patterns

### Creational Patterns

**Factory**
- Purpose: Abstract object creation
- Use when: Complex creation logic, runtime type determination
- Structure: Client calls Factory, Factory creates Product

**Builder**
- Purpose: Stepwise construction of complex objects
- Use when: Many optional parameters, immutable objects

### Structural Patterns

**Adapter**
- Purpose: Connect incompatible interfaces
- Use when: Legacy code with new interface, wrapping third-party libraries
- Structure: Client calls Adapter, Adapter calls Adaptee

**Repository**
- Purpose: Abstract data access
- Use when: Hide data source, improve testability
- Structure: Domain depends on Repository Interface, Implementation implements Interface

### Behavioral Patterns

**Strategy**
- Purpose: Switch algorithms
- Use when: Choose from multiple implementations, reduce conditional branching
- Structure: Context uses Strategy Interface, Concrete Strategies implement Interface

**Observer**
- Purpose: Notify state changes
- Use when: One-to-many dependencies, event-driven architecture

---

## Module Boundaries

### Public API Design

Principles:
- Minimal interface
- Hide implementation details
- Stable interface

Good example:
- save(entity) exposes only what to save

Bad example:
- openConnection(), executeSQL(), closeConnection() exposes implementation

### Dependency Direction

Depend toward stability. Recommended layer structure:

1. UI layer depends on Application layer
2. Application layer depends on Domain layer
3. Domain layer has no external dependencies
4. Infrastructure layer implements interfaces defined by Domain

Key rule: Domain layer is the most stable and has no outward dependencies.

---

## Refactoring Indicators

**God class**
- Description: One class with too many responsibilities
- Action: Split by responsibility

**Feature envy**
- Description: Heavy use of another class's data
- Action: Move method to that class

**Shotgun surgery**
- Description: One change requires many file edits
- Action: Consolidate related functionality

**Primitive obsession**
- Description: Overuse of primitive types
- Action: Introduce value objects

**Long parameter list**
- Description: Too many parameters
- Action: Introduce parameter object

---

## Checklist

### Design phase

- [ ] Each class/module has clear responsibility
- [ ] Dependencies point toward stability
- [ ] Interfaces are minimal
- [ ] Design is testable

### Implementation phase

- [ ] Using only public APIs
- [ ] Appropriate abstraction level
- [ ] No duplication (DRY)

### Review phase

- [ ] No SOLID principle violations
- [ ] No circular dependencies
- [ ] No over-abstraction

---

## Anti-patterns

**God class**
- Problem: Hard to change, hard to test
- Alternative: Split by single responsibility

**Anemic domain model**
- Problem: Logic scattered
- Alternative: Add behavior to domain

**Circular dependency**
- Problem: Change propagation
- Alternative: Organize dependency direction

**Premature abstraction**
- Problem: Unnecessary complexity
- Alternative: Abstract on third occurrence

**Deep inheritance**
- Problem: Hard to understand, fragile
- Alternative: Use composition

---

## Related

- `skills/tdd-protocol.md` - domain model separation
- `skills/api-endpoint.md` - API design
- `skills/testing.md` - testability
