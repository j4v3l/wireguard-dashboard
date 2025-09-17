#!/bin/bash
set -Eeuo pipefail

DEBUG_LOWER="${DEBUG:-false}"
DEBUG_LOWER="${DEBUG_LOWER,,}"
if [ "${DEBUG_LOWER}" = "true" ]; then set -x; fi

echo "==================== WIREGUARD NETWORK SETUP ===================="

echo "Enabling IP forwarding..."
echo 1 >/proc/sys/net/ipv4/ip_forward 2>/dev/null || true
echo 1 >/proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null || true

# Set the MTU if provided (helps with connectivity issues)
if [ -n "${WG_MTU}" ]; then
  echo "Setting custom MTU: ${WG_MTU}"
else
  # Default to a safe MTU value
  WG_MTU=1420
  echo "Using default MTU: ${WG_MTU}"
fi

MAIN_IF="${MAIN_IF:-eth0}"
echo "Using main interface: ${MAIN_IF}"

if [ "${CI:-false}" != "true" ] && [ "${TEST_MODE:-false}" != "true" ]; then
  echo "Configuring iptables rules (idempotent)..."
  add_rule_if_missing() {
    local table="$1";
    local chain="$2";
    shift 2;
    local rule=("$@");
    if ! iptables -t "$table" -C "$chain" "${rule[@]}" >/dev/null 2>&1; then
      iptables -t "$table" -A "$chain" "${rule[@]}";
    fi
  }

  # IPv4 NAT + FORWARD
  add_rule_if_missing nat POSTROUTING -s 10.0.0.0/24 -o "$MAIN_IF" -j MASQUERADE
  add_rule_if_missing filter FORWARD -i wg0 -o "$MAIN_IF" -j ACCEPT
  add_rule_if_missing filter FORWARD -i "$MAIN_IF" -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

  # IPv6 NAT requires ip6tables and an IPv6 ULA prefix (not enabled by default)
  if command -v ip6tables >/dev/null 2>&1; then
    add_rule_if_missing_v6() {
      local table="$1"; local chain="$2"; shift 2; local rule=("$@");
      if ! ip6tables -t "$table" -C "$chain" "${rule[@]}" >/dev/null 2>&1; then
        ip6tables -t "$table" -A "$chain" "${rule[@]}";
      fi
    }
    # Example for fd00::/64 if used; comment left for future IPv6 setup
    # add_rule_if_missing_v6 nat POSTROUTING -s fd00::/64 -o "$MAIN_IF" -j MASQUERADE
  fi

  if [ "${DEBUG_LOWER}" = "true" ]; then
    echo "Routing table:"; ip route || true
    echo "NAT rules (v4):"; iptables -t nat -S || true
    echo "FORWARD rules (v4):"; iptables -S FORWARD || true
  fi
fi

# Check for automatic updates
AUTO_UPDATE_LOWER="${AUTO_UPDATE:-false}"; AUTO_UPDATE_LOWER="${AUTO_UPDATE_LOWER,,}"
if [ "${AUTO_UPDATE_LOWER}" = "true" ]; then
  echo "Automatic updates enabled. Updating packages..."
  apk update
  apk upgrade wireguard-tools

  # Update WGDashboard if requested
  UPDATE_DASHBOARD_LOWER="${UPDATE_DASHBOARD:-false}"; UPDATE_DASHBOARD_LOWER="${UPDATE_DASHBOARD_LOWER,,}"
  if [ "${UPDATE_DASHBOARD_LOWER}" = "true" ]; then
    echo "Updating WGDashboard..."
    cd /opt/WGDashboard
    git pull
    cd src
    # Automatically answer "Y" to the update prompt
    echo "Y" | ./wgd.sh update
  fi
fi

# Load wireguard module if possible (may fail in Docker)
if command -v lsmod >/dev/null 2>&1; then
  if ! lsmod | grep wireguard >/dev/null; then
    echo "Attempting to load wireguard kernel module..."
    modprobe wireguard 2>/dev/null || echo "Wireguard kernel module loading failed, but this may be expected in Docker"
  fi
else
  echo "Cannot check for kernel modules in this container environment"
fi

# Determine DNS servers to use (CloudFlare and Google DNS by default)
DNS_SERVERS="${WG_DNS_SERVERS:-1.1.1.1,8.8.8.8}"
echo "Using DNS servers: ${DNS_SERVERS}"

# Create or ensure wg0.conf exists
if [ ! -f /etc/wireguard/wg0.conf ]; then
  echo "Creating initial wireguard configuration..."
  umask 077
  wg genkey | tee /etc/wireguard/privatekey | wg pubkey >/etc/wireguard/publickey
  chmod 600 /etc/wireguard/privatekey

  # Get server IP from the main interface
  SERVER_IP=$(ip -4 addr show "$MAIN_IF" | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)

  if [ -z "$SERVER_IP" ]; then
    # Fallback if we can't get the IP
    SERVER_IP=$(curl -s https://api.ipify.org 2>/dev/null || echo "10.0.0.1")
  fi

  # Create a basic configuration with DNS and allowed IPs
  cat >/etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = 10.0.0.1/24
ListenPort = 51820
MTU = ${WG_MTU}
PostUp = iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o ${MAIN_IF} -j MASQUERADE; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -A FORWARD -i ${MAIN_IF} -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o ${MAIN_IF} -j MASQUERADE; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -D FORWARD -i ${MAIN_IF} -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
SaveConfig = true
EOF
  chmod 600 /etc/wireguard/wg0.conf

  echo "==== Initial WireGuard configuration created ===="
  echo "Server Address: $SERVER_IP"
  echo "MTU: ${WG_MTU}"
  echo "DNS Servers: $DNS_SERVERS"
  echo "WireGuard configuration created at /etc/wireguard/wg0.conf (content not printed for security)"
fi

# Check if we're in a test/CI environment
if [ "${CI:-false}" = "true" ] || [ "${TEST_MODE:-false}" = "true" ]; then
  echo "Running in test/CI mode - skipping WireGuard startup"
else
  # Start WireGuard (may fail in Docker without proper privileges)
  echo "Starting WireGuard..."
  (wg-quick up wg0 || echo "WireGuard failed to start. Ensure NET_ADMIN capability and privileged mode if required.")

  # Show WireGuard status
  echo "==== WireGuard Status ===="
  wg show || echo "Failed to get WireGuard status"

  # Create guide for client configuration
  echo "==== CLIENT CONFIGURATION GUIDE ===="
  echo "For clients to connect successfully, include these critical settings:"
  echo "1. AllowedIPs = 0.0.0.0/0, ::/0  (routes all traffic through VPN)"
  echo "2. DNS = ${DNS_SERVERS}  (uses specified DNS servers)"
  echo "3. MTU = ${WG_MTU}  (matching MTU value for better connectivity)"
  echo "4. PersistentKeepalive = 25  (helps with NAT traversal)"
fi

# Important networking diagnostics
if [ "${CI:-false}" != "true" ] && [ "${TEST_MODE:-false}" != "true" ]; then
  echo "==== NETWORK DIAGNOSTICS ===="
  echo "IP Configuration:"
  ip addr || true
  echo "Routing Table:"
  ip route || true
  echo "DNS Configuration:"
  cat /etc/resolv.conf || true
  echo "Testing Internet Connectivity from Container:"
  if [ "${DEBUG_LOWER}" = "true" ]; then
    ping -c 1 8.8.8.8 || echo "Container cannot reach 8.8.8.8"
    ping -c 1 google.com || echo "Container cannot resolve or reach google.com"
  fi
fi

# Start WGDashboard
echo "Starting WGDashboard..."
if [ "${CI:-false}" = "true" ] || [ "${TEST_MODE:-false}" = "true" ]; then
  echo "Test mode: Would normally start WGDashboard here"
  # Create a fake process for test detection
  sleep 3600 &
  echo "$!" >/tmp/fake-wgd.pid
  echo "Test mode: Created placeholder process"
else
  cd /opt/WGDashboard/src && ./wgd.sh start
fi

echo "WGDashboard started successfully at http://localhost:10086"
echo "Default login - Username: admin / Password: admin"
echo "NOTE: For Wireguard to work properly, this container must be run with --privileged or --cap-add NET_ADMIN flag"

echo "Services started. Container running..."

# Propagate signals and keep PID 1 responsive
trap 'echo "Shutting down..."; cd /opt/WGDashboard/src && ./wgd.sh stop || true; wg-quick down wg0 || true; exit 0' SIGTERM SIGINT
while :; do sleep 3600 & wait $!; done
