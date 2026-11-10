#!/bin/bash
# =====================================================================
# Módulo: gestión de usuarios del sistema operativo
# =====================================================================

# Usuarios que el script nunca modifica ni borra
USUARIOS_PROTEGIDOS="root"

listar_usuarios() {
    titulo "Usuarios del sistema (UID >= 1000)"
    printf "%-16s %-6s %-26s %-12s %s\n" "USUARIO" "UID" "NOMBRE" "ESTADO" "GRUPOS"
    while IFS=: read -r nombre _ uid _ comentario _ _; do
        if [ "$uid" -ge 1000 ] && [ "$uid" -lt 60000 ]; then
            local estado="activo"
            if passwd -S "$nombre" 2>/dev/null | grep -qE ' (L|LK) '; then
                estado="bloqueado"
            fi
            printf "%-16s %-6s %-26s %-12s %s\n" "$nombre" "$uid" "${comentario:0:25}" "$estado" "$(id -nG "$nombre" | tr ' ' ',')"
        fi
    done < /etc/passwd
}

pedir_usuario_existente() {
    preguntar "Nombre del usuario" USUARIO
    if ! id "$USUARIO" >/dev/null 2>&1; then
        error "El usuario '$USUARIO' no existe."
        return 1
    fi
}

usuario_protegido() {
    if [[ " $USUARIOS_PROTEGIDOS " == *" $1 "* ]] || [ "$1" = "${SUDO_USER:-}" ]; then
        error "El usuario '$1' no se puede modificar desde aquí (es root o es el usuario que está usando el script)."
        return 0
    fi
    return 1
}

crear_usuario() {
    titulo "Crear usuario"
    local nombre completo grupos shell
    preguntar "Nombre de usuario (minúsculas, sin espacios)" nombre
    if ! nombre_valido "$nombre"; then
        error "Nombre no válido. Use minúsculas, números, '-' o '_' y empiece con una letra."
        return
    fi
    if id "$nombre" >/dev/null 2>&1; then
        error "Ya existe un usuario '$nombre'."
        return
    fi
    preguntar "Nombre completo" completo
    preguntar "Grupos adicionales separados por coma (ej. wheel,sigeru-ssh) o vacío" grupos ""
    preguntar "Shell" shell "/bin/bash"

    for g in ${grupos//,/ }; do
        if ! getent group "$g" >/dev/null; then
            error "El grupo '$g' no existe. Créelo primero en Gestión de grupos."
            return
        fi
    done

    if [ -n "$grupos" ]; then
        useradd -m -c "$completo" -s "$shell" -G "$grupos" "$nombre"
    else
        useradd -m -c "$completo" -s "$shell" "$nombre"
    fi || { error "No se pudo crear el usuario."; return; }

    echo "Ingrese la contraseña inicial (el usuario deberá cambiarla en su primer ingreso):"
    local intentos=1
    until passwd "$nombre"; do
        if [ "$intentos" -ge 3 ]; then
            aviso "No se asignó contraseña: la cuenta queda bloqueada hasta asignarla (opción 5)."
            break
        fi
        intentos=$((intentos + 1))
        aviso "La contraseña no cumple la política. Intente de nuevo."
    done
    # política de vencimiento: cambio cada 90 días, aviso 7 días antes; cambio obligatorio al primer ingreso
    chage -M 90 -m 1 -W 7 "$nombre"
    chage -d 0 "$nombre"
    ok "Usuario '$nombre' creado."
    registrar "crear usuario $nombre (grupos: ${grupos:-ninguno})"
}

modificar_usuario() {
    pedir_usuario_existente || return
    usuario_protegido "$USUARIO" && return
    mostrar_menu "Modificar a $USUARIO" "Agregar a un grupo" "Quitar de un grupo" "Cambiar nombre completo" "Cambiar shell"
    local valor
    case $OPCION in
        1) preguntar "Grupo" valor
           gpasswd -a "$USUARIO" "$valor" && registrar "agregar $USUARIO al grupo $valor" ;;
        2) preguntar "Grupo" valor
           gpasswd -d "$USUARIO" "$valor" && registrar "quitar $USUARIO del grupo $valor" ;;
        3) preguntar "Nombre completo" valor
           usermod -c "$valor" "$USUARIO" && ok "Actualizado." && registrar "cambiar comentario de $USUARIO" ;;
        4) preguntar "Shell (ej. /bin/bash o /sbin/nologin)" valor
           if grep -qx "$valor" /etc/shells || [ "$valor" = "/sbin/nologin" ]; then
               usermod -s "$valor" "$USUARIO" && ok "Shell cambiada." && registrar "cambiar shell de $USUARIO a $valor"
           else
               error "Esa shell no figura en /etc/shells."
           fi ;;
    esac
}

bloquear_usuario() {
    pedir_usuario_existente || return
    usuario_protegido "$USUARIO" && return
    if passwd -S "$USUARIO" | grep -qE ' (L|LK) '; then
        if confirmar "El usuario está bloqueado. ¿Desbloquearlo?"; then
            if usermod -U "$USUARIO" 2>/dev/null && chage -E -1 "$USUARIO"; then
                ok "Usuario desbloqueado."
                registrar "desbloquear usuario $USUARIO"
            else
                error "No se pudo desbloquear: la cuenta no tiene contraseña. Asígnela con 'Cambiar contraseña'."
            fi
        fi
    elif confirmar "¿Bloquear al usuario $USUARIO? (no podrá iniciar sesión)"; then
        if usermod -L "$USUARIO" && chage -E 0 "$USUARIO"; then
            pkill -KILL -u "$USUARIO" 2>/dev/null
            ok "Usuario bloqueado y sesiones cerradas."
            registrar "bloquear usuario $USUARIO"
        else
            error "No se pudo bloquear al usuario."
        fi
    fi
}

cambiar_clave() {
    pedir_usuario_existente || return
    passwd "$USUARIO" || return
    if confirmar "¿Obligar a cambiarla en el próximo ingreso?"; then
        chage -d 0 "$USUARIO"
    fi
    registrar "cambiar contraseña de $USUARIO"
}

eliminar_usuario() {
    pedir_usuario_existente || return
    usuario_protegido "$USUARIO" && return
    if [ "$USUARIO" = "$USUARIO_ADMIN" ] || [ "$USUARIO" = "$USUARIO_RESPALDO" ]; then
        error "'$USUARIO' es un usuario del proyecto y no se elimina desde aquí."
        return
    fi
    confirmar "¿Eliminar definitivamente al usuario $USUARIO?" || return
    local hogar respaldo
    hogar=$(getent passwd "$USUARIO" | cut -d: -f6)
    if [ -d "$hogar" ]; then
        mkdir -p "$DIR_RESPALDOS_LOCAL/usuarios"
        respaldo="$DIR_RESPALDOS_LOCAL/usuarios/${USUARIO}_$(date +%Y%m%d_%H%M%S).tar.gz"
        tar -czf "$respaldo" -C "$(dirname "$hogar")" "$(basename "$hogar")" && ok "Carpeta personal respaldada en $respaldo"
    fi
    pkill -KILL -u "$USUARIO" 2>/dev/null
    userdel -r "$USUARIO" && ok "Usuario eliminado."
    registrar "eliminar usuario $USUARIO (respaldo: ${respaldo:-sin carpeta})"
}

detalle_usuario() {
    pedir_usuario_existente || return
    titulo "Detalle de $USUARIO"
    id "$USUARIO"
    getent passwd "$USUARIO"
    echo
    chage -l "$USUARIO"
    echo
    echo "Últimos ingresos:"
    last -n 5 "$USUARIO" 2>/dev/null | head -n 5
}

agregar_clave_ssh() {
    pedir_usuario_existente || return
    local clave hogar archivo temporal
    echo "Pegue la clave pública (una línea que empieza con ssh-ed25519 o ssh-rsa):"
    read -r clave
    temporal=$(mktemp)
    echo "$clave" > "$temporal"
    if ! ssh-keygen -l -f "$temporal" >/dev/null 2>&1; then
        error "La clave no es válida."
        rm -f "${temporal:?}"
        return
    fi
    hogar=$(getent passwd "$USUARIO" | cut -d: -f6)
    archivo="$hogar/.ssh/authorized_keys"
    install -d -m 700 -o "$USUARIO" -g "$(id -gn "$USUARIO")" "$hogar/.ssh"
    if grep -qF "$clave" "$archivo" 2>/dev/null; then
        aviso "Esa clave ya estaba cargada."
    else
        echo "$clave" >> "$archivo"
        chown "$USUARIO":"$(id -gn "$USUARIO")" "$archivo"
        chmod 600 "$archivo"
        restorecon -R "$hogar/.ssh" 2>/dev/null
        ok "Clave agregada: $(ssh-keygen -l -f "$temporal")"
        registrar "agregar clave SSH a $USUARIO"
    fi
    rm -f "${temporal:?}"
}

menu_usuarios() {
    while true; do
        mostrar_menu "Gestión de usuarios" "Listar usuarios" "Crear usuario" "Modificar usuario" "Bloquear / desbloquear" \
            "Cambiar contraseña" "Eliminar usuario" "Ver detalle de un usuario" "Agregar clave pública SSH" "Usuarios conectados ahora"
        case $OPCION in
            1) listar_usuarios ;;
            2) crear_usuario ;;
            3) modificar_usuario ;;
            4) bloquear_usuario ;;
            5) cambiar_clave ;;
            6) eliminar_usuario ;;
            7) detalle_usuario ;;
            8) agregar_clave_ssh ;;
            9) titulo "Usuarios conectados"; w ;;
            0) return ;;
            *) error "Opción no válida." ;;
        esac
        pausa
    done
}
