#!/bin/bash
# =====================================================================
# Módulo: gestión de logs del sistema y de SiGeRU
# =====================================================================

DIR_LOGS_APPS="$DIR_LOGS/aplicaciones"

servicios_del_rol() {
    case $ROL in
        app) echo "sshd firewalld fail2ban docker crond chronyd" ;;
        bd) echo "sshd firewalld fail2ban mysqld crond chronyd" ;;
        respaldo) echo "sshd firewalld fail2ban crond chronyd" ;;
    esac
}

log_de_servicio() {
    local servicio
    echo "Servicios de este servidor: $(servicios_del_rol)"
    preguntar "Servicio" servicio sshd
    journalctl -u "$servicio" -n 60 --no-pager
}

accesos_ssh() {
    titulo "Intentos de acceso SSH fallidos (últimos 30)"
    journalctl -u sshd --no-pager --since "-7 days" | grep -E 'Failed password|Invalid user|authentication failure' | tail -n 30
    echo
    echo "Cantidad de intentos fallidos por IP (últimos 7 días):"
    journalctl -u sshd --no-pager --since "-7 days" | grep -oE 'from ([0-9]{1,3}\.){3}[0-9]{1,3}' | awk '{print $2}' | sort | uniq -c | sort -rn | head
    echo
    titulo "Últimos ingresos correctos"
    last -n 15 -a
}

errores_del_dia() {
    titulo "Errores registrados hoy (journald, prioridad err o mayor)"
    journalctl -p err --since today --no-pager | tail -n 60
}

logs_aplicaciones() {
    requiere_rol app || return
    titulo "Logs de las aplicaciones ($DIR_LOGS_APPS)"
    ls -lh "$DIR_LOGS_APPS" 2>/dev/null | tail -n 20
    local api
    preguntar "Ver el log de hoy de (api-usuarios / api-gestion / api-recoleccion) o Enter para salir" api ""
    [ -z "$api" ] && return
    local archivo="$DIR_LOGS_APPS/$api-$(date +%F).log"
    if [ -f "$archivo" ]; then
        tail -n 50 "$archivo"
        echo
        echo "Errores de hoy: $(grep -c ' ERROR: ' "$archivo")   Accesos: $(grep -c ' ACCESO: ' "$archivo")"
    else
        aviso "No hay log de hoy para $api."
    fi
}

errores_aplicaciones() {
    requiere_rol app || return
    titulo "Errores de las APIs (últimos 7 días)"
    find "$DIR_LOGS_APPS" -name '*.log' -mtime -7 -exec grep -h ' ERROR: ' {} + 2>/dev/null | tail -n 40
    echo
    echo "Respuestas con error por código HTTP (hoy):"
    cat "$DIR_LOGS_APPS"/*-"$(date +%F)".log 2>/dev/null | grep ' ACCESO: ' | awk '{print $8}' | grep -E '^[45][0-9]{2}$' | sort | uniq -c
}

log_mysql() {
    requiere_rol bd || return
    titulo "Log de MySQL"
    tail -n 40 /var/log/mysql/mysqld.log 2>/dev/null
    if [ -f /var/log/mysql/mysql-slow.log ]; then
        echo
        echo "Consultas lentas registradas: $(grep -c '^# Query_time' /var/log/mysql/mysql-slow.log)"
    fi
}

buscar_en_logs() {
    local texto
    preguntar "Texto a buscar" texto
    [ -z "$texto" ] && return
    titulo "Coincidencias en $DIR_LOGS"
    grep -rin -- "$texto" "$DIR_LOGS" 2>/dev/null | tail -n 30
    titulo "Coincidencias en journald (últimos 3 días)"
    journalctl --since "-3 days" --no-pager --grep "$texto" 2>/dev/null | tail -n 30
}

limpiar_logs() {
    titulo "Limpieza de logs viejos"
    local borrados=0
    if [ -d "$DIR_LOGS_APPS" ]; then
        borrados=$(find "$DIR_LOGS_APPS" -name '*.log' -mtime +"$DIAS_LOGS_APLICACIONES" -print -delete | wc -l)
    fi
    echo "Logs de aplicaciones borrados (más de $DIAS_LOGS_APLICACIONES días): $borrados"
    journalctl --vacuum-time=90d
    registrar "limpiar logs (aplicaciones borrados: $borrados)"
}

menu_logs() {
    while true; do
        mostrar_menu "Gestión de logs" "Log de este script (acciones de administración)" "Accesos SSH (fallidos y correctos)" \
            "Log de un servicio" "Errores del sistema de hoy" "Logs de las APIs" "Errores de las APIs" \
            "Logs de un contenedor" "Log de MySQL" "Log de respaldos e integridad (AIDE)" "Buscar un texto en los logs" "Borrar logs viejos"
        case $OPCION in
            1) titulo "Últimas acciones"; tail -n 40 "$LOG_ADMIN" 2>/dev/null ;;
            2) accesos_ssh ;;
            3) log_de_servicio ;;
            4) errores_del_dia ;;
            5) logs_aplicaciones ;;
            6) errores_aplicaciones ;;
            7) requiere_rol app && logs_contenedor ;;
            8) log_mysql ;;
            9) titulo "Respaldos"; tail -n 40 "$DIR_LOGS/respaldos.log" 2>/dev/null
               titulo "Último control de integridad (AIDE)"; tail -n 25 "$DIR_LOGS/aide.log" 2>/dev/null ;;
            10) buscar_en_logs ;;
            11) limpiar_logs ;;
            0) return ;;
            *) error "Opción no válida." ;;
        esac
        pausa
    done
}
