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
#   3. Installs Docker, Docker Compose, and Git inside the container
#   4. Clones the GitHub repo to /opt/lobohub
#   5. Creates a .env file with your Supabase credentials
#   6. Builds the Docker image locally and starts the app
#   7. Creates /opt/lobohub/update.sh — run it to pull + rebuild
#   8. Registers a systemd service so the app survives reboots
# =============================================================================
set -euo pipefail

# ── Configuration — edit these before running ─────────────────────────────────

CTID=200                        # Proxmox container ID (must be free)
HOSTNAME="lobohub"
MEMORY=4096                     # MB — Flutter build needs headroom
SWAP=1024                       # MB
CORES=2
DISK_SIZE=10                    # GB
STORAGE="local-lvm"             # Proxmox storage pool for the rootfs
BRIDGE="vmbr0"                  # Proxmox network bridge

# Network — "ip=dhcp" or a static spec: "ip=192.168.1.100/24,gw=192.168.1.1"
IP_CONFIG="ip=dhcp"

# Host port the web app is served on
APP_PORT=80

# GitHub repo
REPO_OWNER="mrmrslobos"
REPO_NAME="lobo-hub-flutter"
REPO_BRANCH="main"

# GitHub Personal Access Token — needed for private repos
# Create one at: https://github.com/settings/tokens/new?scopes=repo
GITHUB_TOKEN=""

# Supabase credentials — stored in /opt/lobohub/.env on the server (never in git)
SUPABASE_URL=""
SUPABASE_ANON_KEY=""

# ── Template ──────────────────────────────────────────────────────────────────

TEMPLATE_STORAGE="local"
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
TEMPLATE_PATH="/var/lib/vz/template/cache/${TEMPLATE}"

# =============================================================================

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
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
command -v pct &>/dev/null    || error "'pct' not found — are you on the Proxmox host?"

# Prompt for any missing credentials
if [ -z "$GITHUB_TOKEN" ]; then
    read -r -s -p "Enter your GitHub Personal Access Token (repo scope): " GITHUB_TOKEN
    echo ""
    [ -n "$GITHUB_TOKEN" ] || error "GITHUB_TOKEN is required for private repos."
fi

if [ -z "$SUPABASE_URL" ]; then
    read -r -p "Enter your SUPABASE_URL: " SUPABASE_URL
    [ -n "$SUPABASE_URL" ] || error "SUPABASE_URL is required."
fi

if [ -z "$SUPABASE_ANON_KEY" ]; then
    read -r -s -p "Enter your SUPABASE_ANON_KEY: " SUPABASE_ANON_KEY
    echo ""
    [ -n "$SUPABASE_ANON_KEY" ] || error "SUPABASE_ANON_KEY is required."
fi

# Build authenticated clone URL (token embedded so git pull also works)
REPO_URL="https://${GITHUB_TOKEN}@github.com/${REPO_OWNER}/${REPO_NAME}.git"

# ── Destroy existing container if present ─────────────────────────────────────

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
    info "Template already cached."
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
    --unprivileged 0 \
    --onboot    1

info "Starting container..."
pct start "$CTID"
sleep 8

# ── Install Docker and Git ────────────────────────────────────────────────────

info "Installing Docker and Git..."

pct exec "$CTID" -- bash -c '
set -euo pipefail
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg lsb-release git

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

# ── Clone the repository ──────────────────────────────────────────────────────

info "Cloning repository..."

pct exec "$CTID" -- bash -c "
    rm -rf /opt/lobohub
    git clone --branch '${REPO_BRANCH}' '${REPO_URL}' /opt/lobohub
"

# ── Write the .env file (stays on server, never in git) ──────────────────────

info "Writing /opt/lobohub/.env..."

pct exec "$CTID" -- bash -c "cat > /opt/lobohub/.env << 'ENV_EOF'
SUPABASE_URL=${SUPABASE_URL}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
ENV_EOF
chmod 600 /opt/lobohub/.env
"

# ── Create the update script ──────────────────────────────────────────────────

info "Creating /opt/lobohub/update.sh..."

pct exec "$CTID" -- bash -c "cat > /opt/lobohub/update.sh << 'UPDATE_EOF'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/lobohub
echo '>>> Pulling latest code from GitHub...'
git pull origin ${REPO_BRANCH}
echo '>>> Rebuilding and restarting...'
docker compose up --build -d
echo '>>> Done!'
docker compose ps
UPDATE_EOF
chmod +x /opt/lobohub/update.sh
"

# ── Build and start the app ───────────────────────────────────────────────────

info "Building Docker image and starting the app (this takes a few minutes)..."

pct exec "$CTID" -- bash -c "
    cd /opt/lobohub
    docker compose up --build -d
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
TimeoutStartSec=300

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
echo "  Web app  :  http://${LXC_IP}:${APP_PORT}"
echo "  LXC ID   :  $CTID"
echo "  App dir  :  /opt/lobohub  (inside the LXC)"
echo ""
echo "  To update after pushing new code to GitHub:"
echo ""
echo "    pct exec $CTID -- bash /opt/lobohub/update.sh"
echo ""
echo "  Or shell into the LXC and run it directly:"
echo ""
echo "    pct enter $CTID"
echo "    bash /opt/lobohub/update.sh"
echo ""
echo "  To edit Supabase credentials:"
echo "    pct exec $CTID -- nano /opt/lobohub/.env"
echo "    pct exec $CTID -- bash /opt/lobohub/update.sh"
echo ""
echo "  View logs:"
echo "    pct exec $CTID -- docker compose -f /opt/lobohub/docker-compose.yml logs -f"
echo "=============================================="
