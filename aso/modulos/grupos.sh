#!/bin/bash
# =====================================================================
# Módulo: gestión de grupos
# =====================================================================

# Grupos que usa el proyecto:
#   wheel       -> administradores (pueden usar sudo)
#   sigeru-ssh  -> únicos usuarios habilitados a entrar por SSH
#   docker      -> pueden administrar los contenedores (solo servidor de aplicaciones)
#   sigeru-logs -> pueden leer los logs de las aplicaciones (consulta, sin ser administradores)
GRUPOS_PROYECTO="sigeru-ssh sigeru-logs"
GRUPOS_PROTEGIDOS="root wheel docker sigeru-ssh sigeru-logs"

listar_grupos() {
    titulo "Grupos (GID >= 1000 y grupos del proyecto)"
    printf "%-16s %-6s %s\n" "GRUPO" "GID" "MIEMBROS"
    while IFS=: read -r nombre _ gid miembros; do
        if [ "$gid" -ge 1000 ] && [ "$gid" -lt 60000 ] || [[ " $GRUPOS_PROTEGIDOS " == *" $nombre "* ]]; then
            printf "%-16s %-6s %s\n" "$nombre" "$gid" "${miembros:--}"
        fi
    done < /etc/group
}

crear_grupo() {
    local nombre
    preguntar "Nombre del grupo" nombre
    if ! nombre_valido "$nombre"; then
        error "Nombre no válido."
        return
    fi
    if getent group "$nombre" >/dev/null; then
        error "El grupo ya existe."
        return
    fi
    groupadd "$nombre" && ok "Grupo '$nombre' creado." && registrar "crear grupo $nombre"
}

eliminar_grupo() {
    local nombre gid
    preguntar "Nombre del grupo" nombre
    if ! getent group "$nombre" >/dev/null; then
        error "El grupo no existe."
        return
    fi
    if [[ " $GRUPOS_PROTEGIDOS " == *" $nombre "* ]]; then
        error "'$nombre' es un grupo del sistema o del proyecto y no se elimina."
        return
    fi
    gid=$(getent group "$nombre" | cut -d: -f3)
    if awk -F: -v g="$gid" '$4 == g { encontrado = 1 } END { exit !encontrado }' /etc/passwd; then
        error "Es el grupo principal de algún usuario; no se puede eliminar."
        return
    fi
    confirmar "¿Eliminar el grupo $nombre?" || return
    groupdel "$nombre" && ok "Grupo eliminado." && registrar "eliminar grupo $nombre"
}

miembro_grupo() {
    local accion=$1 usuario grupo
    preguntar "Usuario" usuario
    preguntar "Grupo" grupo
    if ! id "$usuario" >/dev/null 2>&1 || ! getent group "$grupo" >/dev/null; then
        error "El usuario o el grupo no existen."
        return
    fi
    if [ "$accion" = "agregar" ]; then
        gpasswd -a "$usuario" "$grupo" && registrar "agregar $usuario al grupo $grupo"
    else
        gpasswd -d "$usuario" "$grupo" && registrar "quitar $usuario del grupo $grupo"
    fi
    aviso "El cambio se aplica en el próximo inicio de sesión del usuario."
}

ver_miembros() {
    local grupo
    preguntar "Grupo" grupo
    if ! getent group "$grupo" >/dev/null; then
        error "El grupo no existe."
        return
    fi
    titulo "Miembros de $grupo"
    getent group "$grupo" | cut -d: -f4 | tr ',' '\n' | sed '/^$/d'
    # también los que lo tienen como grupo principal
    local gid
    gid=$(getent group "$grupo" | cut -d: -f3)
    awk -F: -v g="$gid" '$4 == g { print $1 " (grupo principal)" }' /etc/passwd
}

crear_grupos_proyecto() {
    for g in $GRUPOS_PROYECTO; do
        if getent group "$g" >/dev/null; then
            echo "  $g: ya existe"
        else
            groupadd "$g" && ok "Grupo $g creado" && registrar "crear grupo $g"
        fi
    done
}

menu_grupos() {
    while true; do
        mostrar_menu "Gestión de grupos" "Listar grupos" "Crear grupo" "Eliminar grupo" "Agregar usuario a un grupo" \
            "Quitar usuario de un grupo" "Ver miembros de un grupo" "Crear los grupos del proyecto"
        case $OPCION in
            1) listar_grupos ;;
            2) crear_grupo ;;
            3) eliminar_grupo ;;
            4) miembro_grupo agregar ;;
            5) miembro_grupo quitar ;;
            6) ver_miembros ;;
            7) crear_grupos_proyecto ;;
            0) return ;;
            *) error "Opción no válida." ;;
        esac
        pausa
    done
}
