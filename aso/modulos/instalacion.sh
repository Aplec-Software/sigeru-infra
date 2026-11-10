#!/bin/bash
# =====================================================================
# Módulo: instalación y configuración inicial de cada servidor
#
# Orden recomendado (ver manual de instalación):
#   1. en los tres servidores: "Preparar este servidor"
#   2. sigeru-respaldo: "Preparar el servidor de respaldo"
#   3. sigeru-app: "Instalar Docker", "Descargar repositorios", "Generar configuración"
#   4. sigeru-bd: "Instalar y configurar MySQL" (usa el .env generado en sigeru-app)
#   5. sigeru-app: "Levantar SiGeRU"
# =====================================================================

DIR_CONFIG="$DIR_ASO/config"
REPOS_APP="sigeru-landing sigeru-frontend sigeru-api-usuarios sigeru-api-gestion sigeru-api-recoleccion sigeru-backoffice"

# ------------------------------------------------- todos los servidores
preparar_servidor() {
    titulo "Preparar este servidor (rol: $ROL)"
    confirmar "Se actualizará el sistema y se aplicará la configuración base. ¿Continuar?" || return

    echo "1/9 Actualizando paquetes e instalando herramientas..."
    dnf -y update
    dnf -y install epel-release
    dnf -y install nano vim-enhanced git tar rsync curl wget bash-completion chrony cronie \
        policycoreutils-python-utils firewalld fail2ban dnf-automatic bind-utils lsof psmisc openssl aide audit
    dnf -y install python3-systemd >/dev/null 2>&1 || aviso "python3-systemd no disponible (fail2ban usará /var/log/secure)."

    echo "2/9 Zona horaria y hora sincronizada..."
    timedatectl set-timezone America/Montevideo
    systemctl enable --now chronyd >/dev/null

    echo "3/9 Nombre, red interna y /etc/hosts..."
    hostnamectl set-hostname "$(nombre_de_este_rol)"
    configurar_hosts
    if confirmar "¿Configurar ahora la IP estática de la red interna?"; then
        configurar_ip_estatica
    fi

    echo "4/9 Carpetas de SiGeRU..."
    crear_grupos_proyecto
    install -d -m 700 /etc/sigeru
    install -d -m 750 -g sigeru-logs "$DIR_LOGS"
    install -d -m 700 "$DIR_RESPALDOS_LOCAL"
    install -d -m 755 "$DIR_SIGERU"
    install -m 644 "$DIR_CONFIG/logrotate-sigeru" /etc/logrotate.d/sigeru

    echo "5/9 Política de contraseñas..."
    install -d /etc/security/pwquality.conf.d
    install -m 644 "$DIR_CONFIG/pwquality-sigeru.conf" /etc/security/pwquality.conf.d/sigeru.conf
    sed -i -e 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t90/' -e 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS\t1/' \
           -e 's/^PASS_WARN_AGE.*/PASS_WARN_AGE\t7/' /etc/login.defs

    echo "6/9 Usuario administrador ($USUARIO_ADMIN)..."
    if id "$USUARIO_ADMIN" >/dev/null 2>&1; then
        usermod -aG wheel,sigeru-ssh,sigeru-logs "$USUARIO_ADMIN"
        ok "$USUARIO_ADMIN ya existía; se agregó a los grupos wheel, sigeru-ssh y sigeru-logs."
    else
        useradd -m -c "Administrador SiGeRU" -G wheel,sigeru-ssh,sigeru-logs "$USUARIO_ADMIN"
        echo "Contraseña para $USUARIO_ADMIN (mínimo 10 caracteres, mayúscula, minúscula, número y símbolo):"
        until passwd "$USUARIO_ADMIN"; do aviso "Intente de nuevo."; done
        chage -M 90 -m 1 -W 7 "$USUARIO_ADMIN"
    fi

    echo "7/9 Servicio SSH..."
    configurar_ssh

    echo "8/9 Firewall y fail2ban..."
    systemctl enable --now firewalld >/dev/null
    aplicar_reglas_rol >/dev/null
    sed -e "s/{{PUERTO_SSH}}/$PUERTO_SSH/" -e "s/{{IP_APP}}/$IP_APP/" -e "s/{{IP_BD}}/$IP_BD/" -e "s/{{IP_RESPALDO}}/$IP_RESPALDO/" \
        "$DIR_CONFIG/fail2ban-sigeru.local" > /etc/fail2ban/jail.d/sigeru.local
    if ! python3 -c 'import systemd.journal' 2>/dev/null; then
        sed -i 's/^backend = systemd/logpath = \/var\/log\/secure/' /etc/fail2ban/jail.d/sigeru.local
    fi
    systemctl enable --now fail2ban >/dev/null && systemctl restart fail2ban

    echo "9/9 Actualizaciones automáticas, servicios sin uso y detección de intrusos (AIDE)..."
    sed -i -e 's/^upgrade_type.*/upgrade_type = security/' -e 's/^apply_updates.*/apply_updates = yes/' /etc/dnf/automatic.conf
    systemctl enable --now dnf-automatic.timer >/dev/null
    systemctl disable --now cockpit.socket >/dev/null 2>&1

    # Detección de intrusos en el equipo (HIDS): AIDE guarda una "foto" de los archivos
    # del sistema y cada día avisa si alguno cambió sin motivo. auditd registra eventos de seguridad.
    systemctl enable --now auditd >/dev/null 2>&1
    if [ ! -f /var/lib/aide/aide.db.gz ]; then
        echo "Generando la base de AIDE (puede tardar unos minutos)..."
        aide --init >/dev/null 2>&1 && mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
    fi

    if [ "$(getenforce)" != "Enforcing" ]; then
        aviso "SELinux no está en modo Enforcing. Revise /etc/selinux/config."
    fi
    ok "Servidor preparado."
    registrar "preparar servidor (rol $ROL)"
}

configurar_ssh() {
    local hogar clave_cargada=no password_auth=yes
    hogar=$(getent passwd "$USUARIO_ADMIN" | cut -d: -f6)
    if [ -s "$hogar/.ssh/authorized_keys" ]; then
        clave_cargada=si
        password_auth=no
    fi
    if [ "$clave_cargada" = "no" ]; then
        aviso "$USUARIO_ADMIN todavía no tiene clave pública: se deja el ingreso con contraseña habilitado."
        aviso "Cargue la clave (Usuarios > Agregar clave pública SSH) y vuelva a ejecutar esta opción para deshabilitarlo."
    fi
    if [ "$PUERTO_SSH" != "22" ]; then
        semanage port -a -t ssh_port_t -p tcp "$PUERTO_SSH" 2>/dev/null || semanage port -m -t ssh_port_t -p tcp "$PUERTO_SSH"
    fi
    install -m 644 "$DIR_CONFIG/issue.net" /etc/issue.net
    sed -e "s/{{PUERTO_SSH}}/$PUERTO_SSH/" -e "s/{{PASSWORD_AUTH}}/$password_auth/" \
        "$DIR_CONFIG/sshd-00-sigeru.conf" > /etc/ssh/sshd_config.d/00-sigeru.conf
    chmod 600 /etc/ssh/sshd_config.d/00-sigeru.conf
    # el usuario de respaldos también entra por SSH (solo con clave)
    if id "$USUARIO_RESPALDO" >/dev/null 2>&1; then
        usermod -aG sigeru-ssh "$USUARIO_RESPALDO"
    fi
    if sshd -t; then
        systemctl restart sshd
        ok "SSH configurado: puerto $PUERTO_SSH, sin root, ingreso con contraseña: $password_auth."
        aviso "No cierre esta sesión hasta comprobar que puede entrar como $USUARIO_ADMIN desde otra terminal."
        registrar "configurar SSH (puerto $PUERTO_SSH, contraseña: $password_auth)"
    else
        rm -f /etc/ssh/sshd_config.d/00-sigeru.conf
        error "La configuración de SSH tenía errores; no se aplicó."
    fi
}

# ------------------------------------------------- servidor de aplicaciones
instalar_docker() {
    requiere_rol app || return
    titulo "Instalar Docker Engine y Docker Compose"
    if comando_existe docker; then
        ok "Docker ya está instalado: $(docker --version)"
    else
        # Rocky trae Podman; Docker recomienda quitarlo para evitar conflictos
        dnf -y remove podman buildah runc >/dev/null 2>&1
        dnf -y install dnf-plugins-core
        dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
        dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || { error "Falló la instalación."; return; }
    fi
    install -d /etc/docker
    install -m 644 "$DIR_CONFIG/docker-daemon.json" /etc/docker/daemon.json
    systemctl enable --now docker >/dev/null
    systemctl restart docker
    usermod -aG docker "$USUARIO_ADMIN"
    # carpeta de logs de las APIs: la escribe el usuario www-data (uid 33) de los contenedores
    install -d -m 750 -o 33 -g 33 "$DIR_LOGS/aplicaciones"
    ok "$(docker --version) / $(docker compose version)"
    registrar "instalar Docker"
}

descargar_repositorios() {
    requiere_rol app || return
    titulo "Repositorios de SiGeRU ($GITHUB_ORG)"
    local repo
    for repo in sigeru-infra $REPOS_APP; do
        if [ -d "$DIR_SIGERU/$repo/.git" ]; then
            echo "- $repo: $(git -C "$DIR_SIGERU/$repo" pull --ff-only 2>&1 | tail -n 1)"
        elif [ -d "$DIR_SIGERU/$repo" ]; then
            aviso "$repo existe pero no es un repositorio git (copiado a mano); se deja como está."
        else
            git clone --depth 20 "$GITHUB_ORG/$repo.git" "$DIR_SIGERU/$repo" && ok "$repo descargado"
        fi
    done
    registrar "descargar/actualizar repositorios"
}

generar_configuracion() {
    requiere_rol app || return
    local dir="$DIR_SIGERU/sigeru-infra/docker"
    titulo "Generar .env, claves JWT y certificado HTTPS"
    [ -f "$dir/.env.example" ] || { error "Falta $dir/.env.example (descargue los repositorios)."; return; }

    if [ -f "$dir/.env" ]; then
        aviso "Ya existe un .env. Si lo regenera, hay que actualizar las contraseñas en sigeru-bd."
        confirmar "¿Generar uno nuevo?" || return
        cp "$dir/.env" "$dir/.env.anterior"
    fi
    sed -e "s|^DB_HOST=.*|DB_HOST=$IP_BD|" \
        -e "s|^CLAVE_API_USUARIOS=.*|CLAVE_API_USUARIOS=$(clave_aleatoria 24)|" \
        -e "s|^CLAVE_API_GESTION=.*|CLAVE_API_GESTION=$(clave_aleatoria 24)|" \
        -e "s|^CLAVE_API_RECOLECCION=.*|CLAVE_API_RECOLECCION=$(clave_aleatoria 24)|" \
        -e "s|^CLAVE_BACKOFFICE=.*|CLAVE_BACKOFFICE=$(clave_aleatoria 24)|" \
        -e "s|^APP_SAL=.*|APP_SAL=$(clave_aleatoria 32)|" \
        "$dir/.env.example" > "$dir/.env"
    chmod 600 "$dir/.env"
    ok ".env generado con contraseñas al azar."

    # Claves RSA para firmar (privada, solo API de Usuarios) y verificar (pública) los JWT
    if [ ! -f "$dir/claves/jwt_privada.pem" ]; then
        install -d -m 755 "$dir/claves"
        openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$dir/claves/jwt_privada.pem" 2>/dev/null
        openssl pkey -in "$dir/claves/jwt_privada.pem" -pubout -out "$dir/claves/jwt_publica.pem"
        chown 33:33 "$dir/claves/jwt_privada.pem"
        chmod 400 "$dir/claves/jwt_privada.pem"
        chmod 444 "$dir/claves/jwt_publica.pem"
        ok "Par de claves JWT (RS256) generado."
    else
        ok "Las claves JWT ya existían (no se cambian para no cerrar las sesiones)."
    fi

    generar_certificado "$dir/gateway/certs"
    echo
    echo "Siguiente paso: copiar el .env a sigeru-bd para crear los usuarios de MySQL:"
    echo "  scp $dir/.env $USUARIO_ADMIN@$IP_BD:/tmp/sigeru.env"
    registrar "generar .env, claves JWT y certificado"
}

# Autoridad certificadora propia (Aplec Software) y certificado del servidor
generar_certificado() {
    local certs=$1 ca=/etc/sigeru/ca
    install -d -m 700 "$ca"
    install -d -m 755 "$certs"
    if [ ! -f "$ca/aplec-ca.key" ]; then
        openssl req -x509 -new -nodes -newkey rsa:3072 -sha256 -days 1825 \
            -subj "/C=UY/ST=Montevideo/O=Aplec Software/CN=Aplec Software CA" \
            -keyout "$ca/aplec-ca.key" -out "$ca/aplec-ca.crt" 2>/dev/null
        chmod 600 "$ca/aplec-ca.key"
    fi
    openssl req -new -nodes -newkey rsa:2048 -subj "/C=UY/ST=Montevideo/O=Aplec Software/CN=sigeru.local" \
        -keyout "$certs/sigeru.key" -out "$ca/sigeru.csr" 2>/dev/null
    printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:sigeru.local,DNS:%s,IP:%s\n' \
        "$NOMBRE_APP" "$IP_APP" > "$ca/sigeru.ext"
    openssl x509 -req -in "$ca/sigeru.csr" -CA "$ca/aplec-ca.crt" -CAkey "$ca/aplec-ca.key" -CAcreateserial \
        -days 825 -sha256 -extfile "$ca/sigeru.ext" -out "$certs/sigeru.crt" 2>/dev/null
    chmod 600 "$certs/sigeru.key"
    cp "$ca/aplec-ca.crt" "$certs/aplec-ca.crt"
    ok "Certificado para sigeru.local / $IP_APP válido hasta $(openssl x509 -enddate -noout -in "$certs/sigeru.crt" | cut -d= -f2)"
    aviso "Instale $certs/aplec-ca.crt como entidad de confianza en los equipos que usen SiGeRU."
}

levantar_sigeru() {
    requiere_rol app || return
    levantar || return
    echo "Esperando a que arranquen los servicios..."
    sleep 15
    salud_apis
}

# ------------------------------------------------- servidor de base de datos
instalar_mysql() {
    requiere_rol bd || return
    titulo "Instalar y configurar MySQL 8"
    if ! comando_existe mysqld; then
        dnf -y install mysql-server || { error "Falló la instalación."; return; }
    fi
    sed -e "s/{{IP_BD}}/$IP_BD/" "$DIR_CONFIG/mysql-sigeru.cnf" > /etc/my.cnf.d/sigeru.cnf
    install -d -o mysql -g mysql -m 750 /var/log/mysql
    systemctl enable --now mysqld >/dev/null
    systemctl restart mysqld || { error "MySQL no arrancó: revise journalctl -u mysqld"; return; }

    # equivalente a mysql_secure_installation: contraseña de root, sin usuarios anónimos ni base de prueba
    if [ ! -f /root/.my.cnf ]; then
        local clave
        clave=$(clave_aleatoria 28)
        mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$clave';
                          DELETE FROM mysql.user WHERE user = '';
                          DROP DATABASE IF EXISTS test;
                          FLUSH PRIVILEGES;" || { error "No se pudo asegurar la cuenta root de MySQL."; return; }
        printf '[client]\nuser=root\npassword=%s\n' "$clave" > /root/.my.cnf
        chmod 600 /root/.my.cnf
        ok "Contraseña de root de MySQL generada y guardada en /root/.my.cnf (solo root la lee)."
    fi
    aplicar_reglas_rol >/dev/null
    ok "MySQL $(mysql --defaults-file=/root/.my.cnf -N -e 'SELECT VERSION()') escuchando en $IP_BD:3306"
    registrar "instalar MySQL"

    if confirmar "¿Crear ahora la base sigeru y los usuarios de las aplicaciones?"; then
        crear_estructura
        crear_usuarios_aplicaciones
        confirmar "¿Cargar también los datos de prueba (para la demostración)?" && mysql_root sigeru < "$DIR_SQL/03_datos_prueba.sql" && ok "Datos de prueba cargados."
    fi
    generar_clave_cifrado
}

# ------------------------------------------------- servidor de respaldo
preparar_servidor_respaldo() {
    requiere_rol respaldo || return
    titulo "Preparar el servidor de respaldo"
    if ! id "$USUARIO_RESPALDO" >/dev/null 2>&1; then
        useradd -m -c "Recepción de respaldos SiGeRU" -G sigeru-ssh "$USUARIO_RESPALDO"
        passwd -l "$USUARIO_RESPALDO" >/dev/null   # sin contraseña: solo entra con las claves autorizadas
        ok "Usuario $USUARIO_RESPALDO creado (sin contraseña, solo claves SSH)."
    fi
    install -d -m 750 -o "$USUARIO_RESPALDO" -g "$USUARIO_RESPALDO" "$DIR_RESPALDOS_REMOTO" "$DIR_RESPALDOS_REMOTO/bd" "$DIR_RESPALDOS_REMOTO/archivos"
    programar_respaldos >/dev/null
    ok "Carpetas en $DIR_RESPALDOS_REMOTO y mantenimiento diario programado."
    echo "Ahora autorice a sigeru-app y sigeru-bd: Respaldos > Configurar conexión / autorizar un servidor."
    registrar "preparar servidor de respaldo"
}

resumen_instalacion() {
    titulo "Resumen de este servidor"
    echo "Nombre: $(hostname)   Rol: $ROL   IP interna: $(ip -4 -brief address show "$INTERFAZ_INTERNA" 2>/dev/null | awk '{print $3}')"
    echo "Configuración: $ARCHIVO_CONF"
    echo
    local paso
    echo "Comprobaciones:"
    for paso in "id $USUARIO_ADMIN" "test -f /etc/ssh/sshd_config.d/00-sigeru.conf" "systemctl is-active --quiet firewalld" \
                "systemctl is-active --quiet fail2ban" "test -f /etc/cron.d/sigeru"; do
        if eval "$paso" >/dev/null 2>&1; then ok "$paso"; else error "$paso"; fi
    done
    case $ROL in
        app) for paso in "systemctl is-active --quiet docker" "test -f $DIR_SIGERU/sigeru-infra/docker/.env" "test -f $DIR_SIGERU/sigeru-infra/docker/gateway/certs/sigeru.crt" "test -f /root/.ssh/id_respaldo"; do
                 if eval "$paso" >/dev/null 2>&1; then ok "$paso"; else error "$paso"; fi
             done ;;
        bd) for paso in "systemctl is-active --quiet mysqld" "test -f /root/.my.cnf" "test -f /etc/sigeru/respaldo.cnf" "test -f $CLAVE_RESPALDOS" "test -f /root/.ssh/id_respaldo"; do
                 if eval "$paso" >/dev/null 2>&1; then ok "$paso"; else error "$paso"; fi
             done ;;
        respaldo) for paso in "id $USUARIO_RESPALDO" "test -d $DIR_RESPALDOS_REMOTO/bd"; do
                 if eval "$paso" >/dev/null 2>&1; then ok "$paso"; else error "$paso"; fi
             done ;;
    esac
}

menu_instalacion() {
    while true; do
        mostrar_menu "Instalación y configuración inicial (rol: $ROL)" "Preparar este servidor (los tres)" "Instalar Docker (app)" \
            "Descargar / actualizar repositorios (app)" "Generar .env, claves JWT y certificado (app)" "Levantar SiGeRU (app)" \
            "Instalar y configurar MySQL (bd)" "Preparar el servidor de respaldo (respaldo)" "Volver a aplicar la configuración de SSH" \
            "Resumen de la instalación"
        case $OPCION in
            1) preparar_servidor ;;
            2) instalar_docker ;;
            3) descargar_repositorios ;;
            4) generar_configuracion ;;
            5) levantar_sigeru ;;
            6) instalar_mysql ;;
            7) preparar_servidor_respaldo ;;
            8) configurar_ssh ;;
            9) resumen_instalacion ;;
            0) return ;;
            *) error "Opción no válida." ;;
        esac
        pausa
    done
}
