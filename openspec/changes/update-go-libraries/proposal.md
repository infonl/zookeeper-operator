## Why

The project's direct Go dependencies are significantly out of date — some by multiple years — meaning the project is missing security patches, bug fixes, and compatibility improvements. The k8s ecosystem libraries (k8s.io/*, controller-runtime) are 8 minor versions behind, which compounds risk as each version may contain CVE fixes.

## What Changes

- Update `github.com/go-logr/logr` from v1.2.4 to v1.4.3
- Update `github.com/onsi/gomega` from v1.27.7 to v1.39.1
- Update `github.com/operator-framework/operator-lib` from v0.11.0 to v0.19.0
- Update `github.com/sirupsen/logrus` from v1.9.0 to v1.9.4
- Update `golang.org/x/net` from v0.17.0 to v0.52.0
- Update `k8s.io/api` from v0.27.5 to v0.35.3
- Update `k8s.io/apimachinery` from v0.27.5 to v0.35.3
- Update `k8s.io/client-go` from v0.27.5 to v0.35.3
- Update `sigs.k8s.io/controller-runtime` from v0.15.2 to v0.23.3
- Run `go mod tidy` to update indirect dependencies and `go.sum`
- Fix any compilation or API-breaking changes surfaced by the updates

## Capabilities

### New Capabilities
- `go-library-versions`: All direct Go module dependencies are at their latest compatible versions

### Modified Capabilities
<!-- None — no existing specs to modify -->

## Impact

- **`go.mod` / `go.sum`**: Direct and indirect dependency versions will change
- **Source code**: The k8s ecosystem (k8s.io/*, controller-runtime) and operator-lib span 8 minor versions; API surface changes are likely and will require code fixes
- **Tests**: Updated gomega matchers may require test adjustments
- **Indirect dependencies**: `go mod tidy` will cascade updates to transitive deps
