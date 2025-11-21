#!/bin/bash

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=== Instalador de Supabase ===${NC}"
echo ""

# Verificar si se ejecuta como root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Por favor, ejecuta este script como root o con sudo.${NC}"
  exit 1
fi

# 1. Solicitar información al usuario PRIMERO
# Si no se pasan argumentos, pedirlos interactivamente
if [ -z "$1" ] || [ -z "$2" ]; then
    echo -e "${YELLOW}Uso: $0 <dominio> <email>${NC}"
    echo -e "${YELLOW}O ejecuta sin argumentos para modo interactivo.${NC}"
    echo ""
    echo -e "${YELLOW}Configuración inicial:${NC}"
    echo ""
    
    # Intentar múltiples métodos para leer input
    if [ -t 0 ]; then
        # Si hay terminal disponible
        echo -n "Introduce tu dominio base (ej. midominio.com): "
        read DOMAIN
        echo -n "Introduce tu email para Let's Encrypt: "
        read EMAIL
    elif [ -c /dev/tty ]; then
        # Intentar leer desde /dev/tty
        echo -n "Introduce tu dominio base (ej. midominio.com): "
        read DOMAIN < /dev/tty
        echo -n "Introduce tu email para Let's Encrypt: "
        read EMAIL < /dev/tty
    else
        # Si nada funciona, dar instrucciones
        echo -e "${RED}No se puede leer input interactivamente.${NC}"
        echo ""
        echo -e "${YELLOW}Por favor, ejecuta el script de esta forma:${NC}"
        echo -e "${GREEN}bash <(curl -sL https://raw.githubusercontent.com/alvaro-segunda-cabeza/supabase-installer/main/install_supabase.sh) midominio.com tu@email.com${NC}"
        echo ""
        echo -e "${YELLOW}O descarga el script y ejecútalo:${NC}"
        echo -e "${GREEN}curl -O https://raw.githubusercontent.com/alvaro-segunda-cabeza/supabase-installer/main/install_supabase.sh${NC}"
        echo -e "${GREEN}chmod +x install_supabase.sh${NC}"
        echo -e "${GREEN}sudo ./install_supabase.sh midominio.com tu@email.com${NC}"
        exit 1
    fi
else
    # Si se pasaron argumentos, usarlos
    DOMAIN="$1"
    EMAIL="$2"
fi

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    echo -e "${RED}Error: Dominio y Email son requeridos.${NC}"
    echo ""
    echo -e "${YELLOW}Ejecuta el script así:${NC}"
    echo -e "${GREEN}bash <(curl -sL https://raw.githubusercontent.com/alvaro-segunda-cabeza/supabase-installer/main/install_supabase.sh) midominio.com tu@email.com${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✓ Configuración guardada${NC}"
echo -e "${GREEN}  Dominio: $DOMAIN${NC}"
echo -e "${GREEN}  Email: $EMAIL${NC}"
echo ""

# 2. Actualizar sistema e instalar dependencias básicas
echo -e "${CYAN}[1/8] Actualizando sistema e instalando dependencias...${NC}"
apt-get update -y > /dev/null 2>&1
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" > /dev/null 2>&1
apt-get install -y curl git wget sudo apache2-utils > /dev/null 2>&1
echo -e "${GREEN}✓ Dependencias instaladas${NC}"
echo ""

# 3. Instalar Docker y Docker Compose
echo -e "${CYAN}[2/8] Instalando Docker...${NC}"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh > /dev/null 2>&1
    rm get-docker.sh
fi

systemctl enable docker > /dev/null 2>&1
systemctl start docker > /dev/null 2>&1
sleep 5
echo -e "${GREEN}✓ Docker instalado y corriendo${NC}"
echo ""

# 4. Limpiar instalaciones previas (AHORA que Docker está instalado)
echo -e "${CYAN}[3/8] Limpiando instalaciones previas...${NC}"
if [ -d "/opt/supabase" ]; then
    cd /opt/supabase
    docker compose down -v 2>/dev/null || true
    cd /
    rm -rf /opt/supabase 2>/dev/null || true
fi

docker ps -a | grep -E "supabase|nginx|postgres|kong" | awk '{print $1}' | xargs -r docker stop 2>/dev/null || true
docker ps -a | grep -E "supabase|nginx|postgres|kong" | awk '{print $1}' | xargs -r docker rm 2>/dev/null || true
docker volume ls | grep supabase | awk '{print $2}' | xargs -r docker volume rm 2>/dev/null || true
echo -e "${GREEN}✓ Limpieza completada${NC}"
echo ""

# 5. Preparar directorio de Supabase
echo -e "${CYAN}[4/8] Descargando configuración de Supabase...${NC}"
INSTALL_DIR="/opt/supabase"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

git clone --depth 1 https://github.com/singh-inder/supabase-automated-self-host.git temp_repo > /dev/null 2>&1

if [ -d "temp_repo/docker" ]; then
    cp -r temp_repo/docker/* .
fi

rm -rf temp_repo
echo -e "${GREEN}✓ Configuración descargada${NC}"
echo ""

# 6. Generar Secretos Seguros
echo -e "${CYAN}[5/8] Generando secretos seguros...${NC}"
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

# 7. Crear archivo .env
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
SITE_URL=http://studio.$DOMAIN
ADDITIONAL_REDIRECT_URLS=
JWT_EXPIRY=3600
DISABLE_SIGNUP=false
API_EXTERNAL_URL=http://api.$DOMAIN

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
SUPABASE_PUBLIC_URL=http://api.$DOMAIN

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

# Storage - Variables S3 necesarias
REGION=us-east-1
GLOBAL_S3_BUCKET=supabase-storage
TENANT_ID=stub
S3_PROTOCOL_PREFIX=http
S3_PROTOCOL_ACCESS_KEY_ID=stub
S3_PROTOCOL_ACCESS_KEY_SECRET=stub
IMGPROXY_ENABLE_WEBP_DETECTION=true

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
Dashboard URL: http://studio.$DOMAIN
API URL: http://api.$DOMAIN
=================================
CREDS

echo -e "${GREEN}✓ Secretos generados${NC}"
echo ""

# 8. Corregir docker-compose.yml (eliminar DOCKER_SOCKET_LOCATION)
echo -e "${CYAN}[6/8] Corrigiendo docker-compose.yml...${NC}"

# Eliminar cualquier referencia a DOCKER_SOCKET_LOCATION que cause problemas
sed -i 's|/var/run/docker\.sock/var/run/docker\.sock|/var/run/docker.sock|g' docker-compose.yml
sed -i 's|:\${DOCKER_SOCKET_LOCATION[^}]*}:/var/run/docker.sock|/var/run/docker.sock:/var/run/docker.sock|g' docker-compose.yml
sed -i 's|\${DOCKER_SOCKET_LOCATION[^}]*}|/var/run/docker.sock|g' docker-compose.yml

echo -e "${GREEN}✓ docker-compose.yml corregido${NC}"
echo ""

# 9. Crear docker-compose.override.yml con Nginx
echo -e "${CYAN}[7/8] Configurando Nginx...${NC}"

cat > docker-compose.override.yml << 'OVERRIDE_EOF'
services:
  nginx:
    image: nginx:alpine
    container_name: supabase-nginx
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
    networks:
      - default
    depends_on:
      - studio
      - kong
OVERRIDE_EOF

mkdir -p nginx/conf.d

# Crear configuración principal de nginx
cat > nginx/nginx.conf << 'NGINX_MAIN'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 50M;
    
    include /etc/nginx/conf.d/*.conf;
}
NGINX_MAIN

# Crear configuración HTTP (sin SSL)
cat > nginx/conf.d/supabase.conf << NGINX_CONF
# Studio HTTP
server {
    listen 80;
    server_name studio.$DOMAIN;
    
    # Autenticación básica
    auth_basic "Supabase Studio";
    auth_basic_user_file /etc/nginx/conf.d/.htpasswd;
    
    location / {
        proxy_pass http://studio:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}

# API HTTP
server {
    listen 80;
    server_name api.$DOMAIN;
    
    location / {
        proxy_pass http://kong:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}

# Acceso directo por IP - Default server
server {
    listen 80 default_server;
    
    # Por defecto, redirigir todo al studio (la interfaz principal)
    location / {
        proxy_pass http://studio:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
NGINX_CONF

# Crear archivo .htpasswd para autenticación básica
echo "$BASIC_AUTH_HASH" | sed 's/\$\$/\$/g' > nginx/conf.d/.htpasswd

# 10. Iniciar servicios
echo -e "${CYAN}[8/8] Iniciando todos los servicios...${NC}"
echo -e "${YELLOW}Esto puede tomar varios minutos (descargando imágenes Docker)...${NC}"

# Descargar imágenes primero (sin output verboso que puede causar loops)
docker compose pull --quiet 2>&1 | grep -v "Pulling" | grep -v "Waiting" | grep -v "Downloading" | grep -v "Extracting" || true

echo -e "${CYAN}Imágenes descargadas, iniciando contenedores...${NC}"

# Iniciar servicios sin el output que causa loops
docker compose up -d --quiet-pull 2>&1 | grep -E "Creating|Started|Error" || true

sleep 15
echo -e "${CYAN}Esperando que los servicios se inicialicen...${NC}"
sleep 45

echo -e "${CYAN}Estamos próximos a terminar.${NC}"
echo ""

# Verificar que los servicios estén corriendo
echo -e "${CYAN}Verificando servicios...${NC}"
sleep 20

# Verificar contenedores críticos
NGINX_RUNNING=$(docker ps --filter "name=supabase-nginx" --format "{{.Names}}" 2>/dev/null)
DB_RUNNING=$(docker ps --filter "name=supabase-db" --format "{{.Names}}" 2>/dev/null)
STUDIO_RUNNING=$(docker ps --filter "name=supabase-studio" --format "{{.Names}}" 2>/dev/null)
KONG_RUNNING=$(docker ps --filter "name=supabase-kong" --format "{{.Names}}" 2>/dev/null)

if [ -z "$NGINX_RUNNING" ] || [ -z "$DB_RUNNING" ] || [ -z "$STUDIO_RUNNING" ] || [ -z "$KONG_RUNNING" ]; then
    echo -e "${RED}Algunos servicios no iniciaron correctamente.${NC}"
    echo -e "${YELLOW}Mostrando estado de TODOS los contenedores:${NC}"
    echo ""
    docker compose ps -a
    echo ""
    echo -e "${YELLOW}Logs de los servicios que fallaron:${NC}"
    echo ""
    
    # Mostrar logs específicos
    [ -z "$NGINX_RUNNING" ] && echo -e "${RED}=== Logs de Nginx ===${NC}" && docker compose logs nginx --tail=30
    [ -z "$DB_RUNNING" ] && echo -e "${RED}=== Logs de Database ===${NC}" && docker compose logs db --tail=30
    [ -z "$STUDIO_RUNNING" ] && echo -e "${RED}=== Logs de Studio ===${NC}" && docker compose logs studio --tail=30
    [ -z "$KONG_RUNNING" ] && echo -e "${RED}=== Logs de Kong ===${NC}" && docker compose logs kong --tail=30
    
    echo ""
    echo -e "${RED}Hubo un problema. Revisá los logs arriba.${NC}"
    exit 1
fi

sleep 30

# Obtener IP del servidor
SERVER_IP=$(curl -4 -s ifconfig.me || curl -4 -s icanhazip.com || echo "tu-ip-del-servidor")

echo -e "${CYAN}Listo, ponete a laburar.${NC}"
echo ""
echo ""
echo -e "${YELLOW}Tus credenciales (guardadas en /root/supabase_credentials.txt):${NC}"
echo ""
echo -e "  Dashboard User:    ${YELLOW}$DASHBOARD_USERNAME${NC}"
echo -e "  Dashboard Pass:    ${YELLOW}$DASHBOARD_PASSWORD${NC}"
echo ""
echo -e "  Anon Key:          ${YELLOW}$ANON_KEY${NC}"
echo -e "  Service Role Key:  ${YELLOW}$SERVICE_KEY${NC}"
echo -e "  Postgres Password: ${YELLOW}$POSTGRES_PASSWORD${NC}"
echo ""
echo -e "${GREEN}=== Formas de acceder (HTTP, sin SSL) ===${NC}"
echo ""
echo -e "${YELLOW}1. Por IP directamente:${NC}"
echo -e "   ${GREEN}http://$SERVER_IP/studio${NC}"
echo -e "   ${GREEN}http://$SERVER_IP/api${NC}"
echo ""
echo -e "${YELLOW}2. Por dominio (si DNS está configurado):${NC}"
echo -e "   ${GREEN}http://studio.$DOMAIN${NC}"
echo -e "   ${GREEN}http://api.$DOMAIN${NC}"
echo ""
echo -e "${CYAN}Configurá el DNS en Cloudflare:${NC}"
echo -e "  1. Agregá registro A: ${GREEN}studio.$DOMAIN${NC} → $SERVER_IP (Proxy ${RED}OFF${NC})"
echo -e "  2. Agregá registro A: ${GREEN}api.$DOMAIN${NC} → $SERVER_IP (Proxy ${RED}OFF${NC})"
echo ""
echo -e "${YELLOW}Nota: Esta instalación usa HTTP sin SSL por simplicidad.${NC}"
echo ""
