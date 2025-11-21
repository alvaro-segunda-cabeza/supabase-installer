#!/bin/bash

# ============================================
# INSTALADOR DE DOCKER - VERSIÓN LIMPIA
# ============================================

set -e

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔════════════════════════════════════════════╗"
echo "║                                            ║"
echo "║      INSTALADOR DE DOCKER - LIMPIO         ║"
echo "║                                            ║"
echo "╚════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Verificar ejecución como root
if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}❌ Error: Este script debe ejecutarse como root${NC}"
  echo -e "${YELLOW}Usa: sudo $0${NC}"
  exit 1
fi

echo -e "${BLUE}[INFO]${NC} Iniciando instalación limpia de Docker..."
echo ""

# ============================================
# PASO 1: LIMPIAR INSTALACIONES PREVIAS
# ============================================
echo -e "${CYAN}[1/6]${NC} ${YELLOW}Limpiando instalaciones previas de Docker...${NC}"

# Detener Docker si está corriendo
systemctl stop docker.socket 2>/dev/null || true
systemctl stop docker 2>/dev/null || true
sleep 2

# Remover paquetes antiguos
apt-get remove -y \
    docker \
    docker-engine \
    docker.io \
    containerd \
    runc \
    docker-compose \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin 2>/dev/null || true

apt-get purge -y \
    docker \
    docker-engine \
    docker.io \
    containerd \
    runc \
    docker-compose \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin 2>/dev/null || true

apt-get autoremove -y
apt-get autoclean -y

# Limpiar archivos residuales (OPCIONAL - comentado por seguridad)
# rm -rf /var/lib/docker
# rm -rf /var/lib/containerd
# rm -rf /etc/docker

echo -e "${GREEN}✓ Limpieza completada${NC}"
echo ""

# ============================================
# PASO 2: ACTUALIZAR SISTEMA
# ============================================
echo -e "${CYAN}[2/6]${NC} ${YELLOW}Actualizando sistema...${NC}"

apt-get update -y
apt-get upgrade -y

echo -e "${GREEN}✓ Sistema actualizado${NC}"
echo ""

# ============================================
# PASO 3: INSTALAR DEPENDENCIAS
# ============================================
echo -e "${CYAN}[3/6]${NC} ${YELLOW}Instalando dependencias...${NC}"

apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common

echo -e "${GREEN}✓ Dependencias instaladas${NC}"
echo ""

# ============================================
# PASO 4: CONFIGURAR REPOSITORIO DE DOCKER
# ============================================
echo -e "${CYAN}[4/6]${NC} ${YELLOW}Configurando repositorio oficial de Docker...${NC}"

# Crear directorio para llaves
mkdir -p /etc/apt/keyrings

# Descargar llave GPG de Docker
rm -f /etc/apt/keyrings/docker.gpg
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null

# Si falla con Ubuntu, intentar con Debian
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Intentando con repositorio de Debian...${NC}"
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi

chmod a+r /etc/apt/keyrings/docker.gpg

# Detectar sistema operativo y versión
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION_CODENAME=$(lsb_release -cs 2>/dev/null || echo "$VERSION_CODENAME")
else
    OS="ubuntu"
    VERSION_CODENAME="jammy"
fi

echo -e "${BLUE}[INFO]${NC} Sistema detectado: $OS $VERSION_CODENAME"

# Agregar repositorio
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
  $VERSION_CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y

echo -e "${GREEN}✓ Repositorio configurado${NC}"
echo ""

# ============================================
# PASO 5: INSTALAR DOCKER
# ============================================
echo -e "${CYAN}[5/6]${NC} ${YELLOW}Instalando Docker Engine...${NC}"

apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

echo -e "${GREEN}✓ Docker instalado${NC}"
echo ""

# ============================================
# PASO 6: CONFIGURAR Y VERIFICAR DOCKER
# ============================================
echo -e "${CYAN}[6/6]${NC} ${YELLOW}Configurando y verificando Docker...${NC}"

# Habilitar y arrancar Docker
systemctl enable docker
systemctl start docker

# Esperar que Docker inicie
sleep 3

# Verificar que Docker esté corriendo
if ! systemctl is-active --quiet docker; then
    echo -e "${RED}❌ Error: Docker no se inició correctamente${NC}"
    echo -e "${YELLOW}Verificando logs...${NC}"
    journalctl -xeu docker.service --no-pager | tail -20
    exit 1
fi

echo -e "${GREEN}✓ Docker está corriendo${NC}"
echo ""

# ============================================
# VERIFICACIÓN FINAL
# ============================================
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo -e "${CYAN}         VERIFICACIÓN FINAL            ${NC}"
echo -e "${CYAN}═══════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}Versión de Docker instalada:${NC}"
docker --version
echo ""

echo -e "${YELLOW}Versión de Docker Compose:${NC}"
docker compose version
echo ""

echo -e "${YELLOW}Información del sistema Docker:${NC}"
docker version
echo ""

echo -e "${YELLOW}Información del sistema:${NC}"
docker info | head -20
echo ""

# Prueba con contenedor hello-world
echo -e "${YELLOW}Ejecutando prueba con contenedor hello-world...${NC}"
if docker run --rm hello-world > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Prueba exitosa - Docker funciona correctamente${NC}"
    # Limpiar imagen de prueba
    docker image rm hello-world 2>/dev/null || true
else
    echo -e "${RED}❌ Error: La prueba con hello-world falló${NC}"
    exit 1
fi
echo ""

# ============================================
# CONFIGURACIÓN ADICIONAL (OPCIONAL)
# ============================================
echo -e "${CYAN}Configuración adicional...${NC}"

# Permitir usar Docker sin sudo (agregar usuario a grupo docker)
if [ ! -z "$SUDO_USER" ]; then
    usermod -aG docker $SUDO_USER
    echo -e "${GREEN}✓ Usuario $SUDO_USER agregado al grupo docker${NC}"
    echo -e "${YELLOW}  Nota: Cierra sesión y vuelve a iniciar para que tome efecto${NC}"
fi

# Configurar Docker para arranque automático
systemctl enable docker.service
systemctl enable containerd.service

echo ""
echo -e "${GREEN}"
echo "╔════════════════════════════════════════════╗"
echo "║                                            ║"
echo "║    ✓ DOCKER INSTALADO EXITOSAMENTE        ║"
echo "║                                            ║"
echo "╚════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "${CYAN}📋 RESUMEN:${NC}"
echo -e "  ${GREEN}✓${NC} Docker Engine: $(docker --version | awk '{print $3}')"
echo -e "  ${GREEN}✓${NC} Docker Compose: $(docker compose version --short)"
echo -e "  ${GREEN}✓${NC} Estado del servicio: $(systemctl is-active docker)"
echo ""
echo -e "${CYAN}📝 COMANDOS ÚTILES:${NC}"
echo -e "  ${YELLOW}docker ps${NC}              - Ver contenedores corriendo"
echo -e "  ${YELLOW}docker images${NC}          - Ver imágenes descargadas"
echo -e "  ${YELLOW}docker compose up -d${NC}   - Levantar servicios en segundo plano"
echo -e "  ${YELLOW}docker compose logs -f${NC} - Ver logs en tiempo real"
echo -e "  ${YELLOW}systemctl status docker${NC} - Ver estado del servicio"
echo ""
echo -e "${GREEN}🎉 ¡Listo para usar Docker!${NC}"
echo ""
