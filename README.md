# Supabase Installer

Instala Supabase completo (con SSL y Traefik) en tu VPS con un solo comando.

## Instalación

```bash
bash <(curl -sL https://raw.githubusercontent.com/alvaro-segunda-cabeza/supabase-installer/main/install_supabase.sh)
```

### ¿Qué incluye?

- ✅ Docker y todas las dependencias
- ✅ Supabase (PostgreSQL, Auth, Storage, Realtime, etc.)
- ✅ Claves de seguridad generadas automáticamente
- ✅ SSL/HTTPS con Let's Encrypt (opcional)
- ✅ Compatible con Cloudflare (proxy naranja activado)

## Requisitos

- VPS con Ubuntu/Debian
- 4GB RAM mínimo
- Acceso root o sudo

## Configuración DNS

Si eliges usar SSL, configura estos registros en tu proveedor de DNS:

```
studio.tudominio.com  →  A  →  IP_DE_TU_VPS
api.tudominio.com     →  A  →  IP_DE_TU_VPS
```

**Con Cloudflare:** Puedes usar el proxy (rayito naranja 🟠) sin problemas. El script está configurado para funcionar con él. Solo asegúrate de poner SSL en modo **"Full"** en Cloudflare → SSL/TLS.

## Acceso

Una vez instalado:

- **Studio (Dashboard):** `https://studio.tudominio.com` (o `http://IP:3000` sin SSL)
- **API:** `https://api.tudominio.com` (o `http://IP:8000` sin SSL)

Para ver tus claves API:
```bash
cat /opt/supabase/docker/.env
```

## Solución de problemas

**Si algo no funciona:**

1. Verifica que los contenedores estén corriendo:
   ```bash
   docker ps
   ```

2. Revisa los logs:
   ```bash
   docker logs traefik
   docker logs supabase-kong
   ```

3. Reinicia:
   ```bash
   cd /opt/supabase/docker
   docker compose down
   docker compose up -d
   ```
