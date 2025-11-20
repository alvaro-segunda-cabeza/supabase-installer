#!/bin/bash

# Supabase Self-Hosting Installer Script
# Simple, secure, and Cloudflare-ready

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
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

# 1. Update & Install Dependencies
echo -e "${GREEN}[1/5] Updating system...${NC}"
apt-get update -qq && apt-get upgrade -y -qq
apt-get install -y -qq curl git openssl

# 2. Install Docker
echo -e "${GREEN}[2/5] Installing Docker...${NC}"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
fi

# 3. Clone Supabase
echo -e "${GREEN}[3/5] Downloading Supabase...${NC}"
INSTALL_DIR="/opt/supabase"
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
fi
git clone --depth 1 https://github.com/supabase/supabase "$INSTALL_DIR" > /dev/null 2>&1

# 4. Generate Secrets
echo -e "${GREEN}[4/5] Generating secure keys...${NC}"
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

sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$DB_PASSWORD|" .env
sed -i "s|JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|" .env
sed -i "s|ANON_KEY=.*|ANON_KEY=$ANON_KEY|" .env
sed -i "s|SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$SERVICE_KEY|" .env

# Ask for SSL
echo ""
read -p "Configure SSL with domain? (y/n): " SETUP_SSL

if [[ "$SETUP_SSL" =~ ^[Yy]$ ]]; then
    read -p "Domain (e.g., example.com): " DOMAIN
    read -p "Email: " EMAIL
    
    if [ ! -z "$DOMAIN" ] && [ ! -z "$EMAIL" ]; then
        # Create Traefik config (Cloudflare-compatible)
        cat <<EOF > docker-compose.override.yml
services:
  traefik:
    image: traefik:v2.10
    container_name: traefik
    command:
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
      - "traefik.http.routers.studio.tls.certresolver=letsencrypt"
      - "traefik.http.services.studio.loadbalancer.server.port=3000"

  kong:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(\`api.${DOMAIN}\`)"
      - "traefik.http.routers.api.entrypoints=websecure"
      - "traefik.http.routers.api.tls.certresolver=letsencrypt"
      - "traefik.http.services.api.loadbalancer.server.port=8000"
EOF
        
        sed -i "s|API_EXTERNAL_URL=.*|API_EXTERNAL_URL=https://api.${DOMAIN}|" .env
        sed -i "s|SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=https://api.${DOMAIN}|" .env
        
        echo -e "${BLUE}SSL configured for studio.${DOMAIN} and api.${DOMAIN}${NC}"
    fi
fi

# 5. Start
echo -e "${GREEN}[5/5] Starting services...${NC}"
docker compose pull -q
docker compose up -d

echo ""
echo -e "${GREEN}✓ Installation complete!${NC}"
echo ""
if [[ "$SETUP_SSL" =~ ^[Yy]$ ]] && [ ! -z "$DOMAIN" ]; then
    echo -e "${BLUE}Studio: https://studio.${DOMAIN}${NC}"
    echo -e "${BLUE}API:    https://api.${DOMAIN}${NC}"
else
    SERVER_IP=$(curl -s ifconfig.me)
    echo -e "${BLUE}Studio: http://${SERVER_IP}:3000${NC}"
    echo -e "${BLUE}API:    http://${SERVER_IP}:8000${NC}"
fi
echo ""
echo -e "Credentials: ${INSTALL_DIR}/docker/.env"
