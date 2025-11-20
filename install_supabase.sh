#!/bin/bash

# Supabase Self-Hosting Installer Script
# This script installs Docker, clones Supabase, configures secrets (generating valid JWTs), and starts the services.

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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

echo -e "${BLUE}Starting Supabase Installation...${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Please run as root (sudo ./install_supabase.sh)${NC}"
  exit 1
fi

# 1. Update System and Install Dependencies
echo -e "${GREEN}Updating system and installing dependencies...${NC}"
apt-get update && apt-get upgrade -y
apt-get install -y curl git pwgen openssl sed

# 2. Install/Update Docker
# We run this unconditionally to ensure we have a recent version compatible with Supabase
echo -e "${GREEN}Installing/Updating Docker...${NC}"
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

# 3. Clone Supabase Repository
INSTALL_DIR="/opt/supabase"
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${BLUE}Supabase directory already exists at $INSTALL_DIR. Skipping clone.${NC}"
else
    echo -e "${GREEN}Cloning Supabase repository to $INSTALL_DIR...${NC}"
    git clone --depth 1 https://github.com/supabase/supabase "$INSTALL_DIR"
fi

# 4. Configure Environment Variables
echo -e "${GREEN}Configuring environment variables...${NC}"
cd "$INSTALL_DIR/docker"

# Copy example env if .env doesn't exist
if [ ! -f .env ]; then
    cp .env.example .env
    
    # Generate Secrets
    echo -e "${BLUE}Generating secure keys...${NC}"
    
    # Generate a random DB password
    DB_PASSWORD=$(openssl rand -base64 12)
    
    # Generate JWT Secret
    JWT_SECRET=$(openssl rand -hex 32)
    
    # Generate JWT Tokens
    echo -e "${BLUE}Calculating new ANON and SERVICE_ROLE keys...${NC}"
    
    # Timestamps
    IAT=$(date +%s)
    EXP=$((IAT + 315360000)) # +10 years
    
    # Anon Payload
    ANON_PAYLOAD="{\"role\":\"anon\",\"iss\":\"supabase\",\"iat\":$IAT,\"exp\":$EXP}"
    ANON_KEY=$(generate_jwt "$ANON_PAYLOAD" "$JWT_SECRET")
    
    # Service Role Payload
    SERVICE_PAYLOAD="{\"role\":\"service_role\",\"iss\":\"supabase\",\"iat\":$IAT,\"exp\":$EXP}"
    SERVICE_KEY=$(generate_jwt "$SERVICE_PAYLOAD" "$JWT_SECRET")
    
    # Update .env file safely
    # We use a temporary file to avoid issues with sed on different systems
    
    sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$DB_PASSWORD|" .env
    sed -i "s|JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|" .env
    sed -i "s|ANON_KEY=.*|ANON_KEY=$ANON_KEY|" .env
    sed -i "s|SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$SERVICE_KEY|" .env
    
    echo -e "${BLUE}Keys updated successfully.${NC}"
    echo -e "${BLUE}Database Password: $DB_PASSWORD${NC}"
else
    echo -e "${BLUE}.env file already exists. Skipping configuration.${NC}"
fi

# 5. Configure Traefik / SSL (Optional)
echo -e "${BLUE}---------------------------------------------------${NC}"
read -p "Do you want to set up SSL (HTTPS) with Traefik? (y/n): " SETUP_SSL

if [[ "$SETUP_SSL" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Configuring Traefik and SSL...${NC}"
    
    read -p "Enter your base domain (e.g., mydomain.com): " DOMAIN_NAME
    read -p "Enter your email for Let's Encrypt (e.g., admin@mydomain.com): " SSL_EMAIL
    
    if [ -z "$DOMAIN_NAME" ] || [ -z "$SSL_EMAIL" ]; then
        echo -e "${RED}Domain and Email are required for SSL setup. Skipping SSL.${NC}"
    else
        # Create docker-compose.override.yml
        echo -e "${BLUE}Creating docker-compose.override.yml...${NC}"
        
        cat <<EOF > docker-compose.override.yml
services:
  traefik:
    image: traefik:v2.10
    container_name: traefik
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.myresolver.acme.tlschallenge=true"
      - "--certificatesresolvers.myresolver.acme.email=${SSL_EMAIL}"
      - "--certificatesresolvers.myresolver.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
      # - "8080:8080" # Dashboard (optional, insecure)
    volumes:
      - "./letsencrypt:/letsencrypt"
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
    restart: always

  studio:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.studio.rule=Host(\`studio.${DOMAIN_NAME}\`)"
      - "traefik.http.routers.studio.entrypoints=websecure"
      - "traefik.http.routers.studio.tls.certresolver=myresolver"
      - "traefik.http.services.studio.loadbalancer.server.port=3000"

  kong:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(\`api.${DOMAIN_NAME}\`)"
      - "traefik.http.routers.api.entrypoints=websecure"
      - "traefik.http.routers.api.tls.certresolver=myresolver"
      - "traefik.http.services.api.loadbalancer.server.port=8000"
EOF
        
        # Update API URL in .env to use the new domain
        echo -e "${BLUE}Updating API URLs in .env to https://api.${DOMAIN_NAME}...${NC}"
        sed -i "s|API_EXTERNAL_URL=.*|API_EXTERNAL_URL=https://api.${DOMAIN_NAME}|" .env
        sed -i "s|SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=https://api.${DOMAIN_NAME}|" .env
        
        echo -e "${GREEN}SSL Configuration prepared!${NC}"
        echo -e "${RED}IMPORTANT: Ensure your DNS records (A records) for studio.${DOMAIN_NAME} and api.${DOMAIN_NAME} point to this server IP before starting.${NC}"
    fi
fi

# 6. Start Supabase
echo -e "${GREEN}Starting Supabase services...${NC}"
# Ensure we are in the right directory
cd "$INSTALL_DIR/docker"

docker compose pull
docker compose up -d

echo -e "${GREEN}Supabase installed and running!${NC}"
echo -e "${BLUE}---------------------------------------------------${NC}"
if [[ "$SETUP_SSL" =~ ^[Yy]$ ]] && [ ! -z "$DOMAIN_NAME" ]; then
    echo -e "${BLUE}Supabase Studio: https://studio.${DOMAIN_NAME}${NC}"
    echo -e "${BLUE}API Gateway:     https://api.${DOMAIN_NAME}${NC}"
else
    echo -e "${BLUE}Supabase Studio: http://<YOUR_SERVER_IP>:8000${NC}" # Note: Default might be 3000 depending on setup, but Kong proxies it often.
    echo -e "${BLUE}API Gateway:     http://<YOUR_SERVER_IP>:8000${NC}"
fi
echo -e "${BLUE}---------------------------------------------------${NC}"
echo -e "${BLUE}Your credentials are stored in: $INSTALL_DIR/docker/.env${NC}"
