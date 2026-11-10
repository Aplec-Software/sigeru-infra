#!/bin/bash
# =====================================================================
# Mantenimiento diario del servidor de respaldo (sigeru-respaldo):
#   - verifica la suma SHA-256 de cada respaldo recibido
#   - borra los diarios vencidos, pero conserva el del día 1 de cada mes durante un año
#   - avisa si el disco supera el 85 %
# =====================================================================
DIR_ASO="$(dirname "$(readlink -f "$0")")/.."
# shellcheck source=../modulos/comun.sh
source "$DIR_ASO/modulos/comun.sh"

LOG="$DIR_LOGS/respaldos.log"
log() { mkdir -p "$DIR_LOGS"; echo "$(date '+%F %T') [$(hostname -s)] mantenimiento: $1" | tee -a "$LOG"; }

verificar_root
requiere_rol respaldo || exit 1

errores=0
verificados=0
for suma in "$DIR_RESPALDOS_REMOTO"/*/*.sha256; do
    [ -e "$suma" ] || continue
    if (cd "$(dirname "$suma")" && sha256sum -c --quiet "$(basename "$suma")" 2>/dev/null); then
        verificados=$((verificados + 1))
    else
        errores=$((errores + 1))
        log "ERROR: respaldo dañado o incompleto: $(basename "$suma" .sha256)"
    fi
done
log "verificados $verificados respaldos, con errores: $errores"

# Retención: diarios por DIAS_RESPALDO_REMOTO días; los del día 01 de cada mes, 365 días
borrados=0
while IFS= read -r archivo; do
    nombre=$(basename "$archivo")
    # el nombre lleva la fecha: ..._AAAAMMDD_HHMMSS...
    fecha=$(echo "$nombre" | grep -oE '_[0-9]{8}_' | head -n 1 | tr -d '_')
    if [ "${fecha:6:2}" = "01" ] && [ -z "$(find "$archivo" -mtime +365)" ]; then
        continue
    fi
    rm -f "${archivo:?}" "${archivo:?}.sha256"
    borrados=$((borrados + 1))
done < <(find "$DIR_RESPALDOS_REMOTO" -type f -name 'sigeru_*.enc' -mtime +"$DIAS_RESPALDO_REMOTO")
log "respaldos vencidos borrados: $borrados"

uso=$(df --output=pcent "$DIR_RESPALDOS_REMOTO" | tail -n 1 | tr -dc '0-9')
if [ "$uso" -ge 85 ]; then
    log "AVISO: el disco de respaldos está al $uso %"
fi
[ "$errores" -eq 0 ]
