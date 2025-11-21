#!/usr/bin/env bash
set -e

DOMAIN="segundacabeza.net"
EMAIL="admin@$DOMAIN"

echo "==============================================="
echo " INSTALADOR SUPABASE SELF-HOSTED (2025)        "
echo " Compatible con repo oficial                   "
echo "==============================================="

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
# SUPABASE (docker folder actual)
#########################################################

cd /apps/supabase

if [ ! -d "source" ]; then
  git clone --depth 1 https://github.com/supabase/supabase.git source
fi

cd source/docker

#########################################################
# ENV GENERATION (nuevo formato)
#########################################################

POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
PG_META_CRYPTO_KEY=$(openssl rand -hex 32)
SECRET_KEY_BASE=$(openssl rand -hex 48)
POOLER_TENANT_ID="default"

cat <<EOF >.env

# ---------------------
# DATABASE
# ---------------------
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=postgres
POSTGRES_PORT=5432

# Pooler
POOLER_TENANT_ID=$POOLER_TENANT_ID

# JWT + API KEYS
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY

# INTERNAL ENCRYPTION
PG_META_CRYPTO_KEY=$PG_META_CRYPTO_KEY
SECRET_KEY_BASE=$SECRET_KEY_BASE

# URLS
SUPABASE_PUBLIC_URL=https://api.$DOMAIN
SITE_URL=https://studio.$DOMAIN

# SMTP (vacío por ahora)
SMTP_ADMIN_EMAIL=$EMAIL
EOF

#########################################################
# TRAEFIK ROUTING (solo API + STUDIO)
#########################################################

cat <<EOF >traefik.override.yml
services:

  # EXPOSE KONG GATEWAY
  kong:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.kong.rule=Host(\\\"api.$DOMAIN\\\")"
      - "traefik.http.routers.kong.entrypoints=websecure"
      - "traefik.http.routers.kong.tls.certresolver=letsencrypt"
      - "traefik.http.services.kong.loadbalancer.server.port=8000"
    networks:
      - traefik-network

  # EXPOSE STUDIO
  studio:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.studio.rule=Host(\\\"studio.$DOMAIN\\\")"
      - "traefik.http.routers.studio.entrypoints=websecure"
      - "traefik.http.routers.studio.tls.certresolver=letsencrypt"
      - "traefik.http.services.studio.loadbalancer.server.port=3000"
    networks:
      - traefik-network

EOF

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
echo "Studio:       https://studio.$DOMAIN"
echo "API Gateway:  https://api.$DOMAIN"
echo "==============================================="
echo "POSTGRES_PASSWORD: $POSTGRES_PASSWORD"
echo "SERVICE_ROLE_KEY:  $SERVICE_ROLE_KEY"
echo "ANON_KEY:          $ANON_KEY"
echo "JWT_SECRET:        $JWT_SECRET"
echo "==============================================="
