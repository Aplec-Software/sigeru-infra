<?php
// Servidor de desarrollo: emula el gateway Nginx con "php -S" (sin Docker ni MySQL).
//   ./desarrollo/iniciar.sh        (crea las claves y la base SQLite la primera vez)
// Supone los repositorios uno al lado del otro.
$raiz = dirname(__DIR__, 2);
$ruta = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
putenv('DB_DRIVER=sqlite'); putenv('DB_RUTA=' . __DIR__ . '/sigeru.sqlite');
putenv('JWT_CLAVE_PRIVADA=' . __DIR__ . '/claves/jwt_privada.pem'); putenv('JWT_CLAVE_PUBLICA=' . __DIR__ . '/claves/jwt_publica.pem');
putenv('COOKIE_SEGURA=0'); putenv('LOG_ARCHIVO=' . __DIR__ . '/dev.log');
$apis = ['/api/usuarios' => 'sigeru-api-usuarios', '/api/gestion' => 'sigeru-api-gestion', '/api/recoleccion' => 'sigeru-api-recoleccion'];
foreach ($apis as $prefijo => $dir) {
    if (str_starts_with($ruta, $prefijo . '/') || $ruta === $prefijo) {
        putenv("BASE_PATH=$prefijo"); putenv('APP_NOMBRE=' . substr($dir, 7));
        require "$raiz/$dir/public/index.php"; return true;
    }
}
if (str_starts_with($ruta, '/backoffice')) {
    $archivo = "$raiz/sigeru-backoffice/public" . substr($ruta, strlen('/backoffice'));
    if (is_file($archivo) && !str_ends_with($archivo, '.php')) { return servir($archivo); }
    putenv('BASE_PATH=/backoffice'); require "$raiz/sigeru-backoffice/public/index.php"; return true;
}
$base = str_starts_with($ruta, '/app') ? "$raiz/sigeru-frontend" . substr($ruta, 4) : "$raiz/sigeru-landing$ruta";
if (is_dir($base)) { $base = rtrim($base, '/') . '/index.html'; }
if (is_file($base)) { return servir($base); }
http_response_code(404); echo 'No encontrado'; return true;

function servir(string $archivo): bool {
    $tipos = ['html' => 'text/html; charset=utf-8', 'css' => 'text/css', 'js' => 'text/javascript', 'json' => 'application/json',
              'png' => 'image/png', 'svg' => 'image/svg+xml', 'ico' => 'image/x-icon', 'jpg' => 'image/jpeg', 'webp' => 'image/webp'];
    header('Content-Type: ' . ($tipos[pathinfo($archivo, PATHINFO_EXTENSION)] ?? 'application/octet-stream'));
    readfile($archivo); return true;
}
