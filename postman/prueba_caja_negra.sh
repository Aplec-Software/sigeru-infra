#!/bin/bash
# =====================================================================
# SiGeRU - Pruebas de caja negra de las APIs (a través del gateway)
#
# Solo se usan las URL públicas, como lo haría el navegador: no se mira
# el código. Cada caso indica quién hace la petición, qué se envía y qué
# código HTTP se espera. El resultado queda en un archivo CSV que se usa
# en el plan de pruebas.
#
#   ./prueba_caja_negra.sh https://192.168.56.10      (servidor)
#   ./prueba_caja_negra.sh http://127.0.0.1:8080      (entorno de desarrollo)
#
# IMPORTANTE: crea y modifica datos. Ejecutar sobre la base con los datos
# de prueba (03_datos_prueba.sql), nunca sobre la base en producción.
# =====================================================================

BASE=${1:-https://192.168.56.10}
CLAVE_PRUEBA='Sigeru2026!'
TMP=$(mktemp -d)
SALIDA="resultados_caja_negra_$(date +%Y%m%d_%H%M).csv"
TOTAL=0
APROBADOS=0
UNICO=$(date +%s)

echo "id;modulo;caso;usuario;metodo;ruta;esperado;obtenido;resultado" > "$SALIDA"

# Inicia sesión y guarda la cookie del usuario en $TMP/<nombre>.txt
iniciar_sesion() {
    curl -sk -c "$TMP/$1.txt" -o /dev/null -w '%{http_code}' -X POST \
        -H 'Content-Type: application/json' -H 'X-Requested-With: SiGeRU' \
        -d "{\"email\":\"$2\",\"password\":\"$CLAVE_PRUEBA\"}" "$BASE/api/usuarios/auth/login"
}

# caso ID MODULO "descripción" USUARIO METODO RUTA ESPERADO [JSON]
caso() {
    local id=$1 modulo=$2 descripcion=$3 usuario=$4 metodo=$5 ruta=$6 esperado=$7 cuerpo=${8:-}
    local args=(-sk -o "$TMP/respuesta" -w '%{http_code}' -X "$metodo" -H 'Accept: application/json')
    [ "${SIN_CABECERA:-0}" = "1" ] || args+=(-H 'X-Requested-With: SiGeRU')
    [ "$usuario" != "anonimo" ] && args+=(-b "$TMP/$usuario.txt")
    [ -n "$cuerpo" ] && args+=(-H 'Content-Type: application/json' --data "$cuerpo")
    local obtenido
    obtenido=$(curl "${args[@]}" "$BASE$ruta")
    TOTAL=$((TOTAL + 1))
    local resultado="FALLA"
    if [ "$obtenido" = "$esperado" ]; then
        resultado="OK"
        APROBADOS=$((APROBADOS + 1))
    fi
    printf "%-6s %-5s %-4s %-6s %-60s %s\n" "$id" "$esperado" "$obtenido" "$resultado" "${descripcion:0:60}" "($usuario)"
    echo "$id;$modulo;$descripcion;$usuario;$metodo;$ruta;$esperado;$obtenido;$resultado" >> "$SALIDA"
}

# Lee un dato de la última respuesta JSON, por ejemplo: dato datos.id
dato() {
    python3 -c '
import json, sys
valor = json.load(open(sys.argv[1]))
for parte in sys.argv[2].split("."):
    valor = valor[int(parte)] if parte.isdigit() else valor[parte]
print(valor)' "$TMP/respuesta" "$1" 2>/dev/null
}

echo "Pruebas de caja negra contra $BASE"
echo "Inicio de sesión de los usuarios de prueba:"
for par in admin:admin@sigeru.uy cuadrilla:jpereyra@sigeru.uy cuadrilla3:pmendez@sigeru.uy operario:rbenitez@sigeru.uy vecino:ana.martinez@correo.uy vecino2:luis.gomez@correo.uy; do
    echo "  ${par%%:*} -> $(iniciar_sesion "${par%%:*}" "${par#*:}")"
done
echo
printf "%-6s %-5s %-4s %-6s %s\n" "CASO" "ESP." "OBT." "RESULT" "DESCRIPCIÓN"

# ------------------------------------------------------------- Usuarios
caso CU-01 usuarios "Estado del servicio" anonimo GET /api/usuarios/salud 200
caso CU-02 usuarios "Login con contraseña incorrecta" anonimo POST /api/usuarios/auth/login 401 '{"email":"admin@sigeru.uy","password":"Incorrecta1!"}'
caso CU-03 usuarios "Login con correo mal escrito" anonimo POST /api/usuarios/auth/login 422 '{"email":"no-es-correo","password":"x"}'
caso CU-04 usuarios "Login de cuenta pendiente de aprobación" anonimo POST /api/usuarios/auth/login 403 '{"email":"mcabrera@sigeru.uy","password":"Sigeru2026!"}'
caso CU-05 usuarios "Datos de la sesión sin iniciar sesión" anonimo GET /api/usuarios/auth/me 401
caso CU-06 usuarios "Datos de la sesión del administrador" admin GET /api/usuarios/auth/me 200
caso CU-07 usuarios "Registro de vecino" anonimo POST /api/usuarios/auth/registro 201 "{\"nombre\":\"Rosa\",\"apellido\":\"Pérez\",\"email\":\"rosa$UNICO@correo.uy\",\"password\":\"ClaveSegura#1\"}"
caso CU-08 usuarios "Registro con correo ya usado" anonimo POST /api/usuarios/auth/registro 409 '{"nombre":"Ana","apellido":"Otra","email":"ana.martinez@correo.uy","password":"ClaveSegura#1"}'
caso CU-09 usuarios "Registro con contraseña débil" anonimo POST /api/usuarios/auth/registro 422 "{\"nombre\":\"Rosa\",\"apellido\":\"Pérez\",\"email\":\"debil$UNICO@correo.uy\",\"password\":\"1234\"}"
caso CU-10 usuarios "Registro de personal con cédula inválida" anonimo POST /api/usuarios/auth/registro 422 "{\"nombre\":\"Hugo\",\"apellido\":\"Vera\",\"email\":\"hv$UNICO@sigeru.uy\",\"password\":\"ClaveSegura#1\",\"rol\":\"operario\",\"documento\":\"12345678\"}"
caso CU-11 usuarios "Listado de usuarios como vecino" vecino GET /api/usuarios/usuarios 403
caso CU-12 usuarios "Listado de usuarios como administrador" admin GET "/api/usuarios/usuarios?estado=pendiente" 200
caso CU-13 usuarios "Parámetros públicos sin sesión" anonimo GET /api/usuarios/parametros/publicos 200
caso CU-14 usuarios "Cambiar un parámetro con valor inválido" admin PUT /api/usuarios/parametros/umbral_ocupacion_centro 422 '{"valor":"mucho"}'
caso CU-15 usuarios "Notificaciones del administrador" admin GET /api/usuarios/notificaciones 200
caso CU-16 usuarios "Método no permitido" admin DELETE /api/usuarios/auth/me 405
SIN_CABECERA=1 caso CU-17 usuarios "Modificar perfil sin la cabecera anti-CSRF" vecino PUT /api/usuarios/perfil 403 '{"idioma":"en"}'

# -------------------------------------------------------------- Gestión
caso CG-01 gestion "Mapa público" anonimo GET /api/gestion/mapa 200
caso CG-02 gestion "Contenedores públicos paginados" anonimo GET "/api/gestion/contenedores?por_pagina=5&zona_id=1" 200
caso CG-03 gestion "Contenedor por código QR" anonimo GET /api/gestion/contenedores/codigo/CNT-0005 200
caso CG-04 gestion "Contenedor inexistente" anonimo GET /api/gestion/contenedores/codigo/CNT-9999 404
CONTENEDOR='{"tipo_residuo_id":2,"zona_id":1,"direccion":"Av. Rivera 4321","latitud":-34.8941,"longitud":-56.1322,"capacidad_litros":2400}'
caso CG-05 gestion "Alta de contenedor sin sesión" anonimo POST /api/gestion/contenedores 401 "$CONTENEDOR"
caso CG-06 gestion "Alta de contenedor como vecino" vecino POST /api/gestion/contenedores 403 "$CONTENEDOR"
caso CG-07 gestion "Alta de contenedor como administrador" admin POST /api/gestion/contenedores 201 "$CONTENEDOR"
NUEVO_CONTENEDOR=$(dato datos.id)
NUEVO_CODIGO=$(dato datos.codigo)
caso CG-08 gestion "Alta con latitud fuera de rango" admin POST /api/gestion/contenedores 422 '{"tipo_residuo_id":2,"zona_id":1,"direccion":"Av. Rivera 4321","latitud":200,"longitud":-56.1322,"capacidad_litros":2400}'
caso CG-09 gestion "Alta con código repetido" admin POST /api/gestion/contenedores 409 '{"codigo":"CNT-0001","tipo_residuo_id":2,"zona_id":1,"direccion":"Av. Rivera 4321","latitud":-34.89,"longitud":-56.13,"capacidad_litros":2400}'
caso CG-10 gestion "Reporte de incidencia de vecino" vecino POST /api/gestion/incidencias 201 "{\"contenedor_id\":$NUEVO_CONTENEDOR,\"tipo\":\"desborde\"}"
INCIDENCIA=$(dato datos.id)
caso CG-11 gestion "Mismo reporte de otro vecino (se agrupa)" vecino2 POST /api/gestion/incidencias 200 "{\"contenedor_id\":$NUEVO_CONTENEDOR,\"tipo\":\"desborde\"}"
caso CG-12 gestion "Reporte sobre contenedor dado de baja" vecino POST /api/gestion/incidencias 409 '{"contenedor_id":48,"tipo":"desborde"}'
caso CG-13 gestion "Asignar la incidencia a la cuadrilla 1" admin PUT "/api/gestion/incidencias/$INCIDENCIA/asignar" 200 '{"cuadrilla_id":1}'
caso CG-14 gestion "Resolver sin describir la solución" cuadrilla PUT "/api/gestion/incidencias/$INCIDENCIA/estado" 422 '{"estado":"resuelta"}'
caso CG-15 gestion "Resolver con comentario" cuadrilla PUT "/api/gestion/incidencias/$INCIDENCIA/estado" 200 '{"estado":"resuelta","comentario":"Se vació el contenedor"}'
caso CG-16 gestion "Transición no permitida (resuelta a descartada)" admin PUT "/api/gestion/incidencias/$INCIDENCIA/estado" 409 '{"estado":"descartada"}'
caso CG-17 gestion "Historial de la incidencia" admin GET "/api/gestion/incidencias/$INCIDENCIA/historial" 200
caso CG-18 gestion "Reporte anónimo por QR" anonimo POST /api/gestion/incidencias/qr 201 "{\"contenedor_codigo\":\"$NUEVO_CODIGO\",\"tipo\":\"rotura\"}"
caso CG-19 gestion "Segundo reporte QR desde la misma IP" anonimo POST /api/gestion/incidencias/qr 201 '{"contenedor_codigo":"CNT-0010","tipo":"quema"}'
caso CG-20 gestion "Tercer reporte QR desde la misma IP" anonimo POST /api/gestion/incidencias/qr 201 '{"contenedor_codigo":"CNT-0010","tipo":"falta_recoleccion"}'
caso CG-21 gestion "Cuarto reporte QR desde la misma IP" anonimo POST /api/gestion/incidencias/qr 201 '{"contenedor_codigo":"CNT-0010","tipo":"otro"}'
caso CG-22 gestion "Quinto reporte QR desde la misma IP" anonimo POST /api/gestion/incidencias/qr 201 '{"contenedor_codigo":"CNT-0010","tipo":"desborde"}'
caso CG-23 gestion "Sexto reporte QR en la misma hora (límite)" anonimo POST /api/gestion/incidencias/qr 429 '{"contenedor_codigo":"CNT-0010","tipo":"rotura"}'
caso CG-24 gestion "Movimiento en el centro propio del operario" operario POST /api/gestion/centros/1/movimientos 201 '{"tipo_movimiento":"ingreso","tipo_residuo_id":2,"peso_ton":1.5}'
caso CG-25 gestion "Movimiento en un centro ajeno" operario POST /api/gestion/centros/2/movimientos 403 '{"tipo_movimiento":"ingreso","tipo_residuo_id":2,"peso_ton":1}'
caso CG-26 gestion "Ingreso que supera la capacidad del centro" operario POST /api/gestion/centros/1/movimientos 409 '{"tipo_movimiento":"ingreso","tipo_residuo_id":2,"peso_ton":400}'
caso CG-27 gestion "Salida de repuestos sin stock suficiente" admin POST /api/gestion/repuestos/1/movimientos 409 '{"tipo":"salida","cantidad":999,"motivo":"Prueba"}'
caso CG-28 gestion "Estadísticas como cuadrilla" cuadrilla GET /api/gestion/estadisticas/resumen 403
caso CG-29 gestion "Estadísticas como administrador" admin GET /api/gestion/estadisticas/resumen 200
caso CG-30 gestion "Informe de incidencias en CSV" admin GET "/api/gestion/informes/incidencias?formato=csv&desde=2026-10-01" 200
caso CG-31 gestion "Borrar una zona con contenedores" admin DELETE /api/gestion/zonas/1 409

# ---------------------------------------------------------- Recolección
caso CR-01 recoleccion "Estado del servicio" anonimo GET /api/recoleccion/salud 200
caso CR-02 recoleccion "Listado de camiones sin sesión" anonimo GET /api/recoleccion/camiones 401
caso CR-03 recoleccion "Listado de camiones como cuadrilla" cuadrilla GET /api/recoleccion/camiones 200
caso CR-04 recoleccion "Alta de camión con matrícula mal escrita" admin POST /api/recoleccion/camiones 422 '{"matricula":"sim3201","marca":"Volvo","modelo":"VM 270","anio":2024,"tipo":"compactador","capacidad_ton":11}'
caso CR-05 recoleccion "Alta de camión" admin POST /api/recoleccion/camiones 201 "{\"matricula\":\"SIM $((3300 + UNICO % 600))\",\"marca\":\"Volvo\",\"modelo\":\"VM 270\",\"anio\":2024,\"tipo\":\"compactador\",\"capacidad_ton\":11}"
caso CR-06 recoleccion "Asignación con fecha pasada" admin POST /api/recoleccion/asignaciones 422 '{"ruta_id":4,"cuadrilla_id":1,"camion_id":6,"fecha":"2026-10-01","turno":"nocturno"}'
caso CR-07 recoleccion "Asignación con camión en mantenimiento" admin POST /api/recoleccion/asignaciones 409 '{"ruta_id":4,"cuadrilla_id":1,"camion_id":8,"fecha":"2026-11-03","turno":"nocturno"}'
caso CR-08 recoleccion "Asignación con la cuadrilla ya ocupada en el turno" admin POST /api/recoleccion/asignaciones 409 '{"ruta_id":4,"cuadrilla_id":2,"camion_id":1,"fecha":"2026-11-02","turno":"matutino"}'
caso CR-09 recoleccion "Recorridos de hoy de la cuadrilla" cuadrilla3 GET /api/recoleccion/asignaciones/hoy 200
caso CR-10 recoleccion "Mi cuadrilla" cuadrilla GET /api/recoleccion/cuadrillas/mia 200
caso CR-11 recoleccion "Ruta con contenedores repetidos" admin PUT /api/recoleccion/rutas/4/contenedores 422 '{"contenedores":[37,37]}'
caso CR-12 recoleccion "Volumen recolectado como cuadrilla" cuadrilla GET /api/recoleccion/estadisticas/volumen 403
caso CR-13 recoleccion "Volumen recolectado por zona" admin GET "/api/recoleccion/estadisticas/volumen?desde=2026-10-01&hasta=2026-10-29&agrupar=zona" 200
caso CR-14 recoleccion "Ruta inexistente" admin GET /api/recoleccion/rutas/999 404
caso CR-15 recoleccion "Recurso inexistente en la API" admin GET /api/recoleccion/no-existe 404
caso CR-16 recoleccion "Propuesta de orden de una ruta" admin GET /api/recoleccion/rutas/1/optimizacion 200
caso CR-17 recoleccion "Propuesta de orden de una ruta como cuadrilla" cuadrilla GET /api/recoleccion/rutas/1/optimizacion 403

# ---------------------------------------------------------- Sesión
caso CU-18 usuarios "Cerrar sesión" vecino2 POST /api/usuarios/auth/logout 200
caso CU-19 usuarios "Usar la sesión ya cerrada" vecino2 GET /api/usuarios/auth/me 401

echo
echo "Resultado: $APROBADOS de $TOTAL casos con el código esperado."
echo "Detalle guardado en $SALIDA"
rm -rf "${TMP:?}"
[ "$APROBADOS" -eq "$TOTAL" ]
