#!/bin/bash

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== Fix definitivo del Docker socket ===${NC}"
echo ""

cd /opt/supabase || exit 1

# Detener todo
echo -e "${CYAN}Deteniendo contenedores...${NC}"
docker compose down -v > /dev/null 2>&1

# Corrección EXACTA de la línea 440
echo -e "${CYAN}Corrigiendo línea 440 del docker-compose.yml...${NC}"
sed -i '440s|/var/run/docker.sock/var/run/docker.sock:/var/run/docker.sock:ro|/var/run/docker.sock:/var/run/docker.sock:ro|g' docker-compose.yml

# Verificar que se corrigió
if grep -q "/var/run/docker.sock/var/run/docker.sock" docker-compose.yml; then
    echo -e "${RED}✗ La corrección falló. Intentando método alternativo...${NC}"
    # Método más agresivo: reemplazar TODAS las ocurrencias
    sed -i 's|/var/run/docker\.sock/var/run/docker\.sock|/var/run/docker.sock|g' docker-compose.yml
fi

# Verificar nuevamente
if grep -q "/var/run/docker.sock/var/run/docker.sock" docker-compose.yml; then
    echo -e "${RED}✗ Todavía hay problemas. Mostrando la línea:${NC}"
    grep -n "/var/run/docker.sock/var/run/docker.sock" docker-compose.yml
    exit 1
else
    echo -e "${GREEN}✓ Socket corregido correctamente${NC}"
fi

echo ""
echo -e "${CYAN}Iniciando servicios...${NC}"
docker compose up -d

echo ""
echo -e "${CYAN}Esperando 30 segundos...${NC}"
sleep 30

echo ""
docker compose ps
echo ""
echo -e "${GREEN}✅ Listo. Verificá que todos los contenedores estén 'Up'${NC}"
