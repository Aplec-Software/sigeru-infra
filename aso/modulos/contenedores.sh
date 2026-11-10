#!/bin/bash
# =====================================================================
# Módulo: gestión de contenedores (Docker Compose, servidor sigeru-app)
# =====================================================================

DIR_COMPOSE="$DIR_SIGERU/sigeru-infra/docker"
SERVICIOS="gateway landing frontend api-usuarios api-gestion api-recoleccion backoffice"
REPOSITORIOS="sigeru-infra sigeru-landing sigeru-frontend sigeru-api-usuarios sigeru-api-gestion sigeru-api-recoleccion sigeru-backoffice"

compose() {
    (cd "$DIR_COMPOSE" && docker compose "$@")
}

docker_listo() {
    requiere_rol app || return 1
    if ! comando_existe docker; then
        error "Docker no está instalado (Instalación > Instalar Docker)."
        return 1
    fi
    if ! systemctl is-active --quiet docker; then
        error "El servicio docker no está activo."
        return 1
    fi
    if [ ! -f "$DIR_COMPOSE/docker-compose.yml" ]; then
        error "No se encuentra $DIR_COMPOSE/docker-compose.yml"
        return 1
    fi
}

elegir_servicio() {
    echo "Servicios: $SERVICIOS"
    preguntar "Servicio" SERVICIO
    if [[ " $SERVICIOS " != *" $SERVICIO "* ]]; then
        error "Servicio no válido."
        return 1
    fi
}

estado_contenedores() {
    docker_listo || return
    titulo "Contenedores de SiGeRU"
    compose ps --format 'table {{.Service}}\t{{.State}}\t{{.Status}}\t{{.Ports}}'
}

levantar() {
    docker_listo || return
    if [ ! -f "$DIR_COMPOSE/.env" ] || [ ! -f "$DIR_COMPOSE/gateway/certs/sigeru.crt" ]; then
        error "Falta el .env o el certificado. Use Instalación > Generar configuración."
        return
    fi
    compose up -d --build && ok "SiGeRU en marcha." && registrar "docker compose up"
}

detener() {
    docker_listo || return
    confirmar "Se detiene todo el sistema (los usuarios no podrán ingresar). ¿Seguir?" || return
    compose down && ok "Contenedores detenidos." && registrar "docker compose down"
}

reiniciar_servicio() {
    docker_listo || return
    elegir_servicio || return
    compose restart "$SERVICIO" && ok "$SERVICIO reiniciado." && registrar "reiniciar contenedor $SERVICIO"
}

logs_contenedor() {
    docker_listo || return
    elegir_servicio || return
    compose logs --tail 80 --timestamps "$SERVICIO"
}

actualizar() {
    docker_listo || return
    titulo "Actualizar SiGeRU a la última versión de GitHub"
    aviso "Se recomienda hacer un respaldo de la base de datos antes de actualizar."
    confirmar "¿Continuar?" || return
    local repo
    for repo in $REPOSITORIOS; do
        if [ -d "$DIR_SIGERU/$repo/.git" ]; then
            echo "- $repo: $(git -C "$DIR_SIGERU/$repo" pull --ff-only 2>&1 | tail -n 1)"
        else
            aviso "$repo no es un repositorio git; se deja como está."
        fi
    done
    # --pull descarga la última versión de las imágenes base (parches de seguridad de PHP y Nginx)
    compose build --pull && compose up -d && ok "Actualización aplicada." && registrar "actualizar SiGeRU (git pull + build --pull)"
    version_php
    docker image prune -f >/dev/null
}

salud_apis() {
    docker_listo || return
    titulo "Salud de las aplicaciones (a través del gateway)"
    local ruta codigo
    for ruta in / /app/ /backoffice/login /api/usuarios/salud /api/gestion/salud /api/recoleccion/salud; do
        codigo=$(curl -sk -o /dev/null -w '%{http_code}' "https://127.0.0.1$ruta")
        if [ "$codigo" = "200" ]; then
            ok "$ruta -> $codigo"
        else
            error "$ruta -> $codigo"
        fi
    done
}

# Controla que ningún contenedor PHP tenga una versión con vulnerabilidades conocidas
# (PHP_MINIMO se define en sigeru.conf y se actualiza ante cada aviso de seguridad).
version_php() {
    docker_listo || return
    titulo "Versión de PHP en los contenedores (mínimo seguro: $PHP_MINIMO)"
    local servicio version problemas=0
    for servicio in api-usuarios api-gestion api-recoleccion backoffice; do
        version=$(compose exec -T "$servicio" php -r 'echo PHP_VERSION;' 2>/dev/null)
        if [ -z "$version" ]; then
            aviso "$servicio: no está en ejecución"
        elif [ "$(printf '%s\n%s\n' "$PHP_MINIMO" "$version" | sort -V | head -n 1)" = "$PHP_MINIMO" ]; then
            ok "$servicio: PHP $version"
        else
            error "$servicio: PHP $version es vulnerable; actualizar (Contenedores > Actualizar)"
            problemas=1
        fi
    done
    [ "$problemas" = 0 ] || registrar "AVISO: contenedores con PHP anterior a $PHP_MINIMO"
    return "$problemas"
}

crear_admin_inicial() {
    docker_listo || return
    compose exec api-usuarios php bin/crear_admin.php && registrar "crear administrador inicial"
}

menu_contenedores() {
    docker_listo || { pausa; return; }
    while true; do
        mostrar_menu "Gestión de contenedores" "Estado de los contenedores" "Levantar SiGeRU" "Detener SiGeRU" "Reiniciar un servicio" \
            "Ver logs de un servicio" "Actualizar desde GitHub" "Uso de recursos" "Comprobar salud de las aplicaciones" \
            "Crear el administrador inicial" "Borrar imágenes sin uso" "Controlar la versión de PHP (avisos de seguridad)"
        case $OPCION in
            1) estado_contenedores ;;
            2) levantar ;;
            3) detener ;;
            4) reiniciar_servicio ;;
            5) logs_contenedor ;;
            6) actualizar ;;
            7) titulo "Uso de recursos"; docker stats --no-stream ;;
            8) salud_apis ;;
            9) crear_admin_inicial ;;
            10) docker image prune -f && registrar "docker image prune" ;;
            11) version_php ;;
            0) return ;;
            *) error "Opción no válida." ;;
        esac
        pausa
    done
}
