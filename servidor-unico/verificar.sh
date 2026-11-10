#!/bin/bash
# =====================================================================
# Verificación de la instalación de SiGeRU en un servidor único.
# Recorre lo que se controla en la instancia de instalación:
#   1. contenedores en ejecución y sanos      5. inicio de sesión y ABM (alta, consulta,
#   2. red de Docker y volúmenes                 modificación y baja) de punta a punta
#   3. acceso web por HTTP y HTTPS            6. persistencia (opcional: --persistencia)
#   4. APIs y conexión con MySQL; tablas      7. respaldo .tar.gz y su verificación
# Deja un informe en verificacion_AAAAMMDD_HHMMSS.txt.
#
# Uso:  bash verificar.sh                  verificación completa (tarda menos de un minuto)
#       bash verificar.sh --persistencia   además reinicia los contenedores y comprueba
#                                       que los datos siguen ahí (tarda un par de minutos)
# =====================================================================
set -u
cd "$(dirname "$(readlink -f "$0")")"
[ -f .env ] || { echo "Falta el archivo .env: ejecutar primero bash instalar.sh"; exit 1; }
set -a
# shellcheck disable=SC1091
source ./.env
set +a

PERSISTENCIA=0
[ "${1:-}" = "--persistencia" ] && PERSISTENCIA=1
HTTPS=${PUERTO_HTTPS:-443}
HTTP=${PUERTO_HTTP:-80}
BASE="https://localhost:$HTTPS"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
INFORME="verificacion_$(date +%Y%m%d_%H%M%S).txt"
exec > >(tee "$INFORME") 2>&1

TOTAL=0
FALLAS=0
titulo() { printf '\n%s\n' "$*"; }
resultado() {   # resultado 0|1 "texto"
    TOTAL=$((TOTAL + 1))
    if [ "$1" -eq 0 ]; then
        printf '  [OK]    %s\n' "$2"
    else
        printf '  [FALLA] %s\n' "$2"
        FALLAS=$((FALLAS + 1))
    fi
}
comprobar() {   # comprobar "texto" comando...
    local texto=$1; shift
    "$@" > /dev/null 2>&1
    resultado $? "$texto"
}
# Consulta en MySQL como root, desde dentro del contenedor bd (root no puede entrar desde afuera).
# El cliente usa utf8mb4: si no, compara "Unión" con otra codificación y el control de acentos falla (D-23)
sql() {
    docker exec sigeru-bd sh -c 'f=$(mktemp); printf "[client]\nuser=root\npassword=%s\ndefault-character-set=utf8mb4\n" "$MYSQL_ROOT_PASSWORD" > "$f";
        mysql --defaults-extra-file="$f" -N -B sigeru -e "$1"; r=$?; rm -f "$f"; exit $r' sh "$1"
}
# Pedido a la API con la cookie de sesión del administrador: api MÉTODO RUTA [JSON] -> imprime el código HTTP
api() {
    local args=(-sk -o "$TMP/respuesta" -w '%{http_code}' -X "$1" -b "$TMP/cookies" -c "$TMP/cookies"
                -H 'Accept: application/json' -H 'X-Requested-With: SiGeRU')
    [ -n "${3:-}" ] && args+=(-H 'Content-Type: application/json' --data "$3")
    curl "${args[@]}" "$BASE$2"
}
codigo() { curl -sk -o /dev/null -w '%{http_code}' "$@"; }
esperar_sanos() {
    local limite=$((SECONDS + 300)) c estado listo
    while [ $SECONDS -lt $limite ]; do
        listo=1
        for c in sigeru-bd sigeru-api sigeru-web; do
            estado=$(docker inspect -f '{{.State.Health.Status}}' "$c" 2>/dev/null)
            [ "$estado" = "healthy" ] || listo=0
        done
        [ $listo -eq 1 ] && return 0
        sleep 5
    done
    return 1
}

echo "Verificación de SiGeRU - $(date '+%F %T') - $(hostname)"

# ------------------------------------------------------------------ 1
titulo "1. Contenedores"
for c in sigeru-web sigeru-api sigeru-bd sigeru-respaldo; do
    estado=$(docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' "$c" 2>/dev/null)
    [ "$estado" = "running healthy" ]
    resultado $? "$c: ${estado:-no existe}"
done

# ------------------------------------------------------------------ 2
titulo "2. Red de Docker y volúmenes"
red=$(docker network inspect sigeru_red -f '{{range .Containers}}{{.Name}}={{.IPv4Address}} {{end}}' 2>/dev/null)
for c in sigeru-web sigeru-api sigeru-bd sigeru-respaldo; do
    [[ " $red" == *" $c="* ]]
    resultado $? "$c conectado a sigeru_red ($(tr ' ' '\n' <<< "$red" | grep "^$c=" | cut -d= -f2))"
done
for v in datos_mysql claves certificados logs; do
    comprobar "volumen sigeru_$v" docker volume inspect "sigeru_$v"
done
[ -d respaldos ]
resultado $? "carpeta de respaldos en el anfitrión ($(pwd)/respaldos)"

# ------------------------------------------------------------------ 3
titulo "3. Acceso web"
[ "$(codigo "http://localhost:$HTTP/")" = "301" ]
resultado $? "HTTP ($HTTP) redirige a HTTPS"
docker exec sigeru-web cat /etc/sigeru/certificados/aplec-ca.crt > "$TMP/aplec-ca.crt" 2>/dev/null
comprobar "certificado HTTPS válido, firmado por la CA de Aplec" curl -fsS --cacert "$TMP/aplec-ca.crt" -o /dev/null "$BASE/salud"
for ruta in / /app/ /backoffice/login /aplec-ca.crt; do
    c=$(codigo "$BASE$ruta")
    [ "$c" = "200" ]
    resultado $? "GET $ruta -> $c"
done
cabeceras=$(curl -skI "$BASE/")
grep -qi '^strict-transport-security' <<< "$cabeceras" && grep -qi '^content-security-policy' <<< "$cabeceras"
resultado $? "cabeceras de seguridad (HSTS y CSP)"
! grep -qiE '^server: .*[0-9]' <<< "$cabeceras"
resultado $? "Apache no muestra su versión"
grep -qi '^referrer-policy: strict-origin-when-cross-origin' <<< "$cabeceras"
resultado $? "Referrer-Policy strict-origin-when-cross-origin (los mosaicos del mapa la necesitan, D-21)"

# ------------------------------------------------------------------ 4
titulo "4. APIs y base de datos"
for a in usuarios gestion recoleccion; do
    cuerpo=$(curl -sk "$BASE/api/$a/salud")
    grep -q '"bd":"ok"' <<< "$cuerpo"
    resultado $? "API de $a responde y llega a MySQL: $cuerpo"
done
tablas=$(sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='sigeru' AND table_type='BASE TABLE'")
vistas=$(sql "SELECT COUNT(*) FROM information_schema.views WHERE table_schema='sigeru'")
claves=$(sql "SELECT COUNT(*) FROM information_schema.referential_constraints WHERE constraint_schema='sigeru'")
[ "${tablas:-0}" -gt 0 ] && [ "${claves:-0}" -gt 0 ]
resultado $? "estructura: ${tablas:-?} tablas, ${vistas:-?} vistas y ${claves:-?} claves foráneas"
for t in usuarios contenedores camiones incidencias rutas; do
    n=$(sql "SELECT COUNT(*) FROM $t")
    [ "${n:-0}" -gt 0 ]
    resultado $? "datos de prueba en $t: ${n:-?} filas"
done
acentos=$(sql "SELECT COUNT(*) FROM zonas WHERE nombre IN ('Unión', 'Malvín', 'Cordón')")
[ "${acentos:-0}" -eq 3 ]
resultado $? "acentos bien cargados en la base (Unión, Malvín, Cordón; D-20)"
usuarios=$(sql "SELECT CONCAT(user,'@',host) FROM mysql.user WHERE user IN ('api_usuarios','api_gestion','api_recoleccion','backoffice','respaldo') ORDER BY user" | tr '\n' ' ')
[ "$(wc -w <<< "$usuarios")" -eq 5 ]
resultado $? "usuarios de MySQL por servicio: $usuarios"

# ------------------------------------------------------------------ 5
titulo "5. Inicio de sesión y ABM de punta a punta (navegador -> web -> api -> MySQL)"
c=$(api POST /api/usuarios/auth/login '{"email":"admin@sigeru.uy","password":"Sigeru2026!"}')
[ "$c" = "200" ]
resultado $? "inicio de sesión del administrador -> $c"
MATRICULA="PRB $(( RANDOM % 9000 + 1000 ))"
c=$(api POST /api/recoleccion/camiones "{\"matricula\":\"$MATRICULA\",\"marca\":\"Volvo\",\"modelo\":\"FL 250\",\"anio\":2024,\"tipo\":\"compactador\",\"capacidad_ton\":10}")
ID=$(grep -o '"id":[0-9]*' "$TMP/respuesta" | head -n 1 | cut -d: -f2)
[ "$c" = "201" ] && [ -n "$ID" ]
resultado $? "alta de un camión de prueba ($MATRICULA) -> $c, id ${ID:-?}"
c=$(api GET "/api/recoleccion/camiones/${ID:-0}")
[ "$c" = "200" ]
resultado $? "consulta del camión -> $c"
c=$(api PUT "/api/recoleccion/camiones/${ID:-0}" '{"modelo":"FL 280"}')
[ "$c" = "200" ] && [ "$(sql "SELECT modelo FROM camiones WHERE id=${ID:-0}")" = "FL 280" ]
resultado $? "modificación del camión (queda guardada en MySQL) -> $c"
if [ $PERSISTENCIA -eq 1 ]; then
    titulo "6. Persistencia: se detienen y se vuelven a crear los contenedores"
    docker compose down > /dev/null 2>&1 && docker compose up -d > /dev/null 2>&1 && esperar_sanos
    resultado $? "contenedores recreados y sanos"
    [ "$(sql "SELECT modelo FROM camiones WHERE id=${ID:-0}")" = "FL 280" ]
    resultado $? "el camión modificado sigue en la base después de recrear los contenedores"
    api POST /api/usuarios/auth/login '{"email":"admin@sigeru.uy","password":"Sigeru2026!"}' > /dev/null
fi
c=$(api DELETE "/api/recoleccion/camiones/${ID:-0}")
[ "$c" = "200" ]
resultado $? "baja del camión de prueba -> $c"
api POST /api/usuarios/auth/logout > /dev/null

# ------------------------------------------------------------------ 7
titulo "7. Respaldo"
docker exec sigeru-respaldo respaldar > "$TMP/respaldo.txt" 2>&1
resultado $? "respaldo generado: $(grep -o 'sigeru_[0-9_]*\.tar\.gz ([^)]*)' "$TMP/respaldo.txt" | head -n 1)"
docker exec sigeru-respaldo verificar > "$TMP/verificacion.txt" 2>&1
resultado $? "verificación del respaldo (SHA-256, gzip, contenido y volcado completo)"
sed 's/^/        /' "$TMP/verificacion.txt"
ultimo=$(ls -1t respaldos/sigeru_*.tar.gz 2>/dev/null | head -n 1)
[ -n "$ultimo" ] && tar -tzf "$ultimo" > /dev/null 2>&1
resultado $? "el .tar.gz está en el anfitrión y se puede abrir: ${ultimo:-ninguno}"

titulo "Resultado: $((TOTAL - FALLAS)) de $TOTAL comprobaciones correctas"
echo "Informe guardado en $(pwd)/$INFORME"
exit "$FALLAS"
