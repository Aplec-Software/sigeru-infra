#!/bin/bash
# =====================================================================
# Funciones comunes que usan todos los módulos del script.
# =====================================================================

# Valores por defecto (se pueden cambiar en /etc/sigeru/sigeru.conf)
ROL=app
INTERFAZ_INTERNA=enp0s8
RED_INTERNA=192.168.56.0/24
IP_APP=192.168.56.10
IP_BD=192.168.56.20
IP_RESPALDO=192.168.56.30
NOMBRE_APP=sigeru-app
NOMBRE_BD=sigeru-bd
NOMBRE_RESPALDO=sigeru-respaldo
USUARIO_ADMIN=aplecadmin
PUERTO_SSH=22
DIR_SIGERU=/opt/aplec/sigeru
DIR_RESPALDOS_LOCAL=/var/backups/sigeru
DIR_RESPALDOS_REMOTO=/srv/respaldos/sigeru
USUARIO_RESPALDO=respaldo
DIAS_RESPALDO_LOCAL=7
DIAS_RESPALDO_REMOTO=30
DIAS_LOGS_APLICACIONES=60
PHP_MINIMO=8.3.36            # versión mínima de PHP sin vulnerabilidades conocidas (php2shell, 10/2026)
GITHUB_ORG=https://github.com/Aplec-Software

ARCHIVO_CONF=/etc/sigeru/sigeru.conf
DIR_LOGS=/var/log/sigeru
LOG_ADMIN="$DIR_LOGS/admin.log"
CLAVE_RESPALDOS=/etc/sigeru/clave_respaldos

if [ -f "$ARCHIVO_CONF" ]; then
    # shellcheck source=/dev/null
    source "$ARCHIVO_CONF"
fi

# Colores (solo si la salida es una terminal)
if [ -t 1 ]; then
    ROJO='\e[31m'; VERDE='\e[32m'; AMARILLO='\e[33m'; AZUL='\e[36m'; NEGRITA='\e[1m'; NORMAL='\e[0m'
else
    ROJO=''; VERDE=''; AMARILLO=''; AZUL=''; NEGRITA=''; NORMAL=''
fi

titulo() {
    echo
    echo -e "${AZUL}${NEGRITA}=== $1 ===${NORMAL}"
}

ok()      { echo -e "${VERDE}[OK]${NORMAL} $1"; }
aviso()   { echo -e "${AMARILLO}[AVISO]${NORMAL} $1"; }
error()   { echo -e "${ROJO}[ERROR]${NORMAL} $1" >&2; }

# Registra una acción en el log del script: fecha, usuario que la hizo y detalle
registrar() {
    mkdir -p "$DIR_LOGS"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$(hostname -s)] ${SUDO_USER:-$(id -un)}: $1" >> "$LOG_ADMIN"
}

pausa() {
    echo
    read -rp "Presione Enter para continuar..." _
}

# confirmar "¿Seguro?" -> devuelve 0 solo si se responde s/S
confirmar() {
    local respuesta
    read -rp "$1 [s/N]: " respuesta
    [[ "$respuesta" =~ ^[sS]$ ]]
}

# preguntar "Texto" VARIABLE [valor_por_defecto]
preguntar() {
    local texto=$1 variable=$2 defecto=${3:-} valor
    if [ -n "$defecto" ]; then
        read -rp "$texto [$defecto]: " valor
        valor=${valor:-$defecto}
    else
        read -rp "$texto: " valor
    fi
    printf -v "$variable" '%s' "$valor"
}

verificar_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Este script se debe ejecutar como root (por ejemplo: sudo sigeru-admin)."
        exit 1
    fi
}

# Comprueba que este servidor tenga el rol pedido antes de hacer algo específico
requiere_rol() {
    if [ "$ROL" != "$1" ]; then
        aviso "Esta opción es para el servidor de rol '$1' y este servidor es '$ROL'."
        return 1
    fi
}

comando_existe() {
    command -v "$1" >/dev/null 2>&1
}

# Validaciones de datos ingresados
nombre_valido() {   # usuarios y grupos: minúsculas, números, guiones; empieza con letra
    [[ "$1" =~ ^[a-z][a-z0-9_-]{1,30}$ ]]
}

ip_valida() {
    local ip=$1 parte
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -ra partes <<< "$ip"
    for parte in "${partes[@]}"; do
        [ "$parte" -le 255 ] || return 1
    done
}

puerto_valido() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

# Genera una contraseña aleatoria (solo letras y números para evitar problemas al reemplazar)
clave_aleatoria() {
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "${1:-24}"
}

estado_servicio() {
    if systemctl is-active --quiet "$1"; then
        echo -e "  $1: ${VERDE}activo${NORMAL}"
    else
        echo -e "  $1: ${ROJO}inactivo${NORMAL}"
    fi
}

# Muestra un menú numerado y deja la opción elegida en OPCION
mostrar_menu() {
    local titulo_menu=$1
    shift
    titulo "$titulo_menu"
    local i=1
    for item in "$@"; do
        echo "  $i) $item"
        i=$((i + 1))
    done
    echo "  0) Volver"
    read -rp "Opción: " OPCION
}
