#!/bin/bash

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== Script de corrección agresiva de Supabase ===${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Por favor, ejecuta este script como root o con sudo.${NC}"
  exit 1
fi

cd /opt/supabase || exit 1

echo -e "${YELLOW}[1/6] Deteniendo contenedores...${NC}"
docker compose down -v > /dev/null 2>&1
sleep 5
echo -e "${GREEN}✓ Contenedores detenidos${NC}"
echo ""

echo -e "${YELLOW}[2/6] Creando backup del docker-compose.yml...${NC}"
cp docker-compose.yml docker-compose.yml.backup
echo -e "${GREEN}✓ Backup creado: docker-compose.yml.backup${NC}"
echo ""

echo -e "${YELLOW}[3/6] Corrigiendo TODOS los problemas del docker-compose.yml...${NC}"

# 1. Eliminar DOCKER_SOCKET_LOCATION del .env si existe (causa problemas)
if grep -q "DOCKER_SOCKET_LOCATION" .env; then
    sed -i '/DOCKER_SOCKET_LOCATION/d' .env
    echo -e "${GREEN}  ✓ Eliminada variable DOCKER_SOCKET_LOCATION del .env${NC}"
fi

# 2. Buscar y corregir TODAS las referencias al Docker socket en docker-compose.yml
echo -e "${CYAN}  Buscando problemas con el Docker socket...${NC}"

# Patrón 1: Socket duplicado
sed -i 's|/var/run/docker.sock/var/run/docker.sock|/var/run/docker.sock|g' docker-compose.yml

# Patrón 2: Variable DOCKER_SOCKET_LOCATION mal formada
sed -i 's|:\${DOCKER_SOCKET_LOCATION[^}]*}:/var/run/docker.sock|/var/run/docker.sock:/var/run/docker.sock|g' docker-compose.yml

# Patrón 3: Líneas que empiezan con ":"
sed -i 's|^[[:space:]]*- :/var/run/docker.sock.*|      - /var/run/docker.sock:/var/run/docker.sock:ro|g' docker-compose.yml

# Patrón 4: ${DOCKER_SOCKET_LOCATION:-/var/run/docker.sock} mal usado
sed -i 's|:\${DOCKER_SOCKET_LOCATION:-/var/run/docker\.sock}:/var/run/docker\.sock:ro,z|/var/run/docker.sock:/var/run/docker.sock:ro|g' docker-compose.yml

# Patrón 5: Cualquier referencia a DOCKER_SOCKET_LOCATION
sed -i 's|\${DOCKER_SOCKET_LOCATION[^}]*}|/var/run/docker.sock|g' docker-compose.yml

echo -e "${GREEN}  ✓ Correcciones aplicadas${NC}"
echo ""

echo -e "${YELLOW}[4/6] Verificando correcciones...${NC}"
echo -e "${CYAN}  Líneas que contienen 'docker.sock':${NC}"
grep -n "docker.sock" docker-compose.yml | head -20

PROBLEMATIC_LINES=$(grep "/var/run/docker.sock/var/run/docker.sock" docker-compose.yml 2>/dev/null | wc -l)
if [ "$PROBLEMATIC_LINES" -eq 0 ]; then
    echo -e "${GREEN}  ✓ No hay sockets duplicados${NC}"
else
    echo -e "${RED}  ✗ Todavía hay $PROBLEMATIC_LINES problemas${NC}"
fi
echo ""

echo -e "${YELLOW}[5/6] Agregando variables S3 faltantes al .env...${NC}"

# Agregar variables S3 si no existen
[ ! "$(grep -c "^REGION=" .env)" -gt 0 ] && echo "REGION=us-east-1" >> .env && echo -e "${GREEN}  + REGION${NC}"
[ ! "$(grep -c "^GLOBAL_S3_BUCKET=" .env)" -gt 0 ] && echo "GLOBAL_S3_BUCKET=supabase-storage" >> .env && echo -e "${GREEN}  + GLOBAL_S3_BUCKET${NC}"
[ ! "$(grep -c "^TENANT_ID=" .env)" -gt 0 ] && echo "TENANT_ID=stub" >> .env && echo -e "${GREEN}  + TENANT_ID${NC}"
[ ! "$(grep -c "^S3_PROTOCOL_PREFIX=" .env)" -gt 0 ] && echo "S3_PROTOCOL_PREFIX=http" >> .env && echo -e "${GREEN}  + S3_PROTOCOL_PREFIX${NC}"
[ ! "$(grep -c "^S3_PROTOCOL_ACCESS_KEY_ID=" .env)" -gt 0 ] && echo "S3_PROTOCOL_ACCESS_KEY_ID=stub" >> .env && echo -e "${GREEN}  + S3_PROTOCOL_ACCESS_KEY_ID${NC}"
[ ! "$(grep -c "^S3_PROTOCOL_ACCESS_KEY_SECRET=" .env)" -gt 0 ] && echo "S3_PROTOCOL_ACCESS_KEY_SECRET=stub" >> .env && echo -e "${GREEN}  + S3_PROTOCOL_ACCESS_KEY_SECRET${NC}"

echo -e "${GREEN}✓ Variables S3 configuradas${NC}"
echo ""

echo -e "${YELLOW}[6/6] Iniciando servicios...${NC}"
docker compose up -d 2>&1 | tee /tmp/docker-up.log

if grep -q "Error response from daemon" /tmp/docker-up.log; then
    echo ""
    echo -e "${RED}✗ Error al iniciar los servicios${NC}"
    echo -e "${YELLOW}Mostrando el error completo:${NC}"
    cat /tmp/docker-up.log | grep -A 5 "Error response from daemon"
    echo ""
    echo -e "${YELLOW}Mostrando las líneas problemáticas del docker-compose.yml:${NC}"
    grep -n "docker.sock" docker-compose.yml
    echo ""
    echo -e "${RED}El archivo docker-compose.yml todavía tiene problemas.${NC}"
    echo -e "${YELLOW}Backup disponible en: docker-compose.yml.backup${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Servicios iniciados${NC}"
echo ""

echo -e "${CYAN}Esperando 45 segundos a que los servicios arranquen...${NC}"
sleep 45

echo ""
echo -e "${GREEN}=== Estado Final ===${NC}"
docker compose ps
echo ""

# Verificar servicios críticos
STORAGE_OK=$(docker ps --filter "name=supabase-storage" --filter "status=running" -q)
FUNCTIONS_OK=$(docker ps --filter "name=supabase-edge-functions" --filter "status=running" -q)
STUDIO_OK=$(docker ps --filter "name=supabase-studio" --filter "status=running" -q)

echo -e "${CYAN}=== Resumen ===${NC}"
[ -n "$STORAGE_OK" ] && echo -e "${GREEN}✓ Storage corriendo${NC}" || echo -e "${RED}✗ Storage con problemas${NC}"
[ -n "$FUNCTIONS_OK" ] && echo -e "${GREEN}✓ Edge Functions corriendo${NC}" || echo -e "${RED}✗ Edge Functions con problemas${NC}"
[ -n "$STUDIO_OK" ] && echo -e "${GREEN}✓ Studio corriendo${NC}" || echo -e "${RED}✗ Studio con problemas${NC}"
echo ""

if [ -n "$STORAGE_OK" ] && [ -n "$STUDIO_OK" ]; then
    echo -e "${GREEN}✅ ¡Supabase está funcionando!${NC}"
    echo -e "${CYAN}Accedé a Studio desde tu navegador.${NC}"
else
    echo -e "${YELLOW}⚠ Algunos servicios tienen problemas. Verificá los logs:${NC}"
    echo -e "  ${CYAN}docker compose logs storage --tail=30${NC}"
    echo -e "  ${CYAN}docker compose logs functions --tail=30${NC}"
fi
echo ""
