#!/bin/bash

# Configuración de colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   INSTALADOR SUPABASE OFICIAL + NGINX HOST   ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"

# 1. Verificaciones iniciales
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}❌ Ejecuta como root (sudo su)${NC}"
  exit 1
fi

# 2. Datos de usuario
echo ""
echo -n "Introduce tu dominio base (ej. midominio.com): "
read DOMAIN
echo -n "Introduce tu IP del servidor (o presiona Enter para detectar): "
read SERVER_IP

if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(curl -4 -s ifconfig.me)
fi

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}❌ El dominio es obligatorio.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Configuración: $DOMAIN ($SERVER_IP)${NC}"
echo ""

# 3. Preparar sistema e instalar dependencias
echo -e "${BLUE}📦 Actualizando sistema e instalando Docker...${NC}"
apt-get update -y && apt-get upgrade -y
apt-get install -y curl git wget sudo nginx apache2-utils

# Instalar Docker si no existe
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
fi

systemctl enable nginx
systemctl start nginx

# 4. Instalar Supabase (Oficial)
echo -e "${BLUE}📥 Descargando Supabase Oficial...${NC}"
rm -rf /opt/supabase
git clone --depth 1 https://github.com/supabase/supabase /opt/supabase/repo
mkdir -p /opt/supabase/docker
cp -r /opt/supabase/repo/docker/* /opt/supabase/docker/
cd /opt/supabase/docker

# Copiar env de ejemplo
cp .env.example .env

# 5. Generar Secretos Reales
echo -e "${BLUE}🔐 Generando claves de seguridad...${NC}"

generate_pass() { openssl rand -base64 32 | tr -d '/+=' | head -c 32; }

POSTGRES_PASSWORD=$(generate_pass)
JWT_SECRET=$(generate_pass)
ANON_KEY=$(generate_pass)
SERVICE_KEY=$(generate_pass)
DASHBOARD_PASSWORD=$(generate_pass)

# Reemplazar en .env usando sed
# Ajustamos claves críticas
sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|g" .env
sed -i "s|JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|g" .env
sed -i "s|ANON_KEY=.*|ANON_KEY=$ANON_KEY|g" .env
sed -i "s|SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$SERVICE_KEY|g" .env
sed -i "s|DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD|g" .env

# Ajustar URLs para producción
sed -i "s|API_EXTERNAL_URL=.*|API_EXTERNAL_URL=http://api.$DOMAIN|g" .env
sed -i "s|SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=http://api.$DOMAIN|g" .env
sed -i "s|SITE_URL=.*|SITE_URL=http://studio.$DOMAIN|g" .env

# Aseguramos que escuche en todas las interfaces para que Nginx del host lo vea
# Nota: En el docker-compose oficial, studio va al 3000 y kong al 8000 por defecto.

# 6. Arrancar Docker
echo -e "${BLUE}🚀 Iniciando contenedores de Supabase...${NC}"
docker compose pull
docker compose up -d

# 7. Configurar Nginx (Host)
echo -e "${BLUE}🌐 Configurando Nginx Proxy...${NC}"

# Crear htpasswd para el Studio (capa extra de seguridad recomendada)
htpasswd -b -c /etc/nginx/.htpasswd admin "$DASHBOARD_PASSWORD"

cat > /etc/nginx/sites-available/supabase <<EOF
# API KONG
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

# STUDIO DASHBOARD
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
        
        # Aumentar timeout para consultas largas en el editor SQL
        proxy_read_timeout 300s; 
    }
}
EOF

# Activar sitio
ln -sf /etc/nginx/sites-available/supabase /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl restart nginx

# 8. Generar archivo de credenciales
cat > /root/supabase_credentials.txt <<EOF
════════════════════════════════════════
   CREDENCIALES SUPABASE ($DOMAIN)
════════════════════════════════════════
URLs:
  - Studio: http://studio.$DOMAIN
  - API:    http://api.$DOMAIN

Usuario Dashboard (Basic Auth si activo): admin
Contraseña Dashboard: $DASHBOARD_PASSWORD

DB Password: $POSTGRES_PASSWORD

API KEYS (Úsalas en tu Frontend/Backend):
  - anon public: $ANON_KEY
  - service_role: $SERVICE_KEY

JWT Secret: $JWT_SECRET
════════════════════════════════════════
EOF

# 9. Mensaje final
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ¡INSTALACIÓN COMPLETADA!             ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "Recuerda configurar tus DNS:"
echo -e "  A  studio.$DOMAIN  ->  $SERVER_IP"
echo -e "  A  api.$DOMAIN     ->  $SERVER_IP"
echo ""
echo -e "📄 Credenciales guardadas en: ${BLUE}/root/supabase_credentials.txt${NC}"
echo ""
echo -e "💡 Para activar SSL (HTTPS) gratis, ejecuta cuando las DNS propaguen:"
echo -e "${BLUE}apt install certbot python3-certbot-nginx${NC}"
echo -e "${BLUE}certbot --nginx -d studio.$DOMAIN -d api.$DOMAIN${NC}"
echo ""
