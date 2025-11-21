#!/bin/bash

# Detener el script inmediatamente si un comando falla
set -e

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   INSTALADOR SUPABASE (MÉTODO ZIP SEGURO)    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"

# 1. Verificaciones básicas
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}❌ Error: Ejecuta como root (sudo su)${NC}"
  exit 1
fi

echo -n "Introduce tu dominio (ej. midominio.com): "
read DOMAIN
if [ -z "$DOMAIN" ]; then echo -e "${RED}❌ Dominio requerido.${NC}"; exit 1; fi

# 2. Limpieza y Preparación
echo -e "${BLUE}🧹 Limpiando sistema...${NC}"
rm -rf /opt/supabase
rm -rf /opt/supabase_temp
mkdir -p /opt/supabase_temp

# 3. Instalar herramientas (IMPORTANTE: unzip)
echo -e "${BLUE}📦 Instalando dependencias...${NC}"
apt-get update -y > /dev/null
apt-get install -y curl wget unzip sudo nginx apache2-utils > /dev/null

# Docker Check
if ! command -v docker &> /dev/null; then
    echo "Instalando Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh > /dev/null
    rm get-docker.sh
fi

# 4. DESCARGA SEGURA (El punto crítico)
echo -e "${BLUE}📥 Descargando Supabase (ZIP)...${NC}"
cd /opt/supabase_temp

# Intentamos descargar. Si falla, el script MORIRÁ aquí gracias a 'set -e'
wget -q -O supabase.zip https://github.com/supabase/supabase/archive/refs/heads/master.zip

echo "📦 Descomprimiendo..."
unzip -q supabase.zip

# Verificamos que la carpeta exista antes de moverla
if [ ! -d "supabase-master/docker" ]; then
    echo -e "${RED}❌ ERROR FATAL: El ZIP se descargó pero no contiene la carpeta 'docker'.${NC}"
    exit 1
fi

# Mover a destino final
mkdir -p /opt/supabase
cp -r supabase-master/docker/* /opt/supabase/
cp supabase-master/docker/.env.example /opt/supabase/.env
cd /opt/supabase

# Limpiar temporales
rm -rf /opt/supabase_temp

echo -e "${GREEN}✓ Archivos descargados correctamente.${NC}"

# 5. Configuración
echo -e "${BLUE}⚙️  Generando configuración...${NC}"

# Generar claves
generate_pass() { openssl rand -base64 32 | tr -d '/+=' | head -c 32; }
POSTGRES_PASS=$(generate_pass)
JWT_SECRET=$(generate_pass)
ANON_KEY=$(generate_pass)
SERVICE_KEY=$(generate_pass)
DASHBOARD_PASS=$(generate_pass)

# Escribir en .env (Usamos || true para evitar que grep falle el script si no encuentra algo)
sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASS|g" .env
sed -i "s|JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|g" .env
sed -i "s|ANON_KEY=.*|ANON_KEY=$ANON_KEY|g" .env
sed -i "s|SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$SERVICE_KEY|g" .env
sed -i "s|DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=$DASHBOARD_PASS|g" .env
sed -i "s|API_EXTERNAL_URL=.*|API_EXTERNAL_URL=http://api.$DOMAIN|g" .env
sed -i "s|SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=http://api.$DOMAIN|g" .env
sed -i "s|SITE_URL=.*|SITE_URL=http://studio.$DOMAIN|g" .env

# Asegurar Socket Docker
if ! grep -q "DOCKER_SOCKET_LOCATION" .env; then
    echo "DOCKER_SOCKET_LOCATION=/var/run/docker.sock" >> .env
fi

# 6. Nginx
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
nginx -t > /dev/null && systemctl restart nginx

# 7. Arrancar
echo -e "${BLUE}🚀 Arrancando contenedores (Puede tardar)...${NC}"
# Descargar 1 a 1 para evitar colapso de RAM
COMPOSE_PARALLEL_LIMIT=1 docker compose pull --quiet
docker compose up -d

# 8. Final
echo ""
echo -e "${GREEN}✅ INSTALACIÓN COMPLETADA SIN ERRORES${NC}"
cat > /root/supabase_credentials.txt <<EOF
CREDENCIALES ($DOMAIN)
----------------------
Studio:   http://studio.$DOMAIN
API:      http://api.$DOMAIN
User:     admin
Pass:     $DASHBOARD_PASS
DB Pass:  $POSTGRES_PASS
Anon Key: $ANON_KEY
EOF
echo "Credenciales en: /root/supabase_credentials.txt"
