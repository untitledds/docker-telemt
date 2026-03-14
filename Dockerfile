# syntax=docker/dockerfile:1.7

ARG TELEMT_REPO=https://github.com/telemt/telemt.git
ARG TELEMT_REF=main
ARG RUST_VERSION=1.94

# === Stage 1: Build ===
FROM --platform=$BUILDPLATFORM rust:${RUST_VERSION}-alpine AS builder

ARG TELEMT_REPO
ARG TELEMT_REF
ARG TARGETARCH

ENV RUSTUP_HOME="/usr/local/rustup" \
    CARGO_HOME="/usr/local/cargo" \
    PATH="/usr/local/cargo/bin:${PATH}"

RUN --mount=type=cache,target=/var/cache/apk \
    apk add --no-cache \
      ca-certificates git curl \
      build-base musl-dev pkgconf \
      zlib-dev zlib-static \
      upx \
    && update-ca-certificates

RUN --mount=type=cache,target=/var/cache/apk \
    if [ "$(apk --print-arch)" != "$TARGETARCH" ]; then \
      case "$TARGETARCH" in \
        aarch64) apk add --no-cache gcc-aarch64-linux-musl binutils-aarch64-linux-musl ;; \
        x86_64)  apk add --no-cache gcc-x86_64-linux-musl binutils-x86_64-linux-musl ;; \
      esac; \
      mkdir -p ~/.cargo; \
      case "$TARGETARCH" in \
        aarch64) \
          echo '[target.aarch64-unknown-linux-musl]' > ~/.cargo/config.toml; \
          echo 'linker = "aarch64-linux-musl-gcc"' >> ~/.cargo/config.toml; \
          ;; \
        x86_64) \
          echo '[target.x86_64-unknown-linux-musl]' > ~/.cargo/config.toml; \
          echo 'linker = "x86_64-linux-musl-gcc"' >> ~/.cargo/config.toml; \
          ;; \
      esac; \
    fi

ENV CARGO_NET_GIT_FETCH_WITH_CLI=true \
    CARGO_TERM_COLOR=always \
    ZLIB_STATIC=1 \
    PKG_CONFIG_ALLOW_CROSS=1 \
    PKG_CONFIG_ALL_STATIC=1 \
    RUSTFLAGS="-C target-feature=+crt-static" \
    CARGO_PROFILE_RELEASE_LTO=thin \
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 \
    CARGO_PROFILE_RELEASE_DEBUG=false \
    CARGO_PROFILE_RELEASE_STRIP=true \
    CARGO_PROFILE_RELEASE_PANIC=abort

RUN case "$(apk --print-arch)" in \
      x86_64)  echo "x86_64-unknown-linux-musl" > /tmp/rust_target ;; \
      aarch64) echo "aarch64-unknown-linux-musl" > /tmp/rust_target ;; \
    esac

WORKDIR /src

RUN --mount=type=cache,target=/root/.cache/git \
    git clone --depth=1 --branch "${TELEMT_REF}" "${TELEMT_REPO}" . \
    || (git init . && git remote add origin "${TELEMT_REPO}" \
        && git fetch --depth=1 origin "${TELEMT_REF}" \
        && git checkout --detach FETCH_HEAD)

RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/src/target,sharing=locked \
    set -eux; \
    RUST_TARGET=$(cat /tmp/rust_target); \
    rustup target add "$RUST_TARGET" 2>/dev/null || true; \
    cargo build --release --target "$RUST_TARGET" --bin telemt; \
    mkdir -p /out; \
    install -Dm755 "target/${RUST_TARGET}/release/telemt" /out/telemt; \
    if readelf -lW /out/telemt 2>/dev/null | grep -q "Requesting program interpreter"; then \
      echo "ERROR: dynamically linked"; exit 1; \
    fi; \
    echo "✅ Statically linked: $(file /out/telemt)"

# === Stage 2: Runtime ===
FROM --platform=$TARGETPLATFORM gcr.io/distroless/static:nonroot

ARG BUILD_DATE VCS_REF VERSION TARGETPLATFORM

LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="https://github.com/telemt/telemt" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.title="telemt" \
      org.opencontainers.image.description="Telegram MTProto proxy (musl-static)" \
      org.opencontainers.image.licenses="MIT"

STOPSIGNAL SIGINT
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["/usr/local/bin/telemt", "-healthcheck"]

COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /out/telemt /usr/local/bin/telemt

WORKDIR /tmp
EXPOSE 443/tcp 9090/tcp
USER nonroot:nonroot
ENTRYPOINT ["/usr/local/bin/telemt"]
CMD ["/etc/telemt.toml"]