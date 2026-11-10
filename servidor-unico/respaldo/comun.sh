#!/bin/bash
# Funciones comunes de los scripts de respaldo
DIR_RESPALDOS=/respaldos
LOG="$DIR_RESPALDOS/respaldos.log"
ESTADO="$DIR_RESPALDOS/.ultimo_estado"

log() {
    local linea
    linea="$(date '+%F %T') [respaldo] $*"
    echo "$linea"
    echo "$linea" >> "$LOG" 2>/dev/null || true
}

# Archivo de opciones del cliente de MySQL: así la contraseña no queda a la vista en la lista de procesos
opciones_mysql() {
    local cnf
    cnf=$(mktemp)
    chmod 600 "$cnf"
    printf '[client]\nhost=%s\nuser=%s\npassword=%s\ndefault-character-set=utf8mb4\n' \
        "${DB_HOST:-bd}" "${DB_USER:-respaldo}" "${DB_PASS:?Falta DB_PASS}" > "$cnf"
    echo "$cnf"
}

ultimo_respaldo() {
    ls -1t "$DIR_RESPALDOS"/sigeru_*.tar.gz 2>/dev/null | head -n 1
}
