# syntax=docker/dockerfile:1.7

ARG TELEMT_REPO=https://github.com/telemt/telemt.git
ARG TELEMT_REF=main
ARG RUST_VERSION=1.85.0

# Сборка на BUILDPLATFORM с кросс-компиляцией для TARGETPLATFORM
FROM --platform=$BUILDPLATFORM alpine:3.20 AS builder

ARG TELEMT_REPO
ARG TELEMT_REF
ARG RUST_VERSION
ARG TARGETPLATFORM
ARG TARGETARCH

# Устанавливаем зависимости для сборки
RUN apk add --no-cache \
    git \
    curl \
    build-base \
    musl-dev \
    pkgconf \
    openssl-dev \
    openssl-libs-static \
    zlib-dev \
    zlib-static \
    upx \
    file \
    bash \
    ca-certificates \
    && update-ca-certificates

# Установка Rust
ENV RUSTUP_HOME="/usr/local/rustup" \
    CARGO_HOME="/usr/local/cargo" \
    PATH="/usr/local/cargo/bin:${PATH}"

RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain ${RUST_VERSION} --profile minimal

# Установка кросс-компиляторов с musl.cc для статической линковки
RUN case "$TARGETARCH" in \
    'arm64') \
        echo "Installing arm64 cross-compiler from musl.cc" && \
        curl -L https://musl.cc/aarch64-linux-musl-cross.tgz | tar xz -C /usr/local && \
        ln -sf /usr/local/aarch64-linux-musl-cross/bin/aarch64-linux-musl-gcc /usr/local/bin/aarch64-linux-musl-gcc && \
        ln -sf /usr/local/aarch64-linux-musl-cross/bin/aarch64-linux-musl-ld /usr/local/bin/aarch64-linux-musl-ld && \
        ln -sf /usr/local/aarch64-linux-musl-cross/bin/aarch64-linux-musl-ar /usr/local/bin/aarch64-linux-musl-ar && \
        ln -sf /usr/local/aarch64-linux-musl-cross/bin/aarch64-linux-musl-strip /usr/local/bin/aarch64-linux-musl-strip ;; \
    'amd64') \
        echo "Installing amd64 cross-compiler from musl.cc" && \
        curl -L https://musl.cc/x86_64-linux-musl-cross.tgz | tar xz -C /usr/local && \
        ln -sf /usr/local/x86_64-linux-musl-cross/bin/x86_64-linux-musl-gcc /usr/local/bin/x86_64-linux-musl-gcc && \
        ln -sf /usr/local/x86_64-linux-musl-cross/bin/x86_64-linux-musl-ld /usr/local/bin/x86_64-linux-musl-ld && \
        ln -sf /usr/local/x86_64-linux-musl-cross/bin/x86_64-linux-musl-ar /usr/local/bin/x86_64-linux-musl-ar && \
        ln -sf /usr/local/x86_64-linux-musl-cross/bin/x86_64-linux-musl-strip /usr/local/bin/x86_64-linux-musl-strip ;; \
    esac

ENV PATH="/usr/local/bin:${PATH}"

# Настройка переменных для статической сборки
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true \
    CARGO_TERM_COLOR=always \
    CARGO_PROFILE_RELEASE_LTO=true \
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 \
    CARGO_PROFILE_RELEASE_DEBUG=false \
    CARGO_PROFILE_RELEASE_STRIP=true \
    CARGO_PROFILE_RELEASE_DEBUG_ASSERTIONS=false \
    CARGO_PROFILE_RELEASE_OVERFLOW_CHECKS=false \
    CARGO_PROFILE_RELEASE_PANIC=abort \
    OPENSSL_STATIC=1 \
    PKG_CONFIG_ALLOW_CROSS=1 \
    PKG_CONFIG_SYSROOT_DIR=/ \
    RUSTFLAGS="-C target-feature=+crt-static -C link-self-contained=yes"

# Определяем target в зависимости от архитектуры
RUN case "$TARGETARCH" in \
    'amd64') \
        echo "RUST_TARGET=x86_64-unknown-linux-musl" >> /etc/environment && \
        echo "CC=x86_64-linux-musl-gcc" >> /etc/environment && \
        echo "AR=x86_64-linux-musl-ar" >> /etc/environment && \
        echo "STRIP=x86_64-linux-musl-strip" >> /etc/environment ;; \
    'arm64') \
        echo "RUST_TARGET=aarch64-unknown-linux-musl" >> /etc/environment && \
        echo "CC=aarch64-linux-musl-gcc" >> /etc/environment && \
        echo "AR=aarch64-linux-musl-ar" >> /etc/environment && \
        echo "STRIP=aarch64-linux-musl-strip" >> /etc/environment ;; \
    *) \
        echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac

# Добавляем target для Rust
RUN . /etc/environment && \
    rustup target add ${RUST_TARGET}

WORKDIR /src

# Кэширование зависимостей (для ускорения последующих сборок)
COPY Cargo.toml Cargo.lock* ./
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    . /etc/environment && \
    mkdir -p src && echo "fn main() {}" > src/main.rs && \
    cargo build --release --target ${RUST_TARGET} --bin telemt || true && \
    rm -rf src

# Клонирование репозитория с проверкой целостности
RUN --mount=type=cache,target=/root/.cache/git \
    git clone --depth=1 --branch "${TELEMT_REF}" "${TELEMT_REPO}" . && \
    git fsck --full && \
    COMMIT_HASH=$(git rev-parse HEAD) && \
    echo "$COMMIT_HASH" > /commit.txt && \
    echo "Building commit: $COMMIT_HASH for ${TARGETARCH}"

# Статическая сборка с явным указанием линкера
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/src/target \
    . /etc/environment && \
    export CC="${CC}" && \
    export AR="${AR}" && \
    export RUSTFLAGS="${RUSTFLAGS} -C linker=${CC}" && \
    echo "Building for ${RUST_TARGET} with CC=${CC}" && \
    echo "RUSTFLAGS: ${RUSTFLAGS}" && \
    cargo build --release --target ${RUST_TARGET} --bin telemt && \
    mkdir -p /out && \
    cp target/${RUST_TARGET}/release/telemt /out/telemt && \
    # Проверка статической линковки
    echo "=== Binary information ===" && \
    file /out/telemt && \
    if readelf -l /out/telemt 2>/dev/null | grep -q "INTERP"; then \
      echo "ERROR: telemt is dynamically linked (has INTERP section)"; \
      exit 1; \
    fi && \
    if ldd /out/telemt 2>/dev/null | grep -q "=>"; then \
      echo "ERROR: telemt is dynamically linked (ldd shows dependencies)"; \
      exit 1; \
    fi && \
    echo "✓ Static linking verified"

# Опциональное сжатие UPX (если нужно)
RUN set -eux; \
    echo "=== Before compression: $(ls -lh /out/telemt)"; \
    if upx --ultra-brute --preserve-build-id /out/telemt; then \
      echo "=== After UPX: $(ls -lh /out/telemt)"; \
      upx -t /out/telemt; \
    else \
      echo "UPX compression failed, keeping original binary"; \
    fi

# Финальный образ - минимальный distroless
FROM --platform=$TARGETPLATFORM gcr.io/distroless/static:nonroot

ARG BUILD_DATE
ARG VCS_REF
ARG VERSION
ARG TARGETARCH

LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.source="https://github.com/telemt/telemt" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.title="telemt" \
      org.opencontainers.image.description="Telegram MTProto proxy (statically linked)" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.architecture="${TARGETARCH}"

STOPSIGNAL SIGINT

# Healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["/usr/local/bin/telemt", "-healthcheck"]

# Копируем только сертификаты и бинарник
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /out/telemt /usr/local/bin/telemt
COPY --from=builder /commit.txt /commit.txt

WORKDIR /tmp

EXPOSE 443/tcp 9090/tcp

USER nonroot:nonroot
ENTRYPOINT ["/usr/local/bin/telemt"]
CMD ["/etc/telemt.toml"]