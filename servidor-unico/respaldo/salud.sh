#!/bin/bash
# Healthcheck del contenedor: el último respaldo tiene menos de 26 horas y pasó la verificación
# shellcheck source=comun.sh
source /usr/local/lib/sigeru-respaldo-comun.sh
ULTIMO=$(ultimo_respaldo)
[ -n "$ULTIMO" ] || exit 1
[ $(( $(date +%s) - $(date -r "$ULTIMO" +%s) )) -lt $(( 26 * 3600 )) ] || exit 1
grep -q '^ok ' "$ESTADO" 2>/dev/null
