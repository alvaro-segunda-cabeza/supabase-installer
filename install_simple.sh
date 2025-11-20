#!/bin/bash
set -e

echo "=== Instalando Supabase ==="

# Ir a directorio seguro
cd /root

# Instalar dependencias
apt-get update -qq && apt-get install -y -qq docker.io docker-compose git

# Limpiar instalación previa
docker ps -aq | xargs -r docker rm -f
rm -rf /opt/supabase

# Clonar Supabase
git clone --depth 1 https://github.com/supabase/supabase /opt/supabase
cd /opt/supabase/docker

# Copiar configuración
cp .env.example .env

# Iniciar servicios
docker-compose up -d

echo ""
echo "✅ Instalado!"
echo "Studio: http://$(curl -s ifconfig.me):3000"
echo "API: http://$(curl -s ifconfig.me):8000"
