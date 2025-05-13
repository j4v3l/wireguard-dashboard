#!/bin/bash
set -e

# Enable IP forwarding
echo "Enabling IP forwarding..."
echo 1 >/proc/sys/net/ipv4/ip_forward
echo 1 >/proc/sys/net/ipv6/conf/all/forwarding

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

# Create or ensure wg0.conf exists
if [ ! -f /etc/wireguard/wg0.conf ]; then
  echo "Creating initial wireguard configuration..."
  wg genkey | tee /etc/wireguard/privatekey | wg pubkey >/etc/wireguard/publickey
  chmod 600 /etc/wireguard/privatekey

  # Create a basic configuration
  cat >/etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = 10.0.0.1/24
ListenPort = 51820
SaveConfig = true
EOF
  chmod 600 /etc/wireguard/wg0.conf
fi

# Start WireGuard (may fail in Docker without proper privileges)
echo "Starting WireGuard..."
(wg-quick up wg0 2>/dev/null || echo "WireGuard failed to start. This is normal when running in Docker without NET_ADMIN capability or without the kernel module.")

# Start WGDashboard
echo "Starting WGDashboard..."
cd /opt/WGDashboard/src && ./wgd.sh start

echo "WGDashboard started successfully at http://localhost:10086"
echo "Default login - Username: admin / Password: admin"
echo "NOTE: For Wireguard to work properly, this container must be run with --privileged or --cap-add NET_ADMIN flag"

# Keep container running
echo "Services started. Container running..."
tail -f /dev/null
