#!/usr/bin/env python3
"""
Convierte 01_estructura.sql (MySQL 8) a un esquema equivalente para SQLite.

Se usa solamente para las pruebas automáticas: los tests de las APIs levantan
una base SQLite en memoria con la misma estructura que la base real, así se
pueden ejecutar sin tener un servidor MySQL disponible.

Uso:
    python3 mysql_a_sqlite.py ../01_estructura.sql > schema.sqlite.sql
"""
import re
import sys


def convertir_columna(linea: str) -> str:
    # ENUM('a','b') -> TEXT ... CHECK (col IN ('a','b'))
    m = re.match(r"^(\s*)(\w+)\s+ENUM\(([^)]*)\)(.*?)(,?)\s*$", linea)
    if m:
        sangria, col, valores, resto, coma = m.groups()
        resto = resto.strip()
        return f"{sangria}{col} TEXT {resto} CHECK ({col} IN ({valores})){coma}\n".replace("  ", " ")

    l = linea
    l = re.sub(r"\b(TINYINT|SMALLINT|INT|BIGINT)\s+UNSIGNED\s+AUTO_INCREMENT\s+PRIMARY KEY",
               "INTEGER PRIMARY KEY AUTOINCREMENT", l)
    l = re.sub(r"\bTINYINT\(1\)", "INTEGER", l)
    l = re.sub(r"\b(TINYINT|SMALLINT|BIGINT|INT)\s+UNSIGNED\b", "INTEGER", l)
    l = re.sub(r"\b(TINYINT|SMALLINT|BIGINT)\b", "INTEGER", l)
    l = re.sub(r"\bDECIMAL\(\d+,\d+\)", "NUMERIC", l)
    l = re.sub(r"\bDATETIME\b", "TEXT", l)
    l = re.sub(r"\bDATE\b", "TEXT", l)
    l = l.replace(" ON UPDATE CURRENT_TIMESTAMP", "")
    return l


def convertir(sql: str) -> str:
    salida = ["PRAGMA foreign_keys = ON;\n"]
    for linea in sql.splitlines(keepends=True):
        s = linea.strip()
        if not s or s.startswith("--"):
            continue
        if re.match(r"^(CREATE DATABASE|USE |SET |DEFAULT CHARACTER|DEFAULT COLLATE)", s):
            continue
        if s.startswith("DROP "):
            continue
        linea = re.sub(r"\)\s*ENGINE=.*;", ");", linea)
        salida.append(convertir_columna(linea))
    return "".join(salida)


if __name__ == "__main__":
    origen = sys.argv[1] if len(sys.argv) > 1 else "01_estructura.sql"
    with open(origen, encoding="utf-8") as f:
        print(convertir(f.read()))
