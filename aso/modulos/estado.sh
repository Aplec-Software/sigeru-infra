#!/bin/bash
# =====================================================================
# Módulo: verificación del estado del servidor
# (versión ampliada del script estado_servidor.sh del curso)
# =====================================================================

verificar_servidor() {
    local SERVIDOR FECHA
    SERVIDOR=$(hostname)
    FECHA=$(date '+%d/%m/%Y %H:%M:%S')

    echo "=== ESTADO DEL SERVIDOR ==="
    echo "Servidor: $SERVIDOR (rol: $ROL)"
    echo "Fecha de ejecución: $FECHA"
    echo "Sistema: $(. /etc/os-release && echo "$PRETTY_NAME")  Núcleo: $(uname -r)"
    echo "Encendido desde: $(uptime -s)   Carga: $(cut -d' ' -f1-3 /proc/loadavg)"
    echo
    echo "=== SERVICIOS ==="
    local servicios="sshd firewalld fail2ban crond chronyd"
    case $ROL in
        app) servicios="$servicios docker" ;;
        bd) servicios="$servicios mysqld" ;;
    esac
    for s in $servicios; do
        estado_servicio "$s"
    done
    echo
    echo "=== RED ==="
    ip -brief address | grep -v '^lo'
    echo
    echo "=== ESPACIO EN DISCO ==="
    df -h -x tmpfs -x devtmpfs
    local uso
    uso=$(df --output=pcent / | tail -n 1 | tr -dc '0-9')
    if [ "$uso" -ge 85 ]; then
        aviso "La partición / está al $uso %"
    fi
    echo
    echo "=== MEMORIA ==="
    free -h
    echo
    echo "=== SEGURIDAD ==="
    echo "SELinux: $(getenforce 2>/dev/null || echo 'no disponible')"
    echo "Usuarios conectados: $(who | wc -l)"
    echo "Intentos de SSH fallidos hoy: $(journalctl -u sshd --since today --no-pager 2>/dev/null | grep -c 'Failed password')"
    if comando_existe fail2ban-client && systemctl is-active --quiet fail2ban; then
        echo "IP bloqueadas por fail2ban: $(fail2ban-client status sshd 2>/dev/null | awk -F: '/Currently banned/ { gsub(/ /, "", $2); print $2 }')"
    fi
    echo "Actualizaciones pendientes: $(dnf -q check-update 2>/dev/null | grep -c '^[a-zA-Z0-9]')"

    case $ROL in
        app)
            echo
            echo "=== CONTENEDORES ==="
            if comando_existe docker && systemctl is-active --quiet docker; then
                docker ps --format 'table {{.Names}}\t{{.Status}}'
                version_php >/dev/null || aviso "Hay contenedores con una versión de PHP vulnerable (Contenedores > Controlar la versión de PHP)."
            fi ;;
        bd)
            echo
            echo "=== BASE DE DATOS ==="
            if systemctl is-active --quiet mysqld && [ -f /root/.my.cnf ]; then
                mysql --defaults-file=/root/.my.cnf -N -e "SELECT CONCAT('Conexiones activas: ', COUNT(*)) FROM information_schema.processlist;"
            fi
            echo "Último respaldo: $(ls -1t "$DIR_RESPALDOS_LOCAL"/bd/*.enc 2>/dev/null | head -n 1 | xargs -r basename)" ;;
        respaldo)
            echo
            echo "=== RESPALDOS RECIBIDOS ==="
            echo "Cantidad: $(find "$DIR_RESPALDOS_REMOTO" -name '*.enc' 2>/dev/null | wc -l)"
            echo "Último: $(find "$DIR_RESPALDOS_REMOTO" -name '*.enc' -printf '%T@ %f\n' 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2)" ;;
    esac
    echo
}

menu_estado() {
    titulo "Verificación del servidor"
    verificar_servidor
    if confirmar "¿Guardar esta verificación en $DIR_LOGS/verificacion_servidor.log?"; then
        verificar_servidor >> "$DIR_LOGS/verificacion_servidor.log" 2>&1
        ok "Agregada al log (no se borran las anteriores)."
    fi
    pausa
}
