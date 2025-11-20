# Supabase VPS Installer

Este repositorio contiene un script para instalar automáticamente Supabase (Self-Hosted) en un servidor Linux (Ubuntu/Debian recomendado), como un VPS de Hetzner, DigitalOcean o AWS.

## Requisitos

- Un servidor VPS con Linux (Ubuntu 20.04/22.04 recomendado).
- Acceso root o usuario con privilegios sudo.
- Al menos 4GB de RAM (recomendado para correr todos los servicios de Supabase).

## Instalación Rápida (One-Line)

Simplemente copia y pega esta línea en tu terminal:

```bash
bash <(curl -sL https://raw.githubusercontent.com/alvaro-segunda-cabeza/supabase-installer/main/install_supabase.sh)
```

*(Asegúrate de reemplazar `alvaro-segunda-cabeza` con tu nombre de usuario de GitHub una vez publiques el repositorio).*

## Instalación Manual

Si prefieres ver el script antes de ejecutarlo:

1. Conéctate a tu servidor vía SSH:
   ```bash
   ssh root@tu-ip-servidor
   ```

2. Descarga y ejecuta el script:
   ```bash
   curl -O https://raw.githubusercontent.com/alvaro-segunda-cabeza/supabase-installer/main/install_supabase.sh
   chmod +x install_supabase.sh
   sudo ./install_supabase.sh
   ```

## ¿Qué hace el script?

1. **Actualiza el sistema**: Ejecuta `apt-get update` y `upgrade`.
2. **Instala Docker**: Si no está instalado, descarga e instala la última versión.
3. **Clona Supabase**: Descarga el repositorio oficial en `/opt/supabase`.
4. **Configura Seguridad Automáticamente**:
   - Genera una contraseña aleatoria para la base de datos.
   - Genera un nuevo `JWT_SECRET` aleatorio.
   - **Calcula y firma** nuevas `ANON_KEY` y `SERVICE_ROLE_KEY` válidas usando el nuevo secreto (esto es crítico para que funcione).
   - Guarda todo en `/opt/supabase/docker/.env`.
5. **Configura SSL / Traefik (Opcional)**:
   - Te pregunta si quieres usar HTTPS.
   - Si dices que sí, te pide tu dominio (ej. `midominio.com`) y email.
   - Configura **Traefik** automáticamente para manejar certificados SSL (Let's Encrypt).
   - Configura los subdominios `studio.midominio.com` y `api.midominio.com`.
6. **Inicia los Servicios**: Levanta los contenedores con Docker Compose.

## Requisitos DNS (Si usas SSL)

Si eliges instalar SSL, asegúrate de configurar los registros DNS en tu proveedor de dominio (Cloudflare, Namecheap, etc.) apuntando a la IP de tu VPS:

- `studio.tudominio.com` -> `A Record` -> `TU_IP_VPS`
- `api.tudominio.com`    -> `A Record` -> `TU_IP_VPS`

## Acceso

Una vez finalizado:

**Si configuraste SSL:**
- **Supabase Studio**: `https://studio.tudominio.com`
- **API URL**: `https://api.tudominio.com`

**Si NO configuraste SSL:**
- **Supabase Studio**: `http://tu-ip-servidor:8000` (o puerto 3000 según config)
- **API URL**: `http://tu-ip-servidor:8000`

Para ver tus claves generadas (necesarias para conectar tu frontend):
```bash
cat /opt/supabase/docker/.env
```
Busca `ANON_KEY` y `SERVICE_ROLE_KEY`.

## Solución de Problemas (Troubleshooting)

Si algo no funciona o tus dominios dan error, ejecuta estos comandos en tu servidor para diagnosticar:

### 1. Verificar que los contenedores están corriendo
```bash
docker ps
```
Deberías ver una lista de contenedores (supabase-studio, supabase-kong, traefik, etc.) con estado "Up". Si alguno dice "Restarting" o no aparece, hay un error.

### 2. Ver logs de Traefik (Problemas de SSL)
Si tus dominios no cargan o dan error de certificado, revisa los logs de Traefik:
```bash
docker logs traefik
```
Busca errores en rojo relacionados con "acme" o "letsencrypt". Común: errores de validación DNS si los registros A no apuntaban a la IP antes de instalar.

### 3. Verificar si Supabase responde localmente
Intenta conectar desde dentro del servidor para descartar problemas de firewall:
```bash
curl -I http://localhost:8000
```
Deberías recibir un `HTTP/1.1 200 OK` (o 404, pero respuesta al fin).

### 4. Reiniciar todo
A veces un reinicio limpio soluciona problemas de configuración:
```bash
cd /opt/supabase/docker
docker compose down
docker compose up -d
```
