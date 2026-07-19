.PHONY: run build test docker docker-push tidy ffi

# Optional local path for asic-rs-go when developing against a sibling checkout.
# Docker does not need this — it pulls github.com/adamdecaf/asic-rs-go via the module proxy.
ASIC_RS_GO ?= ../asic-rs-go

# Local image name (compose / plain docker run).
IMAGE ?= hasherdash

# Docker Hub repository (override if publishing under another account/org).
DOCKER_IMAGE ?= adamdecaf/hasherdash

# Image tag (no leading v). Prefer an exact git tag; fall back to describe / dev.
# Matches CI docker/metadata-action semver tags (v1.2.3 → 1.2.3).
VERSION ?= $(shell \
	(git describe --tags --exact-match 2>/dev/null \
	 || git describe --tags --always --dirty 2>/dev/null \
	 || echo dev) | sed 's/^v//')

export CGO_ENABLED ?= 1

# Build asic-rs FFI for local run/build (sibling checkout; override with ASIC_RS_GO=).
# Docker does not use this target — the image builds FFI from the module proxy.
ffi:
	$(MAKE) -C $(ASIC_RS_GO) ffi

run: ## run against real miners (requires built FFI + config)
	go run ./cmd/hasherdash $(if $(CONFIG),-config $(CONFIG),)

build:
	go build -o bin/hasherdash ./cmd/hasherdash

test:
	go test ./internal/config ./internal/store ./internal/axetemp -count=1

tidy:
	go mod tidy

# Build image from this repo only (asic-rs-go comes from the public Go module proxy).
# Tags local name + Hub :latest and :$(VERSION) (release publish uses both).
docker:
	docker build -f Dockerfile \
		-t $(IMAGE):latest \
		-t $(DOCKER_IMAGE):latest \
		-t $(DOCKER_IMAGE):$(VERSION) \
		.

# Publish release images to Docker Hub: :$(VERSION) and :latest.
# Requires docker login. Prefer an exact git tag: git checkout v1.2.3 && make docker-push
docker-push: docker
	@echo "Publishing $(DOCKER_IMAGE):$(VERSION) and $(DOCKER_IMAGE):latest"
	docker push $(DOCKER_IMAGE):$(VERSION)
	docker push $(DOCKER_IMAGE):latest
