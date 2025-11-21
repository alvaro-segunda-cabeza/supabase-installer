# Supabase Self-Hosted Installer with Nginx & HTTP

Este repositorio contiene un script automatizado para desplegar una instancia de **Supabase** completa en un servidor Ubuntu/Debian, utilizando **Nginx** como proxy inverso.

## Características

- 🚀 **Instalación en 1 comando**: Instala Docker, Supabase y configura todo automáticamente.
- 🛡️ **Seguridad**: Protege el Dashboard (Studio) con autenticación básica.
- 🐳 **Dockerizado**: Todo corre en contenedores aislados.
- 🎯 **Simple**: Sin complicaciones de SSL, ideal para desarrollo y entornos internos.

## Requisitos

- Un servidor VPS con **Ubuntu 20.04+** o **Debian 10+**.
- Acceso **root** o usuario con `sudo`.
- Un dominio (ej. `midominio.com`) apuntando a la IP del servidor (opcional).
  - Si usas dominio, necesitas registros A para `studio.midominio.com` y `api.midominio.com`.

## Instalación en 1 Comando

```bash
bash <(curl -sL https://raw.githubusercontent.com/alvaro-segunda-cabeza/supabase-installer/main/install_supabase.sh)
```

El script te pedirá de forma interactiva:
1. **Dominio**: Tu dominio base (ej. `midominio.com`)
2. **Email**: Tu email para notificaciones

¡Así de simple! El script se encarga del resto.

## Post-Instalación

Al finalizar, el script te mostrará:
- **URL del Dashboard**: `http://studio.tudominio.com` o `http://TU-IP`
- **URL de la API**: `http://api.tudominio.com`
- **Credenciales**:
  - Usuario/Pass para entrar al Dashboard (Basic Auth).
  - Anon Key y Service Role Key para tu aplicación.
  - Contraseña de PostgreSQL.

### Configuración de DNS (Opcional)

Si usas un dominio:
1. Agrega registro A: `studio.tudominio.com` → IP del servidor
2. Agrega registro A: `api.tudominio.com` → IP del servidor
3. **Importante**: Desactiva el proxy de Cloudflare (nube gris) si lo usas.

## Estructura

El script instala Supabase en `/opt/supabase`.
- `docker-compose.yml`: Configuración base de Supabase.
- `docker-compose.override.yml`: Configuración de Nginx.
- `.env`: Variables de entorno y secretos.

## Gestión Post-Instalación

### Ver logs
```bash
cd /opt/supabase
docker compose logs -f
```

### Reiniciar servicios
```bash
cd /opt/supabase
docker compose restart
```

### Detener servicios
```bash
cd /opt/supabase
docker compose down
```

### Iniciar servicios
```bash
cd /opt/supabase
docker compose up -d
```

### Ver credenciales
```bash
cat /root/supabase_credentials.txt
```
