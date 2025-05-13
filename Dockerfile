FROM alpine:latest

# Install dependencies and Wireguard
RUN apk update && \
  apk add --no-cache \
  wireguard-tools \
  python3 \
  python3-dev \
  git \
  iptables \
  net-tools \
  gcc \
  musl-dev \
  linux-headers \
  sudo \
  openrc \
  bash \
  curl

# Install WGDashboard
RUN git clone https://github.com/donaldzou/WGDashboard.git /opt/WGDashboard && \
  cd /opt/WGDashboard/src && \
  chmod +x ./wgd.sh && \
  ./wgd.sh install

# Create necessary directories
RUN mkdir -p /etc/wireguard

# Add configuration directories for persistence
VOLUME ["/etc/wireguard", "/opt/WGDashboard/src/db"]

# Setup entry point for services
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose ports for WireGuard and WGDashboard
EXPOSE 51820/udp 10086/tcp

# Start services
ENTRYPOINT ["/entrypoint.sh"] 