#!/usr/bin/env python3
"""Arma la colección de Postman a partir de los casos de prueba_caja_negra.sh,
así las dos herramientas prueban exactamente lo mismo."""
import json
import shlex
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[3]   # carpeta con todos los repositorios
SCRIPT = RAIZ / 'sigeru-infra/postman/prueba_caja_negra.sh'
DESTINO = RAIZ / 'sigeru-infra/postman'

CUENTAS = {
    'admin': 'admin@sigeru.uy', 'cuadrilla': 'jpereyra@sigeru.uy', 'cuadrilla3': 'pmendez@sigeru.uy',
    'operario': 'rbenitez@sigeru.uy', 'vecino': 'ana.martinez@correo.uy', 'vecino2': 'luis.gomez@correo.uy',
}
CONTENEDOR = ('{"tipo_residuo_id":2,"zona_id":1,"direccion":"Av. Rivera 4321","latitud":-34.8941,'
              '"longitud":-56.1322,"capacidad_litros":2400}')
VARIABLES = {
    '$NUEVO_CONTENEDOR': '{{nuevo_contenedor}}', '$NUEVO_CODIGO': '{{nuevo_codigo}}', '$INCIDENCIA': '{{incidencia}}',
    '$UNICO': '{{$timestamp}}', '$((3300 + UNICO % 600))': '{{numero_camion}}', '$CONTENEDOR': CONTENEDOR,
}
# después de estos casos se guarda un dato de la respuesta para usarlo en los siguientes
GUARDAR = {
    'CG-07': ['pm.collectionVariables.set("nuevo_contenedor", pm.response.json().datos.id);',
              'pm.collectionVariables.set("nuevo_codigo", pm.response.json().datos.codigo);'],
    'CG-10': ['pm.collectionVariables.set("incidencia", pm.response.json().datos.id);'],
}
# antes de estos casos se prepara un dato (Postman no tiene un número de 4 cifras al azar)
PREVIO = {
    'CR-05': ['pm.collectionVariables.set("numero_camion", 3300 + Math.floor(Math.random() * 600));'],
}
CARPETAS = {'usuarios': 'API de Usuarios', 'gestion': 'API de Gestión', 'recoleccion': 'API de Recolección',
            'cierre': 'Cierre de sesión'}
# el cierre de sesión va al final para no invalidar el token que usan los otros casos
CIERRE = {'CU-18', 'CU-19'}


def reemplazar(texto):
    for bash, postman in VARIABLES.items():
        texto = texto.replace(bash, postman)
    return texto


def peticion(nombre, metodo, ruta, usuario, cuerpo=None, pruebas=None, csrf=True, cookies=False):
    """Por defecto se usa el token en la cabecera Authorization y no las cookies.
    cookies=True: la petición guarda/envía la cookie de sesión (como el navegador)."""
    cabeceras = [{'key': 'Accept', 'value': 'application/json'}]
    if csrf:
        cabeceras.append({'key': 'X-Requested-With', 'value': 'SiGeRU'})
    if usuario != 'anonimo' and not cookies:
        cabeceras.append({'key': 'Authorization', 'value': '{{token_%s}}' % usuario})
    item = {
        'name': nombre,
        'protocolProfileBehavior': {'disableCookies': not cookies},
        'request': {
            'method': metodo,
            'header': cabeceras,
            'url': {'raw': '{{base}}' + ruta, 'host': ['{{base}}'], 'path': [p for p in ruta.split('?')[0].split('/') if p]},
        },
        'event': [{'listen': 'test', 'script': {'type': 'text/javascript', 'exec': pruebas or []}}],
    }
    previo = PREVIO.get(nombre.split(' ')[0])
    if previo:
        item['event'].insert(0, {'listen': 'prerequest', 'script': {'type': 'text/javascript', 'exec': previo}})
    if '?' in ruta:
        item['request']['url']['query'] = [
            {'key': k, 'value': v} for k, v in (par.split('=', 1) for par in ruta.split('?', 1)[1].split('&'))
        ]
    if cuerpo:
        cabeceras.append({'key': 'Content-Type', 'value': 'application/json'})
        item['request']['body'] = {'mode': 'raw', 'raw': json.dumps(json.loads(cuerpo), ensure_ascii=False, indent=2)
                                   if '{{' not in cuerpo else cuerpo}
    return item


def main():
    lineas = SCRIPT.read_text(encoding='utf-8').splitlines()
    carpetas = {clave: [] for clave in CARPETAS}

    inicio = []
    for usuario, email in CUENTAS.items():
        inicio.append(peticion(
            f'Login {usuario}', 'POST', '/api/usuarios/auth/login', 'anonimo',
            json.dumps({'email': email, 'password': '{{clave_prueba}}'}),
            ['pm.test("200 OK", () => pm.response.to.have.status(200));',
             f'pm.collectionVariables.set("token_{usuario}", "Bearer " + pm.response.json().datos.token);'],
            cookies=True))

    for linea in lineas:
        linea = linea.strip()
        sin_csrf = linea.startswith('SIN_CABECERA=1 ')
        if sin_csrf:
            linea = linea[len('SIN_CABECERA=1 '):]
        if not linea.startswith('caso '):
            continue
        partes = shlex.split(linea, posix=True)
        _, id_caso, modulo, descripcion, usuario, metodo, ruta, esperado, *resto = partes
        cuerpo = reemplazar(resto[0]) if resto else None
        ruta = reemplazar(ruta)
        pruebas = [f'pm.test("{id_caso}: responde {esperado}", () => pm.response.to.have.status({esperado}));']
        if esperado.startswith('2') and 'csv' not in ruta:
            pruebas.append('pm.test("Formato de respuesta de SiGeRU", () => pm.expect(pm.response.json().status).to.eql("ok"));')
        pruebas += GUARDAR.get(id_caso, [])
        # el control CSRF solo aplica cuando la sesión viaja en la cookie (navegador)
        carpetas['cierre' if id_caso in CIERRE else modulo].append(peticion(f'{id_caso} {descripcion}', metodo, ruta, usuario, cuerpo, pruebas,
                                         csrf=not sin_csrf, cookies=sin_csrf))

    coleccion = {
        'info': {
            'name': 'SiGeRU - APIs',
            'description': 'Pruebas de caja negra de las APIs de SiGeRU (Aplec Software). '
                           'Ejecutar la colección completa en orden (Runner) sobre una base con los datos de prueba. '
                           'La última sesión iniciada (vecino2) queda en la cookie y la usa el caso CU-17. '
                           'Con el entorno "servidor" desactivar la verificación SSL (certificado propio).',
            'schema': 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
        },
        'item': [{'name': '0. Inicio de sesión', 'item': inicio}]
                + [{'name': f'{n}. {CARPETAS[clave]}', 'item': carpetas[clave]} for n, clave in enumerate(CARPETAS, 1)],
        'variable': [{'key': 'clave_prueba', 'value': 'Sigeru2026!'}]
                    + [{'key': f'token_{u}', 'value': ''} for u in CUENTAS]
                    + [{'key': k, 'value': ''} for k in ('nuevo_contenedor', 'nuevo_codigo', 'incidencia', 'numero_camion')],
    }
    (DESTINO / 'SiGeRU.postman_collection.json').write_text(json.dumps(coleccion, ensure_ascii=False, indent=2), encoding='utf-8')
    for nombre, base in (('desarrollo', 'http://127.0.0.1:8080'), ('servidor', 'https://192.168.56.10')):
        entorno = {'name': f'SiGeRU - {nombre}', 'values': [{'key': 'base', 'value': base, 'enabled': True}]}
        (DESTINO / f'SiGeRU-{nombre}.postman_environment.json').write_text(json.dumps(entorno, indent=2), encoding='utf-8')
    total = sum(len(v) for v in carpetas.values())
    print(f'Colección generada: {total} casos + {len(inicio)} inicios de sesión')
    return 0


if __name__ == '__main__':
    sys.exit(main())
