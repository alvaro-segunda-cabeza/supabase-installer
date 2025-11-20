#!/bin/bash

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Instalador Profesional de Supabase con Traefik y SSL ===${NC}"
echo -e "${YELLOW}Este script instalará Docker, Supabase y configurará Traefik con SSL automático.${NC}"
echo -e "${YELLOW}Requisitos: Ubuntu/Debian, Dominio apuntando a este servidor (Cloudflare Proxy OK).${NC}"
echo ""

# Verificar si se ejecuta como root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Por favor, ejecuta este script como root o con sudo.${NC}"
  exit 1
fi

# 1. Solicitar información al usuario
echo -e "${GREEN}Configuración inicial:${NC}"
echo ""
echo -n "Introduce tu dominio base (ej. midominio.com): "
read DOMAIN
echo -n "Introduce tu email para Let's Encrypt: "
read EMAIL

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    echo -e "${RED}Error: Dominio y Email son requeridos.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Configuración confirmada:${NC}"
echo -e "  Dominio: ${YELLOW}$DOMAIN${NC}"
echo -e "  Email: ${YELLOW}$EMAIL${NC}"
echo -e "  Studio: ${YELLOW}https://studio.$DOMAIN${NC}"
echo -e "  API: ${YELLOW}https://api.$DOMAIN${NC}"
echo ""
echo -e "${YELLOW}Iniciando instalación en 3 segundos...${NC}"
sleep 3

# 2. Actualizar sistema e instalar dependencias básicas
echo -e "${GREEN}Actualizando sistema...${NC}"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
apt-get install -y curl git wget sudo apache2-utils

# 3. Instalar Docker y Docker Compose
if ! command -v docker &> /dev/null; then
    echo -e "${GREEN}Instalando Docker...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
else
    echo -e "${GREEN}Docker ya está instalado.${NC}"
fi

# Asegurarse de que Docker está corriendo
systemctl enable docker
systemctl start docker

# 4. Preparar directorio de Supabase
INSTALL_DIR="/opt/supabase"
echo -e "${GREEN}Instalando Supabase en $INSTALL_DIR...${NC}"

if [ -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}El directorio $INSTALL_DIR ya existe. Haciendo backup...${NC}"
    mv "$INSTALL_DIR" "${INSTALL_DIR}_backup_$(date +%s)"
fi

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Clonar el repo oficial de docker de supabase (solo la carpeta docker)
echo -e "${GREEN}Descargando configuración de Supabase...${NC}"
git clone --depth 1 https://github.com/supabase/supabase.git temp_repo

# Verificar donde está la carpeta docker
if [ -d "temp_repo/docker" ]; then
    cp -r temp_repo/docker/* .
elif [ -d "temp_repo" ]; then
    # Si no hay carpeta docker, buscar archivos relevantes
    find temp_repo -name "docker-compose.yml" -type f -exec dirname {} \; | head -1 | xargs -I {} cp -r {}/* .
fi

rm -rf temp_repo

# Si no existe .env.example, crear uno básico
if [ ! -f ".env.example" ]; then
    echo -e "${YELLOW}Creando archivo .env desde cero...${NC}"
    cat > .env <<'ENVFILE'
############
# Secrets
############
POSTGRES_PASSWORD=your-super-secret-and-long-postgres-password
JWT_SECRET=your-super-secret-jwt-token-with-at-least-32-characters-long
ANON_KEY=your-anon-key
SERVICE_ROLE_KEY=your-service-role-key
DASHBOARD_USERNAME=supabase
DASHBOARD_PASSWORD=this_password_is_insecure_and_should_be_updated

############
# Database - You can change these to any PostgreSQL database that has logical replication enabled.
############
POSTGRES_HOST=db
POSTGRES_DB=postgres
POSTGRES_PORT=5432

############
# API Proxy - Configuration for the Kong Reverse proxy.
############
KONG_HTTP_PORT=8000
KONG_HTTPS_PORT=8443

############
# API - Configuration for PostgREST.
############
PGRST_DB_SCHEMAS=public,storage,graphql_public

############
# Auth - Configuration for the GoTrue authentication server.
############
SITE_URL=http://localhost:3000
ADDITIONAL_REDIRECT_URLS=
JWT_EXPIRY=3600
DISABLE_SIGNUP=false
API_EXTERNAL_URL=http://localhost:8000

MAILER_URLPATHS_CONFIRMATION=/auth/v1/verify
MAILER_URLPATHS_INVITE=/auth/v1/verify
MAILER_URLPATHS_RECOVERY=/auth/v1/verify
MAILER_URLPATHS_EMAIL_CHANGE=/auth/v1/verify

############
# Email auth
############
ENABLE_EMAIL_SIGNUP=true
ENABLE_EMAIL_AUTOCONFIRM=false
SMTP_ADMIN_EMAIL=admin@example.com
SMTP_HOST=mail
SMTP_PORT=2500
SMTP_USER=fake_mail_user
SMTP_PASS=fake_mail_password
SMTP_SENDER_NAME=fake_sender

############
# Phone auth
############
ENABLE_PHONE_SIGNUP=true
ENABLE_PHONE_AUTOCONFIRM=true

############
# Studio - Configuration for the Dashboard
############
STUDIO_DEFAULT_ORGANIZATION=Default Organization
STUDIO_DEFAULT_PROJECT=Default Project
SUPABASE_PUBLIC_URL=http://localhost:8000

############
# Functions - Configuration for Functions
############
FUNCTIONS_VERIFY_JWT=false

############
# Logs - Configuration for Logflare
############
LOGFLARE_PUBLIC_ACCESS_TOKEN=your-logflare-token
LOGFLARE_PRIVATE_ACCESS_TOKEN=your-logflare-private-token

############
# Metrics - Configuration for Prometheus
############

############
# Pooler - Configuration for Supavisor
############
POOLER_DEFAULT_POOL_SIZE=20
POOLER_MAX_CLIENT_CONN=100
POOLER_TENANT_ID=pooler-dev
POOLER_PROXY_PORT_TRANSACTION=6543
POOLER_DB_POOL_SIZE=10

############
# Storage - Configuration for Supabase Storage
############
IMGPROXY_ENABLE_WEBP_DETECTION=true

############
# Edge Runtime - Configuration for Edge Runtime
############
DOCKER_SOCKET_LOCATION=/var/run/docker.sock

############
# Vault - Configuration for Supabase Vault
############
VAULT_ENC_KEY=your-vault-encryption-key

############
# Meta - Configuration for Supabase Meta
############
PG_META_CRYPTO_KEY=your-pg-meta-crypto-key

############
# Misc
############
SECRET_KEY_BASE=your-secret-key-base
ENABLE_ANONYMOUS_USERS=false
ENVFILE
else
    cp .env.example .env
fi

# 5. Generar Secretos Seguros
echo -e "${GREEN}Generando secretos seguros...${NC}"
# Función para generar strings aleatorios
generate_secret() {
    openssl rand -base64 32 | tr -d '/+' | cut -c -32
}

POSTGRES_PASSWORD=$(generate_secret)
JWT_SECRET=$(generate_secret)
ANON_KEY=$(generate_secret)
SERVICE_KEY=$(generate_secret)
DASHBOARD_USERNAME="admin"
DASHBOARD_PASSWORD=$(generate_secret)

echo -e "${GREEN}Generando autenticación básica para el Dashboard...${NC}"
# Generar hash para Traefik Basic Auth (sin -B para evitar errores)
BASIC_AUTH_USER="$DASHBOARD_USERNAME"
BASIC_AUTH_PASS="$DASHBOARD_PASSWORD"
BASIC_AUTH_HASH=$(echo "$BASIC_AUTH_PASS" | htpasswd -ni $BASIC_AUTH_USER | sed 's/\$/\$\$/g')

# Configurar TODAS las variables necesarias en el .env
echo -e "${GREEN}Configurando variables de entorno...${NC}"

# Variables de Postgres
sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|g" .env
sed -i "s|POSTGRES_HOST=.*|POSTGRES_HOST=db|g" .env
sed -i "s|POSTGRES_DB=.*|POSTGRES_DB=postgres|g" .env
sed -i "s|POSTGRES_PORT=.*|POSTGRES_PORT=5432|g" .env

# Variables JWT y Keys
sed -i "s|JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|g" .env
sed -i "s|ANON_KEY=.*|ANON_KEY=$ANON_KEY|g" .env
sed -i "s|SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$SERVICE_KEY|g" .env

# Variables de URLs
sed -i "s|API_EXTERNAL_URL=.*|API_EXTERNAL_URL=https://api.$DOMAIN|g" .env
sed -i "s|SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=https://api.$DOMAIN|g" .env
sed -i "s|SITE_URL=.*|SITE_URL=https://studio.$DOMAIN|g" .env

# Variables de Studio
sed -i "s|STUDIO_DEFAULT_ORGANIZATION=.*|STUDIO_DEFAULT_ORGANIZATION=Default Organization|g" .env
sed -i "s|STUDIO_DEFAULT_PROJECT=.*|STUDIO_DEFAULT_PROJECT=Default Project|g" .env

# Variables de Dashboard
sed -i "s|DASHBOARD_USERNAME=.*|DASHBOARD_USERNAME=$DASHBOARD_USERNAME|g" .env
sed -i "s|DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD|g" .env

# Variables de Kong
sed -i "s|KONG_HTTP_PORT=.*|KONG_HTTP_PORT=8000|g" .env
sed -i "s|KONG_HTTPS_PORT=.*|KONG_HTTPS_PORT=8443|g" .env

# Verificar que las variables se aplicaron
if ! grep -q "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" .env; then
    echo -e "${YELLOW}Agregando variables faltantes al .env...${NC}"
    cat >> .env <<ENVVARS

# Variables configuradas por el instalador
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_HOST=db
POSTGRES_DB=postgres
POSTGRES_PORT=5432
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_KEY
API_EXTERNAL_URL=https://api.$DOMAIN
SUPABASE_PUBLIC_URL=https://api.$DOMAIN
SITE_URL=https://studio.$DOMAIN
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD
KONG_HTTP_PORT=8000
KONG_HTTPS_PORT=8443
ENVVARS
fi

# Guardar credenciales
cat > /root/supabase_credentials.txt <<CREDS
=== CREDENCIALES DE SUPABASE ===
Dominio: $DOMAIN
Postgres Password: $POSTGRES_PASSWORD
Dashboard User: $DASHBOARD_USERNAME
Dashboard Pass: $DASHBOARD_PASSWORD
Dashboard URL: https://studio.$DOMAIN
API URL: https://api.$DOMAIN
=================================
CREDS

# 6. Crear docker-compose.override.yml para Traefik
echo -e "${GREEN}Configurando Traefik y SSL...${NC}"

cat <<'EOF' > docker-compose.override.yml
version: "3.8"

services:
  traefik:
    image: traefik:v2.10
    container_name: traefik
    restart: unless-stopped
    command:
      - "--api.insecure=false"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=EMAIL_PLACEHOLDER"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--log.level=INFO"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "./letsencrypt:/letsencrypt"
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
    networks:
      - default

  studio:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.studio.rule=Host(\`studio.DOMAIN_PLACEHOLDER\`)"
      - "traefik.http.routers.studio.entrypoints=websecure"
      - "traefik.http.routers.studio.tls.certresolver=letsencrypt"
      - "traefik.http.services.studio.loadbalancer.server.port=3000"
      - "traefik.http.routers.studio.middlewares=studio-auth,https-redirect"
      - "traefik.http.middlewares.studio-auth.basicauth.users=BASICAUTH_PLACEHOLDER"
      - "traefik.http.routers.studio-http.rule=Host(\`studio.DOMAIN_PLACEHOLDER\`)"
      - "traefik.http.routers.studio-http.entrypoints=web"
      - "traefik.http.routers.studio-http.middlewares=https-redirect"
      - "traefik.http.middlewares.https-redirect.redirectscheme.scheme=https"
      - "traefik.http.middlewares.https-redirect.redirectscheme.permanent=true"

  kong:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(\`api.DOMAIN_PLACEHOLDER\`)"
      - "traefik.http.routers.api.entrypoints=websecure"
      - "traefik.http.routers.api.tls.certresolver=letsencrypt"
      - "traefik.http.services.api.loadbalancer.server.port=8000"
      - "traefik.http.routers.api-http.rule=Host(\`api.DOMAIN_PLACEHOLDER\`)"
      - "traefik.http.routers.api-http.entrypoints=web"
      - "traefik.http.routers.api-http.middlewares=https-redirect"

  vector:
    volumes:
      - ./volumes/logs/vector.yml:/etc/vector/vector.yml:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
EOF

# Reemplazar placeholders
sed -i "s|EMAIL_PLACEHOLDER|$EMAIL|g" docker-compose.override.yml
sed -i "s|DOMAIN_PLACEHOLDER|$DOMAIN|g" docker-compose.override.yml
sed -i "s|BASICAUTH_PLACEHOLDER|$BASIC_AUTH_HASH|g" docker-compose.override.yml

# Crear directorio para certificados
mkdir -p letsencrypt
touch letsencrypt/acme.json
chmod 600 letsencrypt/acme.json

# 7. Detener servicios previos si existen
echo -e "${GREEN}Deteniendo servicios anteriores si existen...${NC}"
docker compose down 2>/dev/null || true

# 8. Iniciar servicios
echo -e "${GREEN}Iniciando contenedores...${NC}"
docker compose up -d

# 9. Esperar a que los servicios estén listos
echo -e "${YELLOW}Esperando a que los servicios inicien (esto puede tomar 1-2 minutos)...${NC}"
sleep 30

# 10. Verificar estado de los contenedores
echo -e "${GREEN}Estado de los contenedores:${NC}"
docker compose ps

echo ""
echo -e "${GREEN}=== ✓ Instalación Completada ===${NC}"
echo ""
echo -e "${GREEN}Tus credenciales (también guardadas en /root/supabase_credentials.txt):${NC}"
echo -e "  Postgres Password: ${YELLOW}$POSTGRES_PASSWORD${NC}"
echo -e "  Dashboard User:    ${YELLOW}$DASHBOARD_USERNAME${NC}"
echo -e "  Dashboard Pass:    ${YELLOW}$DASHBOARD_PASSWORD${NC}"
echo -e "  Dashboard URL:     ${YELLOW}https://studio.$DOMAIN${NC}"
echo -e "  API URL:           ${YELLOW}https://api.$DOMAIN${NC}"
echo ""
echo -e "${YELLOW}IMPORTANTE - Configuración DNS en Cloudflare:${NC}"
echo -e "  1. Ve a Cloudflare > DNS > Records"
echo -e "  2. Crea registro A: ${GREEN}studio.$DOMAIN${NC} -> IP de tu servidor (Proxy: ${GREEN}Activado${NC})"
echo -e "  3. Crea registro A: ${GREEN}api.$DOMAIN${NC} -> IP de tu servidor (Proxy: ${GREEN}Activado${NC})"
echo -e "  4. En SSL/TLS > Overview, selecciona modo: ${GREEN}Full${NC}"
echo ""
echo -e "${YELLOW}Para ver los logs:${NC} cd /opt/supabase && docker compose logs -f"
echo -e "${YELLOW}Para reiniciar:${NC} cd /opt/supabase && docker compose restart"
echo ""
