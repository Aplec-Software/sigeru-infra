#!/bin/bash
# =====================================================================
# Arranque del contenedor web: prepara el certificado HTTPS (la primera vez
# o si cambian el nombre o la IP del servidor) y deja Apache en primer plano.
# =====================================================================
set -euo pipefail

export SERVIDOR_NOMBRE="${SERVIDOR_NOMBRE:-sigeru.local}"
php /usr/local/lib/sigeru/certificado.php /etc/sigeru/certificados "$SERVIDOR_NOMBRE" "${SERVIDOR_IP:-}"

# La redirección de HTTP a HTTPS incluye el puerto solo si no es el 443
if [ "${PUERTO_HTTPS:-443}" = "443" ]; then
    export REDIR_PUERTO=""
else
    export REDIR_PUERTO=":${PUERTO_HTTPS}"
fi

exec apache2-foreground
