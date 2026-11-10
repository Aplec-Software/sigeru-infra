#!/bin/bash
# =====================================================================
# Instalación de SiGeRU en un servidor único (cuatro contenedores).
#   1. comprueba Docker, Docker Compose y que estén los siete repositorios
#   2. crea el archivo .env con contraseñas al azar (solo la primera vez)
#   3. construye las imágenes y levanta los contenedores
#   4. espera a que los cuatro estén sanos y ejecuta verificar.sh
#
# Uso (desde sigeru-infra/servidor-unico):   sudo bash instalar.sh
# =====================================================================
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
RAIZ=$(cd ../.. && pwd)
CONTENEDORES=(sigeru-bd sigeru-api sigeru-web sigeru-respaldo)

titulo() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()     { printf '  \033[32m[OK]\033[0m    %s\n' "$*"; }
aviso()  { printf '  \033[33m[AVISO]\033[0m %s\n' "$*"; }
falla()  { printf '  \033[31m[FALLA]\033[0m %s\n' "$*"; exit 1; }

# ------------------------------------------------------------------ 1
titulo "1. Requisitos"
command -v docker > /dev/null || falla "Docker no está instalado (ver el manual de instalación, Anexo VII)"
docker info > /dev/null 2>&1 || falla "Docker no está en ejecución o falta permiso: ejecutar con sudo o 'sudo systemctl start docker'"
ok "Docker Engine $(docker version --format '{{.Server.Version}}')"

COMPOSE=$(docker compose version --short 2>/dev/null) || falla "Falta Docker Compose (paquete docker-compose-plugin)"
COMPOSE=${COMPOSE#v}
IFS=. read -r MAYOR MENOR _ <<< "$COMPOSE"
if [ "${MAYOR:-0}" -lt 2 ] || { [ "${MAYOR:-0}" -eq 2 ] && [ "${MENOR:-0}" -lt 17 ]; }; then
    falla "Docker Compose $COMPOSE es muy viejo: se necesita 2.17 o posterior"
fi
ok "Docker Compose $COMPOSE"

for repo in sigeru-landing sigeru-frontend sigeru-backoffice sigeru-api-usuarios sigeru-api-gestion sigeru-api-recoleccion sigeru-infra; do
    [ -d "$RAIZ/$repo" ] || falla "No está $RAIZ/$repo: los siete repositorios van en la misma carpeta"
done
ok "Los siete repositorios están en $RAIZ"

for puerto in 80 443; do
    if command -v ss > /dev/null && ss -ltnH "sport = :$puerto" 2>/dev/null | grep -q .; then
        if ! docker ps --format '{{.Names}}' | grep -qx sigeru-web; then
            aviso "El puerto $puerto ya está en uso en este equipo: cambiar PUERTO_HTTP o PUERTO_HTTPS en .env"
        fi
    fi
done

# ------------------------------------------------------------------ 2
titulo "2. Configuración (.env)"
clave() { head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-24; }
if [ -f .env ]; then
    ok ".env existente: se conserva (las contraseñas ya están en la base de datos)"
else
    IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
    cp .env.example .env
    for variable in CLAVE_ROOT_MYSQL CLAVE_API_USUARIOS CLAVE_API_GESTION CLAVE_API_RECOLECCION CLAVE_BACKOFFICE CLAVE_RESPALDO APP_SAL; do
        sed -i "s/^$variable=.*/$variable=$(clave)/" .env
    done
    sed -i "s/^SERVIDOR_IP=.*/SERVIDOR_IP=${IP}/" .env
    chmod 600 .env
    ok ".env creado con contraseñas al azar (permisos 600)"
    [ -n "$IP" ] && ok "IP del servidor para el certificado: $IP"
fi

# firewalld: abrir HTTP y HTTPS si está activo (Rocky Linux)
if command -v firewall-cmd > /dev/null && firewall-cmd --state > /dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then
        firewall-cmd --quiet --permanent --add-service=http --add-service=https && firewall-cmd --quiet --reload \
            && ok "firewalld: servicios http y https abiertos"
    else
        aviso "firewalld está activo: ejecutar con sudo para abrir los puertos 80 y 443"
    fi
fi

# ------------------------------------------------------------------ 3
titulo "3. Construcción de las imágenes y arranque de los contenedores"
mkdir -p respaldos
docker compose up -d --build

# ------------------------------------------------------------------ 4
titulo "4. Esperando a que los cuatro contenedores estén sanos"
echo "  (la primera vez MySQL carga la estructura y los datos de prueba: puede tardar un par de minutos)"
LIMITE=$((SECONDS + 600))
while :; do
    pendientes=()
    for c in "${CONTENEDORES[@]}"; do
        estado=$(docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' "$c" 2>/dev/null || echo "sin-crear")
        [ "$estado" = "running healthy" ] || pendientes+=("$c: $estado")
    done
    [ ${#pendientes[@]} -eq 0 ] && break
    if [ $SECONDS -ge $LIMITE ]; then
        printf '    %s\n' "${pendientes[@]}"
        falla "Algún contenedor no quedó sano en 10 minutos: revisar con 'docker compose logs <servicio>'"
    fi
    sleep 5
done
for c in "${CONTENEDORES[@]}"; do ok "$c en ejecución y sano"; done

titulo "5. Verificación"
bash verificar.sh
