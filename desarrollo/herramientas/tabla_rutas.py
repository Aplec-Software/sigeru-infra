#!/usr/bin/env python3
"""Imprime en Markdown la tabla de rutas de una API leyendo su app/rutas.php
(se usa para el README de cada API y para el manual técnico)."""
import re
import sys
from pathlib import Path

ACCIONES_RECURSO = [('GET', '', 'index', 'lectura'), ('GET', '/{id}', 'show', 'lectura'),
                    ('POST', '', 'store', 'escritura'), ('PUT', '/{id}', 'update', 'escritura'),
                    ('DELETE', '/{id}', 'destroy', 'escritura')]


def roles_texto(valor, variables):
    valor = valor.strip()
    if valor in variables:
        valor = variables[valor]
    if valor == 'null':
        return 'pública'
    if valor == '[]':
        return 'cualquier usuario con sesión'
    return ', '.join(re.findall(r"'([a-z]+)'", valor))


def main(ruta_api):
    codigo = Path(ruta_api, 'app/rutas.php').read_text(encoding='utf-8')
    variables = dict(re.findall(r"^(\$\w+)\s*=\s*(\[[^\]]*\]);", codigo, re.M))
    filas = []
    for m in re.finditer(r"\$r->(get|post|put|delete)\('([^']+)',\s*\[(\w+)Controller::class,\s*'(\w+)'\],\s*([^)]+?)\);", codigo):
        metodo, ruta, controlador, accion, roles = m.groups()
        filas.append((metodo.upper(), ruta, f'{controlador}::{accion}', roles_texto(roles, variables)))
    for m in re.finditer(r"\$r->recurso\('([^']+)',\s*(\w+)Controller::class,\s*([^,]+),\s*([^)]+)\);", codigo):
        base, controlador, lectura, escritura = m.groups()
        for metodo, sufijo, accion, tipo in ACCIONES_RECURSO:
            filas.append((metodo, base + sufijo, f'{controlador}::{accion}', roles_texto(lectura if tipo == 'lectura' else escritura, variables)))
    # mismo orden en que aparecen en el archivo
    orden = {r: codigo.find(f"'{r.split('/{')[0]}") for _, r, _, _ in filas}
    filas.sort(key=lambda f: (orden.get(f[1], 0), f[1], ['GET', 'POST', 'PUT', 'DELETE'].index(f[0])))
    print('| Método | Ruta | Controlador | Acceso |')
    print('|---|---|---|---|')
    for metodo, ruta, ctrl, roles in filas:
        print(f'| {metodo} | `{ruta}` | {ctrl} | {roles} |')


if __name__ == '__main__':
    main(sys.argv[1])
