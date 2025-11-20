#!/bin/bash

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=== Diagnóstico Completo de Supabase ===${NC}"
echo ""

# 1. Verificar si Docker está instalado y corriendo
echo -e "${YELLOW}[1/10] Verificando Docker...${NC}"
if command -v docker &> /dev/null; then
    if systemctl is-active --quiet docker; then
        echo -e "${GREEN}✓ Docker está instalado y corriendo${NC}"
        DOCKER_VERSION=$(docker --version)
        echo -e "  Versión: ${CYAN}$DOCKER_VERSION${NC}"
    else
        echo -e "${RED}✗ Docker está instalado pero no está corriendo${NC}"
        echo "  Intenta: systemctl start docker"
    fi
else
    echo -e "${RED}✗ Docker no está instalado${NC}"
    exit 1
fi
echo ""

# 2. Verificar si existe el directorio de Supabase
echo -e "${YELLOW}[2/10] Verificando instalación de Supabase...${NC}"
if [ -d "/opt/supabase" ]; then
    echo -e "${GREEN}✓ Directorio /opt/supabase existe${NC}"
    cd /opt/supabase
else
    echo -e "${RED}✗ Supabase no está instalado en /opt/supabase${NC}"
    exit 1
fi
echo ""

# 3. Verificar archivos importantes
echo -e "${YELLOW}[3/10] Verificando archivos de configuración...${NC}"
if [ -f "docker-compose.yml" ]; then
    echo -e "${GREEN}✓ docker-compose.yml existe${NC}"
else
    echo -e "${RED}✗ docker-compose.yml no encontrado${NC}"
fi

if [ -f ".env" ]; then
    echo -e "${GREEN}✓ .env existe${NC}"
else
    echo -e "${RED}✗ .env no encontrado${NC}"
fi

if [ -f "docker-compose.override.yml" ]; then
    echo -e "${GREEN}✓ docker-compose.override.yml existe (Traefik configurado)${NC}"
    # Verificar si el archivo es válido
    if docker compose config > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Configuración de Docker Compose es válida${NC}"
    else
        echo -e "${RED}✗ Error en la configuración de Docker Compose${NC}"
        docker compose config 2>&1 | head -5
    fi
else
    echo -e "${RED}✗ docker-compose.override.yml no encontrado${NC}"
fi
echo ""

# 4. Verificar contenedores corriendo
echo -e "${YELLOW}[4/10] Verificando contenedores Docker...${NC}"
CONTAINERS=$(docker compose ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null)
if [ -n "$CONTAINERS" ]; then
    echo "$CONTAINERS"
    echo ""
    
    # Contar contenedores UP
    UP_COUNT=$(docker compose ps | grep -c "Up" || echo "0")
    TOTAL_COUNT=$(docker compose ps -a | tail -n +2 | wc -l)
    echo -e "Contenedores activos: ${GREEN}$UP_COUNT${NC} de $TOTAL_COUNT"
else
    echo -e "${RED}✗ No hay contenedores corriendo${NC}"
    echo "  Intenta: cd /opt/supabase && docker compose up -d"
fi
echo ""

# 5. Verificar puertos
echo -e "${YELLOW}[5/10] Verificando puertos...${NC}"
if ss -tuln 2>/dev/null | grep -q ":80 " || netstat -tuln 2>/dev/null | grep -q ":80 "; then
    echo -e "${GREEN}✓ Puerto 80 (HTTP) está abierto${NC}"
    PORT_80_PROCESS=$(ss -tlnp 2>/dev/null | grep ":80 " | awk '{print $6}' | head -1)
    echo -e "  Proceso: ${CYAN}$PORT_80_PROCESS${NC}"
else
    echo -e "${RED}✗ Puerto 80 (HTTP) no está escuchando${NC}"
fi

if ss -tuln 2>/dev/null | grep -q ":443 " || netstat -tuln 2>/dev/null | grep -q ":443 "; then
    echo -e "${GREEN}✓ Puerto 443 (HTTPS) está abierto${NC}"
    PORT_443_PROCESS=$(ss -tlnp 2>/dev/null | grep ":443 " | awk '{print $6}' | head -1)
    echo -e "  Proceso: ${CYAN}$PORT_443_PROCESS${NC}"
else
    echo -e "${RED}✗ Puerto 443 (HTTPS) no está escuchando${NC}"
fi
echo ""

# 6. Verificar IP del servidor
echo -e "${YELLOW}[6/10] Información del servidor...${NC}"
SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "No se pudo obtener")
echo -e "IP Pública del servidor: ${GREEN}$SERVER_IP${NC}"
echo ""

# 7. Verificar Traefik específicamente
echo -e "${YELLOW}[7/10] Verificando Traefik...${NC}"
if docker ps | grep -q traefik; then
    echo -e "${GREEN}✓ Contenedor Traefik está corriendo${NC}"
    
    # Verificar dashboard de Traefik
    if curl -s http://localhost:8080/api/overview > /dev/null 2>&1; then
        echo -e "${GREEN}✓ API de Traefik responde${NC}"
    else
        echo -e "${YELLOW}⚠ API de Traefik no responde${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Últimas 15 líneas de logs de Traefik:${NC}"
    docker compose logs --tail=15 traefik 2>/dev/null
else
    echo -e "${RED}✗ Contenedor Traefik no está corriendo${NC}"
fi
echo ""

# 8. Verificar certificados SSL
echo -e "${YELLOW}[8/10] Verificando certificados SSL...${NC}"
if [ -f "letsencrypt/acme.json" ]; then
    SIZE=$(stat -f%z "letsencrypt/acme.json" 2>/dev/null || stat -c%s "letsencrypt/acme.json" 2>/dev/null)
    if [ "$SIZE" -gt 100 ]; then
        echo -e "${GREEN}✓ Certificados SSL generados (${SIZE} bytes)${NC}"
        
        # Intentar ver qué dominios tienen certificados
        if command -v jq &> /dev/null; then
            DOMAINS=$(jq -r '.letsencrypt.Certificates[].domain.main' letsencrypt/acme.json 2>/dev/null)
            if [ -n "$DOMAINS" ]; then
                echo -e "${CYAN}Dominios con certificado:${NC}"
                echo "$DOMAINS" | while read domain; do
                    echo -e "  - ${GREEN}$domain${NC}"
                done
            fi
        fi
    else
        echo -e "${YELLOW}⚠ acme.json existe pero está vacío (${SIZE} bytes)${NC}"
        echo -e "${YELLOW}  Los certificados pueden estar generándose todavía${NC}"
        echo -e "${YELLOW}  Esto puede tomar 2-3 minutos después de iniciar${NC}"
    fi
else
    echo -e "${RED}✗ No se encontró letsencrypt/acme.json${NC}"
fi
echo ""

# 9. Probar acceso local a los servicios
echo -e "${YELLOW}[9/10] Probando acceso local a los servicios...${NC}"

# Probar Studio
if curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null | grep -q "200\|301\|302"; then
    echo -e "${GREEN}✓ Studio responde en puerto 3000${NC}"
else
    echo -e "${RED}✗ Studio no responde en puerto 3000${NC}"
fi

# Probar Kong (API Gateway)
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/health 2>/dev/null | grep -q "200\|404"; then
    echo -e "${GREEN}✓ Kong responde en puerto 8000${NC}"
else
    echo -e "${RED}✗ Kong no responde en puerto 8000${NC}"
fi

# Probar Traefik
if curl -s -o /dev/null -w "%{http_code}" http://localhost 2>/dev/null | grep -q "200\|301\|302\|404"; then
    echo -e "${GREEN}✓ Traefik responde en puerto 80${NC}"
else
    echo -e "${RED}✗ Traefik no responde en puerto 80${NC}"
fi
echo ""

# 10. Mostrar credenciales y URLs
echo -e "${YELLOW}[10/10] Credenciales y acceso...${NC}"
if [ -f "/root/supabase_credentials.txt" ]; then
    echo -e "${GREEN}✓ Credenciales encontradas${NC}"
    echo ""
    cat /root/supabase_credentials.txt
    echo ""
    
    # Extraer dominio
    DOMAIN=$(grep "Dominio:" /root/supabase_credentials.txt | awk '{print $2}')
    if [ -n "$DOMAIN" ]; then
        echo -e "${CYAN}=== Formas de acceder ===${NC}"
        echo ""
        echo -e "${YELLOW}1. Por dominio (requiere DNS configurado):${NC}"
        echo -e "   Studio: ${GREEN}https://studio.$DOMAIN${NC}"
        echo -e "   API:    ${GREEN}https://api.$DOMAIN${NC}"
        echo ""
        echo -e "${YELLOW}2. Por IP directamente (sin SSL):${NC}"
        echo -e "   Studio: ${GREEN}http://$SERVER_IP:3000${NC}"
        echo -e "   API:    ${GREEN}http://$SERVER_IP:8000${NC}"
        echo ""
        echo -e "${YELLOW}3. Via Traefik (requiere configurar /etc/hosts):${NC}"
        echo -e "   Agregá a tu /etc/hosts local:"
        echo -e "   ${CYAN}$SERVER_IP  studio.$DOMAIN api.$DOMAIN${NC}"
        echo -e "   Luego accedé a: ${GREEN}http://studio.$DOMAIN${NC}"
    fi
else
    echo -e "${RED}✗ No se encontró el archivo de credenciales${NC}"
fi
echo ""

# Resumen final
echo -e "${CYAN}=== Diagnóstico completado ===${NC}"
echo ""

# Verificar si todo está OK
TRAEFIK_OK=$(docker ps | grep -c "traefik" || echo "0")
DB_OK=$(docker ps | grep -c "supabase-db" || echo "0")
STUDIO_OK=$(docker ps | grep -c "supabase-studio" || echo "0")
KONG_OK=$(docker ps | grep -c "supabase-kong" || echo "0")

if [ "$TRAEFIK_OK" -gt 0 ] && [ "$DB_OK" -gt 0 ] && [ "$STUDIO_OK" -gt 0 ] && [ "$KONG_OK" -gt 0 ]; then
    echo -e "${GREEN}✓ Todos los servicios principales están corriendo${NC}"
    echo ""
    echo -e "${YELLOW}Si ves error 404 en el dominio, verifica:${NC}"
    echo -e "  1. ${CYAN}DNS en Cloudflare:${NC} Los registros A para studio.$DOMAIN y api.$DOMAIN deben apuntar a ${GREEN}$SERVER_IP${NC}"
    echo -e "  2. ${CYAN}Esperá 2-3 minutos:${NC} Let's Encrypt necesita tiempo para generar certificados"
    echo -e "  3. ${CYAN}Logs de Traefik:${NC} cd /opt/supabase && docker compose logs traefik -f"
    echo -e "  4. ${CYAN}Modo SSL Cloudflare:${NC} Debe estar en 'Full' no en 'Flexible'"
else
    echo -e "${RED}✗ Algunos servicios no están corriendo correctamente${NC}"
    echo ""
    echo -e "${YELLOW}Comandos útiles:${NC}"
    echo -e "  Reiniciar todo:   ${GREEN}cd /opt/supabase && docker compose restart${NC}"
    echo -e "  Ver logs:         ${GREEN}cd /opt/supabase && docker compose logs -f${NC}"
    echo -e "  Ver solo errores: ${GREEN}cd /opt/supabase && docker compose logs | grep -i error${NC}"
fi
echo ""
