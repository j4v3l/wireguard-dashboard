# Wireguard with Dashboard Docker Image

[![Build and Publish Docker Image](https://github.com/j4v3l/wireguard-dashboard/actions/workflows/docker-build.yml/badge.svg)](https://github.com/j4v3l/wireguard-dashboard/actions/workflows/docker-build.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/j4v3l/wireguard-dashboard.svg)](https://hub.docker.com/r/j4v3l/wireguard-dashboard)
[![Docker Stars](https://img.shields.io/docker/stars/j4v3l/wireguard-dashboard.svg)](https://hub.docker.com/r/j4v3l/wireguard-dashboard)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Docker image running Wireguard VPN server with WGDashboard web interface on Alpine Linux. This container allows you to easily set up and manage a Wireguard VPN server with a web-based administration interface.

## Features

- **Multi-architecture support**: Run on any platform - amd64, arm64, armv7, and armhf
- **Lightweight**: Based on Alpine Linux for minimal resource usage
- **WGDashboard integration**: Web-based interface for easy Wireguard management
- **Customizable configuration**: Extensive environment variables for easy configuration
- **Persistent storage**: Volume mounts for configuration and client data
- **Auto-generated configs**: Automatic generation of initial Wireguard configuration if none exists
- **Secure by default**: Proper permissions and secure defaults
- **Automatic updates**: Optional automatic updates for Wireguard and WGDashboard
- **Regular updates**: Multiple release channels (stable, beta, latest)

## Supported Tags

- `latest` - Latest stable release from the main branch
- `stable` - Stable release, tagged with version
- `beta` - Development build from the dev branch
- `x.y.z` - Specific version releases (e.g., `1.0.0`, `1.2.3`)
- `linux/amd64`, `linux/arm64`, `linux/arm/v7`, `linux/arm/v6` - Platform-specific images

## Quick Start

### Option 1: Using Docker

```bash
# Pull the image
docker pull j4v3l/wireguard-dashboard:latest

# Create directories for persistent storage
mkdir -p config dashboard-data

# Run the container
docker run -d \
  --name wireguard \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --sysctl net.ipv4.ip_forward=1 \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  -p 51820:51820/udp \
  -p 10086:10086/tcp \
  -v "$(pwd)/config:/etc/wireguard" \
  -v "$(pwd)/dashboard-data:/opt/WGDashboard/src/db" \
  --restart unless-stopped \
  j4v3l/wireguard-dashboard:latest
```

### Option 2: Using Docker Compose (Recommended)

1. Create a `docker-compose.yml` file:

```yaml
version: '3'

services:
  wireguard:
    image: j4v3l/wireguard-dashboard:beta
    container_name: wireguard
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    environment:
      - TZ=${TZ:-UTC}
      - PUID=${PUID:-1000}
      - PGID=${PGID:-1000}
      - WG_HOST=${WG_HOST:-auto}  # Server's public IP, 'auto' for automatic detection
      - WG_PORT=${WG_PORT:-51820}  # WireGuard port
      - WG_DASHBOARD_PORT=${WG_DASHBOARD_PORT:-10086}  # WGDashboard web interface port
      - WG_DASHBOARD_HOST=${WG_DASHBOARD_HOST:-0.0.0.0}  # WGDashboard bind address
      - WG_ALLOWED_IPS=${WG_ALLOWED_IPS:-0.0.0.0/0, ::/0}  # Allowed IPs for clients
      - WG_PERSISTENT_KEEPALIVE=${WG_PERSISTENT_KEEPALIVE:-25}  # KeepAlive interval
      - WG_DNS_SERVERS=${WG_DNS_SERVERS:-1.1.1.1,8.8.8.8}  # DNS servers for clients
      - AUTO_UPDATE=${AUTO_UPDATE:-false}  # Enable automatic updates of packages
      - UPDATE_DASHBOARD=${UPDATE_DASHBOARD:-false}  # Enable automatic updates of WGDashboard
    volumes:
      - ./config:/etc/wireguard
      - ./dashboard-data:/opt/WGDashboard/src/db
    ports:
      - "${WG_PORT:-51820}:51820/udp"
      - "${WG_DASHBOARD_PORT:-10086}:10086/tcp"
    restart: unless-stopped
    privileged: true  # Required for wireguard kernel module and network changes
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv6.conf.all.forwarding=1 
```

1. Start the container:

```bash
docker-compose up -d
```

## Accessing the Dashboard

Once the container is running, access the WGDashboard at:

```text
http://your-server-ip:10086
```

Default login credentials:

- Username: `admin`
- Password: `admin`

**IMPORTANT:** For security reasons, immediately change the default password after the first login.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TZ` | `UTC` | Timezone for the container (e.g., `America/New_York`, `Europe/London`) |
| `PUID` | `1000` | User ID for file permissions |
| `PGID` | `1000` | Group ID for file permissions |
| `WG_HOST` | `auto` | Server's public IP address. Use `auto` for automatic detection or specify manually |
| `WG_PORT` | `51820` | WireGuard UDP port |
| `WG_DASHBOARD_PORT` | `10086` | WGDashboard web interface TCP port |
| `WG_DASHBOARD_HOST` | `0.0.0.0` | WGDashboard interface binding address |
| `WG_ALLOWED_IPS` | `0.0.0.0/0, ::/0` | IPs/networks to route through the VPN for clients |
| `WG_PERSISTENT_KEEPALIVE` | `25` | KeepAlive interval in seconds for NAT traversal |
| `WG_MTU` | `1420` | MTU for the WireGuard interface. Tuning this can improve throughput on some networks |
| `WG_DNS_SERVERS` | `1.1.1.1,8.8.8.8` | Comma-separated DNS servers to use in client configs |
| `AUTO_UPDATE` | `false` | Enable automatic updates of wireguard-tools. Set to `true` to enable |
| `UPDATE_DASHBOARD` | `false` | Enable automatic updates of WGDashboard. Set to `true` to enable |
| `DEBUG` | `false` | Enable verbose logging and additional diagnostics |

## Automatic Updates

The container includes support for automatic updates of both Wireguard tools and the WGDashboard:

- Set `AUTO_UPDATE=true` to enable automatic updates of Wireguard tools when the container starts
- Set `UPDATE_DASHBOARD=true` to also update the WGDashboard from the Git repository when the container starts

Example with automatic updates enabled:

```bash
docker run -d \
  --name wireguard \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  -e AUTO_UPDATE=true \
  -e UPDATE_DASHBOARD=true \
  -p 51820:51820/udp \
  -p 10086:10086/tcp \
  -v "$(pwd)/config:/etc/wireguard" \
  -v "$(pwd)/dashboard-data:/opt/WGDashboard/src/db" \
  --restart unless-stopped \
  j4v3l/wireguard-dashboard:latest
```

## Volume Mounts

For data persistence, mount these volumes:

| Container Path | Description |
|----------------|-------------|
| `/etc/wireguard` | Wireguard configuration files, including `wg0.conf` and keys |
| `/opt/WGDashboard/src/db` | WGDashboard database for storing settings and client information |

## Network Configuration

The container requires the following ports to be exposed:

| Port | Protocol | Description |
|------|----------|-------------|
| `51820` | UDP | Default Wireguard VPN port (configurable) |
| `10086` | TCP | WGDashboard web interface port (configurable) |

## Security Considerations

1. **Change default credentials**: Immediately change the default admin password in WGDashboard
2. **Firewall rules**: Only expose necessary ports to the internet
3. **Regular updates**: Keep the container updated to receive security fixes
4. **Key storage**: Protect the `/etc/wireguard` directory as it contains private keys
5. **Secure dashboard access**: Consider putting the web interface behind a reverse proxy with HTTPS

## Adding Clients

WGDashboard provides an easy web interface for managing clients:

1. Navigate to `http://your-server-ip:10086`
2. Log in with your credentials
3. Select your Wireguard interface (default: wg0)
4. Click "Add Client" to create a new VPN client
5. Configure the client name and allowed IPs
6. The dashboard will generate configuration and QR codes for easy client setup

## Advanced Usage

### Custom Wireguard Configuration

You can provide your own `wg0.conf` file by placing it in the mounted `/etc/wireguard` directory before starting the container. If a configuration already exists, the container will use it instead of generating a new one.

### Running Behind NAT

If your server is behind NAT, you'll need to forward the appropriate ports:

- UDP port 51820 (or your custom WG_PORT) for Wireguard VPN
- TCP port 10086 (or your custom WG_DASHBOARD_PORT) for WGDashboard web interface

### Integration with Other Services

The container can be integrated with other services like Nginx Proxy Manager or Traefik for handling SSL termination and access control to the dashboard.

## Troubleshooting

### Common Issues

1. **Container fails to start**: Check if the required kernel modules are available on the host

   ```bash
   lsmod | grep wireguard
   ```

2. **Cannot connect to the VPN**: Verify port forwarding and firewall rules

3. **WGDashboard is not accessible**: Check that the dashboard port is correctly exposed

4. **Permission issues**: Ensure proper PUID/PGID settings in the environment variables

5. **No internet access through VPN**: Several things to check:
   - Make sure the container is running in privileged mode or with `--cap-add NET_ADMIN`
   - Try using `network_mode: host` in your docker-compose.yml
   - Verify IP forwarding is enabled on the host: `sysctl net.ipv4.ip_forward`
   - Check iptables NAT rules: `iptables -t nat -L -v`
   - Ensure the client configuration has `AllowedIPs = 0.0.0.0/0, ::/0` to route all traffic
   - For manual fix, run these commands on the host:

     ```bash
     sudo iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
     sudo iptables -A FORWARD -i wg0 -j ACCEPT
     sudo iptables -A FORWARD -o wg0 -j ACCEPT
     ```

### Logs

To view container logs:

```bash
docker logs wireguard
# or with docker-compose
docker-compose logs wireguard
```

### Healthcheck

This image includes a Docker healthcheck that probes the WGDashboard on port 10086. In Docker Compose, you can see the health status with:

```bash
docker ps --format '{{.Names}}\t{{.Status}}'
```

## Updates and Maintenance

### Updating the Container

```bash
# With Docker
docker pull j4v3l/wireguard-dashboard:latest
docker-compose down
docker-compose up -d

# With Docker Compose
docker-compose pull
docker-compose up -d
```

### Backup

To backup your Wireguard configuration and WGDashboard data:

```bash
# Stop the container first
docker-compose down

# Backup directories
tar -czvf wireguard-backup.tar.gz config/ dashboard-data/

# Restart the container
docker-compose up -d
```

## Technical Details

This Docker image includes:

- Alpine Linux (latest)
- Wireguard-tools
- WGDashboard (from <https://github.com/donaldzou/WGDashboard>)
- Python 3 and dependencies
- iptables for network configuration

## Resources

- [GitHub Repository](https://github.com/j4v3l/wireguard-dashboard)
- [Docker Hub](https://hub.docker.com/r/j4v3l/wireguard-dashboard)
- [Wireguard Official Website](https://www.wireguard.com/)
- [WGDashboard Project](https://github.com/donaldzou/WGDashboard)

## License

This project is licensed under the MIT License - see the [LICENSE](https://github.com/j4v3l/wireguard-dashboard/blob/main/LICENSE) file for details.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](https://github.com/j4v3l/wireguard-dashboard/blob/main/CONTRIBUTING.md) for details on how to contribute to this project.
