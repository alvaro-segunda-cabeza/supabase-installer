#!/usr/bin/env bash
set -e

###############################################
# CONFIG
###############################################
DOMAIN="segundacabeza.net"
EMAIL="admin@$DOMAIN"
SUPABASE_DIR="/apps/supabase"
TRAEFIK_DIR="/apps/traefik"
NETWORK="traefik-network"

echo "==============================================="
echo " 🚀 INSTALANDO SUPABASE SELF-HOST"
echo "==============================================="

###############################################
# DEPENDENCIAS
###############################################
apt update -y
apt install -y git curl jq openssl nano ufw

mkdir -p "$SUPABASE_DIR"
mkdir -p "$TRAEFIK_DIR"

docker network create "$NETWORK" 2>/dev/null || true

###############################################
# TRAEFIK
###############################################
cat <<EOF >$TRAEFIK_DIR/docker-compose.yml
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
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=$EMAIL"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--serversTransport.insecureSkipVerify=true"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "$TRAEFIK_DIR/letsencrypt:/letsencrypt"
    networks:
      - $NETWORK

networks:
  $NETWORK:
    external: true
EOF

docker compose -f $TRAEFIK_DIR/docker-compose.yml up -d

###############################################
# SUPABASE OFICIAL
###############################################
cd "$SUPABASE_DIR"

# Clonar repo (branch/master)
if [ ! -d "supabase" ]; then
  git clone --depth 1 https://github.com/supabase/supabase.git
fi

cd supabase/docker

###############################################
# ENV FILE (basado en .env.example OFICIAL)
###############################################
cp .env.example .env

POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -base64 32 | tr -d '\n')

# Generar JWT tokens usando Python (disponible en la mayoría de sistemas)
ANON_KEY=$(python3 -c "
import jwt
import time
secret = '$JWT_SECRET'
payload = {
    'iss': 'supabase',
    'ref': 'default',
    'role': 'anon',
    'iat': int(time.time()),
    'exp': int(time.time()) + 315360000
}
print(jwt.encode(payload, secret, algorithm='HS256'))
" 2>/dev/null || echo "")

SERVICE_ROLE_KEY=$(python3 -c "
import jwt
import time
secret = '$JWT_SECRET'
payload = {
    'iss': 'supabase',
    'ref': 'default',
    'role': 'service_role',
    'iat': int(time.time()),
    'exp': int(time.time()) + 315360000
}
print(jwt.encode(payload, secret, algorithm='HS256'))
" 2>/dev/null || echo "")

# Si Python no funciona, instalar PyJWT y reintentar
if [ -z "$ANON_KEY" ] || [ -z "$SERVICE_ROLE_KEY" ]; then
  echo "📦 Instalando PyJWT para generar tokens..."
  apt install -y python3-pip
  pip3 install PyJWT --break-system-packages 2>/dev/null || pip3 install PyJWT
  
  ANON_KEY=$(python3 -c "
import jwt
import time
secret = '$JWT_SECRET'
payload = {
    'iss': 'supabase',
    'ref': 'default',
    'role': 'anon',
    'iat': int(time.time()),
    'exp': int(time.time()) + 315360000
}
print(jwt.encode(payload, secret, algorithm='HS256'))
")

  SERVICE_ROLE_KEY=$(python3 -c "
import jwt
import time
secret = '$JWT_SECRET'
payload = {
    'iss': 'supabase',
    'ref': 'default',
    'role': 'service_role',
    'iat': int(time.time()),
    'exp': int(time.time()) + 315360000
}
print(jwt.encode(payload, secret, algorithm='HS256'))
")
fi

# Actualizar variables críticas
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|" .env
sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|" .env
sed -i "s|^ANON_KEY=.*|ANON_KEY=$ANON_KEY|" .env
sed -i "s|^SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY|" .env

# URLs externas
sed -i "s|^API_EXTERNAL_URL=.*|API_EXTERNAL_URL=https://api.$DOMAIN|" .env
sed -i "s|^SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=https://api.$DOMAIN|" .env
sed -i "s|^STUDIO_DEFAULT_PROJECT=.*|STUDIO_DEFAULT_PROJECT=Default Project|" .env

# URLs internas para Studio
sed -i "s|^SUPABASE_URL=.*|SUPABASE_URL=http://kong:8000|" .env
sed -i "s|^STUDIO_PG_META_URL=.*|STUDIO_PG_META_URL=http://meta:8080|" .env

# Dashboard
sed -i "s|^DASHBOARD_USERNAME=.*|DASHBOARD_USERNAME=supabase|" .env
sed -i "s|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=$POSTGRES_PASSWORD|" .env

###############################################
# TRAEFIK OVERRIDE
###############################################
cat <<EOF > traefik.override.yml
services:
  kong:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.kong.rule=Host(\`api.$DOMAIN\`)"
      - "traefik.http.routers.kong.entrypoints=websecure"
      - "traefik.http.routers.kong.tls.certresolver=letsencrypt"
      - "traefik.http.services.kong.loadbalancer.server.port=8000"
    networks:
      - $NETWORK

  studio:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.studio.rule=Host(\`studio.$DOMAIN\`)"
      - "traefik.http.routers.studio.entrypoints=websecure"
      - "traefik.http.routers.studio.tls.certresolver=letsencrypt"
      - "traefik.http.services.studio.loadbalancer.server.port=3000"
    networks:
      - $NETWORK

networks:
  $NETWORK:
    external: true
EOF

###############################################
# INICIAR SUPABASE
###############################################
docker compose pull
docker compose -f docker-compose.yml -f traefik.override.yml up -d

# Esperar a que los servicios estén listos
echo "⏳ Esperando a que los servicios inicien..."
sleep 30

###############################################
# FIN
###############################################
echo "==============================================="
echo " ✅ SUPABASE INSTALADO"
echo "==============================================="
echo "Studio: https://studio.$DOMAIN"
echo "API:    https://api.$DOMAIN"
echo ""
echo "Credenciales Dashboard:"
echo "Username: supabase"
echo "Password: $POSTGRES_PASSWORD"
echo ""
echo "Guardá estas claves:"
echo "POSTGRES_PASSWORD: $POSTGRES_PASSWORD"
echo "SERVICE_ROLE_KEY:  $SERVICE_ROLE_KEY"
echo "ANON_KEY:          $ANON_KEY"
echo "JWT_SECRET:        $JWT_SECRET"
echo "==============================================="
