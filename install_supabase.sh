#!/bin/bash

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Cabecera
clear
echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   INSTALADOR SUPABASE FINAL (AUTO-CLEAN)     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"

# 1. Verificar Root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}❌ Por favor, ejecuta como root (sudo su)${NC}"
  exit 1
fi

# 2. Solicitar Dominio
echo ""
echo -e "${YELLOW}Esta acción borrará cualquier instalación previa de Supabase en este servidor.${NC}"
echo -n "Introduce tu dominio (ej. midominio.com): "
read DOMAIN

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}❌ Dominio requerido.${NC}"
    exit 1
fi

SERVER_IP=$(curl -4 -s ifconfig.me)

# 3. LIMPIEZA PROFUNDA (Deep Clean)
echo ""
echo -e "${RED}🧹 Limpiando rastro de instalaciones anteriores...${NC}"

# Detener contenedores si existen
if [ -d "/opt/supabase/docker" ]; then
    cd /opt/supabase/docker
    docker compose down -v 2>/dev/null || true
fi

# Eliminar cualquier contenedor con nombre supabase
docker ps -a --format '{{.Names}}' | grep supabase | xargs -r docker rm -f

# Eliminar carpeta de instalación
rm -rf /opt/supabase

# Limpiar Nginx antiguo
rm -f /etc/nginx/sites-enabled/supabase
rm -f /etc/nginx/sites-available/supabase
systemctl reload nginx 2>/dev/null || true

echo -e "${GREEN}✓ Sistema limpio y listo.${NC}"

# 4. Instalación de Dependencias
echo ""
echo -e "${BLUE}📦 Instalando Docker y Nginx...${NC}"
apt-get update -y > /dev/null 2>&1
apt-get install -y curl git wget sudo nginx apache2-utils > /dev/null 2>&1

# Instalar Docker si no existe
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh > /dev/null 2>&1
    rm get-docker.sh
fi

systemctl enable nginx > /dev/null 2>&1
systemctl start nginx > /dev/null 2>&1

# 5. Descargar Supabase Oficial
echo ""
echo -e "${BLUE}📥 Descargando Repositorio Oficial...${NC}"
mkdir -p /opt/supabase
git clone --depth 1 https://github.com/supabase/supabase /opt/supabase/repo > /dev/null 2>&1

# Preparar carpeta Docker
mkdir -p /opt/supabase/docker
# Usamos cp -a para asegurar que se copian archivos ocultos como .env.example
cp -a /opt/supabase/repo/docker/. /opt/supabase/docker/
cd /opt/supabase/docker

# 6. Configuración .ENV (Corrección de errores previos)
echo -e "${BLUE}⚙️  Configurando variables de entorno...${NC}"

# Copiar ejemplo
cp .env.example .env

# Generar claves seguras
generate_pass() { openssl rand -base64 32 | tr -d '/+=' | head -c 32; }

POSTGRES_PASSWORD=$(generate_pass)
JWT_SECRET=$(generate_pass)
ANON_KEY=$(generate_pass)
SERVICE_KEY=$(generate_pass)
DASHBOARD_PASSWORD=$(generate_pass)

# Reemplazos en .env
sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|g" .env
sed -i "s|JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|g" .env
sed -i "s|ANON_KEY=.*|ANON_KEY=$ANON_KEY|g" .env
sed -i "s|SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$SERVICE_KEY|g" .env
sed -i "s|DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD|g" .env

# URLs
sed -i "s|API_EXTERNAL_URL=.*|API_EXTERNAL_URL=http://api.$DOMAIN|g" .env
sed -i "s|SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=http://api.$DOMAIN|g" .env
sed -i "s|SITE_URL=.*|SITE_URL=http://studio.$DOMAIN|g" .env

# FIX CRÍTICO: Asegurar variable DOCKER_SOCKET_LOCATION para evitar error "invalid spec"
if grep -q "DOCKER_SOCKET_LOCATION" .env; then
    sed -i 's|# DOCKER_SOCKET_LOCATION=.*|DOCKER_SOCKET_LOCATION=/var/run/docker.sock|g' .env
else
    echo "" >> .env
    echo "DOCKER_SOCKET_LOCATION=/var/run/docker.sock" >> .env
fi

# 7. Configurar Nginx (Host)
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
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
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
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -sf /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t > /dev/null 2>&1 && systemctl restart nginx

# 8. Arrancar Docker (Modo Seguro)
echo ""
echo -e "${BLUE}🚀 Iniciando Supabase...${NC}"
echo -e "${YELLOW}Nota: Descargando imágenes de una en una para evitar errores de memoria.${NC}"
echo -e "${YELLOW}Esto tomará unos minutos. Paciencia...${NC}"

# Usamos PARALLEL_LIMIT=1 para que no se cuelgue tu servidor de 4GB
COMPOSE_PARALLEL_LIMIT=1 docker compose pull --quiet

echo -e "${BLUE}Levantando contenedores...${NC}"
docker compose up -d

# 9. Resultado
cat > /root/supabase_credentials.txt <<EOF
════════════════════════════════════════
   INSTALACIÓN COMPLETADA - $DOMAIN
════════════════════════════════════════
URLs:
  - Studio: http://studio.$DOMAIN
  - API:    http://api.$DOMAIN

Usuario: admin
Password: $DASHBOARD_PASSWORD

DB Password: $POSTGRES_PASSWORD
Anon Key: $ANON_KEY
Service Key: $SERVICE_KEY
════════════════════════════════════════
EOF

echo ""
echo -e "${GREEN}✅ ¡TODO LISTO!${NC}"
echo -e "Espera 1 minuto a que la base de datos inicie antes de entrar."
echo -e "Credenciales guardadas en: ${YELLOW}/root/supabase_credentials.txt${NC}"
echo ""
