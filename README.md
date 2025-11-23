# Supabase Self-Hosted Installer

![Supabase](https://img.shields.io/badge/Supabase-Self--Hosted-3ECF8E?style=for-the-badge&logo=supabase)
![Docker](https://img.shields.io/badge/Docker-Required-2496ED?style=for-the-badge&logo=docker)
![License](https://img.shields.io/badge/License-MIT-blue?style=for-the-badge)

**Instalador automatizado de Supabase completo** - Despliega tu propia instancia de Supabase (como supabase.com) en un solo comando.

---

## 🚀 Características

✅ **Instalación con 1 comando** - Todo automatizado, sin configuración manual  
✅ **Supabase completo** - Todos los servicios: Auth, Database, Storage, Realtime, Edge Functions  
✅ **SSL automático** - Certificados Let's Encrypt con renovación automática  
✅ **Modo sin dominio** - También funciona con IP directa (ideal para desarrollo)  
✅ **Instalador Docker incluido** - Si no tienes Docker, se instala automáticamente  
✅ **Seguro** - Genera claves aleatorias y credenciales únicas  
✅ **Interactivo** - Te guía paso a paso durante la instalación  

---

## 📋 Requisitos

- **Sistema Operativo**: Ubuntu 20.04+ o Debian 10+
- **Acceso**: Usuario con privilegios `sudo` o `root`
- **Recursos mínimos**: 2GB RAM, 2 CPU cores, 20GB disco
- **Opcional**: Un dominio apuntando al servidor (para SSL)

---

## ⚡ Instalación Rápida

### Opción 1: Descarga directa

```bash
# Descargar el instalador
curl -O https://raw.githubusercontent.com/TU-USUARIO/supabase-installer/main/install_supabase.sh

# Ejecutar
sudo bash install_supabase.sh
```

### Opción 2: Clonar repositorio

```bash
git clone https://github.com/TU-USUARIO/supabase-installer.git
cd supabase-installer
sudo bash install_supabase.sh
```

---

## 🎯 ¿Qué hace el instalador?

El script realiza automáticamente:

1. ✅ Verifica e instala Docker (si no está presente)
2. ✅ Te pregunta si quieres usar dominio o IP
3. ✅ Instala todas las dependencias necesarias
4. ✅ Descarga Supabase oficial desde GitHub
5. ✅ Genera claves de seguridad aleatorias
6. ✅ Configura variables de entorno
7. ✅ Instala Traefik para SSL (si usas dominio)
8. ✅ Inicia todos los servicios de Supabase
9. ✅ Guarda tus credenciales de forma segura

---

## 🌐 Dos modos de instalación

### Modo 1: Con Dominio (SSL Automático) 🔒

**Ideal para producción**

```
Studio: https://studio.tudominio.com
API:    https://api.tudominio.com
```

**Requisitos DNS previos:**
- Crear registro `A` para `studio.tudominio.com` → IP del servidor
- Crear registro `A` para `api.tudominio.com` → IP del servidor

El instalador generará certificados SSL automáticamente con Let's Encrypt.

### Modo 2: Con IP (Sin SSL) 🔓

**Ideal para desarrollo o redes internas**

```
Studio: http://123.45.67.89:3000
API:    http://123.45.67.89:8000
```

No necesitas dominio ni configurar DNS.

---

## 📱 Después de la instalación

### Acceder al Dashboard

El instalador te mostrará:
- 🌐 **URL del Studio** (dashboard web)
- 🔑 **Usuario y contraseña** para acceder
- 📦 **Claves de API** para conectar tu aplicación

Las credenciales completas se guardan en: `/root/supabase_credentials.txt`

### Conectar tu aplicación

Usa las credenciales proporcionadas en tu aplicación:

```javascript
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = 'https://api.tudominio.com'  // o tu IP
const supabaseAnonKey = 'tu-anon-key'

const supabase = createClient(supabaseUrl, supabaseAnonKey)
```

---

## 🛠️ Comandos útiles

### Ver credenciales guardadas
```bash
cat /root/supabase_credentials.txt
```

### Ver logs en tiempo real
```bash
cd /opt/supabase/supabase/docker
docker compose logs -f
```

### Ver estado de los servicios
```bash
cd /opt/supabase/supabase/docker
docker compose ps
```

### Reiniciar servicios
```bash
cd /opt/supabase/supabase/docker
docker compose restart
```

### Detener servicios
```bash
cd /opt/supabase/supabase/docker
docker compose down
```

### Iniciar servicios
```bash
cd /opt/supabase/supabase/docker
docker compose up -d
```

---

## 🔧 Solución de problemas

### Los servicios no inician
```bash
# Ver logs de todos los servicios
cd /opt/supabase/supabase/docker
docker compose logs

# Verificar que Docker está corriendo
systemctl status docker
```

### Error de certificados SSL
- Verifica que el DNS esté correctamente configurado
- Los certificados pueden tardar 1-2 minutos en generarse
- Revisa los logs de Traefik: `docker logs supabase-traefik`

### No puedo acceder al Studio
- Verifica que los puertos 80, 443 (o 3000, 8000) estén abiertos en el firewall
- Si usas un proveedor cloud, revisa los security groups
- Verifica que los servicios estén corriendo: `docker compose ps`

### Reinstalar desde cero
```bash
# Detener y eliminar todo
cd /opt/supabase/supabase/docker
docker compose down -v

# Eliminar directorio
rm -rf /opt/supabase

# Volver a ejecutar el instalador
sudo bash install_supabase.sh
```

---

## 📚 Servicios incluidos

El instalador configura todos estos servicios:

- **Kong** - API Gateway
- **PostgreSQL** - Base de datos
- **GoTrue** - Servicio de autenticación
- **PostgREST** - API REST automática
- **Realtime** - Suscripciones en tiempo real
- **Storage** - Almacenamiento de archivos
- **imgproxy** - Optimización de imágenes
- **pg_meta** - API de metadata de PostgreSQL
- **Studio** - Dashboard web
- **Edge Functions** - Funciones serverless
- **Traefik** - Proxy inverso con SSL (opcional)

---

## 🔐 Seguridad

- ✅ Todas las contraseñas se generan aleatoriamente
- ✅ JWT secrets únicos por instalación
- ✅ Certificados SSL automáticos con Let's Encrypt
- ✅ Credenciales guardadas con permisos 600 (solo root)
- ✅ Firewall UFW configurado automáticamente

**Recomendaciones adicionales:**
- Cambia la contraseña del dashboard después de la instalación
- Usa claves SSH para acceder al servidor
- Mantén Docker actualizado
- Haz backups regulares de `/opt/supabase/supabase/docker/volumes`

---

## 🆘 Soporte

¿Problemas o preguntas?
- 📝 Abre un [Issue](https://github.com/TU-USUARIO/supabase-installer/issues)
- 📖 Consulta la [documentación oficial de Supabase](https://supabase.com/docs)

---

## 📄 Licencia

MIT License - Usa libremente este instalador

---

## 🙏 Créditos

- [Supabase](https://supabase.com) - El increíble proyecto open source
- [Docker](https://docker.com) - Containerización
- [Traefik](https://traefik.io) - Proxy inverso

---

**¿Te fue útil?** Dale una ⭐ al repositorio
