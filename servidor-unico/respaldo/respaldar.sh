#!/bin/bash
# =====================================================================
# Genera un respaldo de la base sigeru:
#   mysqldump (copia consistente, sin detener el servicio)
#   + MANIFIESTO.txt (fecha, versión de MySQL y filas por tabla)
#   -> sigeru_AAAAMMDD_HHMMSS.tar.gz y su suma SHA-256 (.sha256)
# Después lo verifica y aplica la retención de RESPALDO_DIAS días.
# =====================================================================
set -o pipefail
# shellcheck source=comun.sh
source /usr/local/lib/sigeru-respaldo-comun.sh

BASE=${DB_NAME:-sigeru}
FECHA=$(date +%Y%m%d_%H%M%S)
NOMBRE="sigeru_${FECHA}"
TRABAJO=$(mktemp -d)
CNF=$(opciones_mysql)
trap 'rm -rf "$TRABAJO" "$CNF"' EXIT

mkdir -p "$DIR_RESPALDOS"

# --single-transaction: foto consistente de las tablas InnoDB sin bloquearlas
if ! mysqldump --defaults-extra-file="$CNF" --single-transaction --no-tablespaces --triggers \
        --set-gtid-purged=OFF --hex-blob "$BASE" > "$TRABAJO/sigeru.sql" 2> "$TRABAJO/error.txt"; then
    log "ERROR: falló mysqldump: $(tr '\n' ' ' < "$TRABAJO/error.txt")"
    echo "error $(date '+%F %T') mysqldump" > "$ESTADO"
    exit 1
fi

{
    echo "Respaldo de SiGeRU"
    echo "Archivo:        $NOMBRE.tar.gz"
    echo "Fecha:          $(date '+%F %T %z')"
    echo "Base de datos:  $BASE (servidor $DB_HOST, MySQL $(mysql --defaults-extra-file="$CNF" -N -e 'SELECT VERSION()'))"
    echo "SHA-256 del volcado: $(sha256sum "$TRABAJO/sigeru.sql" | cut -d' ' -f1)"
    echo
    echo "Filas por tabla:"
    mysql --defaults-extra-file="$CNF" -N -e \
        "SELECT table_name FROM information_schema.tables WHERE table_schema = '$BASE' AND table_type = 'BASE TABLE' ORDER BY table_name" \
    | while read -r tabla; do
        printf '  %-24s %s\n' "$tabla" "$(mysql --defaults-extra-file="$CNF" -N -e "SELECT COUNT(*) FROM \`$BASE\`.\`$tabla\`")"
    done
} > "$TRABAJO/MANIFIESTO.txt"

# Se arma con otro nombre y se renombra al final: nunca queda un .tar.gz a medias
if ! tar -czf "$DIR_RESPALDOS/.$NOMBRE.tmp" -C "$TRABAJO" sigeru.sql MANIFIESTO.txt; then
    rm -f "$DIR_RESPALDOS/.$NOMBRE.tmp"
    log "ERROR: no se pudo crear el archivo .tar.gz"
    echo "error $(date '+%F %T') tar" > "$ESTADO"
    exit 1
fi
mv "$DIR_RESPALDOS/.$NOMBRE.tmp" "$DIR_RESPALDOS/$NOMBRE.tar.gz"
(cd "$DIR_RESPALDOS" && sha256sum "$NOMBRE.tar.gz" > "$NOMBRE.tar.gz.sha256")
log "respaldo creado $NOMBRE.tar.gz ($(du -h --apparent-size "$DIR_RESPALDOS/$NOMBRE.tar.gz" | cut -f1))"

# Verificación inmediata
if verificar "$DIR_RESPALDOS/$NOMBRE.tar.gz" > "$TRABAJO/verificacion.txt"; then
    echo "ok $(date '+%F %T') $NOMBRE.tar.gz" > "$ESTADO"
    log "verificación correcta de $NOMBRE.tar.gz"
else
    cat "$TRABAJO/verificacion.txt"
    echo "error $(date '+%F %T') verificación $NOMBRE.tar.gz" > "$ESTADO"
    log "ERROR: el respaldo $NOMBRE.tar.gz no pasó la verificación"
    exit 1
fi

# Retención: se borran los respaldos de más de RESPALDO_DIAS días (siempre queda el último)
DIAS=${RESPALDO_DIAS:-7}
find "$DIR_RESPALDOS" -maxdepth 1 -name 'sigeru_*.tar.gz' -mtime +"$DIAS" ! -name "$NOMBRE.tar.gz" -print \
| while read -r viejo; do
    rm -f "$viejo" "$viejo.sha256"
    log "retención: se borró $(basename "$viejo") (más de $DIAS días)"
done
exit 0
