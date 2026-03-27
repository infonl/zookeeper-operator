## ADDED Requirements

### Requirement: go-logr/logr is at v1.4.3
The `go.mod` file SHALL declare `github.com/go-logr/logr` at v1.4.3 or later.

#### Scenario: logr version in go.mod
- **WHEN** inspecting `go.mod`
- **THEN** `github.com/go-logr/logr` SHALL be at `v1.4.3` or later

### Requirement: onsi/gomega is at v1.39.1
The `go.mod` file SHALL declare `github.com/onsi/gomega` at v1.39.1 or later.

#### Scenario: gomega version in go.mod
- **WHEN** inspecting `go.mod`
- **THEN** `github.com/onsi/gomega` SHALL be at `v1.39.1` or later

### Requirement: operator-framework/operator-lib is at v0.19.0
The `go.mod` file SHALL declare `github.com/operator-framework/operator-lib` at v0.19.0 or later.

#### Scenario: operator-lib version in go.mod
- **WHEN** inspecting `go.mod`
- **THEN** `github.com/operator-framework/operator-lib` SHALL be at `v0.19.0` or later

### Requirement: sirupsen/logrus is at v1.9.4
The `go.mod` file SHALL declare `github.com/sirupsen/logrus` at v1.9.4 or later.

#### Scenario: logrus version in go.mod
- **WHEN** inspecting `go.mod`
- **THEN** `github.com/sirupsen/logrus` SHALL be at `v1.9.4` or later

### Requirement: golang.org/x/net is at v0.52.0
The `go.mod` file SHALL declare `golang.org/x/net` at v0.52.0 or later.

#### Scenario: x/net version in go.mod
- **WHEN** inspecting `go.mod`
- **THEN** `golang.org/x/net` SHALL be at `v0.52.0` or later

### Requirement: k8s.io ecosystem is at v0.35.3
The `go.mod` file SHALL declare `k8s.io/api`, `k8s.io/apimachinery`, and `k8s.io/client-go` all at v0.35.3 or later, and `sigs.k8s.io/controller-runtime` at v0.23.3 or later.

#### Scenario: k8s.io/api version in go.mod
- **WHEN** inspecting `go.mod`
- **THEN** `k8s.io/api` SHALL be at `v0.35.3` or later

#### Scenario: k8s.io/apimachinery version in go.mod
- **WHEN** inspecting `go.mod`
- **THEN** `k8s.io/apimachinery` SHALL be at `v0.35.3` or later

#### Scenario: k8s.io/client-go version in go.mod
- **WHEN** inspecting `go.mod`
- **THEN** `k8s.io/client-go` SHALL be at `v0.35.3` or later

#### Scenario: controller-runtime version in go.mod
- **WHEN** inspecting `go.mod`
- **THEN** `sigs.k8s.io/controller-runtime` SHALL be at `v0.23.3` or later

### Requirement: ctrl.Options uses updated metrics and cache API
The `main.go` SHALL use the controller-runtime v0.16+ API for metrics and cache namespace configuration.

#### Scenario: MetricsBindAddress replaced with Metrics.BindAddress
- **WHEN** inspecting `main.go`
- **THEN** `ctrl.Options` SHALL NOT contain a `MetricsBindAddress` field
- **AND** SHALL use `Metrics: server.Options{BindAddress: ...}` instead

#### Scenario: cache.Options uses DefaultNamespaces
- **WHEN** inspecting namespace-scoped cache configuration
- **THEN** `cache.Options` SHALL use `DefaultNamespaces map[string]cache.Config` instead of `Namespaces []string`

### Requirement: Project compiles after dependency updates
The project SHALL compile without errors after all dependency updates.

#### Scenario: Successful build
- **WHEN** running `go build ./...` after updating dependencies
- **THEN** the build SHALL succeed with exit code 0

### Requirement: Unit tests pass after dependency updates
All unit tests SHALL pass after the dependency updates.

#### Scenario: Unit tests pass
- **WHEN** running `go test` for all non-e2e packages
- **THEN** all tests SHALL pass

### Requirement: go vet passes after dependency updates
The project SHALL pass `go vet` after the dependency updates.

#### Scenario: Vet clean
- **WHEN** running `go vet ./...`
- **THEN** no vet errors SHALL be reported
