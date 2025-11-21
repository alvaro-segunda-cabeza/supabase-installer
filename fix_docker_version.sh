#!/bin/bash

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   DIAGNÓSTICO Y FIX DE DOCKER VERSION ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
echo ""

# Verificar si se ejecuta como root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}❌ Por favor, ejecuta este script como root o con sudo.${NC}"
  exit 1
fi

# 1. Diagnóstico actual
echo -e "${CYAN}[1/4] 🔍 Diagnóstico actual de Docker...${NC}"
echo ""

echo -e "${YELLOW}Versión de Docker instalada:${NC}"
docker --version 2>&1 || echo "Docker no encontrado o no responde"
echo ""

echo -e "${YELLOW}Versión de Docker Compose:${NC}"
docker compose version 2>&1 || docker-compose --version 2>&1 || echo "Docker Compose no encontrado"
echo ""

echo -e "${YELLOW}API Version del servidor Docker:${NC}"
docker version 2>&1 | grep -A 5 "Server:" || echo "No se pudo obtener info del servidor"
echo ""

echo -e "${YELLOW}Estado del servicio Docker:${NC}"
systemctl status docker --no-pager | head -n 5
echo ""

# 2. Detener servicios
echo -e "${CYAN}[2/4] 🛑 Deteniendo servicios Docker...${NC}"
if [ -d "/opt/supabase" ]; then
    cd /opt/supabase
    docker compose down 2>/dev/null || docker-compose down 2>/dev/null || true
    cd /
fi

systemctl stop docker 2>/dev/null || true
sleep 2
echo -e "${GREEN}✓ Servicios detenidos${NC}"
echo ""

# 3. Desinstalar versión antigua y reinstalar Docker
echo -e "${CYAN}[3/4] 🔄 Reinstalando Docker con última versión...${NC}"

# Eliminar versiones antiguas
apt-get remove -y docker docker-engine docker.io containerd runc docker-compose 2>/dev/null || true
apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true

# Limpiar
apt-get autoremove -y 2>/dev/null
apt-get autoclean -y 2>/dev/null

# Instalar dependencias
apt-get update -y
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Agregar repositorio oficial de Docker
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || \
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Detectar sistema operativo
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION_CODENAME=$(lsb_release -cs 2>/dev/null || echo $VERSION_CODENAME)
else
    OS="ubuntu"
    VERSION_CODENAME="focal"
fi

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $VERSION_CODENAME stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

# Instalar Docker más reciente
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo -e "${GREEN}✓ Docker reinstalado${NC}"
echo ""

# 4. Verificar instalación
echo -e "${CYAN}[4/4] ✅ Verificando instalación...${NC}"
echo ""

systemctl enable docker
systemctl start docker
sleep 3

echo -e "${YELLOW}Nueva versión de Docker:${NC}"
docker --version
echo ""

echo -e "${YELLOW}Nueva versión de Docker Compose:${NC}"
docker compose version
echo ""

echo -e "${YELLOW}Versión de API del servidor:${NC}"
docker version | grep -A 5 "Server:"
echo ""

# Verificar que funcione con un contenedor de prueba
echo -e "${YELLOW}Probando Docker con contenedor de prueba:${NC}"
if docker run --rm hello-world > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Docker funcionando correctamente${NC}"
else
    echo -e "${RED}❌ Docker tiene problemas${NC}"
    exit 1
fi
echo ""

# Limpiar imagen de prueba
docker image rm hello-world 2>/dev/null || true

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✓ DOCKER ACTUALIZADO EXITOSAMENTE   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📋 SIGUIENTE PASO:${NC}"
echo -e "  Si Supabase estaba instalado, reinicia los servicios con:"
echo -e "  ${YELLOW}cd /opt/supabase && docker compose up -d${NC}"
echo ""
