<?php
/**
 * Par de claves RSA de los tokens JWT (RS256), en el volumen "claves".
 *   jwt_privada.pem  la usa solo la API de Usuarios para firmar
 *   jwt_publica.pem  la usan las tres APIs para verificar
 * Se genera la primera vez que arranca el contenedor api; si ya existe no se toca,
 * para que las sesiones abiertas sigan siendo válidas.
 *
 * Uso: php claves.php <carpeta>
 */
$dir = rtrim($argv[1] ?? '/claves', '/');
$privada = "$dir/jwt_privada.pem";
$publica = "$dir/jwt_publica.pem";

if (is_file($privada) && is_file($publica)) {
    echo "Claves JWT existentes.\n";
    exit(0);
}

$cnf = tempnam(sys_get_temp_dir(), 'sigeru');
file_put_contents($cnf, "[req]\ndistinguished_name = dn\n[dn]\n");
$opciones = ['config' => $cnf, 'private_key_bits' => 2048, 'private_key_type' => OPENSSL_KEYTYPE_RSA];

$clave = openssl_pkey_new($opciones);
if ($clave === false || !openssl_pkey_export($clave, $pem, null, $opciones)) {
    fwrite(STDERR, "No se pudo generar el par de claves JWT: " . openssl_error_string() . "\n");
    exit(1);
}
$detalle = openssl_pkey_get_details($clave);
file_put_contents($privada, $pem);
file_put_contents($publica, $detalle['key']);
unlink($cnf);

// la privada solo la lee Apache (www-data); la pública puede leerla cualquiera
chmod($privada, 0640);
chmod($publica, 0644);
@chgrp($privada, 'www-data');
echo "Se generó el par de claves JWT (RSA 2048).\n";
