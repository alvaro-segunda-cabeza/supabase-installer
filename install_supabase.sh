#!/usr/bin/env bash
set -e

DOMAIN="segundacabeza.net"
EMAIL="admin@$DOMAIN"

API_DOMAIN="api.$DOMAIN"
STUDIO_DOMAIN="studio.$DOMAIN"

echo "==============================================="
echo " SUPABASE SELF-HOST (OFICIAL)                 "
echo " Usando Kong API Gateway con 1 solo dominio   "
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
    restart: always
    container_name: traefik
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
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /apps/traefik/letsencrypt:/letsencrypt
    networks:
      - traefik-network
networks:
  traefik-network:
    external: true
EOF

docker compose -f /apps/traefik/docker-compose.yml up -d

#########################################################
# SUPABASE
#########################################################

cd /apps/supabase

git clone --depth 1 --branch docker-compose https://github.com/supabase/supabase.git source || true

cd source/docker

#########################################################
# ENV GENERATION (OFICIAL)
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

API_EXTERNAL_URL=https://$API_DOMAIN
SITE_URL=https://$STUDIO_DOMAIN

POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=postgres
PGRST_DB_SCHEMAS=public,storage
EOF

#########################################################
# TRAEFIK OVERRIDE (OFICIAL 2 DOMINIOS)
#########################################################

cat <<EOF >traefik.override.yml
services:

  kong:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.kong.rule=Host(\\"$API_DOMAIN\\")"
      - "traefik.http.routers.kong.entrypoints=websecure"
      - "traefik.http.routers.kong.tls.certresolver=letsencrypt"
      - "traefik.http.services.kong.loadbalancer.server.port=8000"
    networks:
      - traefik-network

  studio:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.studio.rule=Host(\\"$STUDIO_DOMAIN\\")"
      - "traefik.http.routers.studio.entrypoints=websecure"
      - "traefik.http.routers.studio.tls.certresolver=letsencrypt"
      - "traefik.http.services.studio.loadbalancer.server.port=3000"
    networks:
      - traefik-network

networks:
  traefik-network:
    external: true
EOF

#########################################################
# START SUPABASE (OFICIAL)
#########################################################

docker compose -f docker-compose.yml -f traefik.override.yml up -d

#########################################################
# DONE
#########################################################

echo "==============================================="
echo " SUPABASE INSTALADO CORRECTAMENTE"
echo "==============================================="
echo "API Gateway (Kong): https://$API_DOMAIN"
echo "Studio Dashboard:   https://$STUDIO_DOMAIN"
echo "==============================================="
echo "POSTGRES_PASSWORD: $POSTGRES_PASSWORD"
echo "SERVICE_ROLE_KEY:  $SERVICE_ROLE_KEY"
echo "ANON_KEY:          $ANON_KEY"
echo "JWT_SECRET:        $JWT_SECRET"
echo "==============================================="
