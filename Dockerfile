FROM alpine:latest

# Install runtime dependencies and temporary build deps
RUN apk update && apk add --no-cache \
    wireguard-tools \
    python3 \
    py3-pip \
    git \
    iptables \
    net-tools \
  bash \
    curl \
    ca-certificates \
  sudo \
  && apk add --no-cache --virtual .build-deps \
    python3-dev \
    gcc \
    musl-dev \
    linux-headers

# Install WGDashboard (shallow clone) and Python deps
ENV PIP_NO_CACHE_DIR=1
RUN git clone --depth 1 https://github.com/donaldzou/WGDashboard.git /opt/WGDashboard && \
  cd /opt/WGDashboard/src && \
  chmod +x ./wgd.sh && \
  ./wgd.sh install && \
  (update-ca-certificates || true) && \
  apk del .build-deps && \
  rm -rf /var/cache/apk/* /root/.cache

# Create necessary directories
RUN mkdir -p /etc/wireguard

# Add configuration directories for persistence
VOLUME ["/etc/wireguard", "/opt/WGDashboard/src/db"]

# Setup entry point for services
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose ports for WireGuard and WGDashboard
EXPOSE 51820/udp 10086/tcp

# Lightweight healthcheck: verify dashboard port responds (uses env var if overridden)
HEALTHCHECK --interval=30s --timeout=5s --retries=5 CMD sh -c 'curl -fsS "http://127.0.0.1:${WG_DASHBOARD_PORT:-10086}/" >/dev/null || exit 1'

# Start services
ENTRYPOINT ["/entrypoint.sh"] 