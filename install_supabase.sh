#!/bin/bash
set -e

###############################
# CONFIG
###############################
ROOT_DOMAIN="segundacabeza.net"
EMAIL="alvaro@segundacabeza.net"
INSTALL_DIR="/opt/supabase"

echo ">>> Installing full Supabase stack on $ROOT_DOMAIN"

###############################
# INSTALL DEPENDENCIES
###############################
apt update -y && apt upgrade -y
apt install -y ca-certificates curl gnupg git ufw openssl lsb-release

###############################
# INSTALL DOCKER
###############################
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
ufw allow ssh
ufw allow 80
ufw allow 443
yes | ufw enable || true

###############################
# DIRECTORY STRUCTURE
###############################
mkdir -p $INSTALL_DIR/traefik/dynamic
touch $INSTALL_DIR/traefik/acme.json
chmod 600 $INSTALL_DIR/traefik/acme.json

###############################
# GENERATE SECRETS
###############################
POSTGRES_PASSWORD=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32)
SERVICE_ROLE_KEY=$(openssl rand -hex 32)
PG_META_CRYPTO_KEY=$(openssl rand -hex 32)
DASHBOARD_PASSWORD=$(openssl rand -hex 16)
VAULT_ENC_KEY=$(openssl rand -hex 32)

###############################
# TRAEFIK STATIC CONFIG
###############################
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
# CREATE ENV FILE
###############################
cat <<EOF > $INSTALL_DIR/.env
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
PG_META_CRYPTO_KEY=$PG_META_CRYPTO_KEY
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD
VAULT_ENC_KEY=$VAULT_ENC_KEY

API_URL=https://api.$ROOT_DOMAIN
STUDIO_URL=https://studio.$ROOT_DOMAIN
AUTH_URL=https://auth.$ROOT_DOMAIN
STORAGE_URL=https://storage.$ROOT_DOMAIN
REALTIME_URL=https://realtime.$ROOT_DOMAIN
FUNCTIONS_URL=https://functions.$ROOT_DOMAIN
REST_URL=https://rest.$ROOT_DOMAIN
GRAPHQL_URL=https://graphql.$ROOT_DOMAIN
META_URL=https://meta.$ROOT_DOMAIN
IMG_URL=https://img.$ROOT_DOMAIN
ANALYTICS_URL=https://analytics.$ROOT_DOMAIN
EOF

###############################
# DOCKER COMPOSE
###############################
cat <<EOF > $INSTALL_DIR/docker-compose.yml
version: "3.9"

services:

  traefik:
    image: traefik:v3.1
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - ./traefik/acme.json:/acme.json
      - ./traefik/dynamic:/traefik/dynamic
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped

  db:
    image: supabase/postgres:15.1.0.89
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data
    restart: unless-stopped

  studio:
    image: supabase/studio:latest
    env_file: .env
    depends_on: [api]
    labels:
      - traefik.enable=true
      - traefik.http.routers.studio.rule=Host(\`studio.${ROOT_DOMAIN}\`)
      - traefik.http.routers.studio.entrypoints=websecure
      - traefik.http.routers.studio.tls.certresolver=letsencrypt
    restart: unless-stopped

  api:
    image: supabase/postgrest:latest
    env_file: .env
    depends_on: [db]
    labels:
      - traefik.enable=true
      - traefik.http.routers.api.rule=Host(\`api.${ROOT_DOMAIN}\`)
      - traefik.http.routers.api.entrypoints=websecure
      - traefik.http.routers.api.tls.certresolver=letsencrypt
    restart: unless-stopped

  auth:
    image: supabase/gotrue:latest
    env_file: .env
    depends_on: [db]
    labels:
      - traefik.enable=true
      - traefik.http.routers.auth.rule=Host(\`auth.${ROOT_DOMAIN}\`)
      - traefik.http.routers.auth.entrypoints=websecure
      - traefik.http.routers.auth.tls.certresolver=letsencrypt
    restart: unless-stopped

  storage:
    image: supabase/storage-api:latest
    env_file: .env
    depends_on: [db]
    labels:
      - traefik.enable=true
      - traefik.http.routers.storage.rule=Host(\`storage.${ROOT_DOMAIN}\`)
      - traefik.http.routers.storage.entrypoints=websecure
      - traefik.http.routers.storage.tls.certresolver=letsencrypt
    restart: unless-stopped

  realtime:
    image: supabase/realtime:latest
    env_file: .env
    depends_on: [db]
    labels:
      - traefik.enable=true
      - traefik.http.routers.realtime.rule=Host(\`realtime.${ROOT_DOMAIN}\`)
      - traefik.http.routers.realtime.entrypoints=websecure
      - traefik.http.routers.realtime.tls.certresolver=letsencrypt
    restart: unless-stopped

  functions:
    image: supabase/functions:latest
    env_file: .env
    labels:
      - traefik.enable=true
      - traefik.http.routers.functions.rule=Host(\`functions.${ROOT_DOMAIN}\`)
      - traefik.http.routers.functions.entrypoints=websecure
      - traefik.http.routers.functions.tls.certresolver=letsencrypt
    restart: unless-stopped

  graphql:
    image: supabase/graphql:latest
    depends_on: [db]
    labels:
      - traefik.enable=true
      - traefik.http.routers.graphql.rule=Host(\`graphql.${ROOT_DOMAIN}\`)
      - traefik.http.routers.graphql.entrypoints=websecure
      - traefik.http.routers.graphql.tls.certresolver=letsencrypt
    restart: unless-stopped

  rest:
    image: supabase/postgrest:latest
    env_file: .env
    depends_on: [db]
    labels:
      - traefik.enable=true
      - traefik.http.routers.rest.rule=Host(\`rest.${ROOT_DOMAIN}\`)
      - traefik.http.routers.rest.entrypoints=websecure
      - traefik.http.routers.rest.tls.certresolver=letsencrypt
    restart: unless-stopped

  meta:
    image: supabase/meta:latest
    env_file: .env
    depends_on: [db]
    labels:
      - traefik.enable=true
      - traefik.http.routers.meta.rule=Host(\`meta.${ROOT_DOMAIN}\`)
      - traefik.http.routers.meta.entrypoints=websecure
      - traefik.http.routers.meta.tls.certresolver=letsencrypt
    restart: unless-stopped

  img:
    image: supabase/imgproxy:latest
    labels:
      - traefik.enable=true
      - traefik.http.routers.img.rule=Host(\`img.${ROOT_DOMAIN}\`)
      - traefik.http.routers.img.entrypoints=websecure
      - traefik.http.routers.img.tls.certresolver=letsencrypt
    restart: unless-stopped

  analytics:
    image: supabase/logflare:latest
    labels:
      - traefik.enable=true
      - traefik.http.routers.analytics.rule=Host(\`analytics.${ROOT_DOMAIN}\`)
      - traefik.http.routers.analytics.entrypoints=websecure
      - traefik.http.routers.analytics.tls.certresolver=letsencrypt
    restart: unless-stopped

volumes:
  pgdata:
EOF

###############################
# START STACK
###############################
cd $INSTALL_DIR
docker compose up -d

echo ""
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
echo "Traefik:    https://traefik.$ROOT_DOMAIN"
echo ""
echo ">>> DONE."
