# =====================================================================
# Contenedor api de SiGeRU: Apache + PHP 8.3 con las tres APIs REST
#   puerto 8001   API de Usuarios
#   puerto 8002   API de Gestión
#   puerto 8003   API de Recolección
# Cada API es un sitio de Apache con su carpeta, su usuario de MySQL y su
# log. No publica puertos: se llega solo desde el contenedor web, por la
# red de Docker. La primera vez que arranca genera el par de claves RSA de
# los JWT (sigeru-api-inicio).
#
# Las fuentes vienen de los repositorios de cada API (contextos "usuarios",
# "gestion" y "recoleccion" definidos en compose.yaml).
# =====================================================================
# Versión fijada en una que incluye los parches de seguridad de octubre de 2026
# (php2shell: CVE-2026-109618 y CVE-2026-109619, corregidas en PHP 8.3.36).
ARG PHP_VERSION=8.3.36
FROM php:${PHP_VERSION}-apache

RUN docker-php-ext-install pdo_mysql \
    && a2enmod rewrite headers \
    && a2dissite 000-default \
    && mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && printf '%s\n' \
        'expose_php = Off' \
        'display_errors = Off' \
        'log_errors = On' \
        '; mitigación recomendada por PHP para CVE-2026-115560 (aviso del 23/10/2026)' \
        'session.upload_progress.enabled = 0' \
        > "$PHP_INI_DIR/conf.d/sigeru.ini" \
    && mkdir -p /var/log/sigeru /claves \
    && chown www-data:www-data /var/log/sigeru

# Configuración de Apache (un sitio por API)
COPY apache/ports.conf /etc/apache2/ports.conf
COPY apache/sigeru-api.conf /etc/apache2/sites-available/sigeru-api.conf
RUN a2ensite sigeru-api

# Las tres APIs
COPY --from=usuarios app/ /var/www/sigeru/api-usuarios/app/
COPY --from=usuarios lang/ /var/www/sigeru/api-usuarios/lang/
COPY --from=usuarios public/ /var/www/sigeru/api-usuarios/public/
COPY --from=usuarios bin/ /var/www/sigeru/api-usuarios/bin/

COPY --from=gestion app/ /var/www/sigeru/api-gestion/app/
COPY --from=gestion lang/ /var/www/sigeru/api-gestion/lang/
COPY --from=gestion public/ /var/www/sigeru/api-gestion/public/

COPY --from=recoleccion app/ /var/www/sigeru/api-recoleccion/app/
COPY --from=recoleccion lang/ /var/www/sigeru/api-recoleccion/lang/
COPY --from=recoleccion public/ /var/www/sigeru/api-recoleccion/public/
COPY --from=recoleccion bin/ /var/www/sigeru/api-recoleccion/bin/

COPY claves.php /usr/local/lib/sigeru/claves.php
COPY sigeru-api-inicio.sh /usr/local/bin/sigeru-api-inicio
RUN chmod 755 /usr/local/bin/sigeru-api-inicio \
    && chown -R root:root /var/www/sigeru \
    && find /var/www/sigeru -type d -exec chmod 755 {} + \
    && find /var/www/sigeru -type f -exec chmod 644 {} +

# Sano solo si las tres APIs responden y llegan a la base de datos
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -fsS -o /dev/null http://127.0.0.1:8001/salud \
     && curl -fsS -o /dev/null http://127.0.0.1:8002/salud \
     && curl -fsS -o /dev/null http://127.0.0.1:8003/salud || exit 1

EXPOSE 8001 8002 8003
CMD ["sigeru-api-inicio"]
