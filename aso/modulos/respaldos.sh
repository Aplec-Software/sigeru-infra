#!/bin/bash
# =====================================================================
# Módulo: gestión de respaldos
#
# Estrategia (ver documentación de ASO):
#   - base de datos: respaldo completo diario 02:30 (sigeru-bd)
#   - configuración y archivos: semanal, domingo 03:00 (todos los servidores)
#   - todo se cifra (AES-256) y se copia por SSH al servidor sigeru-respaldo
#   - retención: 7 días en cada servidor, 30 días en sigeru-respaldo y
#     un respaldo por mes durante un año; copia mensual a disco externo
# =====================================================================

CLAVE_SSH_RESPALDO=/root/.ssh/id_respaldo
CRON_SIGERU=/etc/cron.d/sigeru

ssh_respaldo() {
    ssh -i "$CLAVE_SSH_RESPALDO" -p "$PUERTO_SSH" -o BatchMode=yes -o ConnectTimeout=8 "$USUARIO_RESPALDO@$IP_RESPALDO" "$@"
}

generar_clave_cifrado() {
    if [ -f "$CLAVE_RESPALDOS" ]; then
        return
    fi
    install -d -m 700 /etc/sigeru
    openssl rand -base64 48 > "$CLAVE_RESPALDOS"
    chmod 600 "$CLAVE_RESPALDOS"
    aviso "Se generó la clave de cifrado de respaldos en $CLAVE_RESPALDOS."
    aviso "Guarde una copia fuera del servidor: sin ella los respaldos NO se pueden restaurar."
    aviso "Conviene usar la misma clave en sigeru-app y sigeru-bd: copie este archivo al otro servidor (scp)."
}

listar_locales() {
    titulo "Respaldos en este servidor ($DIR_RESPALDOS_LOCAL)"
    find "$DIR_RESPALDOS_LOCAL" -type f -name '*.enc' -printf '%TY-%Tm-%Td %TH:%TM  %8s bytes  %p\n' 2>/dev/null | sort -r | head -n 20
    echo
    du -sh "$DIR_RESPALDOS_LOCAL" 2>/dev/null
}

listar_remotos() {
    if [ "$ROL" = "respaldo" ]; then
        titulo "Respaldos recibidos ($DIR_RESPALDOS_REMOTO)"
        find "$DIR_RESPALDOS_REMOTO" -type f -name '*.enc' -printf '%TY-%Tm-%Td %TH:%TM  %8s bytes  %p\n' | sort -r | head -n 30
        df -h "$DIR_RESPALDOS_REMOTO"
        return
    fi
    titulo "Respaldos en $NOMBRE_RESPALDO"
    ssh_respaldo "ls -lht $DIR_RESPALDOS_REMOTO/bd $DIR_RESPALDOS_REMOTO/archivos | head -n 30" \
        || error "No se pudo conectar. Configure primero la conexión (opción 7)."
}

verificar_integridad() {
    titulo "Verificación de integridad (SHA-256)"
    local base=$DIR_RESPALDOS_LOCAL
    [ "$ROL" = "respaldo" ] && base=$DIR_RESPALDOS_REMOTO
    local bien=0 mal=0 suma
    for suma in "$base"/*/*.sha256; do
        [ -e "$suma" ] || continue
        if (cd "$(dirname "$suma")" && sha256sum -c --quiet "$(basename "$suma")" 2>/dev/null); then
            bien=$((bien + 1))
        else
            mal=$((mal + 1))
            error "Dañado: $suma"
        fi
    done
    echo "Correctos: $bien   Con problemas: $mal"
}

# En sigeru-app y sigeru-bd: clave SSH sin frase para que cron pueda enviar los respaldos
configurar_conexion() {
    if [ "$ROL" = "respaldo" ]; then
        autorizar_servidor
        return
    fi
    titulo "Conexión con el servidor de respaldo"
    if [ ! -f "$CLAVE_SSH_RESPALDO" ]; then
        ssh-keygen -t ed25519 -N "" -C "respaldos@$(hostname -s)" -f "$CLAVE_SSH_RESPALDO" >/dev/null
        ok "Clave SSH creada: $CLAVE_SSH_RESPALDO"
    fi
    echo "Copie esta línea y péguela en $NOMBRE_RESPALDO (sigeru-admin > Respaldos > Autorizar un servidor):"
    echo
    cat "$CLAVE_SSH_RESPALDO.pub"
    echo
    if confirmar "¿Ya la autorizó y quiere probar la conexión?"; then
        if ssh_respaldo "echo conectado" >/dev/null 2>&1; then
            ok "Conexión correcta con $NOMBRE_RESPALDO."
            registrar "conexión de respaldos con $NOMBRE_RESPALDO configurada"
        else
            error "No se pudo conectar. Revise la clave autorizada y el firewall."
        fi
    fi
}

# En sigeru-respaldo: autoriza la clave de un servidor, con restricciones
autorizar_servidor() {
    requiere_rol respaldo || return
    local clave hogar archivo temporal
    echo "Pegue la clave pública que mostró el otro servidor:"
    read -r clave
    temporal=$(mktemp)
    echo "$clave" > "$temporal"
    if ! ssh-keygen -l -f "$temporal" >/dev/null 2>&1; then
        error "Clave no válida."
        rm -f "${temporal:?}"
        return
    fi
    rm -f "${temporal:?}"
    hogar=$(getent passwd "$USUARIO_RESPALDO" | cut -d: -f6)
    archivo="$hogar/.ssh/authorized_keys"
    install -d -m 700 -o "$USUARIO_RESPALDO" -g "$USUARIO_RESPALDO" "$hogar/.ssh"
    # restrict: sin terminal ni reenvíos; from: solo desde la red interna
    echo "restrict,from=\"$RED_INTERNA\" $clave" >> "$archivo"
    chown "$USUARIO_RESPALDO":"$USUARIO_RESPALDO" "$archivo"
    chmod 600 "$archivo"
    restorecon -R "$hogar/.ssh" 2>/dev/null
    ok "Servidor autorizado a enviar respaldos."
    registrar "autorizar clave de respaldos: ${clave##* }"
}

programar_respaldos() {
    titulo "Tareas programadas de SiGeRU ($CRON_SIGERU)"
    local admin="/usr/local/sbin/sigeru-admin"
    {
        echo "# Tareas programadas de SiGeRU (generado por sigeru-admin, rol $ROL)"
        echo "SHELL=/bin/bash"
        echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        echo "# verificación del estado del servidor cada 6 horas"
        echo "0 */6 * * * root $admin estado >> $DIR_LOGS/verificacion_servidor.log 2>&1"
        echo "# control de integridad de archivos del sistema (AIDE), todos los días"
        echo "30 4 * * * root /usr/sbin/aide --check >> $DIR_LOGS/aide.log 2>&1"
        case $ROL in
            bd)
                echo "# respaldo completo de la base de datos, todos los días"
                echo "30 2 * * * root $DIR_ASO/respaldo/respaldo_bd.sh >/dev/null 2>&1"
                echo "# respaldo de configuración, los domingos"
                echo "0 3 * * 0 root $DIR_ASO/respaldo/respaldo_archivos.sh >/dev/null 2>&1" ;;
            app)
                echo "# respaldo de configuración (.env, claves, certificados), los domingos"
                echo "0 3 * * 0 root $DIR_ASO/respaldo/respaldo_archivos.sh >/dev/null 2>&1"
                echo "# alertas de SiGeRU (mantenimientos próximos, contenedores sin recolección)"
                echo "0 7 * * * root cd $DIR_SIGERU/sigeru-infra/docker && docker compose exec -T api-recoleccion php bin/alertas.php >> $DIR_LOGS/alertas.log 2>&1"
                echo "# limpieza de logs viejos de las aplicaciones"
                echo "15 4 * * * root $admin limpiar-logs >/dev/null 2>&1" ;;
            respaldo)
                echo "# verificación de integridad y retención de los respaldos recibidos"
                echo "0 5 * * * root $DIR_ASO/respaldo/mantener_respaldos.sh >/dev/null 2>&1" ;;
        esac
    } > "$CRON_SIGERU"
    chmod 644 "$CRON_SIGERU"
    cat "$CRON_SIGERU"
    systemctl enable --now crond >/dev/null 2>&1
    ok "Tareas programadas instaladas."
    registrar "programar tareas de cron del rol $ROL"
}

copiar_disco_externo() {
    requiere_rol respaldo || return
    titulo "Copia de los respaldos a un disco externo (largo plazo)"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
    local punto
    preguntar "Carpeta donde está montado el disco externo" punto "/mnt/externo"
    if ! mountpoint -q "$punto"; then
        error "$punto no es un punto de montaje. Monte el disco primero (mount /dev/sdX1 $punto)."
        return
    fi
    rsync -a --info=stats1 "$DIR_RESPALDOS_REMOTO/" "$punto/sigeru/" \
        && ok "Copia terminada en $punto/sigeru/" && registrar "copia de respaldos a disco externo $punto"
}

menu_respaldos() {
    while true; do
        mostrar_menu "Gestión de respaldos" "Respaldar la base de datos ahora" "Respaldar la configuración de este servidor ahora" \
            "Listar respaldos de este servidor" "Listar respaldos del servidor de respaldo" "Verificar integridad" \
            "Restaurar la base de datos" "Configurar conexión / autorizar un servidor" "Programar respaldos automáticos (cron)" \
            "Ver tareas programadas" "Copiar respaldos a disco externo" "Mantenimiento de respaldos recibidos"
        case $OPCION in
            1) requiere_rol bd && generar_clave_cifrado && "$DIR_ASO/respaldo/respaldo_bd.sh" ;;
            2) generar_clave_cifrado; "$DIR_ASO/respaldo/respaldo_archivos.sh" ;;
            3) listar_locales ;;
            4) listar_remotos ;;
            5) verificar_integridad ;;
            6) requiere_rol bd && "$DIR_ASO/respaldo/restaurar_bd.sh" ;;
            7) configurar_conexion ;;
            8) programar_respaldos ;;
            9) titulo "Tareas programadas"; cat /etc/cron.d/sigeru* 2>/dev/null; crontab -l 2>/dev/null ;;
            10) copiar_disco_externo ;;
            11) requiere_rol respaldo && "$DIR_ASO/respaldo/mantener_respaldos.sh" ;;
            0) return ;;
            *) error "Opción no válida." ;;
        esac
        pausa
    done
}
