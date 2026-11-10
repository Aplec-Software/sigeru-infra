#!/bin/bash
# =====================================================================
# Módulo: gestión de redes (NetworkManager / nmcli)
# =====================================================================

ip_de_este_rol() {
    case $ROL in
        app) echo "$IP_APP" ;;
        bd) echo "$IP_BD" ;;
        respaldo) echo "$IP_RESPALDO" ;;
    esac
}

nombre_de_este_rol() {
    case $ROL in
        app) echo "$NOMBRE_APP" ;;
        bd) echo "$NOMBRE_BD" ;;
        respaldo) echo "$NOMBRE_RESPALDO" ;;
    esac
}

ver_configuracion_red() {
    titulo "Configuración de red de $(hostname)"
    echo "Interfaces:"
    ip -brief address
    echo
    echo "Rutas:"
    ip route
    echo
    echo "Servidores DNS:"
    grep '^nameserver' /etc/resolv.conf
    echo
    echo "Conexiones de NetworkManager:"
    nmcli -f NAME,DEVICE,TYPE,STATE connection show
}

configurar_ip_estatica() {
    titulo "IP estática de la red interna"
    local interfaz ip prefijo conexion
    echo "Interfaces disponibles:"
    nmcli -f DEVICE,TYPE,STATE device status | grep ethernet
    preguntar "Interfaz de la red interna" interfaz "$INTERFAZ_INTERNA"
    if ! nmcli device show "$interfaz" >/dev/null 2>&1; then
        error "La interfaz $interfaz no existe."
        return
    fi
    preguntar "Dirección IP" ip "$(ip_de_este_rol)"
    ip_valida "$ip" || { error "IP no válida."; return; }
    preguntar "Prefijo de red" prefijo "${RED_INTERNA#*/}"

    conexion=$(nmcli -g GENERAL.CONNECTION device show "$interfaz")
    if [ -z "$conexion" ]; then
        conexion="sigeru-interna"
        nmcli connection add type ethernet ifname "$interfaz" con-name "$conexion" >/dev/null
    fi
    # sin puerta de enlace: la salida a Internet es por el adaptador NAT
    nmcli connection modify "$conexion" ipv4.method manual ipv4.addresses "$ip/$prefijo" \
        ipv4.gateway "" ipv4.never-default yes ipv6.method disabled connection.autoconnect yes
    if nmcli connection up "$conexion" >/dev/null; then
        ok "Interfaz $interfaz configurada con $ip/$prefijo (conexión '$conexion')."
        registrar "configurar IP estática $ip/$prefijo en $interfaz"
    else
        error "No se pudo activar la conexión. Revise con: nmcli connection show \"$conexion\""
    fi
}

cambiar_nombre_servidor() {
    local nombre
    preguntar "Nuevo nombre del servidor" nombre "$(nombre_de_este_rol)"
    if [[ ! "$nombre" =~ ^[a-z0-9-]{2,40}$ ]]; then
        error "Use minúsculas, números y guiones."
        return
    fi
    hostnamectl set-hostname "$nombre" && ok "Nombre cambiado a $nombre." && registrar "cambiar hostname a $nombre"
}

configurar_hosts() {
    titulo "Agregando los servidores de SiGeRU a /etc/hosts"
    cp /etc/hosts "/etc/hosts.bak.$(date +%Y%m%d%H%M%S)"
    sed -i '/# SiGeRU$/d' /etc/hosts
    {
        echo "$IP_APP   $NOMBRE_APP sigeru.local   # SiGeRU"
        echo "$IP_BD   $NOMBRE_BD   # SiGeRU"
        echo "$IP_RESPALDO   $NOMBRE_RESPALDO   # SiGeRU"
    } >> /etc/hosts
    grep 'SiGeRU' /etc/hosts
    ok "Listo (copia anterior guardada como /etc/hosts.bak.*)."
    registrar "actualizar /etc/hosts"
}

probar_conectividad() {
    titulo "Prueba de conectividad"
    local destino
    for destino in "$NOMBRE_APP:$IP_APP" "$NOMBRE_BD:$IP_BD" "$NOMBRE_RESPALDO:$IP_RESPALDO"; do
        if ping -c 2 -W 2 "${destino#*:}" >/dev/null 2>&1; then
            ok "${destino%%:*} (${destino#*:}) responde"
        else
            error "${destino%%:*} (${destino#*:}) no responde"
        fi
    done
    if ping -c 2 -W 2 1.1.1.1 >/dev/null 2>&1; then ok "Salida a Internet"; else error "Sin salida a Internet"; fi
    if getent hosts github.com >/dev/null; then ok "Resolución de nombres (DNS)"; else error "No resuelve nombres (DNS)"; fi
    if [ "$ROL" = "app" ]; then
        if timeout 3 bash -c "echo > /dev/tcp/$IP_BD/3306" 2>/dev/null; then
            ok "Puerto 3306 de la base de datos accesible"
        else
            error "No se llega al puerto 3306 de $IP_BD"
        fi
    fi
}

menu_redes() {
    while true; do
        mostrar_menu "Gestión de redes" "Ver configuración de red" "Configurar IP estática (red interna)" "Cambiar nombre del servidor" \
            "Agregar los servidores a /etc/hosts" "Probar conectividad" "Puertos en escucha" "Conexiones establecidas"
        case $OPCION in
            1) ver_configuracion_red ;;
            2) configurar_ip_estatica ;;
            3) cambiar_nombre_servidor ;;
            4) configurar_hosts ;;
            5) probar_conectividad ;;
            6) titulo "Puertos en escucha"; ss -tulpn ;;
            7) titulo "Conexiones TCP establecidas"; ss -tnp state established ;;
            0) return ;;
            *) error "Opción no válida." ;;
        esac
        pausa
    done
}
