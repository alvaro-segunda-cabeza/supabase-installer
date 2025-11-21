#!/usr/bin/env bash
set -e

DOMAIN="segundacabeza.net"
EMAIL="admin@$DOMAIN"

echo "==============================================="
echo "   INSTALADOR AUTOMÁTICO SUPABASE SELF-HOSTED  "
echo "        Dominio: $DOMAIN"
echo "==============================================="

echo "=== Actualizando repos ==="
apt update -y

echo "=== Instalando utilidades ==="
apt install -y git curl nano ufw

echo "=== Creando carpetas ==="
mkdir -p /apps/traefik
mkdir -p /apps/supabase

echo "=== Creando red traefik compartida ==="
docker network create traefik-network || true

#########################################
# TRAEFIK
#########################################

echo "=== Configurando Traefik ==="

cat <<EOF >/apps/traefik/docker-compose.yml
version: "3.9"

services:
  traefik:
    image: traefik:v2.11
    container_name: traefik
    restart: always
    command:
      - "--providers.docker=true"
      - "--api.dashboard=true"

      # Entradas
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"

      # Redirect HTTP -> HTTPS
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"

      # LetsEncrypt
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=$EMAIL"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"

      # Cloudflare proxied fix
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

echo "=== Levantando Traefik ==="
docker compose -f /apps/traefik/docker-compose.yml up -d

#########################################
# SUPABASE
#########################################

echo "=== Descargando Supabase Self-Hosted ==="
cd /apps/supabase
if [ ! -d "source" ]; then
  git clone https://github.com/supabase/supabase.git source
fi

cd source/docker

echo "=== Generando override de Traefik para los servicios de Supabase ==="

cat <<EOF >traefik.override.yml
version: "3.9"
services:
EOF

# Servicios → subdominios
declare -A SUBS=(
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

for SERVICE in "${!SUBS[@]}"; do
  SUBDOMAIN=${SUBS[$SERVICE]}

cat <<EOF >>traefik.override.yml
  $SERVICE:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${SERVICE}.entrypoints=websecure"
      - "traefik.http.routers.${SERVICE}.rule=Host(\\\"$SUBDOMAIN.$DOMAIN\\\")"
      - "traefik.http.routers.${SERVICE}.tls.certresolver=letsencrypt"
      - "traefik.http.services.${SERVICE}.loadbalancer.server.port=3000"
    networks:
      - traefik-network

EOF

done

echo "=== Iniciando Supabase ==="
docker compose -f docker-compose.yml -f traefik.override.yml up -d

echo "==============================================="
echo "   SUPABASE INSTALADO CORRECTAMENTE"
echo "==============================================="
echo "Panel: https://studio.$DOMAIN"
echo "API: https://api.$DOMAIN"
echo "REST: https://rest.$DOMAIN"
echo "Auth: https://auth.$DOMAIN"
echo "Storage: https://storage.$DOMAIN"
echo "Realtime: https://realtime.$DOMAIN"
echo "Functions: https://functions.$DOMAIN"
echo "GraphQL: https://graphql.$DOMAIN"
echo "==============================================="
