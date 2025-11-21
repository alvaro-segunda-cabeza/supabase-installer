#!/bin/bash
set -e

###############################
# CONFIG
###############################
ROOT_DOMAIN="segundacabeza.net"
EMAIL="alvaro@segundacabeza.net"
INSTALL_DIR="/opt/supabase"

echo ">>> Starting Supabase full installer for $ROOT_DOMAIN"

###############################
# INSTALL DOCKER
###############################
echo ">>> Installing Docker..."
apt update -y && apt upgrade -y
apt install -y ca-certificates curl gnupg git ufw lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
 | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
 https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
 | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update -y
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

###############################
# FIREWALL
###############################
echo ">>> Configuring firewall..."
ufw allow ssh
ufw allow 80
ufw allow 443
yes | ufw enable || true

###############################
# DIRECTORY STRUCTURE
###############################
echo ">>> Creating structure..."
mkdir -p $INSTALL_DIR/traefik/dynamic
touch $INSTALL_DIR/traefik/acme.json
chmod 600 $INSTALL_DIR/traefik/acme.json

###############################
# TRAEFIK BASE CONFIG
###############################
echo ">>> Writing Traefik config..."

cat <<EOF > $INSTALL_DIR/traefik/traefik.yml
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
    forwardedHeaders:
      insecure: true

certificatesResolvers:
  letsencrypt:
    acme:
      email: "$EMAIL"
      storage: "acme.json"
      httpChallenge:
        entryPoint: web

providers:
  file:
    directory: "/traefik/dynamic"
    watch: true

serversTransport:
  insecureSkipVerify: true

api:
  dashboard: true
EOF

###############################
# DOWNLOAD SUPABASE
###############################
echo ">>> Cloning Supabase repo..."
cd $INSTALL_DIR
git clone https://github.com/supabase/supabase.git || true

cd $INSTALL_DIR/supabase/docker
cp .env.example .env

###############################
# DOMAIN PATCHING
###############################
echo ">>> Setting domains..."

declare -A MAP
MAP=(
 ["KONG_DNS"]="api"
 ["STUDIO"]="studio"
 ["GOTRUE"]="auth"
 ["STORAGE"]="storage"
 ["REALTIME"]="realtime"
 ["FUNCTIONS"]="functions"
 ["POSTGREST"]="rest"
 ["GRAPHQL"]="graphql"
 ["META"]="meta"
 ["IMGPROXY"]="img"
 ["ANALYTICS"]="analytics"
)

for key in "${!MAP[@]}"; do
  sed -i "s|${key}_URL=.*|${key}_URL=https://${MAP[$key]}.$ROOT_DOMAIN|g" .env
done

###############################
# TRAEFIK ROUTERS
###############################
echo ">>> Creating docker-compose override..."

cat <<EOF > $INSTALL_DIR/supabase/docker/docker-compose.override.yml
version: "3.9"
services:
EOF

for key in "${!MAP[@]}"; do
service="${MAP[$key]}"
cat <<EOF >> $INSTALL_DIR/supabase/docker/docker-compose.override.yml
  ${service}:
    labels:
      - traefik.enable=true
      - traefik.http.routers.${service}.rule=Host(\`${service}.${ROOT_DOMAIN}\`)
      - traefik.http.routers.${service}.entrypoints=websecure
      - traefik.http.routers.${service}.tls.certresolver=letsencrypt

EOF
done

###############################
# ROOT DOCKER COMPOSE
###############################
echo ">>> Creating root docker-compose.yml..."

cat <<EOF > $INSTALL_DIR/docker-compose.yml
version: "3.9"

services:
  traefik:
    image: traefik:v3.1
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./traefik/traefik.yml:/traefik/traefik.yml:ro
      - ./traefik/acme.json:/acme.json
      - ./traefik/dynamic:/traefik/dynamic
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: always
EOF

###############################
# START SUPABASE
###############################
echo ">>> Launching Supabase full stack..."

cd $INSTALL_DIR

docker compose \
  -f docker-compose.yml \
  -f supabase/docker/docker-compose.yml \
  -f supabase/docker/docker-compose.override.yml \
  up -d

echo ">>> Supabase installed successfully!"
echo ""
echo "Studio:     https://studio.$ROOT_DOMAIN"
echo "API:        https://api.$ROOT_DOMAIN"
echo "Auth:       https://auth.$ROOT_DOMAIN"
echo "Storage:    https://storage.$ROOT_DOMAIN"
echo "Realtime:   https://realtime.$ROOT_DOMAIN"
echo "Functions:  https://functions.$ROOT_DOMAIN"
echo "REST:       https://rest.$ROOT_DOMAIN"
echo "GraphQL:    https://graphql.$ROOT_DOMAIN"
echo "Meta:       https://meta.$ROOT_DOMAIN"
echo "ImgProxy:   https://img.$ROOT_DOMAIN"
echo "Analytics:  https://analytics.$ROOT_DOMAIN"
echo ""
echo "Traefik dashboard: https://traefik.$ROOT_DOMAIN"
echo ""
echo ">>> ALL DONE."
