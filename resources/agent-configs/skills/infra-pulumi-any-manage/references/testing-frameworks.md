# Testing Frameworks

Pulumi allows testing infrastructure code using standard testing frameworks of the chosen language.

## 1. Unit Tests (Fast, No Cloud)

Uses **Mocks** to simulate cloud resource creation.

- **TypeScript:** `mocha`, `ts-node`.
- **Python:** `pytest`, `unittest`.
- **Go:** `go test`.

### Pattern:
1. Define a mock monitor.
2. Intercept resource creation calls.
3. Return dummy IDs and properties.
4. Assert on the generated properties.

## 2. Integration Tests (Slow, Real Cloud)

Deploys real resources and verifies their behavior.

- **Check:** Use `pulumi.runtime.setAllConfig` to pass parameters.
- **Cleanup:** Ensure resources are destroyed after the test.
- **Tooling:** `pulumi-test` or custom scripts using Automation API.

## 3. Policy-as-Code (CrossGuard)

Verify infrastructure against compliance rules before deployment.

- **Framework:** `CrossGuard`.
- **Languages:** Node.js or Python.
- **Enforcement Levels:**
    - `advisory`: Warning only.
    - `mandatory`: Blocks deployment.

## 4. Automation API Tests

Use Automation API to orchestrate multiple stacks and verify end-to-end flows (e.g., Stack A exports URL -> Stack B consumes URL -> Stack B health check passes).
