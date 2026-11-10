#!/bin/bash
# =====================================================================
# Verifica un respaldo (por defecto, el último):
#   1. la suma SHA-256 coincide con la guardada al crearlo
#   2. el gzip no está dañado
#   3. el .tar contiene sigeru.sql y MANIFIESTO.txt
#   4. el volcado de MySQL está completo (termina con "Dump completed")
# Uso: verificar [archivo.tar.gz]
# =====================================================================
# shellcheck source=comun.sh
source /usr/local/lib/sigeru-respaldo-comun.sh

ARCHIVO=${1:-$(ultimo_respaldo)}
[ -n "$ARCHIVO" ] && [ "${ARCHIVO#/}" = "$ARCHIVO" ] && [ -f "$DIR_RESPALDOS/$ARCHIVO" ] && ARCHIVO="$DIR_RESPALDOS/$ARCHIVO"
if [ -z "$ARCHIVO" ] || [ ! -f "$ARCHIVO" ]; then
    echo "No hay respaldos para verificar en $DIR_RESPALDOS"
    exit 1
fi

FALLAS=0
paso() {   # paso "descripción" comando...
    local texto=$1; shift
    if "$@" > /dev/null 2>&1; then
        echo "  [OK]    $texto"
    else
        echo "  [FALLA] $texto"
        FALLAS=$((FALLAS + 1))
    fi
}

echo "Verificación de $(basename "$ARCHIVO") ($(du -h --apparent-size "$ARCHIVO" | cut -f1), $(date -r "$ARCHIVO" '+%F %T'))"
if [ -f "$ARCHIVO.sha256" ]; then
    paso "suma SHA-256" sh -c "cd '$(dirname "$ARCHIVO")' && sha256sum -c '$(basename "$ARCHIVO").sha256'"
else
    echo "  [FALLA] falta el archivo $(basename "$ARCHIVO").sha256"
    FALLAS=$((FALLAS + 1))
fi
paso "integridad del gzip" gzip -t "$ARCHIVO"
paso "contiene sigeru.sql y MANIFIESTO.txt" sh -c "tar -tzf '$ARCHIVO' | grep -qx 'sigeru.sql' && tar -tzf '$ARCHIVO' | grep -qx 'MANIFIESTO.txt'"
paso "volcado de MySQL completo" sh -c "tar -xzOf '$ARCHIVO' sigeru.sql | tail -n 1 | grep -q 'Dump completed'"

TABLAS=$(tar -xzOf "$ARCHIVO" sigeru.sql 2>/dev/null | grep -c '^CREATE TABLE')
echo "  Tablas en el volcado: $TABLAS"
if [ "$FALLAS" -eq 0 ]; then
    echo "Resultado: respaldo correcto"
else
    echo "Resultado: $FALLAS comprobaciones con falla"
fi
exit "$FALLAS"
