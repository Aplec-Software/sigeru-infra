#!/bin/bash
# =====================================================================
# Módulo: gestión del firewall (firewalld) y de fail2ban
# =====================================================================

firewall_activo() {
    if ! systemctl is-active --quiet firewalld; then
        error "firewalld no está activo. Inícielo con: systemctl enable --now firewalld"
        return 1
    fi
}

ver_reglas() {
    firewall_activo || return
    titulo "Reglas del firewall"
    echo "Zona por defecto: $(firewall-cmd --get-default-zone)"
    firewall-cmd --list-all
}

abrir_o_cerrar() {
    firewall_activo || return
    local accion=$1 tipo valor
    preguntar "¿Servicio (ej. https) o puerto (ej. 8080/tcp)?" valor
    if [[ "$valor" =~ ^[0-9]+/(tcp|udp)$ ]] && puerto_valido "${valor%/*}"; then
        tipo=port
    elif firewall-cmd --get-services | tr ' ' '\n' | grep -qx "$valor"; then
        tipo=service
    else
        error "'$valor' no es un servicio conocido ni un puerto válido (formato 8080/tcp)."
        return
    fi
    if [ "$accion" = "cerrar" ] && [[ "$valor" == "ssh" || "$valor" == "$PUERTO_SSH/tcp" ]]; then
        confirmar "¡Cuidado! Cerrar SSH puede dejarlo sin acceso remoto. ¿Seguir?" || return
    fi
    if [ "$accion" = "abrir" ]; then
        firewall-cmd --permanent --add-$tipo="$valor"
    else
        firewall-cmd --permanent --remove-$tipo="$valor"
    fi
    firewall-cmd --reload >/dev/null && ok "Regla aplicada: $accion $valor" && registrar "firewall: $accion $valor"
}

# Reglas recomendadas según el rol del servidor
aplicar_reglas_rol() {
    firewall_activo || return
    titulo "Aplicando las reglas para el rol '$ROL'"
    if [ "$PUERTO_SSH" = "22" ]; then
        firewall-cmd --permanent --add-service=ssh >/dev/null
    else
        firewall-cmd --permanent --add-port="$PUERTO_SSH/tcp" >/dev/null
        firewall-cmd --permanent --remove-service=ssh >/dev/null 2>&1
    fi
    # servicios que trae abiertos Rocky por defecto y no se usan
    firewall-cmd --permanent --remove-service=cockpit >/dev/null 2>&1
    firewall-cmd --permanent --remove-service=dhcpv6-client >/dev/null 2>&1
    case $ROL in
        app)
            firewall-cmd --permanent --add-service=http >/dev/null
            firewall-cmd --permanent --add-service=https >/dev/null
            ok "Abiertos: SSH, HTTP (redirige a HTTPS) y HTTPS" ;;
        bd)
            firewall-cmd --permanent --remove-service=mysql >/dev/null 2>&1
            firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"$IP_APP/32\" port port=\"3306\" protocol=\"tcp\" accept" >/dev/null
            ok "Abiertos: SSH y MySQL (3306) solo para $IP_APP" ;;
        respaldo)
            ok "Abierto: solo SSH (los respaldos llegan por SSH)" ;;
    esac
    firewall-cmd --reload >/dev/null
    firewall-cmd --list-all
    registrar "firewall: reglas del rol $ROL aplicadas"
}

bloquear_ip() {
    firewall_activo || return
    local ip
    preguntar "IP a bloquear" ip
    ip_valida "$ip" || { error "IP no válida."; return; }
    if [ "$ip" = "$IP_APP" ] || [ "$ip" = "$IP_BD" ] || [ "$ip" = "$IP_RESPALDO" ]; then
        error "Es la IP de un servidor del proyecto."
        return
    fi
    firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"$ip\" drop" >/dev/null
    firewall-cmd --reload >/dev/null && ok "IP $ip bloqueada." && registrar "firewall: bloquear $ip"
}

desbloquear_ip() {
    firewall_activo || return
    local ip
    echo "IP bloqueadas manualmente:"
    firewall-cmd --list-rich-rules | grep drop || echo "  (ninguna)"
    preguntar "IP a desbloquear" ip
    ip_valida "$ip" || { error "IP no válida."; return; }
    firewall-cmd --permanent --remove-rich-rule="rule family=\"ipv4\" source address=\"$ip\" drop" >/dev/null
    firewall-cmd --reload >/dev/null && ok "IP $ip desbloqueada." && registrar "firewall: desbloquear $ip"
}

estado_fail2ban() {
    titulo "fail2ban (bloqueo automático por intentos fallidos de SSH)"
    if ! systemctl is-active --quiet fail2ban; then
        error "fail2ban no está activo."
        return
    fi
    fail2ban-client status sshd
    local ip
    preguntar "IP a desbloquear de fail2ban o Enter para salir" ip ""
    if [ -n "$ip" ]; then
        fail2ban-client set sshd unbanip "$ip" && registrar "fail2ban: desbloquear $ip"
    fi
}

menu_firewall() {
    while true; do
        mostrar_menu "Gestión del firewall" "Ver reglas actuales" "Abrir un servicio o puerto" "Cerrar un servicio o puerto" \
            "Aplicar las reglas recomendadas para este servidor" "Bloquear una IP" "Desbloquear una IP" "Estado de fail2ban"
        case $OPCION in
            1) ver_reglas ;;
            2) abrir_o_cerrar abrir ;;
            3) abrir_o_cerrar cerrar ;;
            4) aplicar_reglas_rol ;;
            5) bloquear_ip ;;
            6) desbloquear_ip ;;
            7) estado_fail2ban ;;
            0) return ;;
            *) error "Opción no válida." ;;
        esac
        pausa
    done
}
