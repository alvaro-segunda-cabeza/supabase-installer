#!/usr/bin/env bash

set -e

DOMAIN="segundacabeza.net"
EMAIL="admin@$DOMAIN"

echo "=== Actualizando servidor ==="
apt update -y && apt upgrade -y

echo "=== Instalando dependencias ==="
apt install -y curl git nano ufw docker.io docker-compose-plugin

echo "=== Creando carpetas de instalación ==="
mkdir -p /apps/traefik
mkdir -p /apps/supabase

echo "=== Creando red compartida ==="
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

      # Redirección HTTP → HTTPS
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"

      # Certificados
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

echo "=== Iniciando Traefik ==="
docker compose -f /apps/traefik/docker-compose.yml up -d

#########################################
# SUPABASE
#########################################

echo "=== Descargando Supabase Self-Hosted ==="
cd /apps/supabase
git clone https://github.com/supabase/supabase.git source || true

cd source/docker

echo "=== Generando archivo Traefik override ==="

cat <<EOF >traefik.override.yml
version: "3.9"
services:
EOF

# Lista de servicios Supabase → subdominios esperados
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

echo "=== Instalación completada ==="
echo "Abrí https://studio.$DOMAIN para acceder al panel."
