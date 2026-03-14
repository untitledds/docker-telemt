# 🐳 docker-telemt

[![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/untitledds/docker-telemt/docker-telemt-build.yml?branch=main&style=flat-square&logo=githubactions&label=build)](https://github.com/untitledds/docker-telemt/actions)
[![Architecture](https://img.shields.io/badge/arch-amd64%20%7C%20arm64-important?style=flat-square)](#)
[![Security: non-root](https://img.shields.io/badge/security-non--root-success?style=flat-square)](#)
[![Base Image](https://img.shields.io/badge/base-distroless%2Fstatic%3Anonroot-blue?style=flat-square)](https://github.com/GoogleContainerTools/distroless)
[![Upstream](https://img.shields.io/badge/upstream-telemt-orange?style=flat-square)](https://github.com/telemt/telemt)
[![Rust](https://img.shields.io/badge/rust-1.94-orange?style=flat-square&logo=rust)](https://www.rust-lang.org)
[![License](https://img.shields.io/badge/license-GPLv3-blue?style=flat-square)](LICENSE)

A minimal, secure, and **automatically updated** Docker image for [Telemt](https://github.com/telemt/telemt) — a fast MTProto proxy server written in **Rust + Tokio**.

**🔄 Auto-build:** Checks for new telemt releases every 2 hours. When found, builds and publishes multi-arch images to [GHCR](https://github.com/untitledds/docker-telemt/pkgs/container/telemt).

---

## ✨ Features

- **🤖 Auto-updates:** Tracks upstream telemt releases automatically
- **🔐 Secure by default:** Distroless runtime + non-root user
- **🏗 Multi-arch:** `amd64` and `arm64` support
- **📦 Fully static:** Built for `gcr.io/distroless/static:nonroot`
- **🧾 Config-driven:** Mount your `telemt.toml` and go
- **📈 Metrics-ready:** Port `9090` support via config
- **⚡ Optimized:** UPX-compressed binary, cached dependencies

---

## ⚠️ Important Notice

Telemt is a Telegram proxy (MTProto). Operating proxies may be restricted depending on your jurisdiction. You are responsible for compliance with local laws.

---

## 🚀 Quick Start

### 1. Generate a secret
```bash
openssl rand -hex 16
```

### 2. Create `telemt.toml`
See [upstream docs](https://github.com/telemt/telemt) for configuration examples.

### 3. Docker Compose
```yaml
services:
  telemt:
    image: ghcr.io/untitledds/telemt:latest
    container_name: telemt
    restart: unless-stopped
    environment:
      RUST_LOG: "info"
    volumes:
      - ./telemt.toml:/etc/telemt.toml:ro
    ports:
      - "443:443/tcp"
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    read_only: true
    tmpfs:
      - /tmp:rw,nosuid,nodev,noexec,size=16m
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
```

### 4. Start
```bash
docker compose up -d
```

---

## 🏷️ Tags

| Tag | Description |
|-----|-------------|
| `latest` | Latest stable release |
| `X.X.X` | Specific version (e.g., `3.3.16`) |
| `b8da986fd57f` | Commit short SHA |

All tags available on [GHCR](https://github.com/untitledds/docker-telemt/pkgs/container/telemt).

---

## ⚙️ Configuration

| Variable | Description |
|----------|-------------|
| `RUST_LOG` | Log level (`info`, `debug`, `trace`) |

| Port | Purpose |
|------|---------|
| `443/tcp` | Main MTProxy listener |
| `9090/tcp` | Metrics (if enabled in config) |

---

## 🛠 Local Build

```bash
# Build for amd64 only
make build-amd64

# Build for arm64 only  
make build-arm64

# Build multi-arch
make build

# Test static linking
make test-static

# See all commands
make help
```

### Build Args
| Argument | Default | Description |
|----------|---------|-------------|
| `TELEMT_REF` | `main` | Branch/tag/commit to build |
| `RUST_VERSION` | `1.94` | Rust version |

---

## ✨ Key Advantages

| Advantage | Description |
|-----------|-------------|
| **🏗️ True multi-arch** | Single build for `amd64` + `arm64` via cross-compilation |
| **🔒 Secure runtime** | Distroless image, no shell, non-root user |
| **🤖 Auto-updates** | Checks for new releases every 2 hours |
| **📦 Minimal size** | Only static binary + SSL certs |
| **🎯 Correct versioning** | Proper annotated tag handling |
| **⚡ Fast rebuilds** | Dependency caching between builds |
| **📊 Transparency** | Full build history in GitHub Actions |

---

## 🙏 Acknowledgements

Inspired by [**An0nX/telemt-docker**](https://github.com/An0nX/telemt-docker). Thanks for the great work! ❤️

---

## 🔗 Links

- [Telemt upstream](https://github.com/telemt/telemt)
- [MTProxy bot](https://t.me/mtproxybot)
- [Distroless images](https://github.com/GoogleContainerTools/distroless)
- [GHCR package](https://github.com/untitledds/docker-telemt/pkgs/container/telemt)

---

## 📄 License

[GNU General Public License v3.0](LICENSE)
