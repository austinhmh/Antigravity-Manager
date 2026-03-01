# --- Frontend Build Stage ---
FROM node:20-slim AS frontend-builder
ARG USE_MIRROR=auto
ARG http_proxy
ARG https_proxy
ENV http_proxy=${http_proxy}
ENV https_proxy=${https_proxy}
WORKDIR /app

# Use npm mirror if needed
RUN if [ "$USE_MIRROR" = "true" ] || ( [ "$USE_MIRROR" = "auto" ] && ! timeout 3 bash -c "</dev/tcp/www.google.com/80" 2>/dev/null ); then \
    echo "Using npm mirror..."; \
    npm config set registry https://registry.npmmirror.com; \
    else \
    echo "Using default npm registry..."; \
    fi

COPY package*.json ./
RUN --mount=type=cache,target=/root/.npm \
    npm ci --legacy-peer-deps --prefer-offline --no-audit --no-fund
COPY tsconfig.json tsconfig.node.json vite.config.ts tailwind.config.js postcss.config.cjs index.html ./
COPY public ./public
COPY src ./src
COPY src-tauri/icons ./src-tauri/icons
RUN npm run build

# --- Backend Build Stage ---
FROM rust:1-slim-bookworm AS backend-builder
ARG USE_MIRROR=auto
ARG http_proxy
ARG https_proxy
ENV http_proxy=${http_proxy}
ENV https_proxy=${https_proxy}

# Conditionally use Aliyun mirror for APT
RUN if [ "$USE_MIRROR" = "true" ] || ( [ "$USE_MIRROR" = "auto" ] && ! timeout 3 bash -c "</dev/tcp/www.google.com/80" 2>/dev/null ); then \
    echo "Using Aliyun mirror for APT..."; \
    sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources || \
    sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list; \
    else \
    echo "Using default APT sources..."; \
    fi

# Install build dependencies (headless: no GTK/WebKit needed)
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    build-essential \
    curl \
    wget \
    file \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Use Aliyun mirror for Cargo if needed (Sparse Index)
ENV CARGO_HTTP_MULTIPLEXING=false
RUN if [ "$USE_MIRROR" = "true" ] || ( [ "$USE_MIRROR" = "auto" ] && ! timeout 3 bash -c "</dev/tcp/www.google.com/80" 2>/dev/null ); then \
    echo "Using Aliyun mirror for Cargo..."; \
    mkdir -p /root/.cargo && \
    echo "[source.crates-io]\nreplace-with = 'aliyun'\n\n[source.aliyun]\nregistry = \"sparse+https://mirrors.aliyun.com/crates.io-index/\"" > /root/.cargo/config.toml; \
    else \
    echo "Using default Cargo registry..."; \
    fi

# Verify Go installation for BoringSSL build
RUN which go && go version || (echo "ERROR: Go compiler not found" && exit 1)

WORKDIR /app
# Copy only backend sources to keep frontend cache intact on backend-only changes
COPY src-tauri ./src-tauri

# [FIX] Copy locales for Rust compilation (needed by i18n.rs include_str!)
COPY src/locales ./src/locales

# Copy frontend dist from builder so Tauri can embed it
COPY --from=frontend-builder /app/dist ./dist

# Build the Rust backend in release mode, headless (no GUI deps)
WORKDIR /app/src-tauri
RUN --mount=type=cache,target=/root/.cargo/registry \
    --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/app/src-tauri/target \
    cargo build --release --bin antigravity_tools --no-default-features --features headless && \
    cp target/release/antigravity_tools /tmp/antigravity_tools

# --- Final Runtime Stage ---
FROM debian:bookworm-slim
ARG USE_MIRROR=auto
WORKDIR /app

# Conditionally use Aliyun mirror for APT
RUN if [ "$USE_MIRROR" = "true" ] || ( [ "$USE_MIRROR" = "auto" ] && ! timeout 3 bash -c "</dev/tcp/www.google.com/80" 2>/dev/null ); then \
    echo "Using Aliyun mirror for APT..."; \
    sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources || \
    sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list; \
    else \
    echo "Using default APT sources..."; \
    fi

# Install runtime dependencies (headless: no GTK/WebKit needed)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy binary from builder
COPY --from=backend-builder /tmp/antigravity_tools /app/antigravity-tools

# Copy frontend dist from builder
COPY --from=frontend-builder /app/dist /app/dist

# Set environment variables
ENV ABV_DIST_PATH=/app/dist
ENV RUST_LOG=info
ENV PORT=8045

# Expose the proxy/admin port
EXPOSE 8045

# Run the application in headless mode
ENTRYPOINT ["/app/antigravity-tools", "--headless"]
