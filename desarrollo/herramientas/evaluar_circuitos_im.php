<?php

/**
 * Prueba de escala del orden de los recorridos con los circuitos reales de Montevideo.
 *
 * Usa el conjunto de datos abiertos "Contenedores de residuos domiciliarios - Ubicación, circuitos y frecuencia de
 * recolección" de la Intendencia de Montevideo (catalogodatos.gub.uy, archivo Contenedores_domiciliarios.csv):
 * por cada circuito ordena sus contenedores con el mismo Optimizador de la API de Recolección y mide cuánto tarda.
 * El archivo no trae el orden real de visita ni las bases de los camiones, así que el recorrido sale y vuelve al
 * centro del circuito y no se calcula ningún ahorro: solo se comprueba que el cálculo funciona con el tamaño real.
 *
 *   php sigeru-infra/desarrollo/herramientas/evaluar_circuitos_im.php Contenedores_domiciliarios.csv [resumen.json] > circuitos_im.csv
 *
 * Si se indica resumen.json, guarda además los totales del archivo (contenedores, circuitos, mediana por circuito y
 * contenedores en mantenimiento o sin instalar).
 *
 * (se ejecuta desde la carpeta que contiene todos los repositorios)
 */

require dirname(__DIR__, 3) . '/sigeru-api-recoleccion/app/Services/Optimizador.php';

use App\Services\Optimizador;

/**
 * Coordenadas UTM zona 21 sur (SIRGAS 2000, elipsoide GRS80), las del archivo, a latitud y longitud en grados.
 * Fórmulas inversas de la proyección transversa de Mercator (Snyder, 1987).
 */
function utm21sAGeograficas(float $x, float $y): array
{
    $a = 6378137.0;
    $f = 1 / 298.257222101;
    $k0 = 0.9996;
    $e2 = $f * (2 - $f);
    $ep2 = $e2 / (1 - $e2);
    $x -= 500000.0;              // falso este
    $y -= 10000000.0;            // falso norte del hemisferio sur
    $mu = $y / $k0 / ($a * (1 - $e2 / 4 - 3 * $e2 ** 2 / 64 - 5 * $e2 ** 3 / 256));
    $e1 = (1 - sqrt(1 - $e2)) / (1 + sqrt(1 - $e2));
    $fi1 = $mu + (3 * $e1 / 2 - 27 * $e1 ** 3 / 32) * sin(2 * $mu) + (21 * $e1 ** 2 / 16 - 55 * $e1 ** 4 / 32) * sin(4 * $mu)
        + (151 * $e1 ** 3 / 96) * sin(6 * $mu) + (1097 * $e1 ** 4 / 512) * sin(8 * $mu);
    $c1 = $ep2 * cos($fi1) ** 2;
    $t1 = tan($fi1) ** 2;
    $n1 = $a / sqrt(1 - $e2 * sin($fi1) ** 2);
    $r1 = $a * (1 - $e2) / (1 - $e2 * sin($fi1) ** 2) ** 1.5;
    $d = $x / ($n1 * $k0);
    $lat = $fi1 - ($n1 * tan($fi1) / $r1) * ($d ** 2 / 2 - (5 + 3 * $t1 + 10 * $c1 - 4 * $c1 ** 2 - 9 * $ep2) * $d ** 4 / 24
        + (61 + 90 * $t1 + 298 * $c1 + 45 * $t1 ** 2 - 252 * $ep2 - 3 * $c1 ** 2) * $d ** 6 / 720);
    $lon = deg2rad(-57.0) + ($d - (1 + 2 * $t1 + $c1) * $d ** 3 / 6
        + (5 - 2 * $c1 + 28 * $t1 - 3 * $c1 ** 2 + 8 * $ep2 + 24 * $t1 ** 2) * $d ** 5 / 120) / cos($fi1);
    return ['latitud' => rad2deg($lat), 'longitud' => rad2deg($lon)];
}

$archivo = $argv[1] ?? '';
if (!is_readable($archivo)) {
    fwrite(STDERR, "Uso: php evaluar_circuitos_im.php Contenedores_domiciliarios.csv\n");
    exit(1);
}
$entrada = fopen($archivo, 'r');
$cabecera = fgetcsv($entrada, 0, ';', '"', '');
$circuitos = [];
$fuera = 0;
$porCircuito = [];
$motivos = [];
$tresPorSemana = 0;     // turnos de tres días por semana (lunes, miércoles y viernes; martes, jueves y sábados; ...)
while (($fila = fgetcsv($entrada, 0, ';', '"', '')) !== false) {
    $c = array_combine($cabecera, $fila);
    $porCircuito[trim($c['COD_CIRCUITO'])] = ($porCircuito[trim($c['COD_CIRCUITO'])] ?? 0) + 1;
    $dias = trim(explode(':', $c['TURNO_HORARIO'])[0]);
    $tresPorSemana += preg_match('/^(LUNES, MIERCOLES Y VIERNES|MARTES,? JUEVES Y SABADOS|DOMINGOS, MARTES Y JUEVES)\b/', $dias) ? 1 : 0;
    if (trim($c['MOTIVO']) !== '') {        // en mantenimiento o sin instalar: no se recolecta
        $motivos[trim($c['MOTIVO'])] = ($motivos[trim($c['MOTIVO'])] ?? 0) + 1;
        $fuera++;
        continue;
    }
    $circuitos[trim($c['COD_CIRCUITO'])][] = ['id' => (int) $c['GID'], 'urgencia' => 0]
        + utm21sAGeograficas((float) $c['X'], (float) $c['Y']);
}
ksort($circuitos);

$salida = fopen('php://output', 'w');
fputcsv($salida, ['circuito', 'contenedores', 'km_estimados', 'milisegundos'], ',', '"', '');
foreach ($circuitos as $codigo => $puntos) {
    $centro = Optimizador::centroide($puntos);
    $desde = hrtime(true);
    $orden = Optimizador::ordenar($puntos, $centro);
    $ms = (hrtime(true) - $desde) / 1e6;
    $km = Optimizador::estimacion($orden, $centro)['km'];
    fputcsv($salida, [$codigo, count($puntos), $km, round($ms)], ',', '"', '');
}
fwrite(STDERR, count($circuitos) . " circuitos; $fuera contenedores en mantenimiento o sin instalar no se incluyeron\n");
if (!empty($argv[2])) {
    $tamanos = array_values($porCircuito);
    sort($tamanos);
    $medio = intdiv(count($tamanos), 2);
    $mediana = count($tamanos) % 2 ? $tamanos[$medio] : ($tamanos[$medio - 1] + $tamanos[$medio]) / 2;
    file_put_contents($argv[2], json_encode([
        'archivo' => basename($archivo), 'contenedores' => array_sum($tamanos), 'circuitos' => count($tamanos), 'mediana_por_circuito' => $mediana,
        'motivos' => $motivos, 'tres_por_semana' => $tresPorSemana,
    ], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) . "\n");
}
