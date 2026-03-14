.PHONY: build build-amd64 build-arm64 build-cross test-static check-size run-amd64 run-arm64 push push-ghcr push-docker manifest info scan clean clean-all analyze setup-qemu help

VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "latest")
COMMIT_HASH ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_DATE ?= $(shell date -u +'%Y-%m-%dT%H:%M:%SZ')

GHCR_REGISTRY ?= ghcr.io/untitledds
DOCKER_REGISTRY ?= docker.io/untitledds
REGISTRY ?= $(GHCR_REGISTRY)

IMAGE_NAME ?= telemt
PLATFORMS ?= linux/amd64,linux/arm64
RUST_VERSION ?= 1.94

RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[0;33m
BLUE = \033[0;34m
NC = \033[0m

setup-builder:
	@echo "${YELLOW}Setting up buildx builder...${NC}"
	docker buildx create --name $(IMAGE_NAME)-builder --use 2>/dev/null || true
	docker buildx inspect --bootstrap
	@echo "${GREEN}✓ Builder ready${NC}"

setup-qemu:
	@echo "${YELLOW}Setting up QEMU for multi-arch emulation...${NC}"
	docker run --privileged --rm tonistiigi/binfmt --install all
	@echo "${GREEN}✓ QEMU configured${NC}"

build: setup-builder
	@echo "${YELLOW}Building multi-arch image: $(PLATFORMS)${NC}"
	docker buildx build \
		--platform $(PLATFORMS) \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		--build-arg VCS_REF=$(COMMIT_HASH) \
		--build-arg VERSION=$(VERSION) \
		--build-arg RUST_VERSION=$(RUST_VERSION) \
		-t $(IMAGE_NAME):$(VERSION) \
		-t $(IMAGE_NAME):latest \
		--load \
		. 2>&1 | tee build.log
	@echo "${GREEN}✓ Build complete${NC}"

build-amd64:
	@echo "${YELLOW}Building amd64 image...${NC}"
	docker build \
		--platform linux/amd64 \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		--build-arg VCS_REF=$(COMMIT_HASH) \
		--build-arg VERSION=$(VERSION) \
		--build-arg RUST_VERSION=$(RUST_VERSION) \
		-t $(IMAGE_NAME):$(VERSION)-amd64 \
		. 2>&1 | tee build-amd64.log
	@echo "${GREEN}✓ amd64 build complete${NC}"

build-arm64: setup-qemu
	@echo "${YELLOW}Building arm64 image...${NC}"
	docker build \
		--platform linux/arm64 \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		--build-arg VCS_REF=$(COMMIT_HASH) \
		--build-arg VERSION=$(VERSION) \
		--build-arg RUST_VERSION=$(RUST_VERSION) \
		-t $(IMAGE_NAME):$(VERSION)-arm64 \
		. 2>&1 | tee build-arm64.log
	@echo "${GREEN}✓ arm64 build complete${NC}"

build-cross: setup-builder
	@echo "${YELLOW}Building with cross-compilation...${NC}"
	docker buildx build \
		--platform $(PLATFORMS) \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		--build-arg VCS_REF=$(COMMIT_HASH) \
		--build-arg VERSION=$(VERSION) \
		--build-arg RUST_VERSION=$(RUST_VERSION) \
		-t $(IMAGE_NAME):$(VERSION) \
		--load \
		. 2>&1 | tee build-cross.log
	@echo "${GREEN}✓ Cross-compilation complete${NC}"

test-static: build-amd64 build-arm64
	@echo "${YELLOW}Testing static linking...${NC}"
	
	@echo "  amd64: "
	@docker run --rm --platform linux/amd64 $(IMAGE_NAME):$(VERSION)-amd64 file /usr/local/bin/telemt | grep -q "statically linked" && \
		echo "    ${GREEN}✅ statically linked${NC}" || \
		(echo "    ${RED}❌ not statically linked${NC}" && exit 1)
	
	@echo "  arm64: "
	@docker run --rm --platform linux/arm64 $(IMAGE_NAME):$(VERSION)-arm64 file /usr/local/bin/telemt | grep -q "statically linked" && \
		echo "    ${GREEN}✅ statically linked${NC}" || \
		(echo "    ${RED}❌ not statically linked${NC}" && exit 1)
	
	@echo "${GREEN}✓ All binaries are statically linked${NC}"

check-size: build-amd64 build-arm64
	@echo "${YELLOW}Binary sizes:${NC}"
	@echo "  amd64: $$(docker run --rm --platform linux/amd64 $(IMAGE_NAME):$(VERSION)-amd64 ls -lh /usr/local/bin/telemt | awk '{print $$5}')"
	@echo "  arm64: $$(docker run --rm --platform linux/arm64 $(IMAGE_NAME):$(VERSION)-arm64 ls -lh /usr/local/bin/telemt | awk '{print $$5}')"

run-amd64:
	@echo "${YELLOW}Running amd64 container...${NC}"
	docker run --rm -it --platform linux/amd64 $(IMAGE_NAME):$(VERSION)-amd64 --version

run-arm64:
	@echo "${YELLOW}Running arm64 container...${NC}"
	docker run --rm -it --platform linux/arm64 $(IMAGE_NAME):$(VERSION)-arm64 --version

push: setup-builder
	@echo "${YELLOW}Pushing to $(REGISTRY)/$(IMAGE_NAME):$(VERSION)${NC}"
	docker buildx build \
		--platform $(PLATFORMS) \
		--build-arg BUILD_DATE=$(BUILD_DATE) \
		--build-arg VCS_REF=$(COMMIT_HASH) \
		--build-arg VERSION=$(VERSION) \
		--build-arg RUST_VERSION=$(RUST_VERSION) \
		-t $(REGISTRY)/$(IMAGE_NAME):$(VERSION) \
		-t $(REGISTRY)/$(IMAGE_NAME):latest \
		--push \
		. 2>&1 | tee push.log
	@echo "${GREEN}✓ Push to $(REGISTRY) complete${NC}"

push-ghcr:
	@$(MAKE) push REGISTRY=$(GHCR_REGISTRY)

push-docker:
	@$(MAKE) push REGISTRY=$(DOCKER_REGISTRY)

manifest:
	@echo "${YELLOW}Creating multi-arch manifest...${NC}"
	docker manifest create $(REGISTRY)/$(IMAGE_NAME):$(VERSION) \
		$(REGISTRY)/$(IMAGE_NAME):$(VERSION)-amd64 \
		$(REGISTRY)/$(IMAGE_NAME):$(VERSION)-arm64 2>/dev/null || true
	docker manifest push $(REGISTRY)/$(IMAGE_NAME):$(VERSION) 2>/dev/null || true
	
	docker manifest create $(REGISTRY)/$(IMAGE_NAME):latest \
		$(REGISTRY)/$(IMAGE_NAME):$(VERSION)-amd64 \
		$(REGISTRY)/$(IMAGE_NAME):$(VERSION)-arm64 2>/dev/null || true
	docker manifest push $(REGISTRY)/$(IMAGE_NAME):latest 2>/dev/null || true
	@echo "${GREEN}✓ Manifest created${NC}"

info:
	@echo "${BLUE}=== Build Information ===${NC}"
	@echo "Version:     $(VERSION)"
	@echo "Commit:      $(COMMIT_HASH)"
	@echo "Build date:  $(BUILD_DATE)"
	@echo "Rust:        $(RUST_VERSION)"
	@echo "Registry:    $(REGISTRY)"
	@echo "Platforms:   $(PLATFORMS)"
	@echo ""
	@echo "${BLUE}=== Docker Images ===${NC}"
	@docker images | grep $(IMAGE_NAME) || echo "No images found"
	@echo ""
	@echo "${BLUE}=== State from GitHub Actions ===${NC}"
	@cat .github/telemt-docker/state.json 2>/dev/null || echo "No state file found"

scan:
	@echo "${YELLOW}Scanning for vulnerabilities...${NC}"
	@if command -v docker scout >/dev/null 2>&1; then \
		docker scout quickview $(REGISTRY)/$(IMAGE_NAME):$(VERSION); \
	else \
		echo "${RED}docker scout not installed. Run: docker scout install${NC}"; \
		exit 1; \
	fi

clean:
	@echo "${YELLOW}Cleaning up...${NC}"
	docker buildx rm $(IMAGE_NAME)-builder 2>/dev/null || true
	docker system prune -f
	rm -f *.log
	@echo "${GREEN}✓ Clean complete${NC}"

clean-all: clean
	@echo "${YELLOW}Removing all $(IMAGE_NAME) images...${NC}"
	docker rmi $$(docker images $(IMAGE_NAME) -q) 2>/dev/null || true
	@echo "${GREEN}✓ Clean all complete${NC}"


analyze:
	@echo "${YELLOW}=== Build Time Analysis ===${NC}"
	@if [ -f build.log ]; then \
		echo "Top 10 longest steps:"; \
		grep -E "seconds|duration" build.log | sort -rn | head -10; \
	else \
		echo "No build.log found. Run 'make build' first."; \
	fi

ci: test-static check-size
	@echo "${GREEN}✓ All CI checks passed${NC}"

help:
	@echo "${BLUE}=== telemt Docker Makefile ===${NC}"
	@echo ""
	@echo "${YELLOW}Build targets:${NC}"
	@echo "  build          - Build multi-arch image (default)"
	@echo "  build-amd64    - Build only amd64"
	@echo "  build-arm64    - Build only arm64"
	@echo "  build-cross    - Build with cross-compilation"
	@echo ""
	@echo "${YELLOW}Test targets:${NC}"
	@echo "  test-static    - Check static linking"
	@echo "  check-size     - Show binary sizes"
	@echo ""
	@echo "${YELLOW}Run targets:${NC}"
	@echo "  run-amd64      - Run amd64 container"
	@echo "  run-arm64      - Run arm64 container"
	@echo ""
	@echo "${YELLOW}Push targets:${NC}"
	@echo "  push           - Push to default registry (GHCR)"
	@echo "  push-ghcr      - Push to GitHub Container Registry"
	@echo "  push-docker    - Push to Docker Hub"
	@echo "  manifest       - Create multi-arch manifest"
	@echo ""
	@echo "${YELLOW}Utility targets:${NC}"
	@echo "  info           - Show build information"
	@echo "  scan           - Scan for vulnerabilities"
	@echo "  clean          - Clean builder and cache"
	@echo "  clean-all      - Remove all images"
	@echo "  analyze        - Analyze build time"
	@echo "  setup-qemu     - Setup QEMU for arm64"
	@echo "  ci             - Run CI checks"
	@echo "  help           - Show this help"
	@echo ""
	@echo "${BLUE}Configuration:${NC}"
	@echo "  VERSION=tag    - Set version (default: git describe)"
	@echo "  REGISTRY=url   - Set registry (default: ghcr.io/untitledds)"
	@echo "  RUST_VERSION=x - Set Rust version (default: 1.94)"