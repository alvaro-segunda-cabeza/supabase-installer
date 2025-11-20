#!/bin/bash

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== Script de corrección de Supabase ===${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Por favor, ejecuta este script como root o con sudo.${NC}"
  exit 1
fi

cd /opt/supabase || exit 1

echo -e "${YELLOW}[1/5] Deteniendo contenedores...${NC}"
docker compose down > /dev/null 2>&1
echo -e "${GREEN}✓ Contenedores detenidos${NC}"
echo ""

echo -e "${YELLOW}[2/5] Agregando variables S3 faltantes al .env...${NC}"

# Verificar si las variables ya existen, si no, agregarlas
if ! grep -q "^REGION=" .env; then
    echo "REGION=us-east-1" >> .env
    echo -e "${GREEN}  + REGION agregada${NC}"
fi

if ! grep -q "^GLOBAL_S3_BUCKET=" .env; then
    echo "GLOBAL_S3_BUCKET=supabase-storage" >> .env
    echo -e "${GREEN}  + GLOBAL_S3_BUCKET agregada${NC}"
fi

if ! grep -q "^TENANT_ID=" .env; then
    echo "TENANT_ID=stub" >> .env
    echo -e "${GREEN}  + TENANT_ID agregada${NC}"
fi

if ! grep -q "^S3_PROTOCOL_PREFIX=" .env; then
    echo "S3_PROTOCOL_PREFIX=http" >> .env
    echo -e "${GREEN}  + S3_PROTOCOL_PREFIX agregada${NC}"
fi

if ! grep -q "^S3_PROTOCOL_ACCESS_KEY_ID=" .env; then
    echo "S3_PROTOCOL_ACCESS_KEY_ID=stub" >> .env
    echo -e "${GREEN}  + S3_PROTOCOL_ACCESS_KEY_ID agregada${NC}"
fi

if ! grep -q "^S3_PROTOCOL_ACCESS_KEY_SECRET=" .env; then
    echo "S3_PROTOCOL_ACCESS_KEY_SECRET=stub" >> .env
    echo -e "${GREEN}  + S3_PROTOCOL_ACCESS_KEY_SECRET agregada${NC}"
fi

echo -e "${GREEN}✓ Variables S3 configuradas${NC}"
echo ""

echo -e "${YELLOW}[3/5] Corrigiendo docker-compose.yml (problema del Docker socket)...${NC}"

# Buscar y corregir todas las ocurrencias del Docker socket duplicado
if grep -q "/var/run/docker.sock/var/run/docker.sock" docker-compose.yml; then
    sed -i 's|/var/run/docker.sock/var/run/docker.sock|/var/run/docker.sock|g' docker-compose.yml
    echo -e "${GREEN}  ✓ Corregido socket duplicado${NC}"
fi

# Corregir formato incorrecto del volumen
if grep -q ":\${DOCKER_SOCKET_LOCATION" docker-compose.yml; then
    sed -i 's|:\${DOCKER_SOCKET_LOCATION[^}]*}:/var/run/docker.sock:ro,z|/var/run/docker.sock:/var/run/docker.sock:ro|g' docker-compose.yml
    echo -e "${GREEN}  ✓ Corregido formato de variable DOCKER_SOCKET_LOCATION${NC}"
fi

# Buscar líneas que empiecen con ":" en volumes (error común)
if grep -q "^[[:space:]]*- :/var/run/docker.sock" docker-compose.yml; then
    sed -i 's|^[[:space:]]*- :/var/run/docker.sock.*|      - /var/run/docker.sock:/var/run/docker.sock:ro|g' docker-compose.yml
    echo -e "${GREEN}  ✓ Corregido volumen con ':' al inicio${NC}"
fi

echo -e "${GREEN}✓ docker-compose.yml corregido${NC}"
echo ""

echo -e "${YELLOW}[4/5] Verificando corrección del Docker socket...${NC}"
SOCKET_ERRORS=$(grep -n "/var/run/docker.sock" docker-compose.yml | grep -E ":/var/run|/var/run.*:" | wc -l)
if [ "$SOCKET_ERRORS" -eq 0 ]; then
    echo -e "${GREEN}✓ No se encontraron más problemas con el socket${NC}"
else
    echo -e "${YELLOW}⚠ Se encontraron $SOCKET_ERRORS posibles problemas. Mostrando líneas:${NC}"
    grep -n "/var/run/docker.sock" docker-compose.yml | grep -E ":/var/run|/var/run.*:"
fi
echo ""

echo -e "${YELLOW}[5/5] Iniciando servicios...${NC}"
docker compose up -d
echo -e "${GREEN}✓ Servicios iniciados${NC}"
echo ""

echo -e "${CYAN}Esperando 45 segundos a que los servicios arranquen completamente...${NC}"
sleep 45

echo ""
echo -e "${GREEN}=== Estado de los contenedores ===${NC}"
docker compose ps
echo ""

echo -e "${CYAN}=== Verificando servicios críticos ===${NC}"
echo ""

# Verificar Storage
STORAGE_STATUS=$(docker ps --filter "name=supabase-storage" --format "{{.Status}}")
if echo "$STORAGE_STATUS" | grep -q "Up"; then
    echo -e "${GREEN}✓ Storage está corriendo${NC}"
else
    echo -e "${RED}✗ Storage tiene problemas:${NC}"
    docker compose logs storage --tail=20
fi

# Verificar Edge Functions
FUNCTIONS_STATUS=$(docker ps --filter "name=supabase-edge-functions" --format "{{.Status}}")
if echo "$FUNCTIONS_STATUS" | grep -q "Up"; then
    echo -e "${GREEN}✓ Edge Functions está corriendo${NC}"
else
    echo -e "${RED}✗ Edge Functions tiene problemas${NC}"
fi

echo ""
echo -e "${CYAN}=== Resumen ===${NC}"
echo ""

STORAGE_OK=$(docker ps --filter "name=supabase-storage" --filter "status=running" --format "{{.Names}}" 2>/dev/null)
FUNCTIONS_OK=$(docker ps --filter "name=supabase-edge-functions" --filter "status=running" --format "{{.Names}}" 2>/dev/null)

if [ -n "$STORAGE_OK" ] && [ -n "$FUNCTIONS_OK" ]; then
    echo -e "${GREEN}✅ ¡Supabase corregido exitosamente!${NC}"
    echo -e "${GREEN}✓ Storage funcionando${NC}"
    echo -e "${GREEN}✓ Edge Functions funcionando${NC}"
    echo ""
    echo -e "${CYAN}Ahora podés acceder a Studio sin errores.${NC}"
else
    echo -e "${YELLOW}⚠ Algunos servicios todavía tienen problemas:${NC}"
    [ -z "$STORAGE_OK" ] && echo -e "  ${RED}✗ Storage${NC}"
    [ -z "$FUNCTIONS_OK" ] && echo -e "  ${RED}✗ Edge Functions${NC}"
    echo ""
    echo -e "${YELLOW}Ejecutá este comando para más detalles:${NC}"
    echo -e "  ${CYAN}cd /opt/supabase && docker compose logs storage functions --tail=50${NC}"
fi
echo ""
