#!/bin/bash

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=== Reparando configuración de Supabase ===${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Por favor, ejecuta este script como root o con sudo.${NC}"
  exit 1
fi

cd /opt/supabase || exit 1

echo -e "${YELLOW}[1/4] Deteniendo contenedores...${NC}"
docker compose down > /dev/null 2>&1
echo -e "${GREEN}✓ Contenedores detenidos${NC}"
echo ""

echo -e "${YELLOW}[2/4] Corrigiendo docker-compose.yml...${NC}"
# Corregir el problema del docker socket duplicado
sed -i 's|/var/run/docker.sock/var/run/docker.sock|/var/run/docker.sock|g' docker-compose.yml
sed -i 's|:/var/run/docker.sock:ro,z|/var/run/docker.sock:/var/run/docker.sock:ro|g' docker-compose.yml
sed -i 's|:\${DOCKER_SOCKET_LOCATION:-/var/run/docker.sock}:ro,z|/var/run/docker.sock:/var/run/docker.sock:ro|g' docker-compose.yml
echo -e "${GREEN}✓ docker-compose.yml corregido${NC}"
echo ""

echo -e "${YELLOW}[3/4] Verificando docker-compose.override.yml...${NC}"
if grep -q "traefik:v2" docker-compose.override.yml 2>/dev/null; then
    echo -e "${YELLOW}Actualizando Traefik a v3.1...${NC}"
    sed -i 's|traefik:v2.*|traefik:v3.1|g' docker-compose.override.yml
fi
echo -e "${GREEN}✓ Traefik actualizado${NC}"
echo ""

echo -e "${YELLOW}[4/4] Iniciando servicios...${NC}"
docker compose up -d
echo -e "${GREEN}✓ Servicios iniciados${NC}"
echo ""

echo -e "${CYAN}Esperando 30 segundos a que los servicios arranquen...${NC}"
sleep 30

echo ""
echo -e "${GREEN}=== Estado de los contenedores ===${NC}"
docker compose ps
echo ""

echo -e "${CYAN}Si todo está OK, verificá con:${NC}"
echo -e "  ${GREEN}bash <(curl -sL https://raw.githubusercontent.com/alvaro-segunda-cabeza/supabase-installer/main/check_supabase.sh)${NC}"
echo ""
