#!/bin/bash

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}Estamos intentando instalar Supabase con un solo comando.${NC}"
echo ""

# Verificar si se ejecuta como root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Por favor, ejecuta este script como root o con sudo.${NC}"
  exit 1
fi

# 0. Limpiar instalaciones previas
if [ -d "/opt/supabase" ]; then
    cd /opt/supabase
    docker compose down -v 2>/dev/null || true
    cd /
fi

docker ps -a | grep -E "supabase|traefik|postgres|kong" | awk '{print $1}' | xargs -r docker stop 2>/dev/null || true
docker ps -a | grep -E "supabase|traefik|postgres|kong" | awk '{print $1}' | xargs -r docker rm 2>/dev/null || true
docker volume ls | grep supabase | awk '{print $2}' | xargs -r docker volume rm 2>/dev/null || true

if [ -d "/opt/supabase" ]; then
    rm -rf /opt/supabase 2>/dev/null || true
fi

# 1. Solicitar información al usuario
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

# 2. Actualizar sistema e instalar dependencias básicas
apt-get update -y > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" > /dev/null 2>&1
apt-get install -y curl git wget sudo apache2-utils > /dev/null 2>&1

sleep 30
echo -e "${CYAN}Ah re que intentando, nada que ver el chabón. Venimos bien.${NC}"
echo ""

# 3. Instalar Docker y Docker Compose
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh > /dev/null 2>&1
    rm get-docker.sh
fi

systemctl enable docker > /dev/null 2>&1
systemctl start docker > /dev/null 2>&1

# 4. Preparar directorio de Supabase
INSTALL_DIR="/opt/supabase"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 5. Descargar configuración de Supabase desde GitHub
git clone --depth 1 https://github.com/supabase/supabase.git temp_repo > /dev/null 2>&1

if [ -d "temp_repo/docker" ]; then
    cp -r temp_repo/docker/* .
fi

rm -rf temp_repo

sleep 30
echo -e "${CYAN}Supabase viene del griego supa, que significa base.${NC}"
echo ""

# 6. Generar Secretos Seguros
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

BASIC_AUTH_HASH=$(echo "$DASHBOARD_PASSWORD" | htpasswd -ni $DASHBOARD_USERNAME 2>/dev/null | sed 's/\$/\$\$/g')

# 7. Crear archivo .env completo
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

sleep 30
echo -e "${CYAN}Bueno no, no era así. Pero igual la instalación viene joya. Faltan unos 3 o 4 minutos, dependiendo cuánto hayas puesto en este servidor.${NC}"
echo ""

# 8. Corregir COMPLETAMENTE docker-compose.yml - TODAS las variantes del error
if [ -f "docker-compose.yml" ]; then
    # Corregir todas las variantes posibles del path duplicado
    sed -i 's|/var/run/docker.sock/var/run/docker.sock|/var/run/docker.sock|g' docker-compose.yml
    sed -i 's|:/var/run/docker.sock:ro,z|/var/run/docker.sock:/var/run/docker.sock:ro|g' docker-compose.yml
    sed -i 's|:\${DOCKER_SOCKET_LOCATION:-/var/run/docker.sock}:ro,z|\${DOCKER_SOCKET_LOCATION:-/var/run/docker.sock}:/var/run/docker.sock:ro|g' docker-compose.yml
    sed -i 's|:\${DOCKER_SOCKET_LOCATION}:ro,z|\${DOCKER_SOCKET_LOCATION:-/var/run/docker.sock}:/var/run/docker.sock:ro|g' docker-compose.yml
    
    # Buscar y reemplazar cualquier línea que empiece con : en volumes
    sed -i '/volumes:/,/^[^ ]/ s|^[[:space:]]*- :[^:]*:|      - /var/run/docker.sock:|g' docker-compose.yml
fi

# 9. Crear docker-compose.override.yml para Traefik
cat > docker-compose.override.yml <<EOF
version: "3.8"

services:
  traefik:
    image: traefik:v3.1
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
      - "traefik.http.routers.studio.rule=Host(\\\`studio.$DOMAIN\\\`)"
      - "traefik.http.routers.studio.entrypoints=websecure"
      - "traefik.http.routers.studio.tls.certresolver=letsencrypt"
      - "traefik.http.services.studio.loadbalancer.server.port=3000"
      - "traefik.http.routers.studio.middlewares=studio-auth,https-redirect"
      - "traefik.http.middlewares.studio-auth.basicauth.users=$BASIC_AUTH_HASH"
      - "traefik.http.routers.studio-http.rule=Host(\\\`studio.$DOMAIN\\\`)"
      - "traefik.http.routers.studio-http.entrypoints=web"
      - "traefik.http.routers.studio-http.middlewares=https-redirect"
      - "traefik.http.middlewares.https-redirect.redirectscheme.scheme=https"
      - "traefik.http.middlewares.https-redirect.redirectscheme.permanent=true"

  kong:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(\\\`api.$DOMAIN\\\`)"
      - "traefik.http.routers.api.entrypoints=websecure"
      - "traefik.http.routers.api.tls.certresolver=letsencrypt"
      - "traefik.http.services.api.loadbalancer.server.port=8000"
      - "traefik.http.routers.api-http.rule=Host(\\\`api.$DOMAIN\\\`)"
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

mkdir -p letsencrypt volumes/logs
touch letsencrypt/acme.json
chmod 600 letsencrypt/acme.json

# 10. Iniciar servicios
docker compose up -d > /dev/null 2>&1

sleep 60
echo -e "${CYAN}Estamos próximos a terminar.${NC}"
echo ""

# 11. Verificar que los servicios estén corriendo
echo -e "${CYAN}Verificando servicios...${NC}"
sleep 30

# Verificar contenedores críticos
TRAEFIK_RUNNING=$(docker ps --filter "name=traefik" --format "{{.Names}}" 2>/dev/null)
DB_RUNNING=$(docker ps --filter "name=supabase-db" --format "{{.Names}}" 2>/dev/null)
STUDIO_RUNNING=$(docker ps --filter "name=supabase-studio" --format "{{.Names}}" 2>/dev/null)
KONG_RUNNING=$(docker ps --filter "name=supabase-kong" --format "{{.Names}}" 2>/dev/null)

if [ -z "$TRAEFIK_RUNNING" ] || [ -z "$DB_RUNNING" ] || [ -z "$STUDIO_RUNNING" ] || [ -z "$KONG_RUNNING" ]; then
    echo -e "${RED}Algunos servicios no iniciaron correctamente.${NC}"
    echo -e "${YELLOW}Mostrando logs de los últimos servicios:${NC}"
    echo ""
    docker compose ps
    echo ""
    docker compose logs --tail=20
    echo ""
    echo -e "${RED}Hubo un problema. Revisá los logs arriba.${NC}"
    echo -e "${YELLOW}Podés intentar reiniciar con: cd /opt/supabase && docker compose restart${NC}"
    exit 1
fi

sleep 30

echo -e "${CYAN}Listo, ponete a laburar.${NC}"
echo ""
echo ""
echo -e "${YELLOW}Tus credenciales (guardadas en /root/supabase_credentials.txt):${NC}"
echo ""
echo -e "  Dashboard URL:     ${GREEN}https://studio.$DOMAIN${NC}"
echo -e "  Dashboard User:    ${YELLOW}$DASHBOARD_USERNAME${NC}"
echo -e "  Dashboard Pass:    ${YELLOW}$DASHBOARD_PASSWORD${NC}"
echo ""
echo -e "  API URL:           ${GREEN}https://api.$DOMAIN${NC}"
echo -e "  Anon Key:          ${YELLOW}$ANON_KEY${NC}"
echo -e "  Service Role Key:  ${YELLOW}$SERVICE_KEY${NC}"
echo ""
echo -e "  Postgres Password: ${YELLOW}$POSTGRES_PASSWORD${NC}"
echo ""
echo -e "${YELLOW}Configurá el DNS en Cloudflare:${NC}"
echo -e "  1. Agregá registro A: ${GREEN}studio.$DOMAIN${NC} → IP del servidor (Proxy ON)"
echo -e "  2. Agregá registro A: ${GREEN}api.$DOMAIN${NC} → IP del servidor (Proxy ON)"
echo -e "  3. SSL/TLS modo: ${GREEN}Full${NC}"
echo ""
echo -e "${CYAN}IMPORTANTE: Esperá 2-3 minutos para que Let's Encrypt genere los certificados SSL.${NC}"
echo -e "${CYAN}Si ves error 521, verificá con: cd /opt/supabase && docker compose logs traefik${NC}"
echo ""
