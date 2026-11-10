#!/bin/bash
# Copia el núcleo común (desarrollo/nucleo) a cada API y al backoffice, y
# regenera los archivos que usan las pruebas. Cada repositorio queda
# independiente: este script solo evita tener que copiar a mano los cambios.
# Supone los repositorios uno al lado del otro (como en /opt/aplec/sigeru).
set -e
RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
SH="$RAIZ/sigeru-infra/desarrollo/nucleo"
DB="$RAIZ/sigeru-infra/db"

ESQUEMA="$(mktemp)"
python3 "$DB/tools/mysql_a_sqlite.py" "$DB/01_estructura.sql" > "$ESQUEMA"

for api in usuarios gestion recoleccion; do
  D="$RAIZ/sigeru-api-$api"
  mkdir -p "$D"/app/{Core,Views,Controllers,Models} "$D"/{public,lang,bin} "$D"/tests/{Support,fixtures,Unit,Feature}
  cp "$SH"/Core/*.php "$D/app/Core/"
  cp "$SH/Views/JsonView.php" "$D/app/Views/"
  cp "$SH/bootstrap.php" "$D/app/"
  cp "$SH/public/index.php" "$SH/public/.htaccess" "$D/public/"
  cp "$SH/lang/es.php" "$D/lang/comun.es.php"
  cp "$SH/lang/en.php" "$D/lang/comun.en.php"
  cp "$SH/Dockerfile.api" "$D/Dockerfile"
  cp "$SH/tests/bootstrap.php" "$D/tests/"
  cp "$SH/tests/Support/TestCase.php" "$D/tests/Support/"
  cp "$ESQUEMA" "$D/tests/fixtures/schema.sqlite.sql"
  cp "$DB/02_datos_base.sql" "$DB/03_datos_prueba.sql" "$D/tests/fixtures/"
  [ -f "$D/bin/.gitkeep" ] || [ "$(ls -A "$D/bin")" ] || touch "$D/bin/.gitkeep"

  cat > "$D/composer.json" <<EOF
{
    "name": "aplec-software/sigeru-api-$api",
    "description": "SiGeRU - API de $api",
    "type": "project",
    "license": "proprietary",
    "require": {
        "php": ">=8.1",
        "ext-pdo": "*",
        "ext-openssl": "*"
    },
    "require-dev": {
        "phpunit/phpunit": "^11.0"
    },
    "autoload": {
        "psr-4": { "App\\\\": "app/" }
    },
    "autoload-dev": {
        "psr-4": { "Tests\\\\": "tests/" }
    },
    "scripts": {
        "test": "phpunit"
    }
}
EOF
  cat > "$D/phpunit.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<phpunit bootstrap="tests/bootstrap.php" colors="true" cacheDirectory=".phpunit.cache">
    <testsuites>
        <testsuite name="Unit">
            <directory>tests/Unit</directory>
        </testsuite>
        <testsuite name="Feature">
            <directory>tests/Feature</directory>
        </testsuite>
    </testsuites>
    <source>
        <include>
            <directory>app</directory>
        </include>
    </source>
</phpunit>
EOF
  printf 'vendor/\n.env\n.phpunit.cache/\n*.log\n' > "$D/.gitignore"
  printf '.git\nvendor\ntests\n.env\n*.md\n.phpunit.cache\n' > "$D/.dockerignore"
done
# Backoffice: usa parte del núcleo (base de datos, validación, idioma, parámetros);
# la sesión, el CSRF, las vistas, el enrutador y la auditoría son propios.
BO="$RAIZ/sigeru-backoffice"
mkdir -p "$BO"/tests/{Support,fixtures,Unit,Feature}
for archivo in Clock Config Database HttpException Lang Model Notifier Params Validator; do
  cp "$SH/Core/$archivo.php" "$BO/app/Core/"
done
cp "$SH/lang/es.php" "$BO/lang/comun.es.php"
cp "$SH/lang/en.php" "$BO/lang/comun.en.php"
cp "$ESQUEMA" "$BO/tests/fixtures/schema.sqlite.sql"
cp "$DB/02_datos_base.sql" "$DB/03_datos_prueba.sql" "$BO/tests/fixtures/"
printf 'vendor/\n.env\n.phpunit.cache/\n*.log\n' > "$BO/.gitignore"
printf '.git\nvendor\ntests\n.env\n*.md\n.phpunit.cache\n' > "$BO/.dockerignore"
rm -f "${ESQUEMA:?}"
echo "Sincronizado"
