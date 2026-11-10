#!/bin/bash
# =====================================================================
# SiGeRU - Script de administración de servidores
# Aplec Software - Proyecto ESI 2026
#
# Uso:  sudo sigeru-admin            (menú interactivo)
#       sudo sigeru-admin estado     (verificación, la usa cron)
#       sudo sigeru-admin ayuda
#
# Cada área está en su propio módulo dentro de modulos/, así se puede
# mantener y probar por separado.
# =====================================================================

DIR_ASO="$(dirname "$(readlink -f "$0")")"
VERSION_SCRIPT="1.0.0"

# shellcheck source=modulos/comun.sh
source "$DIR_ASO/modulos/comun.sh"
for modulo in estado usuarios grupos respaldos redes basedatos firewall logs contenedores instalacion; do
    # shellcheck source=/dev/null
    source "$DIR_ASO/modulos/$modulo.sh"
done

uso() {
    echo "SiGeRU - administración del servidor (versión $VERSION_SCRIPT)"
    echo
    echo "  sigeru-admin                     menú interactivo"
    echo "  sigeru-admin estado              verificación del servidor"
    echo "  sigeru-admin respaldo-bd         respaldo de la base de datos (sigeru-bd)"
    echo "  sigeru-admin respaldo-archivos   respaldo de la configuración"
    echo "  sigeru-admin limpiar-logs        borra los logs vencidos de las aplicaciones"
    echo "  sigeru-admin ayuda               esta ayuda"
}

encabezado() {
    clear
    echo -e "${AZUL}${NEGRITA}"
    echo "  ____  _  ____      ____  _   _ "
    echo " / ___|(_)/ ___| ___|  _ \\| | | |"
    echo " \\___ \\| | |  _ / _ \\ |_) | | | |"
    echo "  ___) | | |_| |  __/  _ <| |_| |"
    echo " |____/|_|\\____|\\___|_| \\_\\\\___/ "
    echo -e "${NORMAL}"
    echo "  Administración del servidor - Aplec Software"
    echo "  Servidor: $(hostname)   Rol: $ROL   Fecha: $(date '+%d/%m/%Y %H:%M')"
}

menu_principal() {
    while true; do
        encabezado
        echo
        echo "  1) Verificar el estado del servidor"
        echo "  2) Gestión de usuarios"
        echo "  3) Gestión de grupos"
        echo "  4) Gestión de respaldos"
        echo "  5) Gestión de redes"
        echo "  6) Gestión de la base de datos"
        echo "  7) Gestión del firewall"
        echo "  8) Gestión de logs"
        echo "  9) Gestión de contenedores"
        echo " 10) Instalación y configuración inicial"
        echo "  0) Salir"
        read -rp "Opción: " OPCION_PRINCIPAL
        case $OPCION_PRINCIPAL in
            1) menu_estado ;;
            2) menu_usuarios ;;
            3) menu_grupos ;;
            4) menu_respaldos ;;
            5) menu_redes ;;
            6) menu_basedatos ;;
            7) menu_firewall ;;
            8) menu_logs ;;
            9) menu_contenedores ;;
            10) menu_instalacion ;;
            0) echo "Hasta luego."; exit 0 ;;
            *) error "Opción no válida."; sleep 1 ;;
        esac
    done
}

verificar_root

case "${1:-}" in
    "") registrar "inicio del menú"; menu_principal ;;
    estado) verificar_servidor ;;
    respaldo-bd) exec "$DIR_ASO/respaldo/respaldo_bd.sh" ;;
    respaldo-archivos) exec "$DIR_ASO/respaldo/respaldo_archivos.sh" ;;
    limpiar-logs) limpiar_logs ;;
    ayuda|-h|--help) uso ;;
    *) error "Opción desconocida: $1"; uso; exit 1 ;;
esac
