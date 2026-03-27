## 1. Update low-risk dependencies

- [ ] 1.1 Run `go get github.com/go-logr/logr@v1.4.3 github.com/onsi/gomega@v1.39.1 github.com/sirupsen/logrus@v1.9.4 golang.org/x/net@v0.52.0`
- [ ] 1.2 Run `go mod tidy`
- [ ] 1.3 Run `go build ./...` and fix any issues
- [ ] 1.4 Run `go test $(go list ./... | grep -v e2e)` and fix any test failures

## 2. Update the k8s ecosystem atomically

- [ ] 2.1 Run `go get k8s.io/api@v0.35.3 k8s.io/apimachinery@v0.35.3 k8s.io/client-go@v0.35.3 sigs.k8s.io/controller-runtime@v0.23.3 github.com/operator-framework/operator-lib@v0.19.0`
- [ ] 2.2 Run `go mod tidy`
- [ ] 2.3 Fix predicted breaking changes (see design.md "Known Breaking Changes"):
  - [ ] 2.3a `main.go:122`: Replace `MetricsBindAddress: metricsAddr` with `Metrics: server.Options{BindAddress: metricsAddr}` and add import `sigs.k8s.io/controller-runtime/pkg/metrics/server`
  - [ ] 2.3b `main.go:121` and `test/e2e/suite_test.go:90`: Replace `cache.Options{Namespaces: ...}` with `cache.Options{DefaultNamespaces: map[string]cache.Config{...}}`
  - [ ] 2.3c `pkg/utils/leader_test.go:80,105`: Replace `WithRuntimeObjects([]runtime.Object{...}...)` with `WithObjects(...)`
  - [ ] 2.3d `pkg/utils/leader.go:37`: Verify `leader.Become(ctx, lockName)` still compiles and behaves correctly in operator-lib v0.19; replace with alternative if the package was removed
- [ ] 2.4 Run `go build ./...` and fix any remaining compilation errors
- [ ] 2.5 Run `go vet ./...` and fix any vet findings
- [ ] 2.6 Run `go test $(go list ./... | grep -v e2e)` and verify all unit tests pass
