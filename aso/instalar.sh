#!/bin/bash
# =====================================================================
# Instala el script de administración de SiGeRU en este servidor.
#
#   git clone https://github.com/Aplec-Software/sigeru-infra.git /opt/aplec/sigeru/sigeru-infra
#   cd /opt/aplec/sigeru/sigeru-infra/aso
#   sudo ./instalar.sh app        (o bd, o respaldo)
# =====================================================================
DIR_ASO="$(dirname "$(readlink -f "$0")")"
ROL_NUEVO=${1:-}

if [ "$EUID" -ne 0 ]; then
    echo "Ejecute como root: sudo ./instalar.sh app|bd|respaldo"
    exit 1
fi
if [[ ! "$ROL_NUEVO" =~ ^(app|bd|respaldo)$ ]]; then
    echo "Indique el rol del servidor: app, bd o respaldo"
    exit 1
fi

install -d -m 700 /etc/sigeru
if [ -f /etc/sigeru/sigeru.conf ]; then
    sed -i "s/^ROL=.*/ROL=$ROL_NUEVO/" /etc/sigeru/sigeru.conf
    echo "Se mantiene /etc/sigeru/sigeru.conf (rol actualizado a $ROL_NUEVO)."
else
    sed "s/^ROL=.*/ROL=$ROL_NUEVO/" "$DIR_ASO/sigeru.conf.example" > /etc/sigeru/sigeru.conf
    chmod 600 /etc/sigeru/sigeru.conf
    echo "Configuración creada en /etc/sigeru/sigeru.conf (revise las IP y el usuario administrador)."
fi

chmod +x "$DIR_ASO/sigeru-admin.sh" "$DIR_ASO"/respaldo/*.sh
ln -sf "$DIR_ASO/sigeru-admin.sh" /usr/local/sbin/sigeru-admin
install -d -m 750 /var/log/sigeru

echo "Listo. Ejecute: sudo sigeru-admin  (y luego: Instalación > Preparar este servidor)"
