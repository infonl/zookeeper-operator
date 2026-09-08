# Copyright (c) 2018 Dell Inc., or its subsidiaries. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0

SHELL=/bin/bash -o pipefail
# Produce CRDs that work back to Kubernetes 1.11 (no version conversion)
CRD_OPTIONS ?= "crd"

PROJECT_NAME=zookeeper-operator
EXPORTER_NAME=zookeeper-exporter
APP_NAME=zookeeper
REPO=pravega/$(PROJECT_NAME)
TEST_REPO=testzkop/$(PROJECT_NAME)
APP_REPO=pravega/$(APP_NAME)
ALTREPO=emccorp/$(PROJECT_NAME)
APP_ALTREPO=emccorp/$(APP_NAME)
# Where this fork actually publishes to. REPO/APP_REPO above (and their
# ALTREPO mirrors) are upstream pravega's/emccorp's own Docker Hub
# namespaces - this fork has no credentials for either and couldn't push
# there even if it wanted to. GHCR under the infonl org is this fork's own
# registry, authenticated via the workflow's own GITHUB_TOKEN (already
# granted packages:write - no extra secret needed). See `push` below.
GHCR_REGISTRY=ghcr.io/infonl
GHCR_REPO=$(GHCR_REGISTRY)/$(PROJECT_NAME)
GHCR_APP_REPO=$(GHCR_REGISTRY)/$(APP_NAME)
HELM_OCI_REGISTRY=oci://$(GHCR_REGISTRY)/charts
VERSION=$(shell git describe --always --tags --dirty | tr -d "v" | sed "s/\(.*\)-g`git rev-parse --short HEAD`/\1/")
GIT_SHA=$(shell git rev-parse --short HEAD)
TEST_IMAGE=$(TEST_REPO)-testimages:$(VERSION)
DOCKER_TEST_PASS=testzkop@123
DOCKER_TEST_USER=testzkop
.PHONY: all build check clean test zu-lock security-scan
# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Install CRDs into a cluster
install: manifests kustomize
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

# Uninstall CRDs from a cluster
uninstall: manifests kustomize
	$(KUSTOMIZE) build config/crd | kubectl delete -f -

crds: ## Generate CRDs
	- make controller-gen
	- $(CONTROLLER_GEN) crd paths=./api/... output:dir=./config/crd/bases schemapatch:manifests=./config/crd/bases


# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
deploy: manifests kustomize
	cd config/manager && $(KUSTOMIZE) edit set image pravega/zookeeper-operator=$(TEST_IMAGE)
	$(KUSTOMIZE) build config/default | kubectl apply -f -


# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
deploy-test: manifests kustomize
	cd config/test
	$(KUSTOMIZE) build config/test | kubectl apply -f -

# Undeploy controller in the configured Kubernetes cluster in ~/.kube/config
undeploy-test: manifests kustomize
	cd config/test
	$(KUSTOMIZE) build config/test | kubectl apply -f -

# Undeploy controller in the configured Kubernetes cluster in ~/.kube/config
undeploy:
	$(KUSTOMIZE) build config/default | kubectl delete -f -

# Generate manifests e.g. CRD, RBAC etc.
manifests: controller-gen
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases

# Run go fmt against code
fmt:
	go fmt ./...

# Run go vet against code
vet:
	go vet ./...

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)
## Tool Binaries
KUSTOMIZE ?= $(LOCALBIN)/kustomize
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen
## Tool Versions
KUSTOMIZE_VERSION ?= v3.5.4
CONTROLLER_TOOLS_VERSION ?= v0.22.0
KUSTOMIZE_INSTALL_SCRIPT ?= "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"
.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary.
$(KUSTOMIZE): $(LOCALBIN)
	# Retried: a bare single curl|bash here hit a transient SSL connect
	# error (curl exit 35) in CI - the exact same install call succeeded in
	# a sibling job 52s earlier/later, so it's the network blip, not the
	# script or the pinned old release. Only bites more now that the E2E
	# matrix runs this once per shard (8 concurrent installs) instead of
	# once for the whole suite, so a few retries buys back that odds hit.
	test -s $(LOCALBIN)/kustomize || { \
		for i in 1 2 3 4 5; do \
			curl -fsSL $(KUSTOMIZE_INSTALL_SCRIPT) | bash -s -- $(subst v,,$(KUSTOMIZE_VERSION)) $(LOCALBIN) && break; \
			echo "kustomize install attempt $$i failed, retrying in 5s..." >&2; \
			sleep 5; \
		done; \
		test -s $(LOCALBIN)/kustomize; \
	}
.PHONY: controller-gen
controller-gen: $(CONTROLLER_GEN) ## Download controller-gen locally if necessary.
$(CONTROLLER_GEN): $(LOCALBIN)
	test -s $(LOCALBIN)/controller-gen || GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-tools/cmd/controller-gen@$(CONTROLLER_TOOLS_VERSION)

all: generate check build

generate:
	$(CONTROLLER_GEN) object paths="./..."
	make manifests
	# sync crd generated to helm-chart
	echo '{{- if .Values.crd.create }}' > charts/zookeeper-operator/templates/zookeeper.pravega.io_zookeeperclusters_crd.yaml
	cat config/crd/bases/zookeeper.pravega.io_zookeeperclusters.yaml >> charts/zookeeper-operator/templates/zookeeper.pravega.io_zookeeperclusters_crd.yaml
	echo '{{- end }}' >> charts/zookeeper-operator/templates/zookeeper.pravega.io_zookeeperclusters_crd.yaml


build: test build-go build-image

build-go:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
		-ldflags "-X github.com/$(REPO)/pkg/version.Version=$(VERSION) -X github.com/$(REPO)/pkg/version.GitSHA=$(GIT_SHA)" \
		-o bin/$(PROJECT_NAME)-linux-amd64 main.go
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
		-ldflags "-X github.com/$(REPO)/pkg/version.Version=$(VERSION) -X github.com/$(REPO)/pkg/version.GitSHA=$(GIT_SHA)" \
		-o bin/$(EXPORTER_NAME)-linux-amd64 cmd/exporter/main.go
	CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build \
		-ldflags "-X github.com/$(REPO)/pkg/version.Version=$(VERSION) -X github.com/$(REPO)/pkg/version.GitSHA=$(GIT_SHA)" \
		-o bin/$(PROJECT_NAME)-darwin-amd64 main.go
	CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build \
		-ldflags "-X github.com/$(REPO)/pkg/version.Version=$(VERSION) -X github.com/$(REPO)/pkg/version.GitSHA=$(GIT_SHA)" \
		-o bin/$(EXPORTER_NAME)-darwin-amd64 cmd/exporter/main.go
	CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build \
		-ldflags "-X github.com/$(REPO)/pkg/version.Version=$(VERSION) -X github.com/$(REPO)/pkg/version.GitSHA=$(GIT_SHA)" \
		-o bin/$(PROJECT_NAME)-windows-amd64.exe main.go
	CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build \
		-ldflags "-X github.com/$(REPO)/pkg/version.Version=$(VERSION) -X github.com/$(REPO)/pkg/version.GitSHA=$(GIT_SHA)" \
		-o bin/$(EXPORTER_NAME)-windows-amd64.exe cmd/exporter/main.go

build-image:
	docker build --build-arg VERSION=$(VERSION) --build-arg DOCKER_REGISTRY=$(DOCKER_REGISTRY) --build-arg DISTROLESS_DOCKER_REGISTRY=$(DISTROLESS_DOCKER_REGISTRY) --build-arg GIT_SHA=$(GIT_SHA) -t $(REPO):$(VERSION) .
	docker tag $(REPO):$(VERSION) $(REPO):latest

build-zk-image:

	docker build --build-arg VERSION=$(VERSION)  --build-arg DOCKER_REGISTRY=$(DOCKER_REGISTRY) --build-arg GIT_SHA=$(GIT_SHA) -t $(APP_REPO):$(VERSION) ./docker
	docker tag $(APP_REPO):$(VERSION) $(APP_REPO):latest

# Regenerate the zu.jar dependency lock file (docker/zu/gradle.lockfile).
# Run after changing anything in docker/zu/build.gradle.kts and commit the result.
zu-lock:
	docker run --rm -v "$(CURDIR)/docker/zu":/zu -w /zu eclipse-temurin:11-jdk \
		./gradlew --no-daemon --write-locks :dependencies

# Scan for HIGH/CRITICAL CVEs the same way CI does (needs trivy + docker locally).
security-scan:
	go run golang.org/x/vuln/cmd/govulncheck@latest ./...
	trivy fs --scanners vuln,misconfig --severity HIGH,CRITICAL --exit-code 1 \
		--ignorefile .trivyignore --skip-dirs vendor,test --skip-files docker/zk-deps/pom.xml .
	docker build -t $(REPO):scan .
	trivy image --severity HIGH,CRITICAL --exit-code 1 --ignore-unfixed --ignorefile .trivyignore $(REPO):scan
	docker build -t $(APP_REPO):scan ./docker
	trivy image --severity HIGH,CRITICAL --exit-code 1 --ignore-unfixed --ignorefile .trivyignore $(APP_REPO):scan

build-zk-image-swarm:
	docker build --build-arg VERSION=$(VERSION)-swarm  --build-arg DOCKER_REGISTRY=$(DOCKER_REGISTRY) --build-arg GIT_SHA=$(GIT_SHA) \
		-f ./docker/Dockerfile-swarm -t $(APP_REPO):$(VERSION)-swarm ./docker

test:
	go test $$(go list ./... | grep -v /vendor/ | grep -v /test/e2e) -race -coverprofile=coverage.txt -covermode=atomic

test-e2e: test-e2e-remote

# FOCUS is a Ginkgo -focus regexp (matched against each spec's full
# container+It description, e.g. the top-level `Describe("...")` text of one
# test/e2e/*_test.go file). Left empty (the default), Ginkgo runs every spec -
# this is what `make test-e2e` / `make test-e2e-remote` still do locally, and
# what a single "run everything on one runner" CI job would set. CI instead
# runs one matrix job per Describe block, each with its own FOCUS, its own
# fresh minikube, and its own single-tenant ZookeeperCluster capacity - see
# test-e2e-build-image below for why that split exists.
FOCUS ?=

# Split out of test-e2e-remote so CI can build+push the test image exactly
# once and fan the (potentially many, resource-heavy) actual test run out
# across several parallel single-purpose runners instead of one, without
# rebuilding/pushing the same image once per runner.
test-e2e-build-image:
	make test-login
	docker build . -t $(TEST_IMAGE)
	docker push $(TEST_IMAGE)

test-e2e-run:
	make deploy
	# Fail fast (~2 min) with real diagnostics if the operator pod itself
	# never becomes Ready, instead of masquerading as the Ginkgo suite's own
	# 15-minute-per-spec ZookeeperCluster-readiness timeout (pkg/test/e2e/
	# e2eutil.ReadyTimeout) with zero information about why - confirmed live
	# that a ZookeeperCluster reconciles and gets pods in seconds once the
	# operator pod is actually Running (see the CVE-remediation PR's own
	# description for the local repro), so an operator pod that isn't Ready
	# yet is the one thing this step exists to catch before wasting the
	# Ginkgo suite's own budget on it.
	kubectl rollout status deployment/zookeeper-operator -n default --timeout=120s || { \
		echo "::error::zookeeper-operator did not become Ready within 120s - dumping diagnostics"; \
		kubectl get pods -n default -o wide; \
		kubectl describe pod -n default -l name=zookeeper-operator; \
		kubectl logs -n default -l name=zookeeper-operator --tail=200 || true; \
		exit 1; \
	}
	# Dump real cluster diagnostics on failure BEFORE undeploy tears
	# everything down - a spec failing WaitForClusterToBecomeReady only
	# ever reported "0/3 ready, pods ([])", with no visibility into *why*
	# pods never appeared (ImagePullBackOff? FailedScheduling? a real
	# CrashLoopBackOff?). Confirmed live that all of those are
	# indistinguishable from the Ginkgo log alone, which cost real time
	# chasing the wrong theory (cross-spec resource starvation, already
	# fixed) when 6 of 8 *fully isolated* single-tenant shards failed with
	# the exact same symptom in one run - something the sharding fix
	# can't explain, so the next failure needs to say what actually
	# happened instead of us guessing again.
	RUN_LOCAL=false go test -v -timeout 2h ./test/e2e... -args -ginkgo.v -ginkgo.focus="$(FOCUS)"; e2e_status=$$?; \
	if [ $$e2e_status -ne 0 ]; then \
		echo "::group::E2E failed - cluster diagnostics before teardown"; \
		kubectl get pods -n default -o wide; \
		kubectl get events -n default --sort-by=.lastTimestamp | tail -100; \
		for p in $$(kubectl get pods -n default -o name); do kubectl describe $$p -n default; done; \
		echo "::endgroup::"; \
	fi; \
	make undeploy; \
	exit $$e2e_status

test-e2e-remote: test-e2e-build-image test-e2e-run

test-e2e-local:
	make deploy-test
	RUN_LOCAL=true go test -v -timeout 2h ./test/e2e... -args -ginkgo.v
	make undeploy-test

run-local:
	go run ./main.go

# For local `make push`/`make push-charts` use: set DOCKER_USER to your
# GitHub username and DOCKER_PASS to a PAT with write:packages scope. CI
# does not call this target - it logs in to ghcr.io itself (via
# GITHUB_TOKEN) as a separate workflow step before `make push` runs, since
# that credential only exists inside the Actions run, not as a Make var.
login:
	@docker login ghcr.io -u "$(DOCKER_USER)" -p "$(DOCKER_PASS)"

test-login:
	echo "$(DOCKER_TEST_PASS)" | docker login -u "$(DOCKER_TEST_USER)" --password-stdin

# Publishes both images to this fork's own registry (see GHCR_REPO/
# GHCR_APP_REPO above). Assumes an existing `docker login ghcr.io` session
# (`make login` locally, or the workflow's own login step in CI) - doesn't
# call `login` itself so CI's own login isn't clobbered by a second,
# credential-less one running here.
push: build-image build-zk-image
	docker tag $(REPO):$(VERSION) $(GHCR_REPO):$(VERSION)
	docker tag $(REPO):$(VERSION) $(GHCR_REPO):latest
	docker tag $(APP_REPO):$(VERSION) $(GHCR_APP_REPO):$(VERSION)
	docker tag $(APP_REPO):$(VERSION) $(GHCR_APP_REPO):latest
	docker push $(GHCR_REPO):$(VERSION)
	docker push $(GHCR_REPO):latest
	docker push $(GHCR_APP_REPO):$(VERSION)
	docker push $(GHCR_APP_REPO):latest

# Packages and OCI-pushes every chart under charts/ (currently
# zookeeper-operator and zookeeper) to ghcr.io/infonl/charts/<name>,
# tagged with that chart's own Chart.yaml `version` - bump that (and
# `appVersion`, kept in sync with the image tag above) to cut a new chart
# release. Assumes an existing `helm registry login ghcr.io` session, same
# reasoning as `push` above.
push-charts:
	@mkdir -p /tmp/helm-package-out
	@for c in charts/*/; do \
		name=$$(basename $$c); \
		helm package $$c -d /tmp/helm-package-out; \
		version=$$(sed -n 's/^version: *//p' $$c/Chart.yaml); \
		helm push /tmp/helm-package-out/$$name-$$version.tgz $(HELM_OCI_REGISTRY); \
	done

clean:
	rm -f bin/$(PROJECT_NAME)

check: check-format check-license

check-format:
	./scripts/check_format.sh

check-license:
	./scripts/check_license.sh
