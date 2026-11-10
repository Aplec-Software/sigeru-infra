#!/bin/bash
# =====================================================================
# Respaldo de configuración y archivos del servidor (semanal).
# En sigeru-app incluye el .env, las claves JWT y el certificado; en
# sigeru-bd la configuración de MySQL. Se cifra igual que el de la base.
# =====================================================================
set -o pipefail
DIR_ASO="$(dirname "$(readlink -f "$0")")/.."
# shellcheck source=../modulos/comun.sh
source "$DIR_ASO/modulos/comun.sh"

FECHA=$(date +%Y%m%d_%H%M%S)
SERVIDOR=$(hostname -s)
DESTINO="$DIR_RESPALDOS_LOCAL/archivos"
ARCHIVO="sigeru_${SERVIDOR}_archivos_${FECHA}.tar.gz.enc"
LOG="$DIR_LOGS/respaldos.log"
CLAVE_SSH=/root/.ssh/id_respaldo

log() {
    mkdir -p "$DIR_LOGS"
    echo "$(date '+%F %T') [$SERVIDOR] archivos: $1" | tee -a "$LOG"
}

verificar_root
if [ ! -f "$CLAVE_RESPALDOS" ]; then
    log "ERROR: falta la clave de cifrado $CLAVE_RESPALDOS"
    exit 1
fi

# Qué se respalda en todos los servidores
RUTAS="/etc/sigeru /etc/ssh/sshd_config.d /etc/firewalld /etc/fail2ban/jail.d /etc/cron.d/sigeru /etc/hosts /etc/NetworkManager/system-connections"
case $ROL in
    app) RUTAS="$RUTAS $DIR_SIGERU/sigeru-infra/docker/.env $DIR_SIGERU/sigeru-infra/docker/claves $DIR_SIGERU/sigeru-infra/docker/gateway/certs /etc/docker/daemon.json" ;;
    bd) RUTAS="$RUTAS /etc/my.cnf.d /root/.my.cnf" ;;
esac

# solo las rutas que existen (tar falla si falta alguna)
EXISTENTES=""
for ruta in $RUTAS; do
    [ -e "$ruta" ] && EXISTENTES="$EXISTENTES ${ruta#/}"
done

install -d -m 700 "$DIR_RESPALDOS_LOCAL" "$DESTINO"
# shellcheck disable=SC2086
if tar -czf - -C / --exclude=etc/sigeru/clave_respaldos $EXISTENTES 2>/dev/null \
    | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass file:"$CLAVE_RESPALDOS" -out "$DESTINO/$ARCHIVO"; then
    (cd "$DESTINO" && sha256sum "$ARCHIVO" > "$ARCHIVO.sha256")
    log "respaldo creado $ARCHIVO ($(du -h --apparent-size "$DESTINO/$ARCHIVO" | cut -f1))"
else
    rm -f "${DESTINO:?}/${ARCHIVO:?}"
    log "ERROR: no se pudo generar el respaldo de archivos"
    exit 1
fi

if [ "$ROL" != "respaldo" ]; then
    if rsync -a -e "ssh -i $CLAVE_SSH -p $PUERTO_SSH -o BatchMode=yes -o ConnectTimeout=10" \
            "$DESTINO/$ARCHIVO" "$DESTINO/$ARCHIVO.sha256" \
            "$USUARIO_RESPALDO@$IP_RESPALDO:$DIR_RESPALDOS_REMOTO/archivos/"; then
        log "copiado a $NOMBRE_RESPALDO:$DIR_RESPALDOS_REMOTO/archivos/"
    else
        log "ERROR: no se pudo copiar a $NOMBRE_RESPALDO (queda solo la copia local)"
        ESTADO=2
    fi
fi

find "$DESTINO" -name 'sigeru_*_archivos_*' -mtime +"$DIAS_RESPALDO_LOCAL" -delete
exit "${ESTADO:-0}"
