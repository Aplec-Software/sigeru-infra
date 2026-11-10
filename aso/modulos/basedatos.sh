#!/bin/bash
# =====================================================================
# Módulo: gestión de la base de datos MySQL (servidor sigeru-bd)
# =====================================================================

DIR_SQL="$DIR_SIGERU/sigeru-infra/db"
CLAVES_BD=/etc/sigeru/claves_bd.env
CNF_ROOT=/root/.my.cnf
CNF_RESPALDO=/etc/sigeru/respaldo.cnf

# Cliente mysql como root (usa /root/.my.cnf si existe)
mysql_root() {
    if [ -f "$CNF_ROOT" ]; then
        mysql --defaults-file="$CNF_ROOT" "$@"
    else
        mysql -u root "$@"
    fi
}

mysql_listo() {
    if ! comando_existe mysql; then
        error "MySQL no está instalado (Instalación > Instalar y configurar MySQL)."
        return 1
    fi
    if ! systemctl is-active --quiet mysqld; then
        error "El servicio mysqld no está activo (systemctl start mysqld)."
        return 1
    fi
}

estado_mysql() {
    titulo "Estado de MySQL"
    estado_servicio mysqld
    mysql_listo || return
    mysql_root -e "SELECT VERSION() AS version, @@bind_address AS escucha_en, @@character_set_server AS juego_caracteres, @@time_zone AS zona_horaria;"
    mysqladmin --defaults-file="$CNF_ROOT" status 2>/dev/null
}

existe_base() {
    [ -n "$(mysql_root -N -e "SHOW DATABASES LIKE 'sigeru'")" ]
}

crear_estructura() {
    mysql_listo || return
    if [ ! -f "$DIR_SQL/01_estructura.sql" ]; then
        error "No se encuentra $DIR_SQL/01_estructura.sql (descargue el repositorio sigeru-infra)."
        return
    fi
    if existe_base; then
        aviso "La base 'sigeru' ya existe: el script de estructura BORRA las tablas y las vuelve a crear."
        confirmar "¿Continuar de todos modos? (haga antes un respaldo)" || return
    fi
    mysql_root < "$DIR_SQL/01_estructura.sql" && mysql_root sigeru < "$DIR_SQL/02_datos_base.sql" \
        && ok "Base 'sigeru' creada con su estructura y datos base." \
        && registrar "crear estructura de la base sigeru"
}

cargar_datos_prueba() {
    mysql_listo || return
    existe_base || { error "Primero cree la estructura."; return; }
    aviso "Se cargan los datos simulados (contenedores, camiones, usuarios de prueba con contraseña Sigeru2026!)."
    aviso "Es para demostración y pruebas; en producción no se usa."
    confirmar "¿Cargar los datos de prueba?" || return
    mysql_root sigeru < "$DIR_SQL/03_datos_prueba.sql" && ok "Datos de prueba cargados." && registrar "cargar datos de prueba"
}

importar_claves() {
    local origen
    echo "Las contraseñas de los usuarios de MySQL se generan en el servidor de aplicaciones (archivo .env)."
    echo "Cópielo primero, por ejemplo desde sigeru-app:"
    echo "  scp $DIR_SIGERU/sigeru-infra/docker/.env $USUARIO_ADMIN@$NOMBRE_BD:/tmp/sigeru.env"
    preguntar "Ruta del archivo copiado" origen "/tmp/sigeru.env"
    if [ ! -f "$origen" ]; then
        error "No existe $origen"
        return 1
    fi
    install -d -m 700 /etc/sigeru
    grep -E '^CLAVE_(API_USUARIOS|API_GESTION|API_RECOLECCION|BACKOFFICE)=' "$origen" > "$CLAVES_BD"
    chmod 600 "$CLAVES_BD"
    shred -u "${origen:?}" 2>/dev/null || rm -f "${origen:?}"
    ok "Contraseñas guardadas en $CLAVES_BD (solo root las puede leer). El archivo copiado se borró."
}

crear_usuarios_aplicaciones() {
    mysql_listo || return
    existe_base || { error "Primero cree la estructura."; return; }
    if [ ! -f "$CLAVES_BD" ]; then
        importar_claves || return
    fi
    # shellcheck source=/dev/null
    source "$CLAVES_BD"
    local falta
    for falta in CLAVE_API_USUARIOS CLAVE_API_GESTION CLAVE_API_RECOLECCION CLAVE_BACKOFFICE; do
        if [ -z "${!falta}" ]; then
            error "Falta $falta en $CLAVES_BD"
            return
        fi
    done

    # el usuario de respaldo es local y su contraseña se genera acá
    local clave_respaldo
    if [ -f "$CNF_RESPALDO" ]; then
        clave_respaldo=$(awk -F= '/^password/ { print $2 }' "$CNF_RESPALDO")
    else
        clave_respaldo=$(clave_aleatoria 28)
        printf '[client]\nuser=respaldo\npassword=%s\n' "$clave_respaldo" > "$CNF_RESPALDO"
        chmod 600 "$CNF_RESPALDO"
    fi

    sed -e "s/{{HOST_APP}}/$IP_APP/g" \
        -e "s/{{CLAVE_API_USUARIOS}}/$CLAVE_API_USUARIOS/g" \
        -e "s/{{CLAVE_API_GESTION}}/$CLAVE_API_GESTION/g" \
        -e "s/{{CLAVE_API_RECOLECCION}}/$CLAVE_API_RECOLECCION/g" \
        -e "s/{{CLAVE_BACKOFFICE}}/$CLAVE_BACKOFFICE/g" \
        -e "s/{{CLAVE_RESPALDO}}/$clave_respaldo/g" \
        "$DIR_SQL/04_usuarios_bd.sql" | mysql_root

    # si los usuarios ya existían, se actualiza la contraseña
    mysql_root -e "ALTER USER 'api_usuarios'@'$IP_APP' IDENTIFIED BY '$CLAVE_API_USUARIOS';
                   ALTER USER 'api_gestion'@'$IP_APP' IDENTIFIED BY '$CLAVE_API_GESTION';
                   ALTER USER 'api_recoleccion'@'$IP_APP' IDENTIFIED BY '$CLAVE_API_RECOLECCION';
                   ALTER USER 'backoffice'@'$IP_APP' IDENTIFIED BY '$CLAVE_BACKOFFICE';
                   ALTER USER 'respaldo'@'localhost' IDENTIFIED BY '$clave_respaldo';" \
        && ok "Usuarios de MySQL creados con permisos mínimos (solo desde $IP_APP)." \
        && registrar "crear/actualizar usuarios de MySQL de las aplicaciones"
}

listar_usuarios_mysql() {
    mysql_listo || return
    titulo "Usuarios de MySQL"
    mysql_root -e "SELECT user AS usuario, host AS desde, plugin, account_locked AS bloqueado FROM mysql.user ORDER BY user;"
    local u
    preguntar "Ver permisos de un usuario (usuario@host) o Enter para salir" u ""
    if [ -n "$u" ]; then
        mysql_root -e "SHOW GRANTS FOR '${u%@*}'@'${u#*@}';"
    fi
}

tamano_base() {
    mysql_listo || return
    titulo "Tamaño de las tablas de sigeru"
    mysql_root -e "SELECT table_name AS tabla, table_rows AS filas_aprox,
                          ROUND((data_length + index_length) / 1024, 1) AS kb
                   FROM information_schema.tables WHERE table_schema = 'sigeru' ORDER BY kb DESC;"
    mysql_root -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS total_mb
                   FROM information_schema.tables WHERE table_schema = 'sigeru';"
}

menu_basedatos() {
    requiere_rol bd || { pausa; return; }
    while true; do
        mostrar_menu "Gestión de la base de datos" "Estado del servicio MySQL" "Crear la base y su estructura" "Cargar datos de prueba" \
            "Crear / actualizar usuarios de las aplicaciones" "Listar usuarios y permisos" "Tamaño de la base" \
            "Conexiones activas" "Abrir consola MySQL" "Respaldar ahora" "Restaurar un respaldo" \
            "Iniciar / detener / reiniciar MySQL"
        case $OPCION in
            1) estado_mysql ;;
            2) crear_estructura ;;
            3) cargar_datos_prueba ;;
            4) crear_usuarios_aplicaciones ;;
            5) listar_usuarios_mysql ;;
            6) tamano_base ;;
            7) mysql_listo && mysql_root -e "SHOW PROCESSLIST;" ;;
            8) mysql_listo && mysql_root sigeru ;;
            9) "$DIR_ASO/respaldo/respaldo_bd.sh" ;;
            10) "$DIR_ASO/respaldo/restaurar_bd.sh" ;;
            11) local accion
                preguntar "Acción (start / stop / restart)" accion restart
                if [[ "$accion" =~ ^(start|stop|restart)$ ]]; then
                    systemctl "$accion" mysqld && ok "mysqld: $accion" && registrar "mysqld $accion"
                else
                    error "Acción no válida."
                fi ;;
            0) return ;;
            *) error "Opción no válida." ;;
        esac
        pausa
    done
}
