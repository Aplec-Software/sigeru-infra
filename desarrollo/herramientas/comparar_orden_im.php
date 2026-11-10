<?php

/**
 * Compara el orden de visita que planifica la Intendencia de Montevideo con el que propone el Optimizador de SiGeRU.
 *
 * Usa el conjunto de datos abiertos "Información de levantes de contenedores domiciliarios" (catalogodatos.gub.uy):
 * una foto por día, a las 6:00, de cada contenedor con su recorrido, su posición en el recorrido, si está inactivo,
 * la fecha y hora de su último levante y sus coordenadas.
 *
 * Para cada recorrido de la fecha elegida se toman los contenedores activos con coordenadas en el orden de su posición
 * y se compara la longitud de ese orden con la del orden que propone SiGeRU, con la misma salida (el primer
 * contenedor) y la misma llegada (el último). Las dos longitudes se calculan igual (línea recta por un factor), sin
 * urgencias. Además se cuentan los contenedores que llevaban más de 3 días sin levante en cada foto.
 *
 *   php sigeru-infra/desarrollo/herramientas/comparar_orden_im.php levantes.csv [AAAA-MM-DD] [resumen.json] > orden_im.csv
 *
 * Si no se indica la fecha se usa la última foto del archivo.
 */

require dirname(__DIR__, 3) . '/sigeru-api-recoleccion/app/Services/Optimizador.php';

use App\Services\Optimizador;

date_default_timezone_set('America/Montevideo');   // las horas del archivo son de Montevideo
$archivo = $argv[1] ?? '';
if (!is_readable($archivo)) {
    fwrite(STDERR, "Uso: php comparar_orden_im.php levantes.csv [AAAA-MM-DD] [resumen.json]\n");
    exit(1);
}

// 1) una pasada por el archivo: contenedores sin levante por foto y filas de la fecha elegida
$fecha = $argv[2] ?? '';
$fotos = [];          // fecha => [activos, con más de 3 días sin levante]
$porFecha = [];       // fecha => recorrido => contenedores
$entrada = fopen($archivo, 'r');
$cabecera = fgetcsv($entrada, 0, ',', '"', '');
while (($fila = fgetcsv($entrada, 0, ',', '"', '')) !== false) {
    $c = array_combine($cabecera, $fila);
    if ($c['cod_motivo_inactiva'] !== '0' || $c['latitud'] === '' || $c['ult_levante'] === '') {
        continue;
    }
    $dia = substr($c['fecha_datos'], 0, 10);
    $dias = (strtotime($c['fecha_datos']) - strtotime($c['ult_levante'])) / 86400;
    $fotos[$dia][0] = ($fotos[$dia][0] ?? 0) + 1;
    $fotos[$dia][1] = ($fotos[$dia][1] ?? 0) + ($dias > 3 ? 1 : 0);
    if ($fecha === '' || $dia === $fecha) {
        $porFecha[$dia][$c['cod_recorrido']][] = ['id' => (int) $c['posicion'], 'posicion' => (int) $c['posicion'],
            'urgencia' => 0, 'latitud' => (float) $c['latitud'], 'longitud' => (float) $c['longitud'],
            'levante' => strtotime($c['ult_levante'])];
    }
}
ksort($fotos);
$fecha = $fecha !== '' ? $fecha : array_key_last($fotos);
$recorridos = $porFecha[$fecha] ?? [];
ksort($recorridos);
unset($porFecha);

// 2) orden planificado contra orden propuesto, con la misma salida y la misma llegada
$salida = fopen('php://output', 'w');
fputcsv($salida, ['recorrido', 'contenedores', 'km_orden_im', 'km_propuesta', 'diferencia_porcentaje', 'milisegundos'], ',', '"', '');
$filas = [];
$pares = $paresEnOrden = 0;      // ¿la posición es el orden en que se levantan? (pares consecutivos del mismo viaje)
foreach ($recorridos as $codigo => $puntos) {
    if (count($puntos) < 4) {
        continue;
    }
    usort($puntos, fn ($a, $b) => $a['posicion'] <=> $b['posicion']);
    foreach (array_slice($puntos, 1) as $k => $b) {
        $a = $puntos[$k];
        if (date('Y-m-d', $a['levante']) === date('Y-m-d', $b['levante']) && abs($b['levante'] - $a['levante']) < 3 * 3600) {
            $pares++;
            $paresEnOrden += $b['levante'] >= $a['levante'] ? 1 : 0;
        }
    }
    $inicio = array_shift($puntos);
    $fin = array_pop($puntos);
    $km = Optimizador::estimacion($puntos, $inicio, $fin)['km'];
    $desde = hrtime(true);
    $propuesta = Optimizador::ordenar($puntos, $inicio, $fin);
    $ms = (hrtime(true) - $desde) / 1e6;
    $kmPropuesta = Optimizador::estimacion($propuesta, $inicio, $fin)['km'];
    $diferencia = $km > 0 ? round(($km - $kmPropuesta) / $km * 100, 1) : 0.0;
    $filas[] = [$codigo, count($puntos) + 2, $km, $kmPropuesta, $diferencia, round($ms)];
    fputcsv($salida, end($filas), ',', '"', '');
}

if (!empty($argv[3])) {
    $porcentajes = array_column($filas, 4);
    sort($porcentajes);
    $percentil = fn (float $p) => $porcentajes[(int) floor($p * (count($porcentajes) - 1))];
    $atrasados = array_map(fn ($f) => $f[1] / $f[0] * 100, $fotos);
    file_put_contents($argv[3], json_encode([
        'fecha' => $fecha, 'recorridos' => count($filas), 'contenedores' => array_sum(array_column($filas, 1)),
        'km_orden_im' => round(array_sum(array_column($filas, 2)), 1), 'km_propuesta' => round(array_sum(array_column($filas, 3)), 1),
        'diferencia_mediana' => $percentil(0.5), 'diferencia_p10' => $percentil(0.1), 'diferencia_p90' => $percentil(0.9),
        'pares_mismo_viaje' => $pares, 'pares_en_orden_porcentaje' => $pares ? round($paresEnOrden / $pares * 100, 1) : null,
        'fotos' => count($fotos), 'primera_foto' => array_key_first($fotos), 'ultima_foto' => array_key_last($fotos),
        'mas_de_3_dias_promedio' => round(array_sum($atrasados) / count($atrasados), 1),
        'mas_de_3_dias_minimo' => round(min($atrasados), 1), 'mas_de_3_dias_maximo' => round(max($atrasados), 1),
    ], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) . "\n");
}
fwrite(STDERR, count($filas) . " recorridos comparados (foto del $fecha)\n");
