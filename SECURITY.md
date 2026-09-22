# Security

## Reporting a vulnerability

Please report suspected vulnerabilities privately to the maintainers (see the
project's GitHub Security Advisories tab) rather than opening a public issue.

## Vulnerability scanning

CI (`.github/workflows/security.yaml`) fails the build on any **HIGH** or
**CRITICAL** finding, on every PR and weekly on a schedule:

| Job | Scans | Tool |
|-----|-------|------|
| `govulncheck` | operator Go code + module graph (call-graph aware) | `govulncheck` |
| `trivy-fs` | `go.mod`/`go.sum`, `docker/zu/gradle.lockfile`, IaC, secrets | Trivy |
| `trivy-image-operator` | the built operator image | Trivy |
| `trivy-image-zookeeper` | the built `pravega/zookeeper` image | Trivy |

Run the same checks locally:

```sh
make security-scan
```

Dependency bumps are automated via `.github/dependabot.yml` (Go modules, both
Dockerfiles, the `docker/zk-deps` Maven set, the `docker/zu` Gradle build, and
GitHub Actions).

## How the images are kept clean

### Operator image (`./Dockerfile`)

Pure Go, `distroless/static-debian12` base. Kept current by bumping `go.mod`
(the `go` directive tracks a supported Go release) and letting Dependabot move
the module and base-image versions. `govulncheck` is the gate.

### ZooKeeper image (`./docker`)

**OS base.** The official `zookeeper:3.9.5-jre-17` image is Ubuntu 22.04 and
carries ~50 unpatched OS CVEs with no jammy fix. `docker/Dockerfile` keeps the
exact ZooKeeper distribution and entrypoint from that image (via `COPY --from`)
but re-bases them on `eclipse-temurin:17-jre-noble` (Ubuntu 24.04), then runs
`apt-get upgrade`. The upstream entrypoint's `gosu` (a Go 1.18 binary, 100+
stale stdlib CVEs) is rewritten to use `setpriv` from util-linux. Net result:
0 HIGH/CRITICAL, and the only residue is a handful of MEDIUM/LOW OS packages
for which **no fixed version exists yet** in any Ubuntu release.

**Bundled Java libraries.** The base image ships several jars with known HIGH
CVEs. Rather than hand-patching with `curl`, the build resolves CVE-fixed
replacements through Maven:

1. `docker/zk-deps/pom.xml` declares the fixed versions. A `dep-resolver`
   build stage runs `mvn package`, which downloads them from Maven Central
   **with checksum verification** and copies the full runtime closure to
   `/overrides`.
2. `docker/zk-lib-override.sh` swaps them into
   `/apache-zookeeper-3.9.5-bin/lib`, and **fails the build** if any expected
   jar is not present in the base image (guards against an upstream ZK image
   reorganising its bundled dependency set).

Currently overridden (all transitive deps pinned to the same version):

| Library | Base image | Overridden to | CVEs |
|---------|-----------|---------------|------|
| Netty (`netty-*`, not `tcnative`) | 4.1.130.Final | 4.1.137.Final | CVE-2026-42583, CVE-2026-59901, CVE-2026-44249, CVE-2026-45416, CVE-2026-50010 |
| Jackson (`jackson-*`) | 2.15.2 | 2.21.6 | GHSA-r7wm-3cxj-wff9, CVE-2026-54512, CVE-2026-54513 |
| JLine (`jline`) | 3.25.1 | 3.30.16 | CVE-2026-56740, CVE-2026-56741 |
| Logback (`logback-classic`, `logback-core`) + `slf4j-api` | 1.3.15 / 2.0.13 | 1.5.38 / 2.0.17 | CVE-2025-11226 (+ CVE-2026-1225, CVE-2026-9828, CVE-2026-10532 LOW) |

The `zu.jar` helper is built with the Kotlin `1.9.25` plugin (was `1.5.31`,
whose `kotlin-stdlib` had CVE-2022-24329).

Keep the Netty version identical between `docker/zk-deps/pom.xml` and
`docker/zu/build.gradle.kts` (the `zu.jar` helper bundles Netty via the
ZooKeeper client). After changing `docker/zu/build.gradle.kts`, regenerate the
lock file:

```sh
make zu-lock   # writes docker/zu/gradle.lockfile
```

## Accepted risk: Eclipse Jetty 9.4.x

**Findings:** against `jetty-*-9.4.58.v20250814` bundled by the ZK base image
and used by ZooKeeper's AdminServer and Prometheus metrics provider:

- `CVE-2026-2332` (HIGH, jetty-http, request smuggling)
- `CVE-2026-10050` (HIGH, jetty-security, Digest-auth bypass)
- `CVE-2024-6763` (MEDIUM, jetty-http, ambiguous authority parsing)
- `CVE-2026-6790` (MEDIUM, jetty-server, response splitting)

Trivy's DB has, at times, both flagged and not flagged these against 9.4.58.
The `.trivyignore` entries are kept regardless so a DB change cannot silently
put the gate back to red; the analysis below stands either way.

**Why they are not fixed:**

- Jetty 9.4.x is community end-of-life. The fixed builds (9.4.60 / 9.4.63) are
  released **only to paid Eclipse "Jetty support" subscribers** and are not
  published to Maven Central, so they cannot be swapped in like the other jars.
- Jetty **10 and 11 are also EOL**. Their last public releases (10.0.26,
  11.0.26 on Maven Central) carry the *same* two CVEs - the fixes (10.0.28+,
  11.0.28+) are again subscriber-only. So a 10/11 jar swap buys nothing.
- Jetty **12** has public fixes, but it is a different servlet API
  (`jakarta.servlet`, `org.eclipse.jetty.ee10.*`). `zookeeper-server` and
  `zookeeper-prometheus-metrics` are compiled against Jetty 9.4 / `javax` and
  would need to be **recompiled from source** against Jetty 12 (plus swapping
  `io.prometheus:simpleclient_servlet` for its `_jakarta` variant). That is a
  maintained fork of three ZK modules until ZooKeeper 4.0 (Jetty 12) is GA -
  see "Moving to Jetty 12" below.

**Compensating controls:**

- `adminServerService.external` stays `false` — no LoadBalancer for `:8080`.
- The `zookeeper` chart ships an opt-in ingress `NetworkPolicy`
  (`networkPolicy.enabled=true`) that restricts the AdminServer port (`:8080`)
  and metrics port (`:7000`) to same-namespace / explicitly selected peers.
- AdminServer Digest authentication is not configured by the operator, so the
  Digest-auth bypass has no privileged endpoint to bypass to; the AdminServer
  is reachable in-cluster only.

**Suppression:** `.trivyignore` (all four CVE ids).

**Review by 2026-12-01** — re-check for a public 9.4.x fix or ZooKeeper 4.0 GA,
and drop the suppression as soon as either lands.

### Moving to Jetty 12 (not done - tracked here)

If the compensating controls ever become insufficient, the path is:

1. Check out the `release-3.9.5` tag of `apache/zookeeper`.
2. Bump `jetty.version` to `12.0.x`; change `javax.servlet` → `jakarta.servlet`
   and `org.eclipse.jetty.servlet.*` → `org.eclipse.jetty.ee10.servlet.*` in
   `JettyAdminServer.java`; bump `javax.servlet-api` → `jakarta.servlet-api:6.x`.
3. In the `zookeeper-prometheus-metrics` module, swap
   `io.prometheus:simpleclient_servlet` → `simpleclient_servlet_jakarta`.
4. Rebuild `zookeeper-server`, `zookeeper-jute`,
   `zookeeper-prometheus-metrics`; run ZK's AdminServer + metrics tests.
5. Replace those 3 jars + all `jetty-*` / `javax.servlet-api` jars in
   `docker/zk-deps` + `docker/zk-lib-override.sh`.

Estimated 1-3 days plus an ongoing rebase burden on every ZK patch bump, for a
HIGH (not CRITICAL) finding that is already mitigated. Prefer waiting for
ZooKeeper 4.0.
