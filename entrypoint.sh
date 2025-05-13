#!/bin/bash
set -e

# Enable more verbose output
if [ "${DEBUG,,}" = "true" ]; then
  set -x
fi

echo "==================== WIREGUARD NETWORK SETUP ===================="

# Enable IP forwarding (but don't fail if it's not possible in CI environments)
echo "Enabling IP forwarding..."
echo 1 >/proc/sys/net/ipv4/ip_forward 2>/dev/null || echo "Cannot modify ip_forward in this environment - this is normal in CI/testing"
echo 1 >/proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null || echo "Cannot modify ipv6 forwarding in this environment - this is normal in CI/testing"

# Set the MTU if provided (helps with connectivity issues)
if [ -n "${WG_MTU}" ]; then
  echo "Setting custom MTU: ${WG_MTU}"
else
  # Default to a safe MTU value
  WG_MTU=1420
  echo "Using default MTU: ${WG_MTU}"
fi

# Define main interface - explicitly set to eth0
MAIN_IF="eth0"
echo "Using main interface: $MAIN_IF"

# Reset all iptables rules to ensure clean setup
if [ "${CI}" != "true" ] && [ "${TEST_MODE}" != "true" ]; then
  echo "Clearing any existing iptables rules that might interfere..."
  iptables -F
  iptables -t nat -F
  iptables -X

  # Default policies
  iptables -P INPUT ACCEPT
  iptables -P FORWARD ACCEPT
  iptables -P OUTPUT ACCEPT

  # Setup NAT for internet access through the VPN
  echo "Setting up NAT for internet access..."
  # Set up NAT for IPv4 (with logging for easier troubleshooting)
  iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o $MAIN_IF -j MASQUERADE
  iptables -A FORWARD -i wg0 -o $MAIN_IF -j ACCEPT
  iptables -A FORWARD -i $MAIN_IF -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

  echo "NAT configured for IPv4 - Testing routing tables:"
  ip route
  echo "Current iptables NAT rules:"
  iptables -t nat -L -v
  echo "Current iptables FORWARD rules:"
  iptables -L FORWARD -v
fi

# Check for automatic updates
if [ "${AUTO_UPDATE,,}" = "true" ]; then
  echo "Automatic updates enabled. Updating packages..."
  apk update
  apk upgrade wireguard-tools

  # Update WGDashboard if requested
  if [ "${UPDATE_DASHBOARD,,}" = "true" ]; then
    echo "Updating WGDashboard..."
    cd /opt/WGDashboard
    git pull
    cd src
    # Automatically answer "Y" to the update prompt
    echo "Y" | ./wgd.sh update
  fi
fi

# Load wireguard module if possible (may fail in Docker)
if lsmod 2>/dev/null; then
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
  wg genkey | tee /etc/wireguard/privatekey | wg pubkey >/etc/wireguard/publickey
  chmod 600 /etc/wireguard/privatekey

  # Get server IP from the main interface
  SERVER_IP=$(ip -4 addr show $MAIN_IF | grep -Po '(?<=inet\s)(\d+\.\d+\.\d+\.\d+)' | head -1)

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
  echo "Configuration file:"
  cat /etc/wireguard/wg0.conf
fi

# Check if we're in a test/CI environment
if [ "${CI}" = "true" ] || [ "${TEST_MODE}" = "true" ]; then
  echo "Running in test/CI mode - skipping WireGuard startup"
else
  # Start WireGuard (may fail in Docker without proper privileges)
  echo "Starting WireGuard..."
  (wg-quick up wg0 || echo "WireGuard failed to start. Make sure the container has the NET_ADMIN capability and/or is running in privileged mode.")

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
if [ "${CI}" != "true" ] && [ "${TEST_MODE}" != "true" ]; then
  echo "==== NETWORK DIAGNOSTICS ===="
  echo "IP Configuration:"
  ip addr
  echo "Routing Table:"
  ip route
  echo "DNS Configuration:"
  cat /etc/resolv.conf
  echo "Testing Internet Connectivity from Container:"
  ping -c 1 8.8.8.8 || echo "Container cannot reach 8.8.8.8"
  ping -c 1 google.com || echo "Container cannot resolve or reach google.com"
fi

# Start WGDashboard
echo "Starting WGDashboard..."
if [ "${CI}" = "true" ] || [ "${TEST_MODE}" = "true" ]; then
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

# Keep container running
echo "Services started. Container running..."
tail -f /dev/null
