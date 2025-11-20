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

## Configuración DNS (IMPORTANTE)

**ANTES de ejecutar el script**, configura estos registros en tu proveedor de DNS:

```
studio.tudominio.com  →  A  →  IP_DE_TU_VPS
api.tudominio.com     →  A  →  IP_DE_TU_VPS
```

**Espera 5-10 minutos** a que los DNS se propaguen antes de continuar con la instalación.

**Con Cloudflare:** 
1. Añade los registros DNS
2. Activa el proxy (rayito naranja 🟠) 
3. Ve a **SSL/TLS** → Elige **"Full"** (no "Flexible")
4. Ejecuta el script

## Verificar que funciona (Diagnóstico)

Si tienes problemas, ejecuta estos comandos en tu servidor:

```bash
# Ver si los contenedores están corriendo
docker ps

# Probar si funciona internamente
curl -I http://localhost:8000  # API
curl -I http://localhost:3000  # Studio

# Ver logs de Traefik (SSL)
docker logs traefik

# Ver logs de Kong (API Gateway)
docker logs supabase-kong
```

## Acceso

Una vez instalado:

- **Studio (Dashboard):** `https://studio.tudominio.com` (o `http://IP:3000` sin SSL)
- **API:** `https://api.tudominio.com` (o `http://IP:8000` sin SSL)

**Nota:** Los certificados SSL pueden tardar 1-2 minutos en generarse. Si ves "no es seguro", espera un momento y recarga.

Para ver tus claves API:
```bash
cat /opt/supabase/docker/.env
```

## Solución de problemas

**Error "404 Not Found":**
- Verifica que los contenedores estén corriendo: `docker ps`
- Revisa logs: `docker logs traefik` y `docker logs supabase-kong`

**Error "Not Secure" / SSL no funciona:**
- Verifica que el DNS apunte correctamente: `nslookup studio.tudominio.com`
- Espera 2 minutos para que Let's Encrypt genere los certificados
- Revisa logs de Traefik: `docker logs traefik 2>&1 | grep -i error`
- Si usas Cloudflare, asegúrate de que SSL esté en modo "Full"

**Reiniciar todo:**
```bash
cd /opt/supabase/docker
docker compose down
docker compose up -d
```
