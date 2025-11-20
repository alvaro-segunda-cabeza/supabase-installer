#!/bin/bash

# Script de limpieza para Supabase
# Úsalo si la instalación se quedó trabada

echo "Limpiando instalación de Supabase..."

# Forzar detención de contenedores
docker ps -a | grep -E "supabase|traefik|kong" | awk '{print $1}' | xargs -r docker rm -f 2>/dev/null || true

# Eliminar directorio
rm -rf /opt/supabase

# Limpiar imágenes viejas
docker image prune -af

echo "✓ Limpieza completada. Ahora puedes ejecutar el instalador de nuevo."
