#!/bin/bash
# =====================================================================
# Restauración de la base de datos desde un respaldo (servidor sigeru-bd).
# Permite restaurar sobre "sigeru" o sobre una base de prueba para
# comprobar que el respaldo sirve sin tocar los datos en uso.
# =====================================================================
set -o pipefail
DIR_ASO="$(dirname "$(readlink -f "$0")")/.."
# shellcheck source=../modulos/comun.sh
source "$DIR_ASO/modulos/comun.sh"

LOCAL="$DIR_RESPALDOS_LOCAL/bd"
TEMPORAL="$DIR_RESPALDOS_LOCAL/restauracion"
CLAVE_SSH=/root/.ssh/id_respaldo
CNF_ROOT=/root/.my.cnf
LOG="$DIR_LOGS/respaldos.log"

log() { echo "$(date '+%F %T') [$(hostname -s)] restauración: $1" | tee -a "$LOG"; }

verificar_root
requiere_rol bd || exit 1
[ -f "$CNF_ROOT" ] || { error "Falta $CNF_ROOT"; exit 1; }

titulo "Restaurar la base de datos"
echo "  1) Usar un respaldo de este servidor ($LOCAL)"
echo "  2) Traer un respaldo del servidor de respaldo ($NOMBRE_RESPALDO)"
read -rp "Opción: " ORIGEN

install -d -m 700 "$TEMPORAL"
if [ "$ORIGEN" = "2" ]; then
    echo "Respaldos disponibles en $NOMBRE_RESPALDO:"
    ssh -i "$CLAVE_SSH" -p "$PUERTO_SSH" -o BatchMode=yes "$USUARIO_RESPALDO@$IP_RESPALDO" \
        "ls -1t $DIR_RESPALDOS_REMOTO/bd/ | grep -v sha256 | head -n 15" || { error "No se pudo conectar."; exit 1; }
    preguntar "Nombre del archivo" ARCHIVO
    [[ "$ARCHIVO" =~ ^sigeru_bd_[0-9_]+\.sql\.gz\.enc$ ]] || { error "Nombre no válido."; exit 1; }
    rsync -a -e "ssh -i $CLAVE_SSH -p $PUERTO_SSH -o BatchMode=yes" \
        "$USUARIO_RESPALDO@$IP_RESPALDO:$DIR_RESPALDOS_REMOTO/bd/$ARCHIVO*" "$TEMPORAL/" || { error "No se pudo descargar."; exit 1; }
    RUTA="$TEMPORAL/$ARCHIVO"
else
    echo "Respaldos disponibles:"
    ls -1t "$LOCAL" 2>/dev/null | grep -v sha256 | head -n 15
    preguntar "Nombre del archivo" ARCHIVO
    [[ "$ARCHIVO" =~ ^sigeru_bd_[0-9_]+\.sql\.gz\.enc$ ]] || { error "Nombre no válido."; exit 1; }
    RUTA="$LOCAL/$ARCHIVO"
fi

if [ ! -f "$RUTA" ]; then
    error "No existe $RUTA"
    exit 1
fi
if [ -f "$RUTA.sha256" ]; then
    if (cd "$(dirname "$RUTA")" && sha256sum -c --quiet "$(basename "$RUTA").sha256"); then
        ok "Integridad verificada (SHA-256)."
    else
        error "La suma SHA-256 no coincide: el archivo está dañado o fue modificado."
        exit 1
    fi
else
    aviso "No hay archivo .sha256 para comprobar la integridad."
    confirmar "¿Seguir igual?" || exit 1
fi

preguntar "Base de destino (sigeru o, para probar, sigeru_prueba)" BASE sigeru_prueba
[[ "$BASE" =~ ^sigeru(_prueba)?$ ]] || { error "Base no válida."; exit 1; }

if [ "$BASE" = "sigeru" ]; then
    aviso "Se reemplazarán los datos actuales de SiGeRU."
    confirmar "¿Confirma la restauración sobre la base en uso?" || exit 1
    log "respaldo de seguridad previo a la restauración"
    "$DIR_ASO/respaldo/respaldo_bd.sh" || confirmar "No se pudo hacer el respaldo previo. ¿Restaurar igual?" || exit 1
fi

mysql --defaults-file="$CNF_ROOT" -e "CREATE DATABASE IF NOT EXISTS $BASE DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
if openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass file:"$CLAVE_RESPALDOS" -in "$RUTA" \
    | gunzip | mysql --defaults-file="$CNF_ROOT" "$BASE"; then
    ok "Restauración terminada en la base '$BASE'."
    mysql --defaults-file="$CNF_ROOT" -e "SELECT COUNT(*) AS usuarios FROM $BASE.usuarios; SELECT COUNT(*) AS incidencias FROM $BASE.incidencias;"
    log "restaurado $ARCHIVO en $BASE"
else
    error "La restauración falló (¿clave de cifrado distinta?)."
    log "ERROR al restaurar $ARCHIVO en $BASE"
    exit 1
fi
rm -rf "${TEMPORAL:?}"
