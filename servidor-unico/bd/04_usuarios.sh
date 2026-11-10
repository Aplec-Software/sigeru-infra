#!/bin/bash
# =====================================================================
# Usuarios de MySQL de cada servicio (instalación en un servidor único).
#
# El contenedor bd lo ejecuta una sola vez, al crear la base, después de
# 01_estructura, 02_datos_base y 03_datos_prueba. Usa la misma plantilla
# que el despliegue de tres servidores (sigeru-infra/db/04_usuarios_bd.sql):
#   - las tres APIs solo pueden entrar desde el contenedor api  (IP_API)
#   - el backoffice solo desde el contenedor web                (IP_WEB)
#   - el usuario de respaldos solo desde el contenedor respaldo (IP_RESPALDO)
# Las contraseñas son las del archivo .env.
# =====================================================================
shopt -u patsub_replacement 2>/dev/null || true   # que un & en una contraseña no se interprete

for v in IP_WEB IP_API IP_RESPALDO CLAVE_API_USUARIOS CLAVE_API_GESTION CLAVE_API_RECOLECCION CLAVE_BACKOFFICE CLAVE_RESPALDO; do
    if [ -z "${!v:-}" ]; then
        echo "04_usuarios.sh: falta la variable $v" >&2
        exit 1
    fi
done

sql=$(sed -e "/'backoffice'@/ s/{{HOST_APP}}/${IP_WEB}/g" \
          -e "s/{{HOST_APP}}/${IP_API}/g" \
          -e "s/'respaldo'@'localhost'/'respaldo'@'${IP_RESPALDO}'/g" \
          /plantillas/04_usuarios_bd.sql)
sql=${sql//'{{CLAVE_API_USUARIOS}}'/$CLAVE_API_USUARIOS}
sql=${sql//'{{CLAVE_API_GESTION}}'/$CLAVE_API_GESTION}
sql=${sql//'{{CLAVE_API_RECOLECCION}}'/$CLAVE_API_RECOLECCION}
sql=${sql//'{{CLAVE_BACKOFFICE}}'/$CLAVE_BACKOFFICE}
sql=${sql//'{{CLAVE_RESPALDO}}'/$CLAVE_RESPALDO}

if declare -F docker_process_sql > /dev/null; then
    docker_process_sql <<< "$sql"          # función del entrypoint oficial de MySQL (este archivo se ejecuta con source)
else
    mysql --protocol=socket -uroot -p"$MYSQL_ROOT_PASSWORD" <<< "$sql"
fi
echo "04_usuarios.sh: usuarios de los servicios creados (api: $IP_API, web: $IP_WEB, respaldo: $IP_RESPALDO)"
