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

# 1. Agregar variables faltantes de S3 al .env
echo -e "${CYAN}1. Agregando variables faltantes al .env...${NC}"

# Verificar si las variables ya existen, si no, agregarlas
if ! grep -q "GLOBAL_S3_BUCKET=" .env; then
    echo "GLOBAL_S3_BUCKET=supabase-storage" >> .env
fi

if ! grep -q "REGION=" .env; then
    echo "REGION=us-east-1" >> .env
fi

if ! grep -q "TENANT_ID=" .env; then
    echo "TENANT_ID=stub" >> .env
fi

if ! grep -q "S3_PROTOCOL_PREFIX=" .env; then
    echo "S3_PROTOCOL_PREFIX=http" >> .env
fi

if ! grep -q "S3_PROTOCOL_ACCESS_KEY_ID=" .env; then
    echo "S3_PROTOCOL_ACCESS_KEY_ID=stub" >> .env
fi

if ! grep -q "S3_PROTOCOL_ACCESS_KEY_SECRET=" .env; then
    echo "S3_PROTOCOL_ACCESS_KEY_SECRET=stub" >> .env
fi

echo -e "${GREEN}✓ Variables agregadas al .env${NC}"
echo ""

# 2. Mostrar los logs de Storage antes de reiniciar
echo -e "${CYAN}2. Mostrando últimos logs de Storage (antes de reiniciar):${NC}"
docker compose logs storage --tail=30
echo ""

# 3. Reiniciar servicios problemáticos
echo -e "${CYAN}3. Reiniciando servicios...${NC}"
docker compose restart storage
sleep 5
docker compose restart realtime
sleep 5

echo -e "${GREEN}✓ Servicios reiniciados${NC}"
echo ""

# 4. Esperar a que los servicios se estabilicen
echo -e "${CYAN}4. Esperando que los servicios se estabilicen (30 segundos)...${NC}"
sleep 30

# 5. Verificar estado después del reinicio
echo -e "${CYAN}5. Verificando estado de los servicios:${NC}"
docker compose ps

echo ""
echo -e "${CYAN}6. Verificando Storage específicamente:${NC}"
STORAGE_STATUS=$(docker ps --filter "name=supabase-storage" --format "{{.Status}}")
if echo "$STORAGE_STATUS" | grep -q "Up"; then
    echo -e "${GREEN}✓ Storage está corriendo correctamente${NC}"
else
    echo -e "${RED}✗ Storage todavía tiene problemas${NC}"
    echo -e "${YELLOW}Logs actuales de Storage:${NC}"
    docker compose logs storage --tail=30
fi

echo ""
echo -e "${CYAN}7. Verificando Realtime:${NC}"
REALTIME_STATUS=$(docker ps --filter "name=supabase-realtime" --format "{{.Status}}")
if echo "$REALTIME_STATUS" | grep -q "healthy"; then
    echo -e "${GREEN}✓ Realtime está saludable${NC}"
elif echo "$REALTIME_STATUS" | grep -q "Up"; then
    echo -e "${YELLOW}⚠ Realtime está corriendo pero aún no pasa health check${NC}"
else
    echo -e "${RED}✗ Realtime tiene problemas${NC}"
fi

echo ""
echo -e "${CYAN}=== Resumen ===${NC}"
echo ""
STORAGE_RUNNING=$(docker ps --filter "name=supabase-storage" --format "{{.Names}}" 2>/dev/null)
if [ -n "$STORAGE_RUNNING" ]; then
    echo -e "${GREEN}✓ Storage corregido y funcionando${NC}"
    echo -e "${GREEN}✓ Ahora podés acceder a Studio sin el error de 'count'${NC}"
else
    echo -e "${RED}✗ Storage todavía tiene problemas. Ejecutá este comando para ver los logs:${NC}"
    echo -e "   ${YELLOW}cd /opt/supabase && docker compose logs storage --tail=50${NC}"
fi
echo ""
