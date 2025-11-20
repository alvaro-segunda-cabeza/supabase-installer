#!/bin/bash

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=== Diagnóstico de Supabase ===${NC}"
echo ""

# 1. Verificar si Docker está instalado y corriendo
echo -e "${YELLOW}[1/8] Verificando Docker...${NC}"
if command -v docker &> /dev/null; then
    if systemctl is-active --quiet docker; then
        echo -e "${GREEN}✓ Docker está instalado y corriendo${NC}"
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
echo -e "${YELLOW}[2/8] Verificando instalación de Supabase...${NC}"
if [ -d "/opt/supabase" ]; then
    echo -e "${GREEN}✓ Directorio /opt/supabase existe${NC}"
    cd /opt/supabase
else
    echo -e "${RED}✗ Supabase no está instalado en /opt/supabase${NC}"
    exit 1
fi
echo ""

# 3. Verificar archivos importantes
echo -e "${YELLOW}[3/8] Verificando archivos de configuración...${NC}"
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
else
    echo -e "${RED}✗ docker-compose.override.yml no encontrado${NC}"
fi
echo ""

# 4. Verificar contenedores corriendo
echo -e "${YELLOW}[4/8] Verificando contenedores Docker...${NC}"
CONTAINERS=$(docker compose ps --format "table {{.Service}}\t{{.Status}}" 2>/dev/null)
if [ -n "$CONTAINERS" ]; then
    echo "$CONTAINERS"
else
    echo -e "${RED}✗ No hay contenedores corriendo${NC}"
    echo "  Intenta: cd /opt/supabase && docker compose up -d"
fi
echo ""

# 5. Verificar puertos
echo -e "${YELLOW}[5/8] Verificando puertos...${NC}"
if netstat -tuln 2>/dev/null | grep -q ":80 "; then
    echo -e "${GREEN}✓ Puerto 80 (HTTP) está abierto${NC}"
else
    echo -e "${RED}✗ Puerto 80 (HTTP) no está escuchando${NC}"
fi

if netstat -tuln 2>/dev/null | grep -q ":443 "; then
    echo -e "${GREEN}✓ Puerto 443 (HTTPS) está abierto${NC}"
else
    echo -e "${RED}✗ Puerto 443 (HTTPS) no está escuchando${NC}"
fi
echo ""

# 6. Verificar Traefik específicamente
echo -e "${YELLOW}[6/8] Verificando Traefik...${NC}"
if docker ps | grep -q traefik; then
    echo -e "${GREEN}✓ Contenedor Traefik está corriendo${NC}"
    
    # Ver logs recientes de Traefik
    echo -e "${CYAN}Últimas líneas de logs de Traefik:${NC}"
    docker compose logs --tail=10 traefik 2>/dev/null
else
    echo -e "${RED}✗ Contenedor Traefik no está corriendo${NC}"
fi
echo ""

# 7. Verificar certificados SSL
echo -e "${YELLOW}[7/8] Verificando certificados SSL...${NC}"
if [ -f "letsencrypt/acme.json" ]; then
    SIZE=$(stat -f%z "letsencrypt/acme.json" 2>/dev/null || stat -c%s "letsencrypt/acme.json" 2>/dev/null)
    if [ "$SIZE" -gt 100 ]; then
        echo -e "${GREEN}✓ Certificados SSL generados (acme.json tiene ${SIZE} bytes)${NC}"
    else
        echo -e "${YELLOW}⚠ acme.json existe pero está vacío o pequeño${NC}"
        echo -e "${YELLOW}  Los certificados pueden estar generándose todavía${NC}"
    fi
    
    # Mostrar permisos
    PERMS=$(stat -f%Lp "letsencrypt/acme.json" 2>/dev/null || stat -c%a "letsencrypt/acme.json" 2>/dev/null)
    if [ "$PERMS" = "600" ]; then
        echo -e "${GREEN}✓ Permisos correctos (600)${NC}"
    else
        echo -e "${RED}✗ Permisos incorrectos ($PERMS), deberían ser 600${NC}"
    fi
else
    echo -e "${RED}✗ No se encontró letsencrypt/acme.json${NC}"
fi
echo ""

# 8. Mostrar credenciales
echo -e "${YELLOW}[8/8] Credenciales guardadas...${NC}"
if [ -f "/root/supabase_credentials.txt" ]; then
    echo -e "${GREEN}✓ Credenciales encontradas en /root/supabase_credentials.txt${NC}"
    echo ""
    cat /root/supabase_credentials.txt
else
    echo -e "${RED}✗ No se encontró el archivo de credenciales${NC}"
fi
echo ""

# Resumen y recomendaciones
echo -e "${CYAN}=== Resumen ===${NC}"
echo ""

# Verificar si todo está OK
ALL_OK=true

if ! docker ps | grep -q traefik; then
    ALL_OK=false
    echo -e "${RED}✗ Traefik no está corriendo${NC}"
fi

if ! docker ps | grep -q "supabase-db"; then
    ALL_OK=false
    echo -e "${RED}✗ Base de datos no está corriendo${NC}"
fi

if ! docker ps | grep -q studio; then
    ALL_OK=false
    echo -e "${RED}✗ Studio no está corriendo${NC}"
fi

if [ "$ALL_OK" = true ]; then
    echo -e "${GREEN}✓ Todos los servicios principales están corriendo${NC}"
    echo ""
    echo -e "${CYAN}Accede a tu instalación:${NC}"
    if [ -f "/root/supabase_credentials.txt" ]; then
        DOMAIN=$(grep "Dominio:" /root/supabase_credentials.txt | cut -d' ' -f2)
        echo -e "  Dashboard: ${GREEN}https://studio.$DOMAIN${NC}"
        echo -e "  API: ${GREEN}https://api.$DOMAIN${NC}"
    fi
    echo ""
    echo -e "${YELLOW}Si ves 404 o error SSL, verifica:${NC}"
    echo -e "  1. Los registros DNS en Cloudflare están creados"
    echo -e "  2. Esperá 2-3 minutos para que SSL se genere"
    echo -e "  3. El modo SSL en Cloudflare está en 'Full'"
else
    echo -e "${RED}✗ Algunos servicios no están corriendo${NC}"
    echo ""
    echo -e "${YELLOW}Intenta reiniciar los servicios:${NC}"
    echo -e "  ${GREEN}cd /opt/supabase && docker compose down${NC}"
    echo -e "  ${GREEN}cd /opt/supabase && docker compose up -d${NC}"
    echo ""
    echo -e "${YELLOW}Para ver logs en tiempo real:${NC}"
    echo -e "  ${GREEN}cd /opt/supabase && docker compose logs -f${NC}"
fi
echo ""
