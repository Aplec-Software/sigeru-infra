#!/bin/bash
# =====================================================================
# Arranque del contenedor api: genera las claves JWT la primera vez y
# deja Apache en primer plano.
# =====================================================================
set -euo pipefail

php /usr/local/lib/sigeru/claves.php /claves

exec apache2-foreground
