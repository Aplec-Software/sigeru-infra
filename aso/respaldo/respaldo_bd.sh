#!/bin/bash
# =====================================================================
# Respaldo completo de la base de datos sigeru (servidor sigeru-bd).
#   mysqldump -> gzip -> cifrado AES-256 -> suma SHA-256 -> copia al servidor de respaldo
# Lo ejecuta cron todos los días (ver /etc/cron.d/sigeru) o el menú de respaldos.
# =====================================================================
set -o pipefail
DIR_ASO="$(dirname "$(readlink -f "$0")")/.."
# shellcheck source=../modulos/comun.sh
source "$DIR_ASO/modulos/comun.sh"

FECHA=$(date +%Y%m%d_%H%M%S)
DESTINO="$DIR_RESPALDOS_LOCAL/bd"
ARCHIVO="sigeru_bd_${FECHA}.sql.gz.enc"
LOG="$DIR_LOGS/respaldos.log"
CLAVE_SSH=/root/.ssh/id_respaldo

log() {
    mkdir -p "$DIR_LOGS"
    echo "$(date '+%F %T') [$(hostname -s)] bd: $1" | tee -a "$LOG"
}

verificar_root
if [ ! -f /etc/sigeru/respaldo.cnf ]; then
    log "ERROR: falta /etc/sigeru/respaldo.cnf (Base de datos > Crear usuarios de las aplicaciones)"
    exit 1
fi
if [ ! -f "$CLAVE_RESPALDOS" ]; then
    log "ERROR: falta la clave de cifrado $CLAVE_RESPALDOS"
    exit 1
fi

install -d -m 700 "$DIR_RESPALDOS_LOCAL" "$DESTINO"

# --single-transaction: copia consistente sin bloquear las tablas (InnoDB)
if mysqldump --defaults-extra-file=/etc/sigeru/respaldo.cnf --single-transaction --no-tablespaces \
        --triggers --events --set-gtid-purged=OFF --default-character-set=utf8mb4 sigeru \
    | gzip -9 \
    | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass file:"$CLAVE_RESPALDOS" -out "$DESTINO/$ARCHIVO"; then
    (cd "$DESTINO" && sha256sum "$ARCHIVO" > "$ARCHIVO.sha256")
    log "respaldo creado $ARCHIVO ($(du -h --apparent-size "$DESTINO/$ARCHIVO" | cut -f1))"
else
    rm -f "${DESTINO:?}/${ARCHIVO:?}"
    log "ERROR: falló mysqldump; no se generó el respaldo"
    exit 1
fi

# Copia al servidor de respaldo
if rsync -a -e "ssh -i $CLAVE_SSH -p $PUERTO_SSH -o BatchMode=yes -o ConnectTimeout=10" \
        "$DESTINO/$ARCHIVO" "$DESTINO/$ARCHIVO.sha256" \
        "$USUARIO_RESPALDO@$IP_RESPALDO:$DIR_RESPALDOS_REMOTO/bd/"; then
    log "copiado a $NOMBRE_RESPALDO:$DIR_RESPALDOS_REMOTO/bd/"
else
    log "ERROR: no se pudo copiar a $NOMBRE_RESPALDO (queda solo la copia local)"
    ESTADO=2
fi

# Retención local: se conservan los últimos días configurados
find "$DESTINO" -name 'sigeru_bd_*' -mtime +"$DIAS_RESPALDO_LOCAL" -delete
exit "${ESTADO:-0}"
