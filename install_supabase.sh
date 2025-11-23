#!/bin/bash
set -e

###############################
# SUPABASE SELF-HOSTED INSTALLER
# Instalador completo de Supabase
# Versión: 2.0
###############################

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

clear

echo -e "${CYAN}"
cat << "EOF"
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║     ███████╗██╗   ██╗██████╗  █████╗ ██████╗  █████╗    ║
║     ██╔════╝██║   ██║██╔══██╗██╔══██╗██╔══██╗██╔══██╗   ║
║     ███████╗██║   ██║██████╔╝███████║██████╔╝███████║   ║
║     ╚════██║██║   ██║██╔═══╝ ██╔══██║██╔══██╗██╔══██║   ║
║     ███████║╚██████╔╝██║     ██║  ██║██████╔╝██║  ██║   ║
║     ╚══════╝ ╚═════╝ ╚═╝     ╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝   ║
║                                                          ║
║          INSTALADOR COMPLETO SELF-HOSTED v2.0           ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo ""

###############################
# VERIFICACIONES PREVIAS
###############################

# Verificar que sea root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}❌ Error: Este script debe ejecutarse como root${NC}"
  echo -e "${YELLOW}Usa: sudo bash $0${NC}"
  exit 1
fi

# Verificar que Docker esté instalado
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker no está instalado${NC}"
    echo -e "${YELLOW}Instalando Docker...${NC}"
    
    # Instalar Docker
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release
    
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION_CODENAME=$(lsb_release -cs 2>/dev/null || echo $VERSION_CODENAME)
    else
        OS="ubuntu"
        VERSION_CODENAME="jammy"
    fi
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $VERSION_CODENAME stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    systemctl enable docker
    systemctl start docker
    
    echo -e "${GREEN}✓ Docker instalado correctamente${NC}"
    echo ""
fi

# Verificar que Docker esté corriendo
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker no está corriendo${NC}"
    echo -e "${YELLOW}Iniciando Docker...${NC}"
    systemctl start docker
    sleep 3
    
    if ! docker info > /dev/null 2>&1; then
        echo -e "${RED}❌ No se pudo iniciar Docker. Verifica la instalación.${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✓ Docker verificado y corriendo${NC}"
echo -e "${BLUE}  Versión: $(docker --version | awk '{print $3}')${NC}"
echo ""

###############################
# CONFIGURACIÓN INTERACTIVA
###############################

echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      CONFIGURACIÓN DE INSTALACIÓN    ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

# Preguntar por el dominio
echo -e "${YELLOW}¿Deseas usar un dominio propio o acceder por IP?${NC}"
echo -e "  ${BLUE}1)${NC} Usar dominio (ej: midominio.com)"
echo -e "  ${BLUE}2)${NC} Usar IP del servidor (sin SSL)"
echo ""
read -p "Selecciona una opción [1-2]: " DOMAIN_OPTION

if [ "$DOMAIN_OPTION" = "1" ]; then
    USE_DOMAIN=true
    read -p "Ingresa tu dominio (ej: midominio.com): " ROOT_DOMAIN
    read -p "Ingresa tu email para certificados SSL: " EMAIL
    
    echo ""
    echo -e "${YELLOW}📝 IMPORTANTE: Configura estos registros DNS:${NC}"
    echo -e "   ${BLUE}A${NC} studio.${ROOT_DOMAIN}  →  IP del servidor"
    echo -e "   ${BLUE}A${NC} api.${ROOT_DOMAIN}     →  IP del servidor"
    echo ""
    read -p "Presiona ENTER cuando hayas configurado el DNS..."
else
    USE_DOMAIN=false
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo -e "${GREEN}✓ Se usará la IP: ${SERVER_IP}${NC}"
fi

echo ""

# Directorio de instalación
INSTALL_DIR="/opt/supabase"
echo -e "${BLUE}Directorio de instalación: ${INSTALL_DIR}${NC}"

# Confirmar instalación
echo ""
echo -e "${YELLOW}═══════════════════════════════════════${NC}"
echo -e "${YELLOW}   RESUMEN DE LA INSTALACIÓN${NC}"
echo -e "${YELLOW}═══════════════════════════════════════${NC}"
if [ "$USE_DOMAIN" = true ]; then
    echo -e "  ${CYAN}Modo:${NC} Dominio con SSL"
    echo -e "  ${CYAN}Studio:${NC} https://studio.${ROOT_DOMAIN}"
    echo -e "  ${CYAN}API:${NC} https://api.${ROOT_DOMAIN}"
else
    echo -e "  ${CYAN}Modo:${NC} IP sin SSL"
    echo -e "  ${CYAN}Studio:${NC} http://${SERVER_IP}:3000"
    echo -e "  ${CYAN}API:${NC} http://${SERVER_IP}:8000"
fi
echo -e "  ${CYAN}Directorio:${NC} ${INSTALL_DIR}"
echo -e "${YELLOW}═══════════════════════════════════════${NC}"
echo ""
read -p "¿Continuar con la instalación? [S/n]: " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Ss]?$ ]]; then
    echo -e "${RED}Instalación cancelada${NC}"
    exit 0
fi

###############################
# INSTALACIÓN
###############################

echo ""
echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     INICIANDO INSTALACIÓN            ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

# Paso 1: Instalar dependencias
echo -e "${MAGENTA}[1/6]${NC} Instalando dependencias..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y > /dev/null 2>&1
apt-get install -y git curl jq openssl python3-pip ufw > /dev/null 2>&1

# Instalar PyJWT para generar tokens
pip3 install PyJWT --quiet --break-system-packages 2>/dev/null || pip3 install PyJWT --quiet

echo -e "${GREEN}✓ Dependencias instaladas${NC}"

# Paso 2: Configurar firewall
echo -e "${MAGENTA}[2/6]${NC} Configurando firewall..."
ufw allow ssh > /dev/null 2>&1
ufw allow 80 > /dev/null 2>&1
ufw allow 443 > /dev/null 2>&1
ufw allow 3000 > /dev/null 2>&1  # Studio (si se usa IP)
ufw allow 8000 > /dev/null 2>&1  # API (si se usa IP)
ufw --force enable > /dev/null 2>&1
echo -e "${GREEN}✓ Firewall configurado${NC}"

# Paso 3: Crear estructura de directorios
echo -e "${MAGENTA}[3/6]${NC} Creando estructura de directorios..."
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# Clonar repositorio oficial de Supabase
if [ ! -d "supabase" ]; then
    git clone --depth 1 https://github.com/supabase/supabase.git > /dev/null 2>&1
fi

cd supabase/docker

echo -e "${GREEN}✓ Estructura creada${NC}"

# Paso 4: Generar secretos
echo -e "${MAGENTA}[4/6]${NC} Generando claves de seguridad..."

POSTGRES_PASSWORD=$(openssl rand -hex 32)
JWT_SECRET=$(openssl rand -base64 32 | tr -d '\n')
DASHBOARD_PASSWORD=$(openssl rand -hex 16)

# Generar JWT tokens válidos
ANON_KEY=$(python3 -c "
import jwt
import time
secret = '$JWT_SECRET'
payload = {
    'iss': 'supabase',
    'ref': 'default',
    'role': 'anon',
    'iat': int(time.time()),
    'exp': int(time.time()) + 315360000
}
print(jwt.encode(payload, secret, algorithm='HS256'))
")

SERVICE_ROLE_KEY=$(python3 -c "
import jwt
import time
secret = '$JWT_SECRET'
payload = {
    'iss': 'supabase',
    'ref': 'default',
    'role': 'service_role',
    'iat': int(time.time()),
    'exp': int(time.time()) + 315360000
}
print(jwt.encode(payload, secret, algorithm='HS256'))
")

echo -e "${GREEN}✓ Claves generadas${NC}"

# Paso 5: Configurar variables de entorno
echo -e "${MAGENTA}[5/6]${NC} Configurando variables de entorno..."

# Copiar archivo de ejemplo
cp .env.example .env

# Configurar URLs según el modo
if [ "$USE_DOMAIN" = true ]; then
    API_URL="https://api.${ROOT_DOMAIN}"
    STUDIO_URL="https://studio.${ROOT_DOMAIN}"
else
    API_URL="http://${SERVER_IP}:8000"
    STUDIO_URL="http://${SERVER_IP}:3000"
fi

# Actualizar todas las variables necesarias
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|" .env
sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|" .env
sed -i "s|^ANON_KEY=.*|ANON_KEY=$ANON_KEY|" .env
sed -i "s|^SERVICE_ROLE_KEY=.*|SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY|" .env
sed -i "s|^DASHBOARD_USERNAME=.*|DASHBOARD_USERNAME=supabase|" .env
sed -i "s|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD|" .env

# URLs públicas
sed -i "s|^API_EXTERNAL_URL=.*|API_EXTERNAL_URL=$API_URL|" .env
sed -i "s|^SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=$API_URL|" .env

# URLs internas (para comunicación entre servicios)
sed -i "s|^SUPABASE_URL=.*|SUPABASE_URL=http://kong:8000|" .env
sed -i "s|^STUDIO_PG_META_URL=.*|STUDIO_PG_META_URL=http://meta:8080|" .env

echo -e "${GREEN}✓ Variables configuradas${NC}"

# Paso 6: Configurar Traefik si se usa dominio
if [ "$USE_DOMAIN" = true ]; then
    echo -e "${MAGENTA}[6/6]${NC} Configurando Traefik (proxy SSL)..."
    
    # Crear override para Traefik
    cat > docker-compose.traefik.yml << EOF
services:
  traefik:
    image: traefik:v3.1
    container_name: supabase-traefik
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=$EMAIL"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./volumes/traefik:/letsencrypt"
    restart: unless-stopped

  kong:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.kong.rule=Host(\`api.${ROOT_DOMAIN}\`)"
      - "traefik.http.routers.kong.entrypoints=websecure"
      - "traefik.http.routers.kong.tls.certresolver=letsencrypt"
      - "traefik.http.services.kong.loadbalancer.server.port=8000"

  studio:
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.studio.rule=Host(\`studio.${ROOT_DOMAIN}\`)"
      - "traefik.http.routers.studio.entrypoints=websecure"
      - "traefik.http.routers.studio.tls.certresolver=letsencrypt"
      - "traefik.http.services.studio.loadbalancer.server.port=3000"
EOF

    mkdir -p ./volumes/traefik
    touch ./volumes/traefik/acme.json
    chmod 600 ./volumes/traefik/acme.json
    
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.traefik.yml"
    echo -e "${GREEN}✓ Traefik configurado${NC}"
else
    echo -e "${MAGENTA}[6/6]${NC} Configurando puertos directos..."
    
    # Modificar docker-compose para exponer puertos
    cat > docker-compose.ports.yml << EOF
services:
  kong:
    ports:
      - "8000:8000"
  
  studio:
    ports:
      - "3000:3000"
EOF
    
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.ports.yml"
    echo -e "${GREEN}✓ Puertos configurados${NC}"
fi

###############################
# INICIAR SERVICIOS
###############################

echo ""
echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     INICIANDO SERVICIOS              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}Descargando imágenes Docker (esto puede tardar unos minutos)...${NC}"
docker compose $COMPOSE_FILES pull

echo ""
echo -e "${YELLOW}Iniciando contenedores...${NC}"
docker compose $COMPOSE_FILES up -d

echo ""
echo -e "${YELLOW}Esperando a que los servicios estén listos (60 segundos)...${NC}"
sleep 60

###############################
# GUARDAR CREDENCIALES
###############################

CREDS_FILE="/root/supabase_credentials.txt"

cat > $CREDS_FILE << EOF
═══════════════════════════════════════════════════════════
           CREDENCIALES DE SUPABASE
═══════════════════════════════════════════════════════════

FECHA DE INSTALACIÓN: $(date)

─────────────────────────────────────────────────────────
  URLs DE ACCESO
─────────────────────────────────────────────────────────
EOF

if [ "$USE_DOMAIN" = true ]; then
    cat >> $CREDS_FILE << EOF
Studio (Dashboard):  https://studio.${ROOT_DOMAIN}
API URL:            https://api.${ROOT_DOMAIN}
EOF
else
    cat >> $CREDS_FILE << EOF
Studio (Dashboard):  http://${SERVER_IP}:3000
API URL:            http://${SERVER_IP}:8000
EOF
fi

cat >> $CREDS_FILE << EOF

─────────────────────────────────────────────────────────
  CREDENCIALES DEL DASHBOARD
─────────────────────────────────────────────────────────
Usuario:  supabase
Password: ${DASHBOARD_PASSWORD}

─────────────────────────────────────────────────────────
  CLAVES DE LA BASE DE DATOS
─────────────────────────────────────────────────────────
PostgreSQL Password:  ${POSTGRES_PASSWORD}
Database Host:        localhost:5432
Database Name:        postgres
Database User:        postgres

─────────────────────────────────────────────────────────
  CLAVES DE API (Para tu aplicación)
─────────────────────────────────────────────────────────
JWT Secret:       ${JWT_SECRET}
Anon Key:         ${ANON_KEY}
Service Role Key: ${SERVICE_ROLE_KEY}

─────────────────────────────────────────────────────────
  COMANDOS ÚTILES
─────────────────────────────────────────────────────────
Ver logs:         cd ${INSTALL_DIR}/supabase/docker && docker compose logs -f
Reiniciar:        cd ${INSTALL_DIR}/supabase/docker && docker compose restart
Detener:          cd ${INSTALL_DIR}/supabase/docker && docker compose down
Iniciar:          cd ${INSTALL_DIR}/supabase/docker && docker compose up -d
Ver estado:       cd ${INSTALL_DIR}/supabase/docker && docker compose ps

═══════════════════════════════════════════════════════════
  ⚠️  GUARDA ESTE ARCHIVO EN UN LUGAR SEGURO
═══════════════════════════════════════════════════════════
EOF

chmod 600 $CREDS_FILE

###############################
# RESUMEN FINAL
###############################

clear
echo -e "${GREEN}"
cat << "EOF"
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║     ✓✓✓  INSTALACIÓN COMPLETADA EXITOSAMENTE  ✓✓✓      ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"
echo ""

echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}         TU SUPABASE ESTÁ LISTO PARA USAR              ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""

if [ "$USE_DOMAIN" = true ]; then
    echo -e "${YELLOW}📍 URLs de acceso:${NC}"
    echo -e "   ${GREEN}Studio:${NC} https://studio.${ROOT_DOMAIN}"
    echo -e "   ${GREEN}API:${NC}    https://api.${ROOT_DOMAIN}"
    echo ""
    echo -e "${YELLOW}⏱  Nota:${NC} Los certificados SSL pueden tardar 1-2 minutos en generarse"
else
    echo -e "${YELLOW}📍 URLs de acceso:${NC}"
    echo -e "   ${GREEN}Studio:${NC} http://${SERVER_IP}:3000"
    echo -e "   ${GREEN}API:${NC}    http://${SERVER_IP}:8000"
fi

echo ""
echo -e "${YELLOW}🔐 Credenciales del Dashboard:${NC}"
echo -e "   Usuario:  ${CYAN}supabase${NC}"
echo -e "   Password: ${CYAN}${DASHBOARD_PASSWORD}${NC}"
echo ""

echo -e "${YELLOW}🔑 Claves de API (para tu app):${NC}"
echo -e "   API URL:  ${CYAN}${API_URL}${NC}"
echo -e "   Anon Key: ${CYAN}${ANON_KEY:0:40}...${NC}"
echo ""

echo -e "${YELLOW}📄 Credenciales completas guardadas en:${NC}"
echo -e "   ${CYAN}${CREDS_FILE}${NC}"
echo ""

echo -e "${YELLOW}📝 Comandos útiles:${NC}"
echo -e "   Ver credenciales: ${CYAN}cat ${CREDS_FILE}${NC}"
echo -e "   Ver logs:         ${CYAN}cd ${INSTALL_DIR}/supabase/docker && docker compose logs -f${NC}"
echo -e "   Ver estado:       ${CYAN}cd ${INSTALL_DIR}/supabase/docker && docker compose ps${NC}"
echo ""

echo -e "${GREEN}¡Disfruta de tu Supabase self-hosted! 🚀${NC}"
echo ""
