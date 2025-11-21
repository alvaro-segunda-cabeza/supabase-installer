#!/bin/bash

INSTALL_DIR="/opt/supabase"
cd $INSTALL_DIR

echo "========================================"
echo " DIAGNÓSTICO DE SUPABASE"
echo "========================================"

# 1. Ver estado de los contenedores
echo -e "\n1. ESTADO DE CONTENEDORES:"
docker compose ps -a --format "table {{.Name}}\t{{.State}}\t{{.Status}}"

# 2. Ver si Traefik detecta los servicios
echo -e "\n2. CHEQUEO RÁPIDO DE PUERTOS:"
if nc -z localhost 443; then
    echo "✅ Puerto 443 (HTTPS) está abierto."
else
    echo "❌ Puerto 443 está CERRADO. Traefik no está corriendo bien."
fi

# 3. Revisar errores en la Base de Datos (Causa #1 de fallos)
echo -e "\n3. LOGS RECIENTES DE LA BASE DE DATOS:"
docker logs supabase-db --tail 10

# 4. Revisar logs de Traefik (Por qué da 404)
echo -e "\n4. LOGS RECIENTES DE TRAEFIK (ROUTING):"
docker logs supabase-traefik --tail 10

echo -e "\n========================================"
