#!/bin/bash
# =====================================================================
# Entorno de desarrollo sin Docker ni MySQL: levanta todo SiGeRU con el
# servidor incorporado de PHP y una base SQLite con los datos de prueba.
#
#   ./iniciar.sh            -> http://127.0.0.1:8080
#
# Requiere PHP 8.1 o superior con pdo_sqlite y openssl, y Python 3.
# =====================================================================
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
PUERTO=${1:-8080}

if [ ! -f "$DIR/claves/jwt_privada.pem" ]; then
    mkdir -p "$DIR/claves"
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$DIR/claves/jwt_privada.pem" 2>/dev/null
    openssl pkey -in "$DIR/claves/jwt_privada.pem" -pubout -out "$DIR/claves/jwt_publica.pem"
    echo "Claves JWT de desarrollo generadas."
fi
if [ ! -f "$DIR/sigeru.sqlite" ]; then
    "$DIR/reiniciar_bd.sh"
fi

echo "SiGeRU en http://127.0.0.1:$PUERTO  (landing /, aplicación /app/, backoffice /backoffice/)"
echo "Usuarios de prueba: admin@sigeru.uy, jpereyra@sigeru.uy, rbenitez@sigeru.uy, ana.martinez@correo.uy - clave Sigeru2026!"
cd "$DIR/../.."
exec php -S "127.0.0.1:$PUERTO" "$DIR/router.php"
