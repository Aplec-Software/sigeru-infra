#!/bin/bash
# =====================================================================
# Genera un respaldo ahora (además del automático diario) y lo verifica.
# Atajo para no tener que recordar el comando dentro del contenedor.
# Uso: bash respaldar.sh
# =====================================================================
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
docker exec sigeru-respaldo respaldar
echo
docker exec sigeru-respaldo listar
