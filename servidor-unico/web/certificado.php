<?php
/**
 * Certificado HTTPS del contenedor web de SiGeRU.
 *
 * La primera vez que arranca el contenedor crea:
 *   aplec-ca.key / aplec-ca.crt  autoridad certificadora propia de Aplec Software (5 años)
 *   sigeru.key / sigeru.crt      certificado del servidor firmado por esa CA (825 días);
 *                                sigeru.crt lleva también el certificado de la CA
 * Si cambia el nombre o la IP del servidor, vuelve a emitir solo el del servidor.
 * Para que el navegador no muestre la advertencia se instala aplec-ca.crt
 * como autoridad de confianza (se descarga desde https://<servidor>/aplec-ca.crt).
 *
 * Uso: php certificado.php <carpeta> <nombre> [ip]
 */

$dir = rtrim($argv[1] ?? '/etc/sigeru/certificados', '/');
$nombre = $argv[2] ?? 'sigeru.local';
$ip = $argv[3] ?? '';

if (!preg_match('/^[A-Za-z0-9.-]{1,253}$/', $nombre)) {
    fwrite(STDERR, "Nombre de servidor no válido: $nombre\n");
    exit(1);
}
$san = ["DNS:$nombre", 'DNS:localhost', 'IP:127.0.0.1'];
foreach (preg_split('/[\s,]+/', $ip, -1, PREG_SPLIT_NO_EMPTY) as $una) {
    if (filter_var($una, FILTER_VALIDATE_IP)) {
        $san[] = "IP:$una";
    }
}
$san = implode(',', array_unique($san));

// Configuración propia de OpenSSL: no depende del openssl.cnf del sistema
$cnf = tempnam(sys_get_temp_dir(), 'sigeru');
file_put_contents($cnf, <<<CNF
[req]
distinguished_name = dn
[dn]
[ca]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
[servidor]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = $san
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid

CNF);
$opciones = fn(string $seccion) => [
    'config' => $cnf,
    'digest_alg' => 'sha256',
    'private_key_bits' => 2048,
    'private_key_type' => OPENSSL_KEYTYPE_RSA,
    'x509_extensions' => $seccion,
];

function guardar(string $ruta, string $contenido, int $permisos): void
{
    file_put_contents($ruta, $contenido);
    chmod($ruta, $permisos);
}

function fallar(string $mensaje): never
{
    while ($e = openssl_error_string()) {
        $mensaje .= "\n  $e";
    }
    fwrite(STDERR, "$mensaje\n");
    exit(1);
}

if (!is_dir($dir) && !mkdir($dir, 0755, true)) {
    fallar("No se pudo crear $dir");
}

// 1. Autoridad certificadora propia
$caKey = "$dir/aplec-ca.key";
$caCrt = "$dir/aplec-ca.crt";
if (!is_file($caKey) || !is_file($caCrt)) {
    $clave = openssl_pkey_new($opciones('ca')) ?: fallar('No se pudo generar la clave de la CA');
    $dn = ['countryName' => 'UY', 'organizationName' => 'Aplec Software', 'commonName' => 'Aplec Software CA SiGeRU'];
    $csr = openssl_csr_new($dn, $clave, $opciones('ca')) ?: fallar('No se pudo crear el pedido de la CA');
    $crt = openssl_csr_sign($csr, null, $clave, 1825, $opciones('ca'), random_int(1, PHP_INT_MAX))
        ?: fallar('No se pudo firmar el certificado de la CA');
    openssl_pkey_export($clave, $pem, null, $opciones('ca')) ?: fallar('No se pudo exportar la clave de la CA');
    openssl_x509_export($crt, $crtPem);
    guardar($caKey, $pem, 0600);
    guardar($caCrt, $crtPem, 0644);
    @unlink("$dir/sigeru.crt");
    echo "Se creó la autoridad certificadora propia (aplec-ca.crt).\n";
}

// 2. Certificado del servidor (se vuelve a emitir si cambian el nombre o la IP)
$srvKey = "$dir/sigeru.key";
$srvCrt = "$dir/sigeru.crt";
$srvSan = "$dir/sigeru.san";
if (!is_file($srvKey) || !is_file($srvCrt) || trim((string) @file_get_contents($srvSan)) !== $san) {
    $ca = openssl_x509_read(file_get_contents($caCrt)) ?: fallar('No se pudo leer aplec-ca.crt');
    $caClave = openssl_pkey_get_private(file_get_contents($caKey)) ?: fallar('No se pudo leer aplec-ca.key');
    $clave = openssl_pkey_new($opciones('servidor')) ?: fallar('No se pudo generar la clave del servidor');
    $dn = ['countryName' => 'UY', 'organizationName' => 'Aplec Software', 'commonName' => $nombre];
    $csr = openssl_csr_new($dn, $clave, $opciones('servidor')) ?: fallar('No se pudo crear el pedido del servidor');
    $crt = openssl_csr_sign($csr, $ca, $caClave, 825, $opciones('servidor'), random_int(1, PHP_INT_MAX))
        ?: fallar('No se pudo firmar el certificado del servidor');
    openssl_pkey_export($clave, $pem, null, $opciones('servidor')) ?: fallar('No se pudo exportar la clave del servidor');
    openssl_x509_export($crt, $crtPem);
    guardar($srvKey, $pem, 0600);
    guardar($srvCrt, $crtPem . file_get_contents($caCrt), 0644);
    guardar($srvSan, $san . "\n", 0644);
    echo "Se emitió el certificado HTTPS para $san.\n";
} else {
    echo "Certificado HTTPS vigente para $san.\n";
}
unlink($cnf);
