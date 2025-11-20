# Supabase Self-Hosted Installer with Traefik & SSL

Este repositorio contiene un script automatizado para desplegar una instancia de **Supabase** completa y lista para producción en un servidor Ubuntu/Debian, utilizando **Traefik** como proxy inverso para gestionar certificados SSL automáticamente (Let's Encrypt) y proteger el acceso.

Diseñado para funcionar detrás de **Cloudflare (Nube Naranja)** o directamente.

## Características

- 🚀 **Instalación en 1 click**: Instala Docker, Supabase y configura todo automáticamente.
- 🔒 **SSL Automático**: Traefik gestiona los certificados Let's Encrypt.
- 🛡️ **Seguridad**: Protege el Dashboard (Studio) con autenticación básica.
- ☁️ **Cloudflare Ready**: Compatible con el modo proxy de Cloudflare.
- 🐳 **Dockerizado**: Todo corre en contenedores aislados.

## Requisitos

- Un servidor VPS con **Ubuntu 20.04+** o **Debian 10+**.
- Acceso **root** o usuario con `sudo`.
- Un dominio (ej. `midominio.com`) apuntando a la IP del servidor.
  - Necesitas registros A para `studio.midominio.com` y `api.midominio.com`.

## Instalación Rápida

Ejecuta el siguiente comando en tu servidor:

```bash
curl -sL https://raw.githubusercontent.com/TU_USUARIO/supabase-installer/main/install_supabase.sh | sudo bash
```

*(Reemplaza `TU_USUARIO` con tu usuario de GitHub una vez hagas fork/push de este repo)*

O clona y ejecuta manualmente:

```bash
git clone https://github.com/TU_USUARIO/supabase-installer.git
cd supabase-installer
chmod +x install_supabase.sh
sudo ./install_supabase.sh
```

## Durante la instalación

El script te pedirá:
1. **Dominio Base**: El dominio donde alojarás los servicios (ej. `midominio.com`).
2. **Email**: Para el registro de certificados SSL de Let's Encrypt.

## Post-Instalación

Al finalizar, el script te mostrará:
- **URL del Dashboard**: `https://studio.midominio.com`
- **URL de la API**: `https://api.midominio.com`
- **Credenciales**:
  - Usuario/Pass para entrar al Dashboard (Basic Auth).
  - Contraseña de la Base de Datos (Postgres).
  - Claves de API (Anon/Service) - *Nota: Se usan las claves por defecto para asegurar compatibilidad inicial, se recomienda rotarlas en producción.*

### Configuración de Cloudflare

Si usas Cloudflare, asegúrate de:
1. Tener los registros DNS (A) con la "Nube Naranja" activada.
2. Ir a **SSL/TLS** > **Overview** y seleccionar modo **Full** o **Full (Strict)**.

## Estructura

El script instala Supabase en `/opt/supabase`.
- `docker-compose.yml`: Configuración base de Supabase.
- `docker-compose.override.yml`: Configuración de Traefik inyectada por el script.
- `.env`: Variables de entorno y secretos.
