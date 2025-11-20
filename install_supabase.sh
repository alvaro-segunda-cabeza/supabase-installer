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
apt-get update && apt-get upgrade -y
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
mv temp_repo/docker/* .
rm -rf temp_repo

# Copiar env example
cp .env.example .env

# 5. Generar Secretos Seguros
echo -e "${GREEN}Generando secretos seguros...${NC}"
# Función para generar strings aleatorios
generate_secret() {
    openssl rand -base64 32 | tr -d '/+' | cut -c -32
}

POSTGRES_PASSWORD=$(generate_secret)
JWT_SECRET=$(generate_secret)
ANON_KEY=$(generate_secret) # Nota: En prod real deberías generar JWTs válidos firmados con el secreto
SERVICE_KEY=$(generate_secret)
DASHBOARD_USERNAME="admin"
DASHBOARD_PASSWORD=$(generate_secret)

echo -e "${GREEN}Generando autenticación básica para el Dashboard...${NC}"
# Generar hash para Traefik Basic Auth
# htpasswd -nb user password -> user:hash
BASIC_AUTH_USER="$DASHBOARD_USERNAME"
BASIC_AUTH_PASS="$DASHBOARD_PASSWORD"
BASIC_AUTH_HASH=$(htpasswd -nb $BASIC_AUTH_USER $BASIC_AUTH_PASS)

# Actualizar .env con sed
sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|g" .env
sed -i "s|JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|g" .env
sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|g" .env
echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >> .env.local # Backup de la pass

# Configurar URLs externas
sed -i "s|API_EXTERNAL_URL=.*|API_EXTERNAL_URL=https://api.$DOMAIN|g" .env
sed -i "s|SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=https://api.$DOMAIN|g" .env
sed -i "s|STUDIO_DEFAULT_ORGANIZATION=.*|STUDIO_DEFAULT_ORGANIZATION=Supabase|g" .env
sed -i "s|STUDIO_DEFAULT_PROJECT=.*|STUDIO_DEFAULT_PROJECT=Supabase|g" .env

# 6. Crear docker-compose.override.yml para Traefik
echo -e "${GREEN}Configurando Traefik y SSL...${NC}"

cat <<EOF > docker-compose.override.yml
version: "3.8"

services:
  traefik:
    image: traefik:v2.10
    container_name: traefik
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      # Usamos HTTP Challenge para mejor compatibilidad con Cloudflare
      - "--certificatesresolvers.myresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.myresolver.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.myresolver.acme.email=$EMAIL"
      - "--certificatesresolvers.myresolver.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "./letsencrypt:/letsencrypt"
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
    networks:
      - monitor
      - default

  studio:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.studio.rule=Host(\`studio.$DOMAIN\`)"
      - "traefik.http.routers.studio.entrypoints=websecure"
      - "traefik.http.routers.studio.tls.certresolver=myresolver"
      - "traefik.http.services.studio.loadbalancer.server.port=3000"
      # Autenticación Básica
      - "traefik.http.routers.studio.middlewares=studio-auth"
      - "traefik.http.middlewares.studio-auth.basicauth.users=$BASIC_AUTH_HASH"
      # Redirección http -> https
      - "traefik.http.routers.studio-http.rule=Host(\`studio.$DOMAIN\`)"
      - "traefik.http.routers.studio-http.entrypoints=web"
      - "traefik.http.routers.studio-http.middlewares=https-redirect"
      - "traefik.http.middlewares.https-redirect.redirectscheme.scheme=https"

  kong:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(\`api.$DOMAIN\`)"
      - "traefik.http.routers.api.entrypoints=websecure"
      - "traefik.http.routers.api.tls.certresolver=myresolver"
      - "traefik.http.services.api.loadbalancer.server.port=8000"
      # Redirección http -> https
      - "traefik.http.routers.api-http.rule=Host(\`api.$DOMAIN\`)"
      - "traefik.http.routers.api-http.entrypoints=web"
      - "traefik.http.routers.api-http.middlewares=https-redirect"

networks:
  monitor:
    driver: bridge
EOF

# 7. Iniciar servicios
echo -e "${GREEN}Iniciando contenedores...${NC}"
docker compose up -d

echo -e "${GREEN}=== Instalación Completada ===${NC}"
echo -e "Tus credenciales:"
echo -e "Postgres Password: ${YELLOW}$POSTGRES_PASSWORD${NC}"
echo -e "Dashboard User:    ${YELLOW}$DASHBOARD_USERNAME${NC}"
echo -e "Dashboard Pass:    ${YELLOW}$DASHBOARD_PASSWORD${NC}"
echo -e "Dashboard URL:     ${YELLOW}https://studio.$DOMAIN${NC}"
echo -e "API URL:           ${YELLOW}https://api.$DOMAIN${NC}"
echo -e "Directorio de instalación: ${YELLOW}$INSTALL_DIR${NC}"
echo -e "${YELLOW}NOTA: Asegúrate de que los registros DNS (A) para studio.$DOMAIN y api.$DOMAIN apunten a la IP de este servidor en Cloudflare (Nube Naranja activada).${NC}"
echo -e "${YELLOW}En Cloudflare, configura el modo SSL/TLS a 'Full' o 'Full (Strict)'.${NC}"
