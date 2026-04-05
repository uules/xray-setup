#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Root check
[[ $EUID -ne 0 ]] && error "Run as root: sudo bash $0"

# Install Xray
info "Installing Xray..."
bash -c "$(curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --version v26.3.27
success "Xray installed: $(xray version | head -1)"

# User input 
echo ""
read -rp "Enter SNI domain (e.g. www.google.com): " SNI
[[ -z "$SNI" ]] && error "SNI cannot be empty."

while true; do
  read -rp "Number of clients [1-10]: " CLIENT_COUNT
  [[ "$CLIENT_COUNT" =~ ^[1-9]$|^10$ ]] && break
  warn "Enter a number between 1 and 10."
done

SERVER_IP=$(curl -s4 https://api.ipify.org || curl -s4 https://ifconfig.me)
[[ -z "$SERVER_IP" ]] && error "Could not determine server IP."
info "Detected server IP: $SERVER_IP"

# Generate keys
info "Generating keys..."

X25519_OUT=$(xray x25519)
PRIVATE_KEY=$(echo "$X25519_OUT" | awk '/^PrivateKey:/{print $2}')
PUBLIC_KEY=$(echo "$X25519_OUT"  | awk '/^Password \(PublicKey\):/{print $NF}')

[[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]] && error "Failed to parse x25519 output:\n$X25519_OUT"

SHORT_ID=$(openssl rand -hex 8)
success "Keys generated."

# Generate UUIDs & build client array
info "Generating $CLIENT_COUNT UUID(s)..."

UUIDS=()
for (( i=0; i<CLIENT_COUNT; i++ )); do
  UUIDS+=("$(xray uuid)")
done

# Build JSON clients block
CLIENTS_JSON=""
for (( i=0; i<CLIENT_COUNT; i++ )); do
  COMMA=$( [[ $i -lt $((CLIENT_COUNT-1)) ]] && echo "," || echo "" )
  CLIENTS_JSON+=$(cat <<EOF
          {
            "id": "${UUIDS[$i]}"
          }${COMMA}
EOF
)
done

# Write config
CONFIG_PATH="/usr/local/etc/xray/config.json"
info "Writing config to $CONFIG_PATH..."

cat > "$CONFIG_PATH" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-reality",
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
${CLIENTS_JSON}
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${SNI}:443",
          "xver": 0,
          "serverNames": ["${SNI}"],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": ["${SHORT_ID}"]
        },
        "xhttpSettings": {
          "path": "/api/v1/sync",
          "mode": "auto"
        }
      },
      "sniffing": {
        "enabled": false,
        "destOverride": ["http", "tls", "quic"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "DIRECT"
    },
    {
      "protocol": "blackhole",
      "tag": "BLOCK"
    }
  ]
}
EOF

success "Config written."

# Restart Xray
info "Restarting Xray..."
systemctl restart xray

sleep 2

if systemctl is-active --quiet xray; then
  success "Xray is running."
else
  systemctl status xray --no-pager
  error "Xray failed to start. Check config."
fi

# Generate links
LINKS_FILE="/root/vless.txt"
> "$LINKS_FILE"

for (( i=0; i<CLIENT_COUNT; i++ )); do
  LINK="vless://${UUIDS[$i]}@${SERVER_IP}:443?type=xhttp&path=/api/v1/sync&security=reality&fp=chrome&sni=${SNI}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}"
  cat >> "$LINKS_FILE" <<EOF
--- Client $((i+1)) ---
${LINK}

EOF
done

chmod 600 "$LINKS_FILE"
echo ""
success "Vless links saved to $LINKS_FILE"