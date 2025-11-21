#!/usr/bin/env bash
set -e

DOMAIN="segundacabeza.net"
EMAIL="admin@$DOMAIN"
# 💡 CAMBIO 1: Usamos 'latest' en lugar de una versión fija
SUPABASE_RELEASE="latest" 

echo "==============================================="
echo " SUPABASE SELF-HOST (OFICIAL, RELEASE ESTABLE)"
echo " Release: $SUPABASE_RELEASE"
echo "==============================================="

apt update -y
apt install -y git curl jq openssl nano ufw

mkdir -p /apps/traefik
mkdir -p /apps/supabase

# Evitar el error "network already exists"
docker network create traefik-network 2>/dev/null || true

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

---------------------------------------------------------

#########################################################
# SUPABASE RELEASE
#########################################################

cd /apps/supabase

if [ ! -d "source" ]; then
  # 💡 CAMBIO 2: Usamos 'latest' como la rama a clonar
  git clone --branch "$SUPABASE_RELEASE" --single-branch --depth 1 https://github.com/supabase/supabase.git source
fi

# El 'cd source' sigue siendo correcto para la estructura moderna
cd source

#########################################################
# GENERACIÓN DE CLAVES
#########################################################

POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)

#########################################################
# CREAR .env OFICIAL
#########################################################

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
EOF

#########################################################
# TRAEFIK OVERRIDE PARA KONG + STUDIO
#########################################################

cat <<EOF >traefik.override.yml
services:
  kong:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.kong.entrypoints=websecure"
      - "traefik.http.routers.kong.rule=Host(\\\"api.$DOMAIN\\\")"
      - "traefik.http.routers.kong.tls.certresolver=letsencrypt"
      - "traefik.http.services.kong.loadbalancer.server.port=8000"
    networks:
      - traefik-network

  studio:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.studio.entrypoints=websecure"
      - "traefik.http.routers.studio.rule=Host(\\\"studio.$DOMAIN\\\")"
      - "traefik.http.routers.studio.tls.certresolver=letsencrypt"
      - "traefik.http.services.studio.loadbalancer.server.port=3000"
    networks:
      - traefik-network
EOF

#########################################################
# LEVANTAR SUPABASE
#########################################################

docker compose -f docker-compose.yml -f traefik.override.yml up -d

---------------------------------------------------------

#########################################################
# DONE
#########################################################

echo "==============================================="
echo " SUPABASE INSTALADO CORRECTAMENTE"
echo "==============================================="
echo "Studio: https://studio.$DOMAIN"
echo "API Gateway (Kong): https://api.$DOMAIN"
echo "==============================================="
echo "POSTGRES_PASSWORD: $POSTGRES_PASSWORD"
echo "SERVICE_ROLE_KEY:  $SERVICE_ROLE_KEY"
echo "ANON_KEY:          $ANON_KEY"
echo "JWT_SECRET:        $JWT_SECRET"
echo "==============================================="
