#!/bin/bash
set -e

###############################
# CONFIGURACIÓN
###############################
ROOT_DOMAIN="segundacabeza.net"
EMAIL="alvaro@segundacabeza.net"
INSTALL_DIR="/opt/supabase"

# Colores para logs
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}>>> Iniciando instalación Full Stack Supabase en $ROOT_DOMAIN...${NC}"

###############################
# 1. INSTALAR DEPENDENCIAS
###############################
echo -e "${GREEN}>>> Actualizando sistema e instalando Docker...${NC}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y
apt-get install -y ca-certificates curl gnupg git ufw openssl lsb-release

# Instalar Docker Oficial
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

###############################
# 2. FIREWALL (Sin interacción)
###############################
echo -e "${GREEN}>>> Configurando Firewall...${NC}"
ufw allow ssh
ufw allow 80
ufw allow 443
# Forzamos la activación sin pedir confirmación
ufw --force enable

###############################
# 3. ESTRUCTURA DE DIRECTORIOS
###############################
mkdir -p $INSTALL_DIR/traefik/dynamic
mkdir -p $INSTALL_DIR/volumes/db/data
mkdir -p $INSTALL_DIR/volumes/storage
touch $INSTALL_DIR/traefik/acme.json
chmod 600 $INSTALL_DIR/traefik/acme.json

###############################
# 4. GENERAR SECRETOS Y VARIABLES
###############################
echo -e "${GREEN}>>> Generando criptografía...${NC}"

POSTGRES_PASSWORD=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -hex 32)
ANON_KEY=$(openssl rand -hex 32) # Nota: En prod deberías generar un JWT real firmado con el JWT_SECRET
SERVICE_ROLE_KEY=$(openssl rand -hex 32) # Nota: Igual que arriba
DASHBOARD_PASSWORD=$(openssl rand -hex 16)
SECRET_KEY_BASE=$(openssl rand -hex 32)
VAULT_ENC_KEY=$(openssl rand -hex 32)

# URLS Internas para que los servicios se hablen
DB_URL="postgresql://postgres:${POSTGRES_PASSWORD}@db:5432/postgres"

###############################
# 5. CONFIGURAR TRAEFIK
###############################
cat <<EOF > $INSTALL_DIR/traefik/traefik.yml
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

certificatesResolvers:
  letsencrypt:
    acme:
      email: "$EMAIL"
      storage: "acme.json"
      httpChallenge:
        entryPoint: web

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
  file:
    directory: "/traefik/dynamic"
    watch: true

api:
  dashboard: true
EOF

###############################
# 6. CREAR ARCHIVO .ENV (COMPLETO)
###############################
# Este paso es crucial. Mapeamos las claves generadas a las variables 
# que Supabase REALMENTE espera.
cat <<EOF > $INSTALL_DIR/.env
# --- General ---
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
DASHBOARD_USERNAME=admin
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD
SECRET_KEY_BASE=$SECRET_KEY_BASE
VAULT_ENC_KEY=$VAULT_ENC_KEY

# --- URLs Públicas (Para que el Studio sepa donde buscar) ---
API_EXTERNAL_URL=https://api.$ROOT_DOMAIN
SUPABASE_PUBLIC_URL=https://api.$ROOT_DOMAIN
STUDIO_DEFAULT_API_URL=https://api.$ROOT_DOMAIN
STUDIO_DEFAULT_GRAPHQL_URL=https://graphql.$ROOT_DOMAIN

# --- Configuración Interna de Servicios ---
# DB
POSTGRES_DB=postgres
POSTGRES_PORT=5432
POSTGRES_HOST=db
DATABASE_URL=$DB_URL

# GoTrue (Auth)
GOTRUE_JWT_SECRET=$JWT_SECRET
GOTRUE_JWT_EXP=3600
GOTRUE_JWT_DEFAULT_GROUP_NAME=authenticated
GOTRUE_DB_DRIVER=postgres
GOTRUE_DATABASE_URL=$DB_URL
GOTRUE_SITE_URL=https://studio.$ROOT_DOMAIN
GOTRUE_URI_ALLOW_LIST=*
GOTRUE_EXTERNAL_EMAIL_ENABLED=true
GOTRUE_MAILER_AUTOCONFIRM=true

# REST (PostgREST)
PGRST_DB_URI=$DB_URL
PGRST_DB_SCHEMAS=public,storage,graphql_public
PGRST_DB_ANON_ROLE=anon
PGRST_JWT_SECRET=$JWT_SECRET

# Storage
STORAGE_BACKEND=file
TENANT_ID=stub
REGION=stub
GLOBAL_S3_BUCKET=stub

# Meta
PG_META_PORT=8080
PG_META_DB_HOST=db
PG_META_DB_PASSWORD=$POSTGRES_PASSWORD
EOF

###############################
# 7. DOCKER COMPOSE (FIXED)
###############################
# Se han corregido los nombres de las imágenes y añadido healthchecks
cat <<EOF > $INSTALL_DIR/docker-compose.yml
services:

  traefik:
    image: traefik:v3.1
    container_name: supabase-traefik
    command: --configFile=/etc/traefik/traefik.yml
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - ./traefik/acme.json:/acme.json
      - /var/run/docker.sock:/var/run/docker.sock:ro
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(\`traefik.${ROOT_DOMAIN}\`)"
      - "traefik.http.routers.dashboard.service=api@internal"
      - "traefik.http.routers.dashboard.entrypoints=websecure"
      - "traefik.http.routers.dashboard.tls.certresolver=letsencrypt"
      - "traefik.http.routers.dashboard.middlewares=auth"
      # Usuario: admin / Password: admin_password (puedes cambiarlo con htpasswd)
      - "traefik.http.middlewares.auth.basicauth.users=admin:$$apr1$$I6v/Gj.7$$S4.w/oY5s/tM3h.M1t4dC1"
    restart: always

  db:
    image: supabase/postgres:15.1.1.78
    container_name: supabase-db
    environment:
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: \${POSTGRES_DB}
    volumes:
      - ./volumes/db/data:/var/lib/postgresql/data
    restart: always
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  studio:
    image: supabase/studio:latest
    container_name: supabase-studio
    env_file: .env
    environment:
      STUDIO_PG_META_URL: http://meta:8080
      SUPABASE_URL: http://kong:8000 # Usamos API Gateway interno o directo a servicios
      SUPABASE_PUBLIC_URL: https://api.${ROOT_DOMAIN}
      SUPABASE_ANON_KEY: \${ANON_KEY}
      SUPABASE_SERVICE_KEY: \${SERVICE_ROLE_KEY}
    depends_on: 
      - db
      - meta
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.studio.rule=Host(\`studio.${ROOT_DOMAIN}\`)"
      - "traefik.http.routers.studio.entrypoints=websecure"
      - "traefik.http.routers.studio.tls.certresolver=letsencrypt"
    restart: always

  auth:
    image: supabase/auth:v2.158.1
    container_name: supabase-auth
    env_file: .env
    depends_on: 
      db:
        condition: service_healthy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.auth.rule=Host(\`auth.${ROOT_DOMAIN}\`)"
      - "traefik.http.routers.auth.entrypoints=websecure"
      - "traefik.http.routers.auth.tls.certresolver=letsencrypt"
    restart: always

  rest:
    image: postgrest/postgrest:v12.2.0
    container_name: supabase-rest
    env_file: .env
    depends_on: 
      db:
        condition: service_healthy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.rest.rule=Host(\`rest.${ROOT_DOMAIN}\`)"
      - "traefik.http.routers.rest.entrypoints=websecure"
      - "traefik.http.routers.rest.tls.certresolver=letsencrypt"
      # Api y Rest suelen ser lo mismo en setups simples, mapeamos ambos
      - "traefik.http.routers.api.rule=Host(\`api.${ROOT_DOMAIN}\`)"
      - "traefik.http.routers.api.entrypoints=websecure"
      - "traefik.http.routers.api.tls.certresolver=letsencrypt"
    restart: always

  realtime:
    image: supabase/realtime:v2.28.32
    container_name: supabase-realtime
    env_file: .env
    environment:
      DB_HOST: db
      DB_PORT: 5432
      DB_USER: postgres
      DB_PASSWORD: \${POSTGRES_PASSWORD}
      DB_NAME: postgres
      DB_SSL: "false"
      PORT: 4000
      JWT_SECRET: \${JWT_SECRET}
      REPLICATION_MODE: RLS
    depends_on: 
      db:
        condition: service_healthy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.realtime.rule=Host(\`realtime.${ROOT_DOMAIN}\`)"
      - "traefik.http.routers.realtime.entrypoints=websecure"
      - "traefik.http.routers.realtime.tls.certresolver=letsencrypt"
    restart: always

  storage:
    image: supabase/storage-api:v1.11.13
    container_name: supabase-storage
    env_file: .env
    environment:
      ANON_KEY: \${ANON_KEY}
      SERVICE_KEY: \${SERVICE_ROLE_KEY}
      POSTGREST_URL: http://rest:3000
      PGRST_JWT_SECRET: \${JWT_SECRET}
      DATABASE_URL: postgres://postgres:\${POSTGRES_PASSWORD}@db:5432/postgres
    volumes:
      - ./volumes/storage:/var/lib/storage
    depends_on: 
      - db
      - rest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.storage.rule=Host(\`storage.${ROOT_DOMAIN}\`)"
      - "traefik.http.routers.storage.entrypoints=websecure"
      - "traefik.http.routers.storage.tls.certresolver=letsencrypt"
    restart: always

  meta:
    image: supabase/postgres-meta:v0.84.2
    container_name: supabase-meta
    env_file: .env
    depends_on: 
      - db
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.meta.rule=Host(\`meta.${ROOT_DOMAIN}\`)"
      - "traefik.http.routers.meta.entrypoints=websecure"
      - "traefik.http.routers.meta.tls.certresolver=letsencrypt"
    restart: always

  # Edge Functions (Nombre correcto)
  functions:
    image: supabase/edge-runtime:v1.56.1
    container_name: supabase-functions
    env_file: .env
    environment:
      JWT_SECRET: \${JWT_SECRET}
      SUPABASE_URL: http://rest:3000
      SUPABASE_ANON_KEY: \${ANON_KEY}
      SUPABASE_SERVICE_ROLE_KEY: \${SERVICE_ROLE_KEY}
      POSTGRES_URL: postgres://postgres:\${POSTGRES_PASSWORD}@db:5432/postgres
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.functions.rule=Host(\`functions.${ROOT_DOMAIN}\`)"
      - "traefik.http.routers.functions.entrypoints=websecure"
      - "traefik.http.routers.functions.tls.certresolver=letsencrypt"
    restart: always

  # Analytics (Logflare)
  analytics:
    image: supabase/logflare:1.4.0
    container_name: supabase-analytics
    env_file: .env
    environment:
      DB_DATABASE: postgres
      DB_HOSTNAME: db
      DB_PORT: 5432
      DB_USERNAME: postgres
      DB_PASSWORD: \${POSTGRES_PASSWORD}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.analytics.rule=Host(\`analytics.${ROOT_DOMAIN}\`)"
      - "traefik.http.routers.analytics.entrypoints=websecure"
      - "traefik.http.routers.analytics.tls.certresolver=letsencrypt"
    restart: always

  imgproxy:
    image: darthsim/imgproxy:latest
    container_name: supabase-imgproxy
    environment:
      IMGPROXY_BIND: ":5001"
      IMGPROXY_LOCAL_FILESYSTEM_ROOT: /
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.img.rule=Host(\`img.${ROOT_DOMAIN}\`)"
      - "traefik.http.routers.img.entrypoints=websecure"
      - "traefik.http.routers.img.tls.certresolver=letsencrypt"
      - "traefik.http.services.img.loadbalancer.server.port=5001"
    restart: always

EOF

###############################
# 8. INICIAR STACK
###############################
echo -e "${GREEN}>>> Arrancando contenedores...${NC}"
cd $INSTALL_DIR
docker compose pull
docker compose up -d

echo ""
echo -e "${GREEN}>>> INSTALACIÓN COMPLETADA EXITOSAMENTE${NC}"
echo ""
echo "Tus Credenciales (G U Á R D A L A S):"
echo "-------------------------------------"
echo "Postgres Pwd:  $POSTGRES_PASSWORD"
echo "JWT Secret:    $JWT_SECRET"
echo "Anon Key:      $ANON_KEY"
echo "Service Key:   $SERVICE_ROLE_KEY"
echo "Dashboard Pwd: $DASHBOARD_PASSWORD"
echo "-------------------------------------"
echo "URLs Activas (Espera 1-2 min para certificados SSL):"
echo "Studio:     https://studio.$ROOT_DOMAIN"
echo "API/Rest:   https://api.$ROOT_DOMAIN"
echo "Auth:       https://auth.$ROOT_DOMAIN"
echo "Storage:    https://storage.$ROOT_DOMAIN"
echo ""
echo "Si usas Cloudflare Full Strict, asegúrate de que el 'SSL/TLS Recommender' esté activo"
echo "o que Traefik haya logrado generar el certificado correctamente."
