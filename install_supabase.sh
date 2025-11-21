#!/bin/bash
set -e # ESTO ES CRÍTICO: Detiene el script si hay CUALQUIER error

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   INSTALADOR SUPABASE (MÉTODO ZIP SEGURO)    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"

# 1. Verificar Root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}❌ Ejecuta como root (sudo su)${NC}"
  exit 1
fi

# 2. Solicitar Dominio
echo -n "Introduce tu dominio (ej. midominio.com): "
read DOMAIN
if [ -z "$DOMAIN" ]; then echo -e "${RED}❌ Dominio requerido.${NC}"; exit 1; fi

# 3. Limpieza TOTAL
echo -e "${RED}🧹 Limpiando sistema...${NC}"
# Parar docker si existe
if [ -d "/opt/supabase/docker" ]; then
    cd /opt/supabase/docker || true
    docker compose down -v 2>/dev/null || true
fi
# Eliminar carpetas
rm -rf /opt/supabase
rm -rf /opt/master.zip
rm -rf /opt/supabase-master

echo -e "${GREEN}✓ Limpieza completada.${NC}"

# 4. Instalar herramientas necesarias
echo -e "${BLUE}📦 Instalando herramientas (Unzip, Docker, Nginx)...${NC}"
apt-get update -y
# Instalamos unzip para descomprimir y curl/wget
apt-get install -y curl wget unzip sudo nginx apache2-utils

# Instalar Docker si falta
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
fi

systemctl enable nginx
systemctl start nginx

# 5. DESCARGAR SUPABASE (MÉTODO ZIP)
echo -e "${BLUE}📥 Descargando Supabase (Vía ZIP)...${NC}"
mkdir -p /opt
cd /opt

# Descargamos el ZIP directamente (más seguro que git clone)
if wget -O master.zip https://github.com/supabase/supabase/archive/refs/heads/master.zip; then
    echo -e "${GREEN}✓ Descarga exitosa.${NC}"
else
    echo -e "${RED}❌ ERROR: No se pudo descargar el archivo ZIP de GitHub. Verifica tu conexión a internet.${NC}"
    exit 1
fi

# Descomprimir
echo "📦 Descomprimiendo..."
unzip -q master.zip
# Mover a la carpeta final
mkdir -p /opt/supabase
mv supabase-master/docker /opt/supabase/docker
# Limpiar basura
rm -rf master.zip supabase-master

# Verificar que los archivos están ahí
if [ ! -f "/opt/supabase/docker/docker-compose.yml" ]; then
    echo -e "${RED}❌ ERROR CRÍTICO: Los archivos no se copiaron correctamente.${NC}"
    exit 1
fi

cd /opt/supabase/docker

# 6. Configurar .ENV
echo -e "${BLUE}⚙️  Configurando secretos...${NC}"

# Copiar env base
cp .env.example .env

# Generar claves
generate_pass() { openssl rand -base64 32 | tr -d '/+=' | head -c 32; }
POSTGRES_PASSWORD=$(generate_pass)
JWT_SECRET=$(generate_pass)
ANON_KEY=$(generate_pass)
SERVICE_KEY=$(generate_pass)
DASHBOARD_PASSWORD=$(generate_pass)

# Reemplazar variables
sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|g" .env
sed -i "s|JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|g" .env
sed -i "s|ANON_KEY=.*|ANON_KEY=$ANON_KEY|g" .env
sed -i "s|SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$SERVICE_KEY|g" .env
sed -i "s|DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD|g" .env
sed -i "s|API_EXTERNAL_URL=.*|API_EXTERNAL_URL=http://api.$DOMAIN|g" .env
sed -i "s|SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=http://api.$DOMAIN|g" .env
sed -i "s|SITE_URL=.*|SITE_URL=http://studio.$DOMAIN|g" .env

# Fix Socket Docker
if grep -q "DOCKER_SOCKET_LOCATION" .env; then
    sed -i 's|# DOCKER_SOCKET_LOCATION=.*|DOCKER_SOCKET_LOCATION=/var/run/docker.sock|g' .env
else
    echo "" >> .env
    echo "DOCKER_SOCKET_LOCATION=/var/run/docker.sock" >> .env
fi

# 7. Configurar Nginx
echo -e "${BLUE}🌐 Configurando Nginx...${NC}"
htpasswd -b -c /etc/nginx/.htpasswd admin "$DASHBOARD_PASSWORD" 2>/dev/null

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
nginx -t > /dev/null && systemctl restart nginx

# 8. Arrancar Docker (LENTO PERO SEGURO)
echo -e "${BLUE}🚀 Arrancando Supabase...${NC}"
echo -e "${YELLOW}Nota: Si falla la descarga, comprueba tu espacio en disco (df -h)${NC}"

# Descargar 1 a 1 para no saturar RAM
COMPOSE_PARALLEL_LIMIT=1 docker compose pull --quiet

docker compose up -d

# 9. Fin
echo ""
echo -e "${GREEN}✅ INSTALACIÓN COMPLETADA CORRECTAMENTE${NC}"
echo -e "Credenciales guardadas en: /root/supabase_credentials.txt"

cat > /root/supabase_credentials.txt <<EOF
CREDENCIALES SUPABASE ($DOMAIN)
--------------------------------
Studio:   http://studio.$DOMAIN
API:      http://api.$DOMAIN

Usuario:  admin
Password: $DASHBOARD_PASSWORD
DB Pass:  $POSTGRES_PASSWORD
Anon Key: $ANON_KEY
EOF
