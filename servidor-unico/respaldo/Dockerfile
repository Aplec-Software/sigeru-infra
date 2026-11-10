# =====================================================================
# Contenedor de respaldos de SiGeRU
# Usa la imagen de MySQL 8.4 solo por sus herramientas (mysqldump y el
# cliente mysql, de la misma versión que el servidor); no ejecuta MySQL.
#   sigeru-respaldo   servicio: respaldo al arrancar si no hay ninguno y
#                     después todos los días a la hora RESPALDO_HORA
#   respaldar         genera un respaldo ahora
#   verificar         verifica un respaldo (o el último)
#   listar            lista los respaldos guardados
# Los archivos quedan en /respaldos (carpeta respaldos/ del anfitrión).
# =====================================================================
FROM mysql:8.4

# tar para empaquetar (gzip, openssl y sha256sum ya vienen en la imagen)
RUN microdnf install -y tar \
    && microdnf clean all

COPY servicio.sh  /usr/local/bin/sigeru-respaldo
COPY respaldar.sh /usr/local/bin/respaldar
COPY verificar.sh /usr/local/bin/verificar
COPY listar.sh    /usr/local/bin/listar
COPY salud.sh     /usr/local/bin/sigeru-respaldo-salud
COPY comun.sh     /usr/local/lib/sigeru-respaldo-comun.sh
RUN chmod 755 /usr/local/bin/sigeru-respaldo /usr/local/bin/respaldar /usr/local/bin/verificar \
              /usr/local/bin/listar /usr/local/bin/sigeru-respaldo-salud \
    && mkdir -p /respaldos

# Sano si el último respaldo tiene menos de 26 horas y pasó la verificación
HEALTHCHECK --interval=60s --timeout=10s --start-period=180s --retries=2 \
    CMD sigeru-respaldo-salud

ENTRYPOINT []
CMD ["sigeru-respaldo"]
