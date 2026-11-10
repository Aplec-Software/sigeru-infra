#!/bin/bash
# Lista los respaldos guardados, del más nuevo al más viejo
# shellcheck source=comun.sh
source /usr/local/lib/sigeru-respaldo-comun.sh
if ! ls "$DIR_RESPALDOS"/sigeru_*.tar.gz > /dev/null 2>&1; then
    echo "Todavía no hay respaldos en $DIR_RESPALDOS"
    exit 0
fi
printf '%-34s %8s  %s\n' "Archivo" "Tamaño" "Fecha"
ls -1t "$DIR_RESPALDOS"/sigeru_*.tar.gz | while read -r f; do
    printf '%-34s %8s  %s\n' "$(basename "$f")" "$(du -h --apparent-size "$f" | cut -f1)" "$(date -r "$f" '+%F %T')"
done
[ -f "$ESTADO" ] && echo && echo "Último resultado: $(cat "$ESTADO")"
exit 0
