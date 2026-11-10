#!/bin/bash
# =====================================================================
# Restaura un respaldo .tar.gz de la carpeta respaldos/.
#   bash restaurar.sh                      el último respaldo, en la base de prueba sigeru_prueba
#   bash restaurar.sh <archivo.tar.gz>     ese respaldo, en sigeru_prueba
#   bash restaurar.sh <archivo.tar.gz> --real
#                                       ese respaldo sobre la base en uso (sigeru); antes
#                                       hace un respaldo de seguridad y pide confirmación
# Restaurar en sigeru_prueba sirve para probar un respaldo sin tocar los datos en uso.
# =====================================================================
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

ARCHIVO=${1:-$(ls -1t respaldos/sigeru_*.tar.gz 2>/dev/null | head -n 1)}
DESTINO=sigeru_prueba
[ "${2:-}" = "--real" ] && DESTINO=sigeru
[ -n "$ARCHIVO" ] || { echo "No hay respaldos en respaldos/"; exit 1; }
[ -f "$ARCHIVO" ] || ARCHIVO="respaldos/$ARCHIVO"
[ -f "$ARCHIVO" ] || { echo "No existe el archivo $ARCHIVO"; exit 1; }

echo "Respaldo: $ARCHIVO"
echo "Base de destino: $DESTINO"
docker exec sigeru-respaldo verificar "$(basename "$ARCHIVO")"

if [ "$DESTINO" = "sigeru" ]; then
    read -r -p "Esto reemplaza los datos en uso por los del respaldo. Escribir SI para seguir: " respuesta
    [ "$respuesta" = "SI" ] || { echo "Cancelado."; exit 1; }
    echo "Respaldo de seguridad de la base actual:"
    docker exec sigeru-respaldo respaldar
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
tar -xzf "$ARCHIVO" -C "$TMP" sigeru.sql MANIFIESTO.txt

# root solo puede entrar desde dentro del contenedor bd; la contraseña no pasa por la línea de comandos
mysql_root() {
    docker exec -i sigeru-bd sh -c 'f=$(mktemp); printf "[client]\nuser=root\npassword=%s\ndefault-character-set=utf8mb4\n" "$MYSQL_ROOT_PASSWORD" > "$f";
        mysql --defaults-extra-file="$f" "$@"; r=$?; rm -f "$f"; exit $r' sh "$@"
}

if [ "$DESTINO" = "sigeru_prueba" ]; then
    mysql_root -e "DROP DATABASE IF EXISTS sigeru_prueba; CREATE DATABASE sigeru_prueba CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
fi
echo "Cargando el volcado en $DESTINO..."
mysql_root "$DESTINO" < "$TMP/sigeru.sql"

echo
echo "Comparación de filas por tabla (respaldo / base restaurada):"
DIFERENCIAS=0
while read -r tabla filas; do
    # < /dev/null: si no, docker exec -i se come el resto de la lista y solo se compara la primera tabla (D-24)
    actual=$(mysql_root -N -B "$DESTINO" -e "SELECT COUNT(*) FROM \`$tabla\`" < /dev/null 2>/dev/null || echo "?")
    marca="OK"
    [ "$actual" = "$filas" ] || { marca="DISTINTO"; DIFERENCIAS=$((DIFERENCIAS + 1)); }
    printf '  %-24s %8s %8s  %s\n' "$tabla" "$filas" "$actual" "$marca"
done < <(sed -n '/^Filas por tabla:/,$p' "$TMP/MANIFIESTO.txt" | tail -n +2)

if [ "$DIFERENCIAS" -eq 0 ]; then
    echo "Restauración correcta en $DESTINO."
else
    echo "Hay $DIFERENCIAS tablas con diferencias."
    exit 1
fi
