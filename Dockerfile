# syntax=docker/dockerfile:1.7
# ============================================================================
# Grok Build — Railway deployment image
#
# Multi-stage build:
#   1) builder  — compiles the `xai-grok-pager` binary (shipped as `grok`)
#   2) runtime  — slim Debian image that runs `grok agent serve` on $PORT
#
# The build compiles the full CLI crate closure (~70 crates), so the first
# build is long. BuildKit cache mounts below make subsequent builds fast.
# ============================================================================

# ---- 1) builder -----------------------------------------------------------
# Toolchain is pinned by rust-toolchain.toml (channel 1.92.0); this base tag
# only needs to be >= that. rustup honors the pin on first cargo invocation.
FROM rust:1.92-bookworm AS builder

# protoc is required by the proto codegen build scripts. The repo's build.rs
# honors $PROTOC first (see crates/build/xai-proto-build), so install the
# system compiler and point at it — avoids depending on the dotslash launcher.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        protobuf-compiler \
        cmake \
        clang \
        pkg-config \
        libssl-dev \
    && rm -rf /var/lib/apt/lists/*
ENV PROTOC=/usr/bin/protoc

WORKDIR /src
COPY . .

# Build the release binary. Cache mounts keep the cargo registry and target
# dir warm across builds; the binary is copied out of the cached target dir
# inside the same layer (cache mounts are not persisted into the image).
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    cargo build --release -p xai-grok-pager-bin \
    && cp /src/target/release/xai-grok-pager /usr/local/bin/grok \
    && strip /usr/local/bin/grok || true

# ---- 2) runtime -----------------------------------------------------------
FROM debian:bookworm-slim AS runtime

# The agent runs real shell commands (git, build tools, etc.). Keep a minimal
# but functional userland; add whatever toolchains your workloads need here.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
        curl \
        less \
        ripgrep \
    && rm -rf /var/lib/apt/lists/*

# Run as a non-root user with a stable home.
RUN useradd --create-home --uid 10001 --shell /bin/bash grok
ENV HOME=/home/grok \
    GROK_HOME=/home/grok/.grok \
    GROK_DISABLE_AUTOUPDATER=1 \
    RUST_LOG=info

# Baked defaults (theme, colors, server config). Owned by the grok user so the
# agent can still write sessions/logs alongside them at runtime.
COPY --chown=grok:grok deploy/grok-home/config.toml /home/grok/.grok/config.toml
COPY --chown=grok:grok deploy/grok-home/pager.toml   /home/grok/.grok/pager.toml

# The binary and the entrypoint.
COPY --from=builder /usr/local/bin/grok /usr/local/bin/grok
COPY --chown=grok:grok deploy/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# A default working directory for sessions that don't specify their own cwd.
RUN mkdir -p /workspace && chown grok:grok /workspace
WORKDIR /workspace

USER grok

# $PORT is provided by Railway at runtime; the entrypoint binds 0.0.0.0:$PORT.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
