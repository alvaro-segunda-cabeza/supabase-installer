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

# 0. Limpiar instalaciones previas
echo -e "${YELLOW}Limpiando instalaciones previas de Supabase...${NC}"
if [ -d "/opt/supabase" ]; then
    cd /opt/supabase
    docker compose down -v 2>/dev/null || true
    cd /
fi

# Detener y eliminar contenedores de Supabase
docker ps -a | grep -E "supabase|traefik|postgres|kong" | awk '{print $1}' | xargs -r docker stop 2>/dev/null || true
docker ps -a | grep -E "supabase|traefik|postgres|kong" | awk '{print $1}' | xargs -r docker rm 2>/dev/null || true

# Eliminar volúmenes de Docker relacionados
docker volume ls | grep supabase | awk '{print $2}' | xargs -r docker volume rm 2>/dev/null || true

# Hacer backup del directorio si existe
if [ -d "/opt/supabase" ]; then
    echo -e "${YELLOW}Respaldando instalación anterior...${NC}"
    mv /opt/supabase /opt/supabase_backup_$(date +%s) 2>/dev/null || true
fi

echo -e "${GREEN}✓ Limpieza completada${NC}"
echo ""

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
echo -e "${GREEN}Creando directorio de instalación...${NC}"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 5. Descargar configuración de Supabase desde GitHub
echo -e "${GREEN}Descargando configuración de Supabase...${NC}"
git clone --depth 1 https://github.com/supabase/supabase.git temp_repo

# Copiar archivos de docker
if [ -d "temp_repo/docker" ]; then
    cp -r temp_repo/docker/* .
fi

rm -rf temp_repo

# 6. Generar Secretos Seguros
echo -e "${GREEN}Generando secretos seguros...${NC}"
generate_secret() {
    openssl rand -base64 32 | tr -d '/+=' | head -c 32
}

POSTGRES_PASSWORD=$(generate_secret)
JWT_SECRET=$(generate_secret)
ANON_KEY=$(generate_secret)
SERVICE_KEY=$(generate_secret)
DASHBOARD_USERNAME="admin"
DASHBOARD_PASSWORD=$(generate_secret)
VAULT_ENC_KEY=$(generate_secret)
PG_META_CRYPTO_KEY=$(generate_secret)
SECRET_KEY_BASE=$(generate_secret)

echo -e "${GREEN}Generando autenticación básica para el Dashboard...${NC}"
BASIC_AUTH_HASH=$(echo "$DASHBOARD_PASSWORD" | htpasswd -ni $DASHBOARD_USERNAME | sed 's/\$/\$\$/g')

# 7. Crear archivo .env completo
echo -e "${GREEN}Creando archivo de configuración .env...${NC}"
cat > .env <<ENVFILE
# Secrets
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_KEY
DASHBOARD_USERNAME=$DASHBOARD_USERNAME
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD

# Database
POSTGRES_HOST=db
POSTGRES_DB=postgres
POSTGRES_PORT=5432

# API Proxy
KONG_HTTP_PORT=8000
KONG_HTTPS_PORT=8443

# API
PGRST_DB_SCHEMAS=public,storage,graphql_public

# Auth
SITE_URL=https://studio.$DOMAIN
ADDITIONAL_REDIRECT_URLS=
JWT_EXPIRY=3600
DISABLE_SIGNUP=false
API_EXTERNAL_URL=https://api.$DOMAIN

MAILER_URLPATHS_CONFIRMATION=/auth/v1/verify
MAILER_URLPATHS_INVITE=/auth/v1/verify
MAILER_URLPATHS_RECOVERY=/auth/v1/verify
MAILER_URLPATHS_EMAIL_CHANGE=/auth/v1/verify

# Email auth
ENABLE_EMAIL_SIGNUP=true
ENABLE_EMAIL_AUTOCONFIRM=true
SMTP_ADMIN_EMAIL=admin@$DOMAIN
SMTP_HOST=mail
SMTP_PORT=2500
SMTP_USER=fake_mail_user
SMTP_PASS=fake_mail_password
SMTP_SENDER_NAME=Supabase

# Phone auth
ENABLE_PHONE_SIGNUP=true
ENABLE_PHONE_AUTOCONFIRM=true

# Studio
STUDIO_DEFAULT_ORGANIZATION=Default Organization
STUDIO_DEFAULT_PROJECT=Default Project
SUPABASE_PUBLIC_URL=https://api.$DOMAIN

# Functions
FUNCTIONS_VERIFY_JWT=false

# Logs
LOGFLARE_PUBLIC_ACCESS_TOKEN=dummy-token
LOGFLARE_PRIVATE_ACCESS_TOKEN=dummy-token

# Pooler
POOLER_DEFAULT_POOL_SIZE=20
POOLER_MAX_CLIENT_CONN=100
POOLER_TENANT_ID=pooler-dev
POOLER_PROXY_PORT_TRANSACTION=6543
POOLER_DB_POOL_SIZE=10

# Storage
IMGPROXY_ENABLE_WEBP_DETECTION=true

# Edge Runtime
DOCKER_SOCKET_LOCATION=/var/run/docker.sock

# Vault
VAULT_ENC_KEY=$VAULT_ENC_KEY

# Meta
PG_META_CRYPTO_KEY=$PG_META_CRYPTO_KEY

# Misc
SECRET_KEY_BASE=$SECRET_KEY_BASE
ENABLE_ANONYMOUS_USERS=false
ENVFILE

# Guardar credenciales
cat > /root/supabase_credentials.txt <<CREDS
=== CREDENCIALES DE SUPABASE ===
Dominio: $DOMAIN
Postgres Password: $POSTGRES_PASSWORD
JWT Secret: $JWT_SECRET
Anon Key: $ANON_KEY
Service Role Key: $SERVICE_KEY
Dashboard User: $DASHBOARD_USERNAME
Dashboard Pass: $DASHBOARD_PASSWORD
Dashboard URL: https://studio.$DOMAIN
API URL: https://api.$DOMAIN
=================================
CREDS

# 8. Corregir docker-compose.yml (eliminar el error del socket)
echo -e "${GREEN}Corrigiendo archivos de Docker Compose...${NC}"
if [ -f "docker-compose.yml" ]; then
    sed -i 's|:/var/run/docker.sock:ro,z|/var/run/docker.sock:/var/run/docker.sock:ro|g' docker-compose.yml
    sed -i 's|:\${DOCKER_SOCKET_LOCATION:-/var/run/docker.sock}:ro,z|/var/run/docker.sock:/var/run/docker.sock:ro|g' docker-compose.yml
fi

# 9. Crear docker-compose.override.yml para Traefik
echo -e "${GREEN}Configurando Traefik y SSL...${NC}"
cat <<EOF > docker-compose.override.yml
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
      - "--certificatesresolvers.letsencrypt.acme.email=$EMAIL"
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
      - "traefik.http.routers.studio.rule=Host(\`studio.$DOMAIN\`)"
      - "traefik.http.routers.studio.entrypoints=websecure"
      - "traefik.http.routers.studio.tls.certresolver=letsencrypt"
      - "traefik.http.services.studio.loadbalancer.server.port=3000"
      - "traefik.http.routers.studio.middlewares=studio-auth,https-redirect"
      - "traefik.http.middlewares.studio-auth.basicauth.users=$BASIC_AUTH_HASH"
      - "traefik.http.routers.studio-http.rule=Host(\`studio.$DOMAIN\`)"
      - "traefik.http.routers.studio-http.entrypoints=web"
      - "traefik.http.routers.studio-http.middlewares=https-redirect"
      - "traefik.http.middlewares.https-redirect.redirectscheme.scheme=https"
      - "traefik.http.middlewares.https-redirect.redirectscheme.permanent=true"

  kong:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(\`api.$DOMAIN\`)"
      - "traefik.http.routers.api.entrypoints=websecure"
      - "traefik.http.routers.api.tls.certresolver=letsencrypt"
      - "traefik.http.services.api.loadbalancer.server.port=8000"
      - "traefik.http.routers.api-http.rule=Host(\`api.$DOMAIN\`)"
      - "traefik.http.routers.api-http.entrypoints=web"
      - "traefik.http.routers.api-http.middlewares=https-redirect"
EOF

# Crear directorio para certificados
mkdir -p letsencrypt volumes/logs
touch letsencrypt/acme.json
chmod 600 letsencrypt/acme.json

# 10. Iniciar servicios
echo -e "${GREEN}Iniciando contenedores de Supabase...${NC}"
docker compose up -d

# 11. Esperar a que los servicios estén listos
echo -e "${YELLOW}Esperando a que los servicios inicien (esto puede tomar 1-2 minutos)...${NC}"
sleep 30

# 12. Verificar estado de los contenedores
echo -e "${GREEN}Estado de los contenedores:${NC}"
docker compose ps

echo ""
echo -e "${GREEN}=== ✓ Instalación Completada ===${NC}"
echo ""
echo -e "${GREEN}Tus credenciales (también guardadas en /root/supabase_credentials.txt):${NC}"
echo -e "  Postgres Password: ${YELLOW}$POSTGRES_PASSWORD${NC}"
echo -e "  Anon Key:          ${YELLOW}$ANON_KEY${NC}"
echo -e "  Service Role Key:  ${YELLOW}$SERVICE_KEY${NC}"
echo -e "  Dashboard User:    ${YELLOW}$DASHBOARD_USERNAME${NC}"
echo -e "  Dashboard Pass:    ${YELLOW}$DASHBOARD_PASSWORD${NC}"
echo ""
echo -e "  Dashboard URL:     ${YELLOW}https://studio.$DOMAIN${NC}"
echo -e "  API URL:           ${YELLOW}https://api.$DOMAIN${NC}"
echo ""
echo -e "${YELLOW}IMPORTANTE - Configuración DNS en Cloudflare:${NC}"
echo -e "  1. Ve a Cloudflare > DNS > Records"
echo -e "  2. Crea registro A: ${GREEN}studio.$DOMAIN${NC} -> IP de tu servidor (Proxy: ${GREEN}Activado${NC})"
echo -e "  3. Crea registro A: ${GREEN}api.$DOMAIN${NC} -> IP de tu servidor (Proxy: ${GREEN}Activado${NC})"
echo -e "  4. En SSL/TLS > Overview, selecciona modo: ${GREEN}Full${NC}"
echo ""
echo -e "${YELLOW}Comandos útiles:${NC}"
echo -e "  Ver logs:     ${GREEN}cd /opt/supabase && docker compose logs -f${NC}"
echo -e "  Reiniciar:    ${GREEN}cd /opt/supabase && docker compose restart${NC}"
echo -e "  Detener:      ${GREEN}cd /opt/supabase && docker compose down${NC}"
echo -e "  Iniciar:      ${GREEN}cd /opt/supabase && docker compose up -d${NC}"
echo ""
