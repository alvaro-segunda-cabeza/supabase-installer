#!/bin/bash
set -e

###############################
# EVOLUTION API INSTALLER
# Instalador completo de Evolution API
# Versión: 1.0
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

echo -e "${GREEN}"
cat << "EOF"
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║   ███████╗██╗   ██╗ ██████╗ ██╗     ██╗   ██╗████████╗  ║
║   ██╔════╝██║   ██║██╔═══██╗██║     ██║   ██║╚══██╔══╝  ║
║   █████╗  ██║   ██║██║   ██║██║     ██║   ██║   ██║     ║
║   ██╔══╝  ╚██╗ ██╔╝██║   ██║██║     ██║   ██║   ██║     ║
║   ███████╗ ╚████╔╝ ╚██████╔╝███████╗╚██████╔╝   ██║     ║
║   ╚══════╝  ╚═══╝   ╚═════╝ ╚══════╝ ╚═════╝    ╚═╝     ║
║                                                          ║
║            EVOLUTION API INSTALLER v1.0                  ║
║               WhatsApp API Self-Hosted                   ║
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
echo -e "  ${BLUE}1)${NC} Usar dominio (ej: evolution.midominio.com)"
echo -e "  ${BLUE}2)${NC} Usar IP del servidor (sin SSL)"
echo ""
read -p "Selecciona una opción [1-2]: " DOMAIN_OPTION

if [ "$DOMAIN_OPTION" = "1" ]; then
    USE_DOMAIN=true
    read -p "Ingresa tu dominio completo (ej: evolution.midominio.com): " EVOLUTION_DOMAIN
    read -p "Ingresa tu email para certificados SSL: " EMAIL
    
    echo ""
    echo -e "${YELLOW}📝 IMPORTANTE: Configura este registro DNS:${NC}"
    echo -e "   ${BLUE}A${NC} ${EVOLUTION_DOMAIN}  →  IP del servidor"
    echo ""
    read -p "Presiona ENTER cuando hayas configurado el DNS..."
else
    USE_DOMAIN=false
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo -e "${GREEN}✓ Se usará la IP: ${SERVER_IP}${NC}"
fi

echo ""

# Preguntar por base de datos
echo -e "${YELLOW}¿Qué base de datos deseas usar?${NC}"
echo -e "  ${BLUE}1)${NC} PostgreSQL (recomendado para producción)"
echo -e "  ${BLUE}2)${NC} SQLite (más simple, ideal para pruebas)"
echo ""
read -p "Selecciona una opción [1-2]: " DB_OPTION

if [ "$DB_OPTION" = "1" ]; then
    USE_POSTGRES=true
    echo -e "${GREEN}✓ Se usará PostgreSQL${NC}"
else
    USE_POSTGRES=false
    echo -e "${GREEN}✓ Se usará SQLite${NC}"
fi

echo ""

# Preguntar por Redis
echo -e "${YELLOW}¿Deseas usar Redis para caché y colas?${NC}"
echo -e "  ${BLUE}1)${NC} Sí (recomendado para producción)"
echo -e "  ${BLUE}2)${NC} No (más simple)"
echo ""
read -p "Selecciona una opción [1-2]: " REDIS_OPTION

if [ "$REDIS_OPTION" = "1" ]; then
    USE_REDIS=true
    echo -e "${GREEN}✓ Se usará Redis${NC}"
else
    USE_REDIS=false
    echo -e "${GREEN}✓ Sin Redis${NC}"
fi

echo ""

# Directorio de instalación
INSTALL_DIR="/opt/evolution-api"
echo -e "${BLUE}Directorio de instalación: ${INSTALL_DIR}${NC}"

# Confirmar instalación
echo ""
echo -e "${YELLOW}═══════════════════════════════════════${NC}"
echo -e "${YELLOW}   RESUMEN DE LA INSTALACIÓN${NC}"
echo -e "${YELLOW}═══════════════════════════════════════${NC}"
if [ "$USE_DOMAIN" = true ]; then
    echo -e "  ${CYAN}Modo:${NC} Dominio con SSL"
    echo -e "  ${CYAN}URL:${NC} https://${EVOLUTION_DOMAIN}"
else
    echo -e "  ${CYAN}Modo:${NC} IP sin SSL"
    echo -e "  ${CYAN}URL:${NC} http://${SERVER_IP}:8080"
fi
echo -e "  ${CYAN}Base de datos:${NC} $([ "$USE_POSTGRES" = true ] && echo "PostgreSQL" || echo "SQLite")"
echo -e "  ${CYAN}Redis:${NC} $([ "$USE_REDIS" = true ] && echo "Sí" || echo "No")"
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
echo -e "${MAGENTA}[1/5]${NC} Instalando dependencias..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y > /dev/null 2>&1
apt-get install -y curl jq openssl ufw > /dev/null 2>&1
echo -e "${GREEN}✓ Dependencias instaladas${NC}"

# Paso 2: Configurar firewall
echo -e "${MAGENTA}[2/5]${NC} Configurando firewall..."
ufw allow ssh > /dev/null 2>&1
ufw allow 80 > /dev/null 2>&1
ufw allow 443 > /dev/null 2>&1
ufw allow 8080 > /dev/null 2>&1  # Evolution API (si se usa IP)
ufw --force enable > /dev/null 2>&1
echo -e "${GREEN}✓ Firewall configurado${NC}"

# Paso 3: Crear estructura de directorios
echo -e "${MAGENTA}[3/5]${NC} Creando estructura de directorios..."
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR
mkdir -p instances
echo -e "${GREEN}✓ Estructura creada${NC}"

# Paso 4: Generar secretos
echo -e "${MAGENTA}[4/5]${NC} Generando claves de seguridad..."

AUTHENTICATION_API_KEY=$(openssl rand -hex 32)
POSTGRES_PASSWORD=$(openssl rand -hex 24)

echo -e "${GREEN}✓ Claves generadas${NC}"

# Paso 5: Crear docker-compose
echo -e "${MAGENTA}[5/5]${NC} Configurando Evolution API..."

# Configurar URL según el modo
if [ "$USE_DOMAIN" = true ]; then
    SERVER_URL="https://${EVOLUTION_DOMAIN}"
else
    SERVER_URL="http://${SERVER_IP}:8080"
fi

# Crear docker-compose.yml
cat > docker-compose.yml << 'COMPOSE_START'
version: '3.8'

services:
  evolution-api:
    image: atendai/evolution-api:latest
    container_name: evolution-api
    restart: unless-stopped
    volumes:
      - evolution_instances:/evolution/instances
    environment:
      # Server Config
      - SERVER_TYPE=http
      - SERVER_PORT=8080
COMPOSE_START

# Agregar SERVER_URL
echo "      - SERVER_URL=${SERVER_URL}" >> docker-compose.yml

cat >> docker-compose.yml << 'COMPOSE_AUTH'
      
      # CORS
      - CORS_ORIGIN=*
      - CORS_METHODS=GET,POST,PUT,DELETE
      - CORS_CREDENTIALS=true
      
      # Logs
      - LOG_LEVEL=ERROR
      - LOG_COLOR=true
      - LOG_BAILEYS=error
      
      # Store Config
      - STORE_MESSAGES=true
      - STORE_MESSAGE_UP=true
      - STORE_CONTACTS=true
      - STORE_CHATS=true
      
      # Clean Store
      - CLEAN_STORE_CLEANING_INTERVAL=7200
      - CLEAN_STORE_MESSAGES=true
      - CLEAN_STORE_MESSAGE_UP=true
      - CLEAN_STORE_CONTACTS=true
      - CLEAN_STORE_CHATS=true
      
      # Authentication
      - AUTHENTICATION_TYPE=apikey
COMPOSE_AUTH

# Agregar API KEY
echo "      - AUTHENTICATION_API_KEY=${AUTHENTICATION_API_KEY}" >> docker-compose.yml

cat >> docker-compose.yml << 'COMPOSE_MORE'
      - AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=true
      
      # QR Code Config
      - QRCODE_LIMIT=30
      - QRCODE_COLOR=#000000
      
      # Typebot (deshabilitado por defecto)
      - TYPEBOT_ENABLED=false
      
      # Chatwoot (deshabilitado por defecto)
      - CHATWOOT_ENABLED=false
      
      # Cache (deshabilitado por defecto, se habilitará si se usa Redis)
      - CACHE_REDIS_ENABLED=false
      - CACHE_LOCAL_ENABLED=false
COMPOSE_MORE

# Agregar configuración de base de datos
if [ "$USE_POSTGRES" = true ]; then
    cat >> docker-compose.yml << COMPOSE_DB
      
      # Database PostgreSQL
      - DATABASE_ENABLED=true
      - DATABASE_PROVIDER=postgresql
      - DATABASE_CONNECTION_URI=postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/evolution
      - DATABASE_CONNECTION_CLIENT_NAME=evolution_api
      - DATABASE_SAVE_DATA_INSTANCE=true
      - DATABASE_SAVE_DATA_NEW_MESSAGE=true
      - DATABASE_SAVE_MESSAGE_UPDATE=true
      - DATABASE_SAVE_DATA_CONTACTS=true
      - DATABASE_SAVE_DATA_CHATS=true
      - DATABASE_SAVE_DATA_LABELS=true
      - DATABASE_SAVE_DATA_HISTORIC=true
COMPOSE_DB
else
    cat >> docker-compose.yml << 'COMPOSE_DB_SQLITE'
      
      # Database SQLite
      - DATABASE_ENABLED=false
COMPOSE_DB_SQLITE
fi

# Agregar configuración de Redis
if [ "$USE_REDIS" = true ]; then
    cat >> docker-compose.yml << 'COMPOSE_REDIS_ENV'
      
      # Redis
      - CACHE_REDIS_ENABLED=true
      - CACHE_REDIS_URI=redis://redis:6379/0
      - CACHE_REDIS_PREFIX_KEY=evolution
      - CACHE_REDIS_SAVE_INSTANCES=true
      - CACHE_LOCAL_ENABLED=false
COMPOSE_REDIS_ENV
fi

# Agregar networks y depends_on
if [ "$USE_POSTGRES" = true ] || [ "$USE_REDIS" = true ]; then
    echo "    depends_on:" >> docker-compose.yml
    [ "$USE_POSTGRES" = true ] && echo "      - postgres" >> docker-compose.yml
    [ "$USE_REDIS" = true ] && echo "      - redis" >> docker-compose.yml
fi

echo "    networks:" >> docker-compose.yml
echo "      - evolution-network" >> docker-compose.yml

# Agregar puertos si no se usa dominio
if [ "$USE_DOMAIN" = false ]; then
    cat >> docker-compose.yml << 'COMPOSE_PORTS'
    ports:
      - "8080:8080"
COMPOSE_PORTS
fi

# Agregar PostgreSQL si se seleccionó
if [ "$USE_POSTGRES" = true ]; then
    cat >> docker-compose.yml << COMPOSE_POSTGRES

  postgres:
    image: postgres:15-alpine
    container_name: evolution-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=evolution
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - evolution-network
COMPOSE_POSTGRES
fi

# Agregar Redis si se seleccionó
if [ "$USE_REDIS" = true ]; then
    cat >> docker-compose.yml << 'COMPOSE_REDIS'

  redis:
    image: redis:7-alpine
    container_name: evolution-redis
    restart: unless-stopped
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    networks:
      - evolution-network
COMPOSE_REDIS
fi

# Agregar Traefik si se usa dominio
if [ "$USE_DOMAIN" = true ]; then
    cat >> docker-compose.yml << COMPOSE_TRAEFIK

  traefik:
    image: traefik:v3.1
    container_name: evolution-traefik
    restart: unless-stopped
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=${EMAIL}"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "traefik_certs:/letsencrypt"
    networks:
      - evolution-network
COMPOSE_TRAEFIK

    # Agregar labels de Traefik al servicio evolution-api
    sed -i '/container_name: evolution-api/a\    labels:\n      - "traefik.enable=true"\n      - "traefik.http.routers.evolution.rule=Host(\`'${EVOLUTION_DOMAIN}'\`)"\n      - "traefik.http.routers.evolution.entrypoints=websecure"\n      - "traefik.http.routers.evolution.tls.certresolver=letsencrypt"\n      - "traefik.http.services.evolution.loadbalancer.server.port=8080"' docker-compose.yml
fi

# Agregar networks y volumes
cat >> docker-compose.yml << 'COMPOSE_END'

networks:
  evolution-network:
    driver: bridge

volumes:
  evolution_instances:
COMPOSE_END

[ "$USE_POSTGRES" = true ] && echo "  postgres_data:" >> docker-compose.yml
[ "$USE_REDIS" = true ] && echo "  redis_data:" >> docker-compose.yml
[ "$USE_DOMAIN" = true ] && echo "  traefik_certs:" >> docker-compose.yml

echo -e "${GREEN}✓ Evolution API configurado${NC}"

###############################
# INICIAR SERVICIOS
###############################

echo ""
echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     INICIANDO SERVICIOS              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

echo -e "${YELLOW}Descargando imágenes Docker...${NC}"
docker compose pull

echo ""
echo -e "${YELLOW}Iniciando contenedores...${NC}"
docker compose up -d

echo ""
echo -e "${YELLOW}Esperando a que los servicios estén listos (30 segundos)...${NC}"
sleep 30

###############################
# GUARDAR CREDENCIALES
###############################

CREDS_FILE="/root/evolution_credentials.txt"

cat > $CREDS_FILE << EOF
═══════════════════════════════════════════════════════════
           CREDENCIALES DE EVOLUTION API
═══════════════════════════════════════════════════════════

FECHA DE INSTALACIÓN: $(date)

─────────────────────────────────────────────────────────
  URL DE ACCESO
─────────────────────────────────────────────────────────
EOF

if [ "$USE_DOMAIN" = true ]; then
    cat >> $CREDS_FILE << EOF
Evolution API:  https://${EVOLUTION_DOMAIN}
EOF
else
    cat >> $CREDS_FILE << EOF
Evolution API:  http://${SERVER_IP}:8080
EOF
fi

cat >> $CREDS_FILE << EOF

─────────────────────────────────────────────────────────
  CLAVE DE API (IMPORTANTE - GUÁRDALA)
─────────────────────────────────────────────────────────
API Key:  ${AUTHENTICATION_API_KEY}

─────────────────────────────────────────────────────────
  ENDPOINTS PRINCIPALES
─────────────────────────────────────────────────────────
EOF

if [ "$USE_DOMAIN" = true ]; then
    cat >> $CREDS_FILE << EOF
Crear instancia:     POST https://${EVOLUTION_DOMAIN}/instance/create
Conectar WhatsApp:   GET  https://${EVOLUTION_DOMAIN}/instance/connect/{instance}
Enviar mensaje:      POST https://${EVOLUTION_DOMAIN}/message/sendText/{instance}
Ver QR Code:         GET  https://${EVOLUTION_DOMAIN}/instance/qrcode/{instance}
Documentación:       https://${EVOLUTION_DOMAIN}/docs
EOF
else
    cat >> $CREDS_FILE << EOF
Crear instancia:     POST http://${SERVER_IP}:8080/instance/create
Conectar WhatsApp:   GET  http://${SERVER_IP}:8080/instance/connect/{instance}
Enviar mensaje:      POST http://${SERVER_IP}:8080/message/sendText/{instance}
Ver QR Code:         GET  http://${SERVER_IP}:8080/instance/qrcode/{instance}
Documentación:       http://${SERVER_IP}:8080/docs
EOF
fi

if [ "$USE_POSTGRES" = true ]; then
    cat >> $CREDS_FILE << EOF

─────────────────────────────────────────────────────────
  BASE DE DATOS POSTGRESQL
─────────────────────────────────────────────────────────
Host:      localhost:5432 (o postgres dentro de Docker)
Database:  evolution
Usuario:   postgres
Password:  ${POSTGRES_PASSWORD}
EOF
fi

cat >> $CREDS_FILE << EOF

─────────────────────────────────────────────────────────
  EJEMPLO: CREAR INSTANCIA DE WHATSAPP
─────────────────────────────────────────────────────────
curl -X POST '${SERVER_URL}/instance/create' \\
  -H 'Content-Type: application/json' \\
  -H 'apikey: ${AUTHENTICATION_API_KEY}' \\
  -d '{
    "instanceName": "mi-whatsapp",
    "qrcode": true,
    "integration": "WHATSAPP-BAILEYS"
  }'

─────────────────────────────────────────────────────────
  COMANDOS ÚTILES
─────────────────────────────────────────────────────────
Ver logs:         cd ${INSTALL_DIR} && docker compose logs -f
Reiniciar:        cd ${INSTALL_DIR} && docker compose restart
Detener:          cd ${INSTALL_DIR} && docker compose down
Iniciar:          cd ${INSTALL_DIR} && docker compose up -d
Ver estado:       cd ${INSTALL_DIR} && docker compose ps

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
echo -e "${CYAN}       EVOLUTION API ESTÁ LISTA PARA USAR              ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
echo ""

if [ "$USE_DOMAIN" = true ]; then
    echo -e "${YELLOW}📍 URL de acceso:${NC}"
    echo -e "   ${GREEN}API:${NC}  https://${EVOLUTION_DOMAIN}"
    echo -e "   ${GREEN}Docs:${NC} https://${EVOLUTION_DOMAIN}/docs"
    echo ""
    echo -e "${YELLOW}⏱  Nota:${NC} Los certificados SSL pueden tardar 1-2 minutos en generarse"
else
    echo -e "${YELLOW}📍 URL de acceso:${NC}"
    echo -e "   ${GREEN}API:${NC}  http://${SERVER_IP}:8080"
    echo -e "   ${GREEN}Docs:${NC} http://${SERVER_IP}:8080/docs"
fi

echo ""
echo -e "${YELLOW}🔑 API Key (para autenticación):${NC}"
echo -e "   ${CYAN}${AUTHENTICATION_API_KEY}${NC}"
echo ""

echo -e "${YELLOW}📱 Pasos siguientes:${NC}"
echo -e "   1. Visita ${CYAN}${SERVER_URL}/docs${NC} para ver la documentación"
echo -e "   2. Crea una instancia de WhatsApp con la API"
echo -e "   3. Escanea el código QR con tu WhatsApp"
echo -e "   4. ¡Empieza a enviar mensajes!"
echo ""

echo -e "${YELLOW}📄 Credenciales completas guardadas en:${NC}"
echo -e "   ${CYAN}${CREDS_FILE}${NC}"
echo ""

echo -e "${YELLOW}📝 Ejemplo rápido - Crear instancia:${NC}"
echo -e "${BLUE}curl -X POST '${SERVER_URL}/instance/create' \\${NC}"
echo -e "${BLUE}  -H 'Content-Type: application/json' \\${NC}"
echo -e "${BLUE}  -H 'apikey: ${AUTHENTICATION_API_KEY}' \\${NC}"
echo -e "${BLUE}  -d '{\"instanceName\": \"mi-whatsapp\", \"qrcode\": true}'${NC}"
echo ""

echo -e "${GREEN}¡Disfruta de Evolution API! 🚀${NC}"
echo ""
