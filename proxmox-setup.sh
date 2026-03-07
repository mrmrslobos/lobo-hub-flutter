#!/bin/bash
# ============================================================
#  LoboHub — Proxmox LXC Auto-Setup Script
#  Run this on your PROXMOX HOST as root:
#    chmod +x proxmox-setup.sh && ./proxmox-setup.sh
# ============================================================
set -euo pipefail

# ── Colours ─────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

banner() { echo -e "\n${BOLD}${CYAN}━━━  $1  ━━━${NC}\n"; }
ok()     { echo -e "  ${GREEN}✓${NC}  $1"; }
warn()   { echo -e "  ${YELLOW}⚠${NC}  $1"; }
info()   { echo -e "  ${BLUE}→${NC}  $1"; }
die()    { echo -e "\n${RED}✗ ERROR: $1${NC}\n"; exit 1; }

# ── Preflight checks ────────────────────────────────────────
[[ $EUID -ne 0 ]] && die "Run as root on the Proxmox host."
command -v pct   &>/dev/null || die "pct not found — run this on a Proxmox VE host."
command -v pveam &>/dev/null || die "pveam not found — run this on a Proxmox VE host."
command -v pvesh &>/dev/null || die "pvesh not found — run this on a Proxmox VE host."

# ── Welcome ──────────────────────────────────────────────────
clear
echo -e "${BOLD}${CYAN}"
echo "  ██╗      ██████╗ ██████╗  ██████╗ ██╗  ██╗██╗   ██╗██████╗ "
echo "  ██║     ██╔═══██╗██╔══██╗██╔═══██╗██║  ██║██║   ██║██╔══██╗"
echo "  ██║     ██║   ██║██████╔╝██║   ██║███████║██║   ██║██████╔╝"
echo "  ██║     ██║   ██║██╔══██╗██║   ██║██╔══██║██║   ██║██╔══██╗"
echo "  ███████╗╚██████╔╝██████╔╝╚██████╔╝██║  ██║╚██████╔╝██████╔╝"
echo "  ╚══════╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ "
echo -e "${NC}"
echo -e "  ${BOLD}Proxmox LXC Auto-Setup${NC} — Docker + LoboHub"
echo ""

# ── LXC Configuration prompts ───────────────────────────────
banner "Step 1 of 6 — Container Configuration"

NEXT_ID=$(pvesh get /cluster/nextid)
read -rp "  Container ID       [$NEXT_ID]: " CT_ID;       CT_ID=${CT_ID:-$NEXT_ID}
read -rp "  Hostname      [lobo-hub]: " CT_HOSTNAME; CT_HOSTNAME=${CT_HOSTNAME:-lobo-hub}

while true; do
  read -rsp "  Root password: " CT_PASSWORD; echo
  read -rsp "  Confirm password: " CT_PASSWORD2; echo
  [[ "$CT_PASSWORD" == "$CT_PASSWORD2" ]] && break
  warn "Passwords don't match — try again."
done
[[ -z "$CT_PASSWORD" ]] && die "Password cannot be empty."

read -rp "  Disk size (GB)     [10]: " CT_DISK;    CT_DISK=${CT_DISK:-10}
read -rp "  RAM (MB)         [2048]: " CT_RAM;     CT_RAM=${CT_RAM:-2048}
read -rp "  CPU cores           [2]: " CT_CORES;   CT_CORES=${CT_CORES:-2}

echo ""
echo -e "  ${BLUE}Available storages:${NC}"
pvesm status | awk 'NR>1 {printf "    %-20s %s\n", $1, $2}'
read -rp "  Storage    [local-lvm]: " CT_STORAGE;  CT_STORAGE=${CT_STORAGE:-local-lvm}

echo ""
echo -e "  ${BLUE}Available bridges:${NC}"
ip link show | awk '/^[0-9]+: vmbr/{gsub(":",""); printf "    %s\n", $2}'
read -rp "  Network bridge   [vmbr0]: " CT_BRIDGE; CT_BRIDGE=${CT_BRIDGE:-vmbr0}

echo ""
read -rp "  IP address (e.g. 192.168.1.100/24) or 'dhcp' [dhcp]: " CT_IP
CT_IP=${CT_IP:-dhcp}
if [[ "$CT_IP" != "dhcp" ]]; then
  read -rp "  Gateway IP (e.g. 192.168.1.1): " CT_GW
  [[ -z "$CT_GW" ]] && die "Gateway required when using a static IP."
fi

# ── Find / download Ubuntu template ─────────────────────────
banner "Step 2 of 6 — LXC Template"

info "Checking local templates..."
TEMPLATE=$(pveam list local 2>/dev/null | grep -i "ubuntu-22.04" | head -1 | awk '{print $1}' || true)

if [[ -z "$TEMPLATE" ]]; then
  info "Updating template list from Proxmox..."
  pveam update 2>/dev/null || true
  TEMPLATE_NAME=$(pveam available --section system 2>/dev/null | grep "ubuntu-22.04" | head -1 | awk '{print $2}' || true)
  [[ -z "$TEMPLATE_NAME" ]] && die "Could not find an Ubuntu 22.04 template. Run 'pveam update' manually."
  info "Downloading $TEMPLATE_NAME ..."
  pveam download local "$TEMPLATE_NAME"
  TEMPLATE="local:vztmpl/${TEMPLATE_NAME}"
fi
ok "Template ready: $TEMPLATE"

# ── Create & start LXC ──────────────────────────────────────
banner "Step 3 of 6 — Creating Container"

NET_OPTS="name=eth0,bridge=${CT_BRIDGE}"
if [[ "$CT_IP" == "dhcp" ]]; then
  NET_OPTS+=",ip=dhcp,ip6=dhcp"
else
  NET_OPTS+=",ip=${CT_IP},gw=${CT_GW}"
fi

info "Creating LXC $CT_ID..."
pct create "$CT_ID" "$TEMPLATE" \
  --hostname   "$CT_HOSTNAME" \
  --password   "$CT_PASSWORD" \
  --cores      "$CT_CORES" \
  --memory     "$CT_RAM" \
  --rootfs     "${CT_STORAGE}:${CT_DISK}" \
  --net0       "$NET_OPTS" \
  --features   "nesting=1,keyctl=1" \
  --unprivileged 1 \
  --onboot     1

info "Starting container..."
pct start "$CT_ID"
sleep 5  # Let it boot fully
ok "Container $CT_ID is running."

# ── Helper: run a command inside the LXC ────────────────────
lxc_exec() { pct exec "$CT_ID" -- bash -c "$1"; }

# Wait for network
info "Waiting for network connectivity..."
for i in $(seq 1 30); do
  lxc_exec "ping -c1 -W2 8.8.8.8 &>/dev/null" && break
  [[ $i -eq 30 ]] && die "Container has no internet after 30 seconds. Check network config."
  sleep 1
done
ok "Network is up."

# ── Install Docker & tools ───────────────────────────────────
banner "Step 4 of 6 — Installing Docker"

info "Updating packages..."
lxc_exec "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq"

info "Installing curl, git, ssh..."
lxc_exec "DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl git openssh-client ca-certificates"

info "Installing Docker..."
lxc_exec "curl -fsSL https://get.docker.com | sh" 2>/dev/null
lxc_exec "systemctl enable --now docker"

ok "Docker $(lxc_exec 'docker --version | cut -d\" \" -f3 | tr -d \",\"') installed."

# ── SSH key for GitHub ───────────────────────────────────────
banner "Step 5 of 6 — GitHub SSH Setup"

info "Generating ed25519 SSH key..."
lxc_exec "mkdir -p /root/.ssh && chmod 700 /root/.ssh"
lxc_exec "ssh-keygen -t ed25519 -C 'lobo-hub@proxmox' -f /root/.ssh/id_ed25519 -N '' -q"

# Write SSH client config via a pushed temp file
TMP_SSH_CFG=$(mktemp)
cat > "$TMP_SSH_CFG" <<'EOF'
Host github.com
  HostName github.com
  User git
  IdentityFile /root/.ssh/id_ed25519
  StrictHostKeyChecking accept-new
EOF
pct push "$CT_ID" "$TMP_SSH_CFG" /root/.ssh/config
rm "$TMP_SSH_CFG"
lxc_exec "chmod 600 /root/.ssh/config"

# Show the public key
PUB_KEY=$(lxc_exec "cat /root/.ssh/id_ed25519.pub")

echo ""
echo -e "${YELLOW}${BOLD}┌──────────────────────────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}${BOLD}│  Add this SSH key to GitHub before continuing:               │${NC}"
echo -e "${YELLOW}${BOLD}│  → github.com → Settings → SSH and GPG keys → New SSH key   │${NC}"
echo -e "${YELLOW}${BOLD}└──────────────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "${CYAN}${PUB_KEY}${NC}"
echo ""
read -rp "  Press ENTER once you've added the key to GitHub..."

info "Testing GitHub SSH connection..."
SSH_TEST=$(lxc_exec "ssh -T git@github.com 2>&1 || true")
if echo "$SSH_TEST" | grep -qi "successfully authenticated"; then
  ok "GitHub SSH connection verified."
else
  warn "Could not verify GitHub SSH automatically."
  warn "SSH output: $SSH_TEST"
  echo ""
  read -rp "  Continue anyway? (y/N): " CONTINUE_ANYWAY
  [[ "${CONTINUE_ANYWAY,,}" != "y" ]] && die "Aborted. Fix SSH access and re-run."
fi

info "Cloning repository..."
lxc_exec "git clone git@github.com:mrmrslobos/lobo-hub-gemini.git /opt/lobo-hub"
ok "Repository cloned to /opt/lobo-hub."

# ── Environment variables ────────────────────────────────────
banner "Step 6 of 6 — App Configuration"

echo -e "  You'll need the following keys:"
echo -e "  ${BLUE}Supabase${NC} → supabase.com → your project → Settings → API"
echo -e "  ${BLUE}Gemini${NC}   → aistudio.google.com/app/apikey"
echo ""

read -rp "  VITE_SUPABASE_URL:      " ENV_SUPABASE_URL
[[ -z "$ENV_SUPABASE_URL" ]] && die "Supabase URL cannot be empty."

read -rp "  VITE_SUPABASE_ANON_KEY: " ENV_SUPABASE_KEY
[[ -z "$ENV_SUPABASE_KEY" ]] && die "Supabase anon key cannot be empty."

read -rp "  VITE_GEMINI_API_KEY:    " ENV_GEMINI_KEY
[[ -z "$ENV_GEMINI_KEY" ]] && die "Gemini API key cannot be empty."

read -rp "  VITE_GEMINI_MODEL [gemini-2.0-flash]: " ENV_GEMINI_MODEL
ENV_GEMINI_MODEL=${ENV_GEMINI_MODEL:-gemini-2.0-flash}

# Write .env via a temp file pushed into the container (handles special chars safely)
TMP_ENV=$(mktemp)
cat > "$TMP_ENV" <<EOF
VITE_SUPABASE_URL=${ENV_SUPABASE_URL}
VITE_SUPABASE_ANON_KEY=${ENV_SUPABASE_KEY}
VITE_GEMINI_API_KEY=${ENV_GEMINI_KEY}
VITE_GEMINI_MODEL=${ENV_GEMINI_MODEL}
EOF
pct push "$CT_ID" "$TMP_ENV" /opt/lobo-hub/.env
rm "$TMP_ENV"
ok ".env written to /opt/lobo-hub/.env"

# ── Build & launch ───────────────────────────────────────────
banner "🚀 Building & Launching LoboHub"

info "Running docker compose up --build (this takes a few minutes)..."
pct exec "$CT_ID" -- bash -c "cd /opt/lobo-hub && docker compose up --build -d"
ok "LoboHub container is up."

# ── Get IP ───────────────────────────────────────────────────
CONTAINER_IP=$(lxc_exec "hostname -I" | awk '{print $1}')

echo ""
echo -e "${GREEN}${BOLD}┌──────────────────────────────────────────────────────────────┐${NC}"
echo -e "${GREEN}${BOLD}│                                                              │${NC}"
echo -e "${GREEN}${BOLD}│   ✅  LoboHub is live!                                       │${NC}"
echo -e "${GREEN}${BOLD}│                                                              │${NC}"
echo -e "${GREEN}${BOLD}│   🌐  http://${CONTAINER_IP}:3000$(printf '%*s' $((46 - ${#CONTAINER_IP})) '')│${NC}"
echo -e "${GREEN}${BOLD}│                                                              │${NC}"
echo -e "${GREEN}${BOLD}│   LXC ID: ${CT_ID}$(printf '%*s' $((51 - ${#CT_ID})) '')│${NC}"
echo -e "${GREEN}${BOLD}│                                                              │${NC}"
echo -e "${GREEN}${BOLD}└──────────────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "  ${BOLD}Useful commands (run on Proxmox host):${NC}"
echo ""
echo -e "  View logs:     ${CYAN}pct exec ${CT_ID} -- docker compose -f /opt/lobo-hub/docker-compose.yml logs -f${NC}"
echo -e "  Restart:       ${CYAN}pct exec ${CT_ID} -- docker compose -f /opt/lobo-hub/docker-compose.yml restart${NC}"
echo -e "  Update & rebuild:"
echo -e "    ${CYAN}pct exec ${CT_ID} -- bash -c 'cd /opt/lobo-hub && git pull && docker compose up --build -d'${NC}"
echo -e "  Shell into LXC:  ${CYAN}pct enter ${CT_ID}${NC}"
echo ""
