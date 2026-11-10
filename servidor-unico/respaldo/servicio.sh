#!/bin/bash
# =====================================================================
# Servicio de respaldos (proceso principal del contenedor respaldo).
#   - espera a que la base acepte conexiones del usuario de respaldos
#   - si todavía no hay ningún respaldo, hace uno enseguida
#   - después hace uno por día a la hora RESPALDO_HORA (por defecto 02:30)
# =====================================================================
# shellcheck source=comun.sh
source /usr/local/lib/sigeru-respaldo-comun.sh
trap 'log "servicio detenido"; exit 0' TERM INT

HORA=${RESPALDO_HORA:-02:30}
if ! date -d "today $HORA" > /dev/null 2>&1; then
    log "RESPALDO_HORA no válida ($HORA); se usa 02:30"
    HORA=02:30
fi
mkdir -p "$DIR_RESPALDOS"
log "servicio iniciado: respaldo diario a las $HORA, se conservan ${RESPALDO_DIAS:-7} días"

CNF=$(opciones_mysql)
for _ in $(seq 1 60); do
    mysql --defaults-extra-file="$CNF" -N -e 'SELECT 1' > /dev/null 2>&1 && break
    sleep 5
done
if ! mysql --defaults-extra-file="$CNF" -N -e 'SELECT 1' > /dev/null 2>&1; then
    log "ERROR: el usuario de respaldos no puede conectarse a ${DB_HOST:-bd}"
fi
rm -f "$CNF"

if [ -z "$(ultimo_respaldo)" ]; then
    log "no hay respaldos: se hace el primero"
    respaldar || true
fi

while true; do
    ahora=$(date +%s)
    proximo=$(date -d "today $HORA" +%s)
    [ "$proximo" -le "$ahora" ] && proximo=$(date -d "tomorrow $HORA" +%s)
    sleep $((proximo - ahora)) &
    wait $!
    respaldar || log "ERROR: falló el respaldo programado"
done
