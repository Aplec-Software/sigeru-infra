# SiGeRU: instalación en un servidor único

Configuración de Docker para la instancia de instalación de la ESI: un solo servidor Linux con Docker Engine y Docker Compose, y cuatro contenedores en una red de Docker propia (`sigeru_red`).

| Contenedor | Tecnología | Función | IP en sigeru_red | Puertos |
|---|---|---|---|---|
| `sigeru-web` | Apache 2.4 + PHP 8.3 | Landing (`/`), frontend (`/app/`) y backoffice (`/backoffice/`). Atiende HTTPS y reenvía `/api/...` al contenedor api. | 172.30.50.10 | 80 y 443 publicados |
| `sigeru-api` | Apache 2.4 + PHP 8.3 | API de Usuarios (8001), de Gestión (8002) y de Recolección (8003), cada una con su usuario de MySQL. | 172.30.50.11 | solo red interna |
| `sigeru-bd` | MySQL 8.4 | Base `sigeru`: estructura, datos base, datos de prueba y usuarios por servicio. | 172.30.50.20 | solo red interna |
| `sigeru-respaldo` | Herramientas de MySQL 8.4 | Respaldo diario `.tar.gz` con suma SHA-256, verificación y retención. | 172.30.50.30 | ninguno |

```
navegador ─HTTPS 443─▶ web (Apache + PHP) ─/api/...─▶ api (Apache + PHP) ─▶ bd (MySQL 8.4) ◀─ respaldo
          (HTTP 80 redirige)   └─ backoffice ─────────────────────────────▶ bd          └─▶ respaldos/*.tar.gz
```

## Requisitos

- Linux con Docker Engine y el plugin Docker Compose 2.17 o posterior (`docker compose version`).
- Los siete repositorios clonados en la misma carpeta:

```bash
mkdir -p ~/sigeru && cd ~/sigeru
for r in sigeru-landing sigeru-frontend sigeru-backoffice sigeru-api-usuarios sigeru-api-gestion sigeru-api-recoleccion sigeru-infra; do
  git clone https://github.com/Aplec-Software/$r.git
done
```

## Instalación

```bash
cd ~/sigeru/sigeru-infra/servidor-unico
sudo bash instalar.sh
```

`instalar.sh` hace todo en orden:

1. Comprueba Docker, Docker Compose y que estén los siete repositorios.
2. Si no existe, crea el `.env` a partir de `.env.example`, con contraseñas al azar y la IP del servidor.
3. Si firewalld está activo, abre los servicios http y https.
4. Ejecuta `docker compose up -d --build`.
5. Espera a que los cuatro contenedores estén sanos.
6. Ejecuta `verificar.sh`.

La primera vez, MySQL carga la estructura y los datos de prueba, y eso tarda un par de minutos.

La instalación también se puede hacer a mano:

```bash
cp .env.example .env        # completar las contraseñas (solo letras y números)
docker compose build        # construir las imágenes de web, api y respaldo
docker compose up -d        # crear y levantar los cuatro contenedores
docker compose ps           # estado y salud de cada uno
```

Después se entra con el navegador a `https://<IP del servidor>/`. El certificado lo firma la autoridad certificadora propia de Aplec, que se genera al instalar. Para que el navegador no muestre la advertencia, se descarga `https://<IP>/aplec-ca.crt` y se instala como autoridad de confianza.

Usuarios de prueba (contraseña `Sigeru2026!`):

| Rol | Correo |
|---|---|
| Administrador | admin@sigeru.uy |
| Cuadrilla | jpereyra@sigeru.uy |
| Operario de centro | rbenitez@sigeru.uy |
| Vecino | ana.martinez@correo.uy |

## Verificación

```bash
bash verificar.sh                  # contenedores, red, volúmenes, HTTPS, APIs, MySQL, ABM y respaldo
bash verificar.sh --persistencia   # además recrea los contenedores y comprueba que los datos siguen
```

Cada ejecución deja un informe en `verificacion_AAAAMMDD_HHMMSS.txt`.

## Respaldos

El contenedor `sigeru-respaldo` hace un respaldo al arrancar si todavía no hay ninguno, y después uno por día a la hora `RESPALDO_HORA`. Conserva los respaldos de los últimos `RESPALDO_DIAS` días. Cada respaldo es un `sigeru_AAAAMMDD_HHMMSS.tar.gz` y contiene:

- `sigeru.sql`: el volcado de mysqldump, una copia consistente que se hace sin detener el servicio;
- `MANIFIESTO.txt`: la fecha, la versión de MySQL y la cantidad de filas de cada tabla.

Junto a cada respaldo queda su suma SHA-256 (`.sha256`).

```bash
bash respaldar.sh                                   # respaldo ahora y lista de respaldos
docker exec sigeru-respaldo verificar            # verifica el último (SHA-256, gzip, contenido)
docker exec sigeru-respaldo listar
bash restaurar.sh                                   # prueba el último en la base sigeru_prueba
bash restaurar.sh sigeru_20261109_023000.tar.gz --real   # restaura sobre la base en uso
```

Los archivos quedan en la carpeta `respaldos/` del servidor, fuera de los volúmenes de Docker. Por eso no se pierden si se borran los contenedores.

## Comandos útiles

```bash
docker compose ps                         # estado y salud
docker compose logs -f api                # logs de un servicio (web, api, bd, respaldo)
docker compose restart web                # reiniciar un servicio
docker compose down                       # detener y quitar los contenedores (los datos quedan en los volúmenes)
docker compose down -v                    # además borra los volúmenes: la próxima vez se crea la base de cero
docker network inspect sigeru_red         # red y dirección de cada contenedor
docker exec -it sigeru-bd mysql -uroot -p sigeru   # consola de MySQL (contraseña CLAVE_ROOT_MYSQL del .env)
```

## Archivos

```
servidor-unico/
├── compose.yaml          los cuatro servicios, la red sigeru_red y los volúmenes
├── .env.example          variables (puertos, IP, contraseñas, respaldo, fecha simulada)
├── instalar.sh           instalación completa
├── verificar.sh          verificación de la instalación
├── respaldar.sh          respaldo manual
├── restaurar.sh          restauración (de prueba o real)
├── web/                  Dockerfile, Apache (ports.conf, sigeru-web.conf), certificado.php
├── api/                  Dockerfile, Apache (un sitio por API), claves.php (claves JWT)
├── bd/04_usuarios.sh     usuarios de MySQL por servicio (usa db/04_usuarios_bd.sql)
└── respaldo/             Dockerfile y scripts respaldar, verificar, listar y del servicio
```

La estructura y los datos de la base son los mismos scripts de `sigeru-infra/db` que se usan en el despliegue de tres servidores (`sigeru-infra/docker` y `sigeru-infra/aso`).

## Problemas frecuentes

| Problema | Causa | Solución |
|---|---|---|
| `Bind for 0.0.0.0:80 failed: port is already allocated` | Otro servicio usa el puerto 80 o el 443. | Cambiar `PUERTO_HTTP` o `PUERTO_HTTPS` en `.env` y repetir `docker compose up -d`. |
| `Pool overlaps with other one on this address space` | La subred 172.30.50.0/24 ya existe en el equipo. | Cambiar `SUBRED` y las cuatro `IP_...` en `.env` (antes de la primera instalación). |
| `sigeru-api` no queda sano y `docker compose logs api` muestra `Access denied` | Se cambió el `.env` después de crear la base. | `docker compose down -v` y `bash instalar.sh` (vuelve a crear la base con las contraseñas nuevas). |
| El navegador advierte que la conexión no es privada | El certificado es de la CA propia. | Instalar `aplec-ca.crt` como autoridad de confianza, o continuar desde la opción avanzada. |
| Falla la construcción de `respaldo` | No hay salida a Internet para descargar `tar`. | Revisar la conexión del servidor y repetir `docker compose build respaldo`. |
