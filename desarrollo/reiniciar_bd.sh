#!/bin/bash
# Vuelve a crear la base SQLite de desarrollo con la estructura y los datos de prueba.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
DB="$DIR/../db"
ESQUEMA="$(mktemp)"
python3 "$DB/tools/mysql_a_sqlite.py" "$DB/01_estructura.sql" > "$ESQUEMA"
rm -f "${DIR:?}/sigeru.sqlite"
php -r '
$pdo = new PDO("sqlite:" . $argv[1]);
$pdo->exec("PRAGMA foreign_keys = ON");
// SET NAMES es solo de MySQL (los scripts lo traen para cargar bien los acentos): SQLite ya trabaja en UTF-8
foreach (array_slice($argv, 2) as $archivo) { $pdo->exec(preg_replace("/^SET NAMES [^;]*;\\s*$/mi", "", file_get_contents($archivo))); }
echo "Base de desarrollo creada: ", $pdo->query("SELECT COUNT(*) FROM incidencias")->fetchColumn(), " incidencias\n";
' "$DIR/sigeru.sqlite" "$ESQUEMA" "$DB/02_datos_base.sql" "$DB/03_datos_prueba.sql"
rm -f "${ESQUEMA:?}"
