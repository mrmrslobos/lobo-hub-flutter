#!/usr/bin/env bash
# =============================================================================
# LoboHub — Proxmox LXC + Docker one-shot setup
#
# Run this script on the PROXMOX HOST as root:
#   bash proxmox-lxc-setup.sh
#
# What it does:
#   1. Downloads a Debian 12 LXC template (if not cached)
#   2. Creates a privileged LXC container with Docker support
#   3. Installs Docker + Docker Compose inside the container
#   4. Authenticates with GitHub Container Registry (ghcr.io)
#   5. Pulls and starts the LoboHub web image + Watchtower
#      (Watchtower auto-redeploys when a new image is pushed to ghcr.io)
#   6. Registers a systemd service so the app survives reboots
# =============================================================================
set -euo pipefail

# ── Configuration — edit these before running ─────────────────────────────────

CTID=200                        # Proxmox container ID (must be free)
HOSTNAME="lobohub"
MEMORY=2048                     # MB
SWAP=512                        # MB
CORES=2
DISK_SIZE=20                    # GB
STORAGE="local-lvm"             # Proxmox storage pool for the rootfs
BRIDGE="vmbr0"                  # Proxmox network bridge

# Network — use "dhcp" or a static spec like "ip=192.168.1.100/24,gw=192.168.1.1"
IP_CONFIG="dhcp"

# Host port the web app is exposed on (access via http://<LXC-IP>:${APP_PORT})
APP_PORT=80

# GitHub Container Registry
GHCR_IMAGE="ghcr.io/mrmrslobos/lobo-hub-flutter:latest"
GHCR_USER="mrmrslobos"

# Create a GitHub Personal Access Token with scope: read:packages
# https://github.com/settings/tokens/new?scopes=read:packages
GHCR_TOKEN=""

# Watchtower poll interval in seconds (300 = 5 minutes)
WATCHTOWER_INTERVAL=300

# ── Template ──────────────────────────────────────────────────────────────────

TEMPLATE_STORAGE="local"
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
TEMPLATE_PATH="/var/lib/vz/template/cache/${TEMPLATE}"

# =============================================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}>>>${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

echo ""
echo "=============================================="
echo "  LoboHub — Proxmox LXC Setup"
echo "=============================================="
echo ""

# ── Pre-flight checks ─────────────────────────────────────────────────────────

[ "$(id -u)" -eq 0 ] || error "Run this script as root on the Proxmox host."

command -v pct  &>/dev/null || error "'pct' not found — are you on the Proxmox host?"
command -v pvesm &>/dev/null || error "'pvesm' not found — are you on the Proxmox host?"

if [ -z "$GHCR_TOKEN" ]; then
    echo ""
    warn "GHCR_TOKEN is not set."
    warn "Create a GitHub PAT with scope 'read:packages':"
    warn "  https://github.com/settings/tokens/new?scopes=read:packages"
    echo ""
    read -r -s -p "Paste your GitHub PAT and press Enter: " GHCR_TOKEN
    echo ""
    [ -n "$GHCR_TOKEN" ] || error "No token provided — aborting."
fi

if pct status "$CTID" &>/dev/null; then
    warn "Container $CTID already exists."
    read -r -p "Destroy and recreate it? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || error "Aborted."
    pct stop "$CTID" 2>/dev/null || true
    sleep 2
    pct destroy "$CTID" --force
fi

# ── Download template ─────────────────────────────────────────────────────────

if [ ! -f "$TEMPLATE_PATH" ]; then
    info "Downloading Debian 12 LXC template..."
    pveam update
    pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
else
    info "Template already cached: $TEMPLATE_PATH"
fi

# ── Create the LXC container ──────────────────────────────────────────────────

info "Creating LXC container $CTID ($HOSTNAME)..."

pct create "$CTID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
    --hostname  "$HOSTNAME" \
    --memory    "$MEMORY" \
    --swap      "$SWAP" \
    --cores     "$CORES" \
    --rootfs    "${STORAGE}:${DISK_SIZE}" \
    --net0      "name=eth0,bridge=${BRIDGE},firewall=1,${IP_CONFIG}" \
    --ostype    debian \
    --features  nesting=1,keyctl=1 \
    --privileged 1 \
    --onboot    1

info "Starting container..."
pct start "$CTID"
sleep 8   # allow networking to initialise

# ── Install Docker ────────────────────────────────────────────────────────────

info "Installing Docker inside the container..."

pct exec "$CTID" -- bash -c '
set -euo pipefail

apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -qq
apt-get install -y -qq \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker
docker --version
'

# ── Authenticate with GitHub Container Registry ───────────────────────────────

info "Authenticating with ghcr.io..."

pct exec "$CTID" -- bash -c "
    echo '${GHCR_TOKEN}' | docker login ghcr.io -u '${GHCR_USER}' --password-stdin
"

# ── Write docker-compose.yml ──────────────────────────────────────────────────

info "Writing /opt/lobohub/docker-compose.yml..."

pct exec "$CTID" -- bash -c "mkdir -p /opt/lobohub"

pct exec "$CTID" -- bash -c "cat > /opt/lobohub/docker-compose.yml << 'COMPOSE_EOF'
services:
  lobohub:
    image: ${GHCR_IMAGE}
    pull_policy: always
    ports:
      - '${APP_PORT}:80'
    restart: unless-stopped

  watchtower:
    image: containrrr/watchtower:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /root/.docker/config.json:/config.json:ro
    # Monitor only the lobohub container; --cleanup removes old images
    command: --interval ${WATCHTOWER_INTERVAL} --cleanup lobohub
    restart: unless-stopped
COMPOSE_EOF
"

# ── Pull image and start services ─────────────────────────────────────────────

info "Pulling image and starting services..."

pct exec "$CTID" -- bash -c "
    cd /opt/lobohub
    docker compose pull
    docker compose up -d
    docker compose ps
"

# ── Systemd unit for auto-start on LXC reboot ────────────────────────────────

info "Registering systemd service..."

pct exec "$CTID" -- bash -c "cat > /etc/systemd/system/lobohub.service << 'SERVICE_EOF'
[Unit]
Description=LoboHub Web App
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/lobohub
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl daemon-reload
systemctl enable lobohub
"

# ── Done ──────────────────────────────────────────────────────────────────────

LXC_IP=$(pct exec "$CTID" -- hostname -I 2>/dev/null | awk '{print $1}')

echo ""
echo "=============================================="
echo -e "  ${GREEN}LoboHub is live!${NC}"
echo "=============================================="
echo ""
echo "  Web app : http://${LXC_IP}:${APP_PORT}"
echo "  LXC ID  : $CTID"
echo ""
echo "  Watchtower polls ghcr.io every $((WATCHTOWER_INTERVAL/60)) minutes."
echo "  Push to the 'main' branch → GitHub Actions builds"
echo "  a new image → Watchtower auto-redeploys."
echo ""
echo "  Next steps:"
echo "  ① Add these secrets to your GitHub repo"
echo "    (Settings → Secrets and variables → Actions):"
echo "      SUPABASE_URL"
echo "      SUPABASE_ANON_KEY"
echo "  ② Merge or push to 'main' to trigger the first build."
echo "  ③ Optionally point a DNS name / reverse proxy at"
echo "      ${LXC_IP}:${APP_PORT} for HTTPS."
echo ""
echo "  Useful commands (run on Proxmox host):"
echo "    pct enter $CTID                       # shell into LXC"
echo "    pct exec $CTID -- docker compose -f /opt/lobohub/docker-compose.yml logs -f"
echo "    pct exec $CTID -- docker compose -f /opt/lobohub/docker-compose.yml pull && docker compose up -d"
echo "=============================================="
