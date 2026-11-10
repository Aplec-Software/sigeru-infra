# =====================================================================
# Contenedor web de SiGeRU: Apache + PHP 8.3
#   /              landing (archivos estáticos)
#   /app/          frontend de usuarios (archivos estáticos)
#   /backoffice/   backoffice (PHP), en un sitio interno 127.0.0.1:8081
#   /api/...       se reenvía al contenedor api
# Atiende HTTPS con un certificado de la autoridad certificadora propia,
# que se genera la primera vez que arranca (sigeru-web-inicio).
#
# Las fuentes vienen de los repositorios de cada aplicación (contextos
# "landing", "frontend" y "backoffice" definidos en compose.yaml).
# =====================================================================
# Versión fijada en una que incluye los parches de seguridad de octubre de 2026
# (php2shell: CVE-2026-109618 y CVE-2026-109619, corregidas en PHP 8.3.36).
ARG PHP_VERSION=8.3.36
FROM php:${PHP_VERSION}-apache

RUN docker-php-ext-install pdo_mysql \
    && a2enmod ssl socache_shmcb rewrite headers proxy proxy_http \
    && a2dissite 000-default \
    && mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && printf '%s\n' \
        'expose_php = Off' \
        'display_errors = Off' \
        'log_errors = On' \
        'session.use_strict_mode = 1' \
        'session.cookie_httponly = 1' \
        'session.gc_maxlifetime = 1800' \
        '; mitigación recomendada por PHP para CVE-2026-115560 (aviso del 23/10/2026)' \
        'session.upload_progress.enabled = 0' \
        > "$PHP_INI_DIR/conf.d/sigeru.ini" \
    && mkdir -p /var/log/sigeru /etc/sigeru/certificados /var/www/sigeru/errores \
    && chown www-data:www-data /var/log/sigeru

# Configuración de Apache (sitios 80, 443 e interno 8081)
COPY apache/ports.conf /etc/apache2/ports.conf
COPY apache/sigeru-web.conf /etc/apache2/sites-available/sigeru-web.conf
RUN a2ensite sigeru-web

# Aplicaciones
COPY --from=landing index.html /var/www/sigeru/landing/
COPY --from=landing css/ /var/www/sigeru/landing/css/
COPY --from=landing js/ /var/www/sigeru/landing/js/
COPY --from=landing img/ /var/www/sigeru/landing/img/
COPY --from=landing lang/ /var/www/sigeru/landing/lang/

COPY --from=frontend index.html /var/www/sigeru/frontend/
COPY --from=frontend css/ /var/www/sigeru/frontend/css/
COPY --from=frontend js/ /var/www/sigeru/frontend/js/
COPY --from=frontend img/ /var/www/sigeru/frontend/img/
COPY --from=frontend lang/ /var/www/sigeru/frontend/lang/

COPY --from=backoffice app/ /var/www/sigeru/backoffice/app/
COPY --from=backoffice lang/ /var/www/sigeru/backoffice/lang/
COPY --from=backoffice public/ /var/www/sigeru/backoffice/public/

# Página de mantenimiento, chequeo de salud y arranque
COPY mantenimiento.html /var/www/sigeru/errores/mantenimiento.html
COPY certificado.php /usr/local/lib/sigeru/certificado.php
COPY sigeru-web-inicio.sh /usr/local/bin/sigeru-web-inicio
RUN printf 'ok\n' > /var/www/sigeru/errores/salud.txt \
    && chmod 755 /usr/local/bin/sigeru-web-inicio \
    && chown -R root:root /var/www/sigeru \
    && find /var/www/sigeru -type d -exec chmod 755 {} + \
    && find /var/www/sigeru -type f -exec chmod 644 {} +

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS -o /dev/null http://127.0.0.1/salud && curl -fsS -o /dev/null http://127.0.0.1:8081/login || exit 1

EXPOSE 80 443
CMD ["sigeru-web-inicio"]
