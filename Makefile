.PHONY: build build-amd64 build-arm64 test-static push

VERSION ?= $(shell git describe --tags --always --dirty)
COMMIT_HASH ?= $(shell git rev-parse --short HEAD)
BUILD_DATE ?= $(shell date -u +'%Y-%m-%dT%H:%M:%SZ')
REGISTRY ?= docker.io/untitledds

build:
	docker buildx build \
		--platform linux/amd64,linux/arm64 \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		--build-arg VCS_REF=$(COMMIT_HASH) \
		--build-arg VERSION=$(VERSION) \
		-t $(REGISTRY)/telemt:$(VERSION) \
		-t $(REGISTRY)/telemt:latest \
		--load \
		.

build-amd64:
	docker build \
		--platform linux/amd64 \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		--build-arg VCS_REF=$(COMMIT_HASH) \
		--build-arg VERSION=$(VERSION) \
		-t telemt:$(VERSION)-amd64 \
		.

build-arm64:
	docker build \
		--platform linux/arm64 \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		--build-arg VCS_REF=$(COMMIT_HASH) \
		--build-arg VERSION=$(VERSION) \
		-t telemt:$(VERSION)-arm64 \
		.

# Проверка статической линковки
test-static:
	@echo "Testing static linking for amd64..."
	@docker run --rm --platform linux/amd64 telemt:$(VERSION)-amd64 file /usr/local/bin/telemt | grep -q "statically linked" || \
		(echo "❌ amd64: not statically linked" && exit 1)
	@echo "✅ amd64: statically linked"
	
	@echo "Testing static linking for arm64..."
	@docker run --rm --platform linux/arm64 telemt:$(VERSION)-arm64 file /usr/local/bin/telemt | grep -q "statically linked" || \
		(echo "❌ arm64: not statically linked" && exit 1)
	@echo "✅ arm64: statically linked"

push:
	docker buildx build \
		--platform linux/amd64,linux/arm64 \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		--build-arg VCS_REF=$(COMMIT_HASH) \
		--build-arg VERSION=$(VERSION) \
		-t $(REGISTRY)/telemt:$(VERSION) \
		-t $(REGISTRY)/telemt:latest \
		--push \
		.