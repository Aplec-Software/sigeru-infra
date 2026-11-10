# SiGeRU - Infraestructura

Todo lo necesario para instalar SiGeRU de dos formas:

- **En un servidor único con cuatro contenedores** (`servidor-unico/`): es la que se usa en la instancia de
  instalación de la ESI. Contenedores web (Apache + PHP), api (Apache + PHP), bd (MySQL 8.4) y respaldo (.tar.gz).
- **En los tres servidores que pide la letra** (aplicaciones, base de datos y respaldo) sobre Rocky Linux 9
  (`docker/` y `aso/`): es la arquitectura de producción.

```
servidor-unico/  compose.yaml de cuatro contenedores, Dockerfiles, instalar.sh, verificar.sh, respaldos .tar.gz
db/          scripts SQL: estructura, datos base, datos de prueba y usuarios de MySQL con permisos mínimos
docker/      docker-compose.yml del servidor de aplicaciones, gateway Nginx (HTTPS) y .env.example
aso/         script de administración de servidores (sigeru-admin) con sus módulos, respaldos y configuraciones
postman/     colección de Postman y script de pruebas de caja negra de las APIs
pruebas/     pruebas de la interfaz con Playwright (landing, frontend y backoffice)
desarrollo/  entorno local sin Docker (servidor de PHP + SQLite) y el núcleo común de las APIs
```

## Instalación en un servidor único

Con los siete repositorios clonados uno al lado del otro:

```bash
cd sigeru-infra/servidor-unico
sudo bash instalar.sh       # crea el .env, construye, levanta los cuatro contenedores y verifica
bash verificar.sh           # se puede repetir en cualquier momento
```

El detalle (contenedores, red, volúmenes, respaldos y problemas frecuentes) está en
[servidor-unico/README.md](servidor-unico/README.md).

## Servidores (producción)

| Servidor | IP (red interna) | Qué corre |
|---|---|---|
| sigeru-app | 192.168.56.10 | Docker: gateway, landing, frontend, 3 APIs y backoffice |
| sigeru-bd | 192.168.56.20 | MySQL 8 (solo acepta conexiones de sigeru-app) |
| sigeru-respaldo | 192.168.56.30 | Recibe por SSH los respaldos cifrados |

## Instalación resumida

En cada servidor:

```bash
sudo dnf -y install git
sudo git clone https://github.com/Aplec-Software/sigeru-infra.git /opt/aplec/sigeru/sigeru-infra
cd /opt/aplec/sigeru/sigeru-infra/aso
sudo ./instalar.sh app      # o bd, o respaldo
sudo sigeru-admin           # Instalación > Preparar este servidor
```

Después, en este orden: preparar el servidor de respaldo, en sigeru-app instalar Docker, descargar los
repositorios y generar la configuración, en sigeru-bd instalar MySQL con el `.env` generado, y por último levantar
SiGeRU. El paso a paso con capturas está en el manual de instalación del documento del proyecto.

## Script de administración

`sudo sigeru-admin` abre un menú con: verificación del servidor, usuarios, grupos, respaldos, redes, base de datos,
firewall, logs, contenedores e instalación.

En **Gestión de contenedores**, "Actualizar desde GitHub" baja los cambios y reconstruye las imágenes con
`docker compose build --pull` (para traer la última imagen de PHP), y "Controlar la versión de PHP" compara la versión
de cada servicio con `PHP_MINIMO` de `/etc/sigeru/sigeru.conf` (hoy 8.3.36). La verificación del estado del servidor
avisa si alguna aplicación quedó por debajo de ese mínimo. Cada área es un módulo en `aso/modulos/`. Todas las acciones quedan
registradas en `/var/log/sigeru/admin.log`.

## Respaldos

- Base de datos: completo todos los días a las 02:30 (`mysqldump` consistente, comprimido y cifrado con AES-256).
- Configuración de cada servidor: todos los domingos.
- Se copian por SSH (clave restringida) a sigeru-respaldo, que verifica la suma SHA-256 todos los días y aplica la
  retención: 7 días en cada servidor, 30 días en el de respaldo y uno por mes durante un año.
- La restauración se puede probar sobre una base aparte (`sigeru_prueba`) sin tocar la que está en uso.

## Pruebas

```bash
bash postman/prueba_caja_negra.sh https://localhost              # caja negra de las APIs (curl, resultados en CSV)
BASE=https://localhost node pruebas/interfaz.js salida.csv       # interfaz con Playwright (19 casos)
```

Las dos crean o modifican datos: usar solo con la base de demostración. Algunos casos dependen de las fechas de los
datos de prueba (recorridos y mantenimientos planificados): necesitan `FECHA_SIMULADA=2026-10-30` en el `.env`
(en `servidor-unico/.env` ya viene así; en producción, ponerla en `docker/.env` solo mientras se corren).

## Desarrollo local

Con los repositorios uno al lado del otro y PHP 8.1+ instalado:

```bash
./desarrollo/iniciar.sh     # http://127.0.0.1:8080 con una base SQLite y los datos de prueba
FECHA_SIMULADA=2026-10-30 ./desarrollo/iniciar.sh   # igual, pero con el reloj en ese día (hora real)
```

Los datos de prueba tienen fecha de referencia 30/10/2026 y recorridos planificados de lunes a sábado hasta el
21/11/2026. `FECHA_SIMULADA=AAAA-MM-DD` hace que el sistema funcione como si fuera ese día: sirve para las pruebas
de interfaz (el caso de «Mi ruta» necesita un recorrido en el día) y para demostraciones fuera de esas fechas.
En los servidores se define en `docker/.env` solo para las pruebas y demostraciones.

`desarrollo/nucleo/` tiene el núcleo común de las APIs (router, validación, JWT, base de datos...). Cada API
guarda su propia copia para ser independiente; `desarrollo/sincronizar.sh` la actualiza en todas cuando se
cambia algo del núcleo.
