#!/bin/bash
set -euo pipefail

###
# Instalador automatizado de Supabase + Traefik (Ubuntu/Debian)
# Modo: Express (todo automático) o Guiado (máx 3 preguntas)
###

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "[ERROR] Este script debe ejecutarse como root (o con sudo)." >&2
  exit 1
fi

OS_ID="$(. /etc/os-release && echo "$ID")"
if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
  echo "[ERROR] Este instalador está pensado para Ubuntu/Debian. OS detectado: $OS_ID" >&2
  exit 1
fi

clear || true
echo "=== Instalador Supabase + Traefik ==="
echo ""
echo "Elige el modo de instalación:"
echo "  1) Express  - todo automático con valores por defecto"
echo "  2) Guiado   - te preguntaré solo 3 cosas"
echo ""
read -rp "Opción [1/2]: " INSTALL_MODE

case "${INSTALL_MODE:-1}" in
  1|"" )
    MODE="express"
    ;;
  2)
    MODE="guiado"
    ;;
  *)
    echo "Opción no válida, usando modo Express por defecto."
    MODE="express"
    ;;
esac

SUPABASE_DOMAIN=""
LE_EMAIL=""
STACK_TYPE="full"  # full | minimal

if [[ "$MODE" == "express" ]]; then
  echo "\n[Modo EXPRESS] Instalación automática."
  echo "Se usará configuración por defecto y se pedirá solo el dominio."
  read -rp "Dominio para Supabase Studio (ej: supabase.midominio.com): " SUPABASE_DOMAIN
  if [[ -z "$SUPABASE_DOMAIN" ]]; then
    echo "[ERROR] Debes indicar un dominio." >&2
    exit 1
  fi
  # Valores por defecto razonables
  LE_EMAIL="admin@${SUPABASE_DOMAIN#*.}"
  STACK_TYPE="full"
else
  echo "\n[Modo GUIADO] Te preguntaré 3 cosas como máximo."
  # 1) Dominio
  read -rp "1/3 - Dominio para Supabase Studio (ej: supabase.midominio.com): " SUPABASE_DOMAIN
  if [[ -z "$SUPABASE_DOMAIN" ]]; then
    echo "[ERROR] Debes indicar un dominio." >&2
    exit 1
  fi
  # 2) Email
  read -rp "2/3 - Email para Let's Encrypt (certificados SSL): " LE_EMAIL
  if [[ -z "$LE_EMAIL" ]]; then
    echo "[ERROR] Debes indicar un email válido." >&2
    exit 1
  fi
  # 3) Tipo de stack
  echo "3/3 - ¿Qué quieres instalar?"
  echo "     1) Stack completo de Supabase (recomendado)"
  echo "     2) Solo Traefik + Studio (mínimo)"
  read -rp "     Opción [1/2]: " STACK_OPT
  case "${STACK_OPT:-1}" in
    1|"" ) STACK_TYPE="full" ;;
    2) STACK_TYPE="minimal" ;;
    *) echo "Opción no válida, usando 'full'."; STACK_TYPE="full" ;;
  esac
fi

# Si en guiado no se escribió LE_EMAIL, derivamos uno por defecto
if [[ -z "$LE_EMAIL" ]]; then
  LE_EMAIL="admin@${SUPABASE_DOMAIN#*.}"
fi

echo ""  
echo "Resumen de instalación:"
echo "  Dominio:        $SUPABASE_DOMAIN"
echo "  Email LE:       $LE_EMAIL"
echo "  Tipo de stack:  $STACK_TYPE"
echo "  Modo:           $MODE"
read -rp "¿Continuar? [s/N]: " CONFIRM
if [[ ! "${CONFIRM:-n}" =~ ^[sS]$ ]]; then
  echo "Cancelado por el usuario."
  exit 0
fi

echo "=== Instalando dependencias (Docker, docker-compose-plugin, git) ==="
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg lsb-release git

if ! command -v docker >/dev/null 2>&1; then
  echo "Instalando Docker Engine desde repositorio oficial..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/\
$OS_ID \
\$(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

echo "=== Habilitando y arrancando Docker ==="
systemctl enable docker
systemctl start docker

mkdir -p /opt/supabase-traefik
cd /opt/supabase-traefik

if [[ "$STACK_TYPE" == "minimal" ]]; then
  cat > docker-compose.yml <<EOF
version: "3.8"

services:
  traefik:
    image: traefik:v3.1
    container_name: traefik
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=$LE_EMAIL"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./letsencrypt:/letsencrypt"
    restart: unless-stopped

  studio:
    image: supabase/studio:latest
    environment:
      STUDIO_PG_META_URL: http://meta:8080
      SUPABASE_URL: http://kong:8000
      SUPABASE_ANON_KEY: "supabase-anon-key"
      SUPABASE_SERVICE_KEY: "supabase-service-role-key"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.studio.rule=Host(\"$SUPABASE_DOMAIN\")"
      - "traefik.http.routers.studio.entrypoints=websecure"
      - "traefik.http.routers.studio.tls=true"
      - "traefik.http.routers.studio.tls.certresolver=letsencrypt"
    depends_on:
      - meta
      - kong
    restart: unless-stopped

  meta:
    image: supabase/postgres-meta:latest
    environment:
      PG_META_DB_HOST: db
      PG_META_DB_PORT: 5432
      PG_META_DB_USER: postgres
      PG_META_DB_PASSWORD: postgres
      PG_META_DB_NAME: postgres
    depends_on:
      - db
    restart: unless-stopped

  kong:
    image: supabase/kong:latest
    depends_on:
      - db
    restart: unless-stopped

  db:
    image: supabase/postgres:15.1.0.140
    environment:
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: postgres
      POSTGRES_USER: postgres
    volumes:
      - db-data:/var/lib/postgresql/data
    restart: unless-stopped

volumes:
  db-data:
EOF
else
  cat > docker-compose.yml <<EOF
version: "3.8"

services:
  traefik:
    image: traefik:v3.1
    container_name: traefik
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=$LE_EMAIL"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./letsencrypt:/letsencrypt"
    restart: unless-stopped

  db:
    image: supabase/postgres:15.1.0.140
    environment:
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: postgres
      POSTGRES_USER: postgres
    volumes:
      - db-data:/var/lib/postgresql/data
    restart: unless-stopped

  kong:
    image: supabase/kong:latest
    environment:
      KONG_DATABASE: "off"
      KONG_DECLARATIVE_CONFIG: /var/lib/kong/kong.yml
    depends_on:
      - db
      - auth
      - rest
      - realtime
      - storage
    restart: unless-stopped

  auth:
    image: supabase/gotrue:v2.151.0
    environment:
      GOTRUE_DB_DRIVER: postgres
      GOTRUE_DB_DATABASE_URL: postgres://postgres:postgres@db:5432/postgres
      GOTRUE_SITE_URL: https://$SUPABASE_DOMAIN
      GOTRUE_JWT_SECRET: super-secret-jwt-token-with-at-least-32-characters-long
    depends_on:
      - db
    restart: unless-stopped

  rest:
    image: supabase/postgrest:v12.0.1
    environment:
      PGRST_DB_URI: postgres://postgres:postgres@db:5432/postgres
      PGRST_DB_SCHEMA: public
      PGRST_DB_ANON_ROLE: anon
    depends_on:
      - db
    restart: unless-stopped

  realtime:
    image: supabase/realtime:v2.25.75
    environment:
      DB_HOST: db
      DB_USER: postgres
      DB_PASSWORD: postgres
      DB_NAME: postgres
    depends_on:
      - db
    restart: unless-stopped

  storage:
    image: supabase/storage-api:v0.43.8
    environment:
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: postgres
      POSTGRES_USER: postgres
      POSTGRES_HOST: db
      POSTGRES_PORT: 5432
    depends_on:
      - db
    restart: unless-stopped

  meta:
    image: supabase/postgres-meta:latest
    environment:
      PG_META_DB_HOST: db
      PG_META_DB_PORT: 5432
      PG_META_DB_USER: postgres
      PG_META_DB_PASSWORD: postgres
      PG_META_DB_NAME: postgres
    depends_on:
      - db
    restart: unless-stopped

  studio:
    image: supabase/studio:latest
    environment:
      STUDIO_PG_META_URL: http://meta:8080
      SUPABASE_URL: http://kong:8000
      SUPABASE_ANON_KEY: "supabase-anon-key"
      SUPABASE_SERVICE_KEY: "supabase-service-role-key"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.studio.rule=Host(\"$SUPABASE_DOMAIN\")"
      - "traefik.http.routers.studio.entrypoints=websecure"
      - "traefik.http.routers.studio.tls=true"
      - "traefik.http.routers.studio.tls.certresolver=letsencrypt"
    depends_on:
      - meta
      - kong
    restart: unless-stopped

volumes:
  db-data:
EOF
fi

mkdir -p letsencrypt
chmod 700 letsencrypt

echo "=== Arrancando Traefik + Supabase (parcial) ==="
DOCKER_COMPOSE="docker compose"
if ! $DOCKER_COMPOSE version >/dev/null 2>&1; then
  DOCKER_COMPOSE="docker-compose"
fi

$DOCKER_COMPOSE up -d

IP_PUBLICA="$(curl -s https://ifconfig.me || echo "TU_IP")"

echo ""
echo "==============================================="
echo " Instalación básica completada"
echo "==============================================="
echo "Dominio configurado:   $SUPABASE_DOMAIN"
echo "IP pública detectada:  $IP_PUBLICA"
echo ""
echo "Asegúrate de que en Cloudflare tienes:" 
echo "  - Un registro A apuntando $SUPABASE_DOMAIN -> $IP_PUBLICA"
echo "  - Nube naranja ACTIVADA (proxy)"
echo ""
echo "Traefik está gestionando HTTP/HTTPS en este servidor."
echo "Cuando la propagación DNS termine, prueba a entrar a:"
echo "  https://$SUPABASE_DOMAIN"
echo ""
echo "IMPORTANTE:"
echo "  - Este compose solo arranca Traefik + Studio + servicios mínimos."
echo "  - Debes completar la configuración de Supabase (db, auth, storage, etc.)"
echo "    según la documentación oficial y adaptar el docker-compose.yml."
echo ""
echo "Script finalizado."