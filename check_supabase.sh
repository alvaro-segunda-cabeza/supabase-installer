#!/bin/bash

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== Diagnóstico de Supabase ===${NC}"
echo ""

cd /opt/supabase || exit 1

# 1. Verificar que los contenedores estén corriendo
echo -e "${CYAN}1. Estado de contenedores:${NC}"
docker compose ps
echo ""

# 2. Verificar contenedores críticos
echo -e "${CYAN}2. Verificando servicios críticos:${NC}"
CRITICAL_SERVICES=("supabase-db" "supabase-studio" "supabase-kong" "supabase-nginx" "supabase-auth" "supabase-rest" "supabase-meta")

for service in "${CRITICAL_SERVICES[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
        echo -e "  ✓ ${GREEN}${service} está corriendo${NC}"
    else
        echo -e "  ✗ ${RED}${service} NO está corriendo${NC}"
    fi
done
echo ""

# 3. Verificar conectividad de la base de datos
echo -e "${CYAN}3. Verificando conectividad de la base de datos:${NC}"
DB_CHECK=$(docker compose exec -T db pg_isready -U postgres 2>&1)
if echo "$DB_CHECK" | grep -q "accepting connections"; then
    echo -e "  ✓ ${GREEN}Base de datos aceptando conexiones${NC}"
else
    echo -e "  ✗ ${RED}Base de datos no responde${NC}"
    echo "  $DB_CHECK"
fi
echo ""

# 4. Verificar API REST (PostgREST)
echo -e "${CYAN}4. Verificando API REST (PostgREST):${NC}"
REST_CHECK=$(docker compose exec -T rest curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>&1)
if [ "$REST_CHECK" = "200" ] || [ "$REST_CHECK" = "404" ]; then
    echo -e "  ✓ ${GREEN}PostgREST respondiendo (HTTP $REST_CHECK)${NC}"
else
    echo -e "  ✗ ${RED}PostgREST no responde correctamente${NC}"
fi
echo ""

# 5. Verificar Kong Gateway
echo -e "${CYAN}5. Verificando Kong Gateway:${NC}"
KONG_CHECK=$(docker compose exec -T kong curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/ 2>&1)
if [ "$KONG_CHECK" = "200" ] || [ "$KONG_CHECK" = "404" ]; then
    echo -e "  ✓ ${GREEN}Kong respondiendo (HTTP $KONG_CHECK)${NC}"
else
    echo -e "  ✗ ${RED}Kong no responde correctamente${NC}"
fi
echo ""

# 6. Verificar Auth (GoTrue)
echo -e "${CYAN}6. Verificando Auth (GoTrue):${NC}"
AUTH_CHECK=$(docker compose exec -T auth curl -s -o /dev/null -w "%{http_code}" http://localhost:9999/health 2>&1)
if [ "$AUTH_CHECK" = "200" ]; then
    echo -e "  ✓ ${GREEN}Auth service respondiendo (HTTP $AUTH_CHECK)${NC}"
else
    echo -e "  ✗ ${RED}Auth service no responde correctamente${NC}"
fi
echo ""

# 7. Verificar Meta API
echo -e "${CYAN}7. Verificando Meta API (Postgres Meta):${NC}"
META_CHECK=$(docker compose exec -T meta curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health 2>&1)
if [ "$META_CHECK" = "200" ]; then
    echo -e "  ✓ ${GREEN}Meta API respondiendo (HTTP $META_CHECK)${NC}"
else
    echo -e "  ✗ ${RED}Meta API no responde correctamente${NC}"
    echo -e "  ${YELLOW}Logs de Meta:${NC}"
    docker compose logs meta --tail=20
fi
echo ""

# 8. Verificar Studio
echo -e "${CYAN}8. Verificando Studio:${NC}"
STUDIO_CHECK=$(docker compose exec -T studio curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/platform/profile 2>&1)
if [ "$STUDIO_CHECK" = "200" ] || [ "$STUDIO_CHECK" = "401" ]; then
    echo -e "  ✓ ${GREEN}Studio respondiendo (HTTP $STUDIO_CHECK)${NC}"
else
    echo -e "  ✗ ${RED}Studio no responde correctamente (HTTP $STUDIO_CHECK)${NC}"
    echo -e "  ${YELLOW}Logs de Studio:${NC}"
    docker compose logs studio --tail=20
fi
echo ""

# 9. Verificar variables de entorno críticas
echo -e "${CYAN}9. Verificando variables de entorno:${NC}"
if [ -f ".env" ]; then
    REQUIRED_VARS=("POSTGRES_PASSWORD" "JWT_SECRET" "ANON_KEY" "SERVICE_ROLE_KEY" "POSTGRES_HOST" "POSTGRES_DB")
    for var in "${REQUIRED_VARS[@]}"; do
        if grep -q "^${var}=" .env && ! grep -q "^${var}=$" .env; then
            echo -e "  ✓ ${GREEN}${var} configurado${NC}"
        else
            echo -e "  ✗ ${RED}${var} falta o está vacío${NC}"
        fi
    done
else
    echo -e "  ✗ ${RED}Archivo .env no encontrado${NC}"
fi
echo ""

# 10. Verificar logs de errores recientes
echo -e "${CYAN}10. Últimos errores en los logs:${NC}"
ERROR_COUNT=$(docker compose logs --tail=100 2>&1 | grep -i "error" | wc -l)
if [ "$ERROR_COUNT" -gt 0 ]; then
    echo -e "  ${YELLOW}Se encontraron $ERROR_COUNT líneas con 'error' en los logs recientes${NC}"
    echo -e "  ${YELLOW}Mostrando los últimos 10 errores:${NC}"
    docker compose logs --tail=200 2>&1 | grep -i "error" | tail -10
else
    echo -e "  ✓ ${GREEN}No se encontraron errores recientes${NC}"
fi
echo ""

# 11. Test de conexión desde Studio a Meta API
echo -e "${CYAN}11. Test de conexión Studio -> Meta API:${NC}"
STUDIO_META_TEST=$(docker compose exec -T studio curl -s -o /dev/null -w "%{http_code}" http://meta:8080/health 2>&1)
if [ "$STUDIO_META_TEST" = "200" ]; then
    echo -e "  ✓ ${GREEN}Studio puede conectar con Meta API${NC}"
else
    echo -e "  ✗ ${RED}Studio NO puede conectar con Meta API (HTTP $STUDIO_META_TEST)${NC}"
fi
echo ""

# 12. Verificar red de Docker
echo -e "${CYAN}12. Verificando red de Docker:${NC}"
NETWORK_NAME=$(docker compose config | grep -A 5 "networks:" | grep "name:" | awk '{print $2}' | head -1)
if [ -z "$NETWORK_NAME" ]; then
    NETWORK_NAME="supabase_default"
fi
if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo -e "  ✓ ${GREEN}Red Docker '$NETWORK_NAME' existe${NC}"
    CONTAINER_COUNT=$(docker network inspect "$NETWORK_NAME" | grep -c "Name")
    echo -e "  ${CYAN}Contenedores en la red: $CONTAINER_COUNT${NC}"
else
    echo -e "  ✗ ${RED}Red Docker no encontrada${NC}"
fi
echo ""

echo -e "${CYAN}=== Fin del diagnóstico ===${NC}"
echo ""
echo -e "${YELLOW}Comandos útiles:${NC}"
echo -e "  Ver logs de un servicio: ${GREEN}cd /opt/supabase && docker compose logs -f [servicio]${NC}"
echo -e "  Reiniciar todo:          ${GREEN}cd /opt/supabase && docker compose restart${NC}"
echo -e "  Ver estado completo:     ${GREEN}cd /opt/supabase && docker compose ps -a${NC}"
echo ""
