#!/bin/bash
set -e # Si algo falla, el script se detiene INMEDIATAMENTE

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   INSTALADOR SUPABASE (MÉTODO OFICIAL)       ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"

# --- 1. VALIDACIONES ---
if [ "$EUID" -ne 0 ]; then echo -e "${RED}❌ Ejecuta como root (sudo su)${NC}"; exit 1; fi

echo -n "Introduce tu dominio (ej. midominio.com): "
read DOMAIN
if [ -z "$DOMAIN" ]; then echo -e "${RED}❌ Dominio requerido.${NC}"; exit 1; fi

# --- 2. LIMPIEZA TOTAL ---
echo -e "${BLUE}🧹 Limpiando instalación anterior...${NC}"
# Detener contenedores viejos
docker ps -a --format '{{.Names}}' | grep "supabase" | xargs -r docker rm -f > /dev/null 2>&1 || true
rm -rf /opt/supabase
rm -rf /tmp/supabase_raw

# --- 3. DEPENDENCIAS ---
echo -e "${BLUE}📦 Instalando Git, Docker y Nginx...${NC}"
apt-get update -y > /dev/null
apt-get install -y git curl wget sudo nginx apache2-utils > /dev/null

# Docker Check
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh > /dev/null
    rm get-docker.sh
fi

# --- 4. CLONAR (MÉTODO OFICIAL) ---
echo -e "${BLUE}📥 Get the code (git clone)...${NC}"

# Clonamos en una carpeta temporal primero para evitar errores de estructura
if git clone --depth 1 https://github.com/supabase/supabase /tmp/supabase_raw; then
    echo -e "${GREEN}✓ Repositorio clonado correctamente.${NC}"
else
    echo -e "${RED}❌ ERROR: No se pudo clonar el repositorio. Revisa tu conexión a internet.${NC}"
    exit 1
fi

# --- 5. PREPARAR DIRECTORIO (MÉTODO OFICIAL) ---
echo -e "${BLUE}📂 Preparando estructura de carpetas...${NC}"

# Make your new supabase project directory
mkdir -p /opt/supabase

# Copy the compose files over to your project
# (Usamos cp -r explícito como dice la docu)
cp -r /tmp/supabase_raw/docker/* /opt/supabase/

# Copy the fake env vars
# (Esto es vital, aquí fallaba el anterior)
cp /tmp/supabase_raw/docker/.env.example /opt/supabase/.env

# Limpiar temporales
rm -rf /tmp/supabase_raw

# Cambiar al directorio
cd /opt/supabase

# Verificar que el .env existe
if [ ! -f ".env" ]; then
    echo -e "${RED}❌ ERROR CRÍTICO: El archivo .env no se copió.${NC}"
    exit 1
fi

# --- 6. CONFIGURACIÓN ---
echo -e "${BLUE}⚙️  Configurando secretos y .env...${NC}"

# Generar claves aleatorias
generate_pass() { openssl rand -base64 32 | tr -d '/+=' | head -c 32; }
POSTGRES_PASS=$(generate_pass)
JWT_SECRET=$(generate_pass)
ANON_KEY=$(generate_pass)
SERVICE_KEY=$(generate_pass)
DASHBOARD_PASS=$(generate_pass)

# Reemplazar en .env
sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASS|g" .env
sed -i "s|JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|g" .env
sed -i "s|ANON_KEY=.*|ANON_KEY=$ANON_KEY|g" .env
sed -i "s|SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$SERVICE_KEY|g" .env
sed -i "s|DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=$DASHBOARD_PASS|g" .env
sed -i "s|API_EXTERNAL_URL=.*|API_EXTERNAL_URL=http://api.$DOMAIN|g" .env
sed -i "s|SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=http://api.$DOMAIN|g" .env
sed -i "s|SITE_URL=.*|SITE_URL=http://studio.$DOMAIN|g" .env

# Fix socket error (Obligatorio para que funcione en Linux nativo)
if ! grep -q "DOCKER_SOCKET_LOCATION" .env; then
    echo "" >> .env
    echo "DOCKER_SOCKET_LOCATION=/var/run/docker.sock" >> .env
fi

# --- 7. NGINX ---
echo -e "${BLUE}🌐 Configurando Nginx...${NC}"
htpasswd -b -c /etc/nginx/.htpasswd admin "$DASHBOARD_PASS" 2>/dev/null

cat > /etc/nginx/sites-available/supabase <<EOF
server {
    listen 80;
    server_name studio.$DOMAIN;
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400;
    }
}
server {
    listen 80;
    server_name api.$DOMAIN;
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF

ln -sf /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t > /dev/null 2>&1 && systemctl restart nginx

# --- 8. ARRANQUE ---
echo -e "${BLUE}🚀 Docker Compose Pull & Up...${NC}"
echo -e "${YELLOW}Nota: Descargando imágenes de una en una (Safe Mode)...${NC}"

# Pull the latest images (Limitado a 1 a la vez para no saturar RAM)
COMPOSE_PARALLEL_LIMIT=1 docker compose pull --quiet

# Start the services
docker compose up -d

# --- 9. FIN ---
echo ""
echo -e "${GREEN}✅ INSTALACIÓN COMPLETADA${NC}"
echo -e "Credenciales guardadas en: /root/supabase_credentials.txt"

cat > /root/supabase_credentials.txt <<EOF
CREDENCIALES SUPABASE ($DOMAIN)
--------------------------------
Studio:   http://studio.$DOMAIN
API:      http://api.$DOMAIN

Usuario:  admin
Password: $DASHBOARD_PASS
DB Pass:  $POSTGRES_PASS
Anon Key: $ANON_KEY
Service Key: $SERVICE_KEY
EOF
