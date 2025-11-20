#!/bin/bash

# Supabase Self-Hosting Installer Script
# Simple, secure, and Cloudflare-ready

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to generate JWT (HS256) using openssl
generate_jwt() {
    local payload=$1
    local secret=$2
    
    local header='{"alg":"HS256","typ":"JWT"}'
    local header_b64=$(echo -n "$header" | openssl base64 -e -A | sed s/\+/-/g | sed s/\//_/g | sed -E s/=+$//)
    local payload_b64=$(echo -n "$payload" | openssl base64 -e -A | sed s/\+/-/g | sed s/\//_/g | sed -E s/=+$//)
    local signature=$(echo -n "${header_b64}.${payload_b64}" | openssl dgst -sha256 -hmac "$secret" -binary | openssl base64 -e -A | sed s/\+/-/g | sed s/\//_/g | sed -E s/=+$//)
    
    echo "${header_b64}.${payload_b64}.${signature}"
}

echo -e "${BLUE}=== Supabase Installer ===${NC}"
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Error: Run as root (use sudo)${NC}"
  exit 1
fi

# Move to a safe directory first
cd /root 2>/dev/null || cd /tmp

# 1. Update & Install Dependencies
echo -e "${GREEN}[1/6] Updating system...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl git openssl

# 2. Install Docker
echo -e "${GREEN}[2/6] Installing Docker...${NC}"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
    systemctl enable docker > /dev/null 2>&1
    systemctl start docker > /dev/null 2>&1
fi

# 3. Clone Supabase
echo -e "${GREEN}[3/6] Downloading Supabase...${NC}"
INSTALL_DIR="/opt/supabase"
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}Removing existing installation...${NC}"
    # Force kill any stuck containers first
    docker ps -a | grep -E "supabase|traefik|kong" | awk '{print $1}' | xargs -r docker rm -f 2>/dev/null || true
    cd "$INSTALL_DIR/docker" 2>/dev/null && timeout 30 docker compose down 2>/dev/null || true
    cd /root
    rm -rf "$INSTALL_DIR"
    echo -e "${BLUE}  ✓ Cleaned up old installation${NC}"
fi

echo -e "${BLUE}  Cloning repository (please wait 1-2 minutes)...${NC}"
git clone --depth 1 --quiet https://github.com/supabase/supabase "$INSTALL_DIR"
echo -e "${BLUE}  ✓ Download complete${NC}"

# 4. Generate Secrets
echo -e "${GREEN}[4/6] Generating secure keys...${NC}"
cd "$INSTALL_DIR/docker"
cp .env.example .env

DB_PASSWORD=$(openssl rand -base64 12)
JWT_SECRET=$(openssl rand -hex 32)

IAT=$(date +%s)
EXP=$((IAT + 315360000))

ANON_PAYLOAD="{\"role\":\"anon\",\"iss\":\"supabase\",\"iat\":$IAT,\"exp\":$EXP}"
ANON_KEY=$(generate_jwt "$ANON_PAYLOAD" "$JWT_SECRET")

SERVICE_PAYLOAD="{\"role\":\"service_role\",\"iss\":\"supabase\",\"iat\":$IAT,\"exp\":$EXP}"
SERVICE_KEY=$(generate_jwt "$SERVICE_PAYLOAD" "$JWT_SECRET")

# Update .env using a safer method with perl instead of sed
export DB_PASSWORD JWT_SECRET ANON_KEY SERVICE_KEY
perl -i -pe "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=\Q$ENV{DB_PASSWORD}\E/" .env
perl -i -pe "s/JWT_SECRET=.*/JWT_SECRET=\Q$ENV{JWT_SECRET}\E/" .env
perl -i -pe "s/ANON_KEY=.*/ANON_KEY=\Q$ENV{ANON_KEY}\E/" .env
perl -i -pe "s/SERVICE_ROLE_KEY=.*/SERVICE_ROLE_KEY=\Q$ENV{SERVICE_KEY}\E/" .env

echo -e "${BLUE}  ✓ Keys generated${NC}"

# Ask for SSL
echo ""
read -p "Configure SSL with domain? (y/n): " SETUP_SSL

if [[ "$SETUP_SSL" =~ ^[Yy]$ ]]; then
    read -p "Domain (e.g., example.com): " DOMAIN
    read -p "Email: " EMAIL
    
    if [ ! -z "$DOMAIN" ] && [ ! -z "$EMAIL" ]; then
        echo -e "${GREEN}[5/6] Configuring SSL...${NC}"
        
        # Create Traefik config with latest version (v3.x) - Cloudflare compatible
        cat <<EOF > docker-compose.override.yml
services:
  traefik:
    image: traefik:latest
    container_name: traefik
    command:
      - "--log.level=INFO"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=${EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "./letsencrypt:/letsencrypt"
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
    restart: unless-stopped

  studio:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.studio.rule=Host(\`studio.${DOMAIN}\`)"
      - "traefik.http.routers.studio.entrypoints=websecure"
      - "traefik.http.routers.studio.tls=true"
      - "traefik.http.routers.studio.tls.certresolver=letsencrypt"
      - "traefik.http.services.studio.loadbalancer.server.port=3000"

  kong:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.kong.rule=Host(\`api.${DOMAIN}\`)"
      - "traefik.http.routers.kong.entrypoints=websecure"
      - "traefik.http.routers.kong.tls=true"
      - "traefik.http.routers.kong.tls.certresolver=letsencrypt"
      - "traefik.http.services.kong.loadbalancer.server.port=8000"
EOF
        
        sed -i "s|API_EXTERNAL_URL=.*|API_EXTERNAL_URL=https://api.${DOMAIN}|" .env
        sed -i "s|SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=https://api.${DOMAIN}|" .env
        
        echo -e "${BLUE}✓ SSL configured for studio.${DOMAIN} and api.${DOMAIN}${NC}"
        echo -e "${YELLOW}⚠ Make sure DNS records point to this server!${NC}"
        echo -e "   studio.${DOMAIN} → A → $(curl -s ifconfig.me)"
        echo -e "   api.${DOMAIN}    → A → $(curl -s ifconfig.me)"
        echo ""
        read -p "Press Enter when DNS is ready..."
    else
        echo -e "${YELLOW}Skipping SSL configuration${NC}"
        SETUP_SSL="n"
    fi
else
    echo -e "${GREEN}[5/6] Skipping SSL...${NC}"
fi

# 6. Start
echo -e "${GREEN}[6/6] Starting services...${NC}"
docker compose pull -q
docker compose up -d

# Wait for services
echo -e "${BLUE}Waiting for services to start...${NC}"
sleep 15

echo ""
echo -e "${GREEN}✓ Installation complete!${NC}"
echo ""

# Get server IP
SERVER_IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')

if [[ "$SETUP_SSL" =~ ^[Yy]$ ]] && [ ! -z "$DOMAIN" ]; then
    echo -e "${BLUE}📍 Access URLs:${NC}"
    echo -e "   Studio: ${GREEN}https://studio.${DOMAIN}${NC}"
    echo -e "   API:    ${GREEN}https://api.${DOMAIN}${NC}"
    echo ""
    echo -e "${YELLOW}⏳ SSL certificates take 1-2 minutes to generate.${NC}"
    echo -e "${YELLOW}   If you see 'not secure', wait and refresh.${NC}"
    echo ""
    echo -e "${BLUE}Cloudflare users: Set SSL/TLS mode to 'Full' (not Flexible)${NC}"
else
    echo -e "${BLUE}📍 Access URLs:${NC}"
    echo -e "   Studio: ${GREEN}http://${SERVER_IP}:3000${NC}"
    echo -e "   API:    ${GREEN}http://${SERVER_IP}:8000${NC}"
fi

echo ""
echo -e "${BLUE}🔑 Credentials:${NC} /opt/supabase/docker/.env"
echo ""
echo -e "${BLUE}📋 Useful commands:${NC}"
echo -e "   Status:  ${GREEN}docker ps${NC}"
echo -e "   Logs:    ${GREEN}cd /opt/supabase/docker && docker compose logs -f traefik${NC}"
echo -e "   Restart: ${GREEN}cd /opt/supabase/docker && docker compose restart${NC}"
echo ""
