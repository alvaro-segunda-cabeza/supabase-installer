#!/usr/bin/env bash
set -e

DOMAIN="segundacabeza.net"
EMAIL="admin@$DOMAIN"

echo "==============================================="
echo " INSTALADOR SUPABASE SELF-HOSTED (OFICIAL)    "
echo " Rama estable: docker-compose                  "
echo "==============================================="

apt update -y
apt install -y git curl jq openssl nano ufw

mkdir -p /apps/traefik
mkdir -p /apps/supabase

docker network create traefik-network || true

#########################################################
# TRAEFIK
#########################################################

cat <<EOF >/apps/traefik/docker-compose.yml
services:
  traefik:
    image: traefik:v2.11
    container_name: traefik
    restart: always
    command:
      - "--providers.docker=true"
      - "--api.dashboard=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=$EMAIL"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--serversTransport.insecureSkipVerify=true"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "/apps/traefik/letsencrypt:/letsencrypt"
    networks:
      - traefik-network

networks:
  traefik-network:
    external: true
EOF

docker compose -f /apps/traefik/docker-compose.yml up -d

#########################################################
# SUPABASE (docker-compose branch)
#########################################################

cd /apps/supabase

if [ ! -d "source" ]; then
  git clone --depth 1 --branch docker-compose https://github.com/supabase/supabase.git source
fi

cd source/docker

#########################################################
# ENV GENERATION
#########################################################

POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)

cat <<EOF >.env
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
ANON_KEY=$ANON_KEY

SITE_URL=https://studio.$DOMAIN
API_EXTERNAL_URL=https://api.$DOMAIN

POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=postgres
PGRST_DB_SCHEMAS=public,storage
EOF

#########################################################
# TRAEFIK OVERRIDE
#########################################################

cat <<EOF >traefik.override.yml
services:
EOF

declare -A SUBDOMAINS=(
  ["kong"]="api"
  ["gotrue"]="auth"
  ["auth"]="auth"
  ["rest"]="rest"
  ["postgres-meta"]="meta"
  ["realtime"]="realtime"
  ["storage-gateway"]="storage"
  ["imgproxy"]="img"
  ["studio"]="studio"
  ["analytics"]="analytics"
  ["pgrst"]="rest"
  ["supavisor"]="graphql"
  ["edge-runtime"]="functions"
)

for SERVICE in "${!SUBDOMAINS[@]}"; do
  SUB=${SUBDOMAINS[$SERVICE]}

cat <<EOF >>traefik.override.yml
  $SERVICE:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${SERVICE}.entrypoints=websecure"
      - "traefik.http.routers.${SERVICE}.rule=Host(\\\"$SUB.$DOMAIN\\\")"
      - "traefik.http.routers.${SERVICE}.tls.certresolver=letsencrypt"
      - "traefik.http.services.${SERVICE}.loadbalancer.server.port=3000"
    networks:
      - traefik-network

EOF
done

#########################################################
# START SUPABASE
#########################################################

docker compose -f docker-compose.yml -f traefik.override.yml up -d

#########################################################
# DONE
#########################################################

echo "==============================================="
echo " SUPABASE INSTALADO CORRECTAMENTE"
echo "==============================================="
echo "Panel Studio: https://studio.$DOMAIN"
echo "API Gateway:  https://api.$DOMAIN"
echo "REST:         https://rest.$DOMAIN"
echo "Auth:         https://auth.$DOMAIN"
echo "Storage:      https://storage.$DOMAIN"
echo "Realtime:     https://realtime.$DOMAIN"
echo "Edge Func:    https://functions.$DOMAIN"
echo "GraphQL:      https://graphql.$DOMAIN"
echo "==============================================="
echo "POSTGRES_PASSWORD: $POSTGRES_PASSWORD"
echo "SERVICE_ROLE_KEY:  $SERVICE_ROLE_KEY"
echo "ANON_KEY:          $ANON_KEY"
echo "JWT_SECRET:        $JWT_SECRET"
echo "==============================================="
