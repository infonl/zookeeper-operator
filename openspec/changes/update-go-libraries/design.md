## Context

The project has 9 outdated direct dependencies. They fall into two groups with different update risk profiles:

**Low-risk (patch/minor, backwards-compatible API):**
- `logrus` v1.9.0 → v1.9.4 (patch only)
- `go-logr/logr` v1.2.4 → v1.4.3 (minor, stable interface)
- `golang.org/x/net` v0.17.0 → v0.52.0 (stdlib extension, backwards compatible)
- `onsi/gomega` v1.27.7 → v1.39.1 (test-only, minor matcher additions)

**High-risk (must be updated together as an ecosystem):**
- `k8s.io/api`, `k8s.io/apimachinery`, `k8s.io/client-go` v0.27.5 → v0.35.3
- `sigs.k8s.io/controller-runtime` v0.15.2 → v0.23.3
- `operator-framework/operator-lib` v0.11.0 → v0.19.0 (depends on controller-runtime)

The k8s ecosystem libraries are tightly coupled and must be updated atomically — mismatched versions cause runtime panics and compile errors.

## Goals / Non-Goals

**Goals:**
- Update all 9 direct dependencies to their latest versions
- Fix all compilation and API breakage introduced by the updates
- Ensure unit tests pass after the upgrade

**Non-Goals:**
- Migrating from `github.com/onsi/ginkgo` v1 to v2 (separate concern, different module path)
- Updating indirect-only dependencies beyond what `go mod tidy` does automatically
- Updating the Go version itself (covered by `update-go-version` change)

## Decisions

**1. Update the k8s ecosystem atomically**
All of `k8s.io/api`, `k8s.io/apimachinery`, `k8s.io/client-go`, `controller-runtime`, and `operator-lib` must be updated in a single `go get` invocation to avoid version mismatch compile errors. Alternative: staged per-library updates — rejected because k8s libraries cross-import each other and partial updates always break the build.

**2. Update low-risk libraries first, k8s ecosystem second**
Updating the independent low-risk libraries first keeps each step reviewable. If the low-risk updates pass build/test, we proceed to the k8s ecosystem. This avoids conflating unrelated failures.

**3. Fix known breaking callsites first, then address any remaining compilation errors**
Code inspection reveals several specific callsites that will break with certainty — these are documented in "Known Breaking Changes" below. Address these first, then handle any remaining issues reactively.

**4. Target latest patch of each minor series**
We target the latest available version of each library (as reported by `go list -m -u`) rather than a conservative intermediate version, since there's no benefit to a staged approach for a direct-dep-only update.

## Known Breaking Changes
These callsites are predicted to fail compilation based on controller-runtime and operator-lib changelog analysis. Fix these as part of task 2.3.

**1. `ctrl.Options.MetricsBindAddress` removed (`main.go:122`)**
In controller-runtime v0.16, `MetricsBindAddress string` was removed from `ctrl.Options` and moved to a nested struct:
```go
// Before
ctrl.Options{MetricsBindAddress: metricsAddr}
// After
ctrl.Options{Metrics: server.Options{BindAddress: metricsAddr}}
```
Requires adding import `sigs.k8s.io/controller-runtime/pkg/metrics/server`.

**2. `cache.Options.Namespaces` type changed (`main.go:121`, `test/e2e/suite_test.go:90`)**
In controller-runtime v0.16, `Namespaces []string` was replaced with `DefaultNamespaces map[string]cache.Config`:
```go
// Before
cache.Options{Namespaces: managerNamespaces}
// After
cache.Options{DefaultNamespaces: map[string]cache.Config{ns: {}}}
```
Both `main.go` (multi-namespace watch) and `suite_test.go` (single-namespace test env) are affected.

**3. `fake.NewClientBuilder().WithRuntimeObjects()` signature changed (`pkg/utils/leader_test.go:80,105`)**
In newer controller-runtime, `WithRuntimeObjects` changed from `...runtime.Object` to `...client.Object`. The test passes a spread `[]runtime.Object` slice which will no longer compile:
```go
// Before
fake.NewClientBuilder().WithRuntimeObjects([]runtime.Object{pod, cm}...)
// After
fake.NewClientBuilder().WithObjects(pod, cm)
```

**4. `operator-lib/leader.Become()` in `pkg/utils/leader.go:37`**
The `leader` package in operator-lib uses ConfigMap-based leader election. Verify the `leader.Become(ctx, lockName)` signature is unchanged in v0.19; if the package was dropped or renamed, replace with a direct call to `k8s.io/client-go/tools/leaderelection`.

## Risks / Trade-offs

- **[Risk] controller-runtime v0.23 has breaking API changes** → The `Manager`, `Reconciler`, and cache options have changed across 8 minor versions; expect to update controller setup and reconcile signatures
- **[Risk] operator-lib v0.19 may have removed deprecated helpers** → Review usage of `operator-lib` APIs after updating
- **[Risk] `go mod tidy` may pull in incompatible transitive dep versions** → Accept and fix any resulting conflicts; do not force-pin transitive deps unless necessary
- **[Trade-off] Updating 8 minor versions at once is a large diff** → Accepted; staged intermediate versions would add complexity without safety benefit for a small codebase
