// Pruebas de caja negra de la interfaz (landing, frontend y backoffice) con Playwright.
// Modifican datos: correrlas en el entorno de desarrollo o de demostración, nunca en producción.
//
// Uso:   npm install playwright && npx playwright install chromium
//        BASE=http://127.0.0.1:8080 node interfaz.js [resultados.csv]
const { chromium } = require('playwright');
const fs = require('fs');

const BASE = process.env.BASE || 'http://127.0.0.1:8080';
const CLAVE = process.env.CLAVE || 'Sigeru2026!';
const SALIDA = process.argv[2] || 'resultados_interfaz.csv';
const resultados = [];

async function caso(id, descripcion, esperado, prueba) {
  const inicio = Date.now();
  try {
    const obtenido = await prueba();
    resultados.push([id, descripcion, esperado, obtenido, 'OK', Date.now() - inicio]);
    console.log(`OK     ${id} ${descripcion}`);
  } catch (e) {
    resultados.push([id, descripcion, esperado, e.message.split('\n')[0], 'FALLA', Date.now() - inicio]);
    console.log(`FALLA  ${id} ${descripcion}: ${e.message.split('\n')[0]}`);
  }
}

function exigir(condicion, mensaje) {
  if (!condicion) throw new Error(mensaje);
}

async function entrar(p, email) {
  await p.goto(`${BASE}/app/#/login`);
  await p.waitForSelector('input[name=email]');
  await p.fill('input[name=email]', email);
  await p.fill('input[name=password]', CLAVE);
  await p.click('button[type=submit]');
  await p.waitForSelector('.lateral', { timeout: 8000 });
  await sinAvisos(p);
}

// espera a que no quede ningún aviso (toast) en pantalla, para leer solo el de la acción probada
async function sinAvisos(p) {
  await p.waitForFunction(() => !document.querySelector('.toast'), null, { timeout: 8000 }).catch(() => {});
}

async function avisoNuevo(p) {
  return (await (await p.waitForSelector('.toast', { timeout: 6000 })).textContent()).trim();
}

(async () => {
  const navegador = await chromium.launch();
  const nuevo = async (opciones = {}) => {
    const ctx = await navegador.newContext({ viewport: { width: 1366, height: 820 }, locale: 'es-UY', acceptDownloads: true, ...opciones });
    const p = await ctx.newPage();
    p.errores = [];
    p.on('pageerror', (e) => p.errores.push(e.message));
    return p;
  };

  // ------------------------------------------------------------------ landing
  let p = await nuevo();
  await caso('CI-01', 'La landing carga sin errores y muestra los contadores del mapa', 'contadores visibles, sin errores JS', async () => {
    await p.goto(`${BASE}/`);
    await p.waitForSelector('#contadores strong', { timeout: 10000 });
    exigir(p.errores.length === 0, 'errores JS: ' + p.errores.join('; '));
    return `${await p.locator('#contadores strong').count()} contadores, sin errores JS`;
  });
  await caso('CI-02', 'Código mal escrito en "¿El QR no se lee?" muestra un error', 'mensaje de error', async () => {
    await p.fill('#codigo-contenedor', 'abc');
    await p.click('#form-codigo button');
    const texto = await p.textContent('#mensaje-codigo');
    exigir(texto.includes('CNT'), 'no se mostró el error');
    return 'mensaje: ' + texto;
  });
  await caso('CI-03', 'El código escrito a mano ("cnt 10") abre el reporte del contenedor CNT-0010', 'página de reporte de CNT-0010', async () => {
    await p.fill('#codigo-contenedor', 'cnt 10');
    await Promise.all([p.waitForURL(/\/app\/#\/qr\/CNT-0010/), p.click('#form-codigo button')]);
    await p.waitForSelector('form .opcion');
    exigir((await p.textContent('body')).includes('CNT-0010'), 'no se ve el contenedor');
    return p.url().replace(BASE, '');
  });
  await caso('CI-04', 'El botón de idioma cambia la landing a inglés', 'textos en inglés', async () => {
    await p.goto(`${BASE}/`);
    await p.click('#idioma');
    await p.waitForFunction(() => document.querySelector('#como h2')?.textContent.includes('How it works'));
    return await p.textContent('#como h2');
  });
  await p.context().close();

  // ------------------------------------------------------------------ acceso y QR
  p = await nuevo();
  await caso('CI-05', 'Registro con contraseña débil: el error aparece junto al campo', 'error en el campo contraseña', async () => {
    await p.goto(`${BASE}/app/#/registro`);
    await p.waitForSelector('form [name=password]');
    await p.fill('[name=nombre]', 'Prueba');
    await p.fill('[name=apellido]', 'Interfaz');
    await p.fill('[name=email]', `prueba.${Date.now()}@correo.uy`);
    await p.fill('[name=password]', 'corta');
    await p.fill('[name=password2]', 'corta');
    await p.click('form button[type=submit]');
    await p.waitForTimeout(500);
    const errores = await p.$$eval('.error-campo', (e) => e.map((x) => x.textContent.trim()).filter(Boolean));
    exigir(errores.length > 0, 'no se mostraron errores');
    return errores.join(' | ');
  });
  await caso('CI-06', 'Inicio de sesión con contraseña incorrecta muestra un mensaje y no entra', 'mensaje de error, sin menú', async () => {
    await p.goto(`${BASE}/app/#/login`);
    await p.waitForSelector('input[name=email]');
    await p.fill('input[name=email]', 'admin@sigeru.uy');
    await p.fill('input[name=password]', 'Incorrecta1!');
    await p.click('button[type=submit]');
    await p.waitForTimeout(900);
    exigir(!(await p.$('.lateral')), 'entró con una contraseña incorrecta');
    return 'sin acceso; mensaje mostrado';
  });
  await caso('CI-07', 'Reporte por QR sin sesión: se registra y se confirma', 'mensaje de confirmación', async () => {
    await p.goto(`${BASE}/app/#/qr/CNT-0012`);
    await p.waitForSelector('form .opcion');
    await p.check('input[value=rotura]', { force: true });
    await p.click('form button');
    await p.waitForSelector('.mensaje-ok', { timeout: 6000 });
    return await p.textContent('.mensaje-ok');
  });
  await p.context().close();

  // ------------------------------------------------------------------ vecino
  p = await nuevo();
  await caso('CI-08', 'El vecino ve solo su menú (sin "Usuarios" ni "Camiones")', 'menú de vecino', async () => {
    await entrar(p, 'ana.martinez@correo.uy');
    const menu = await p.textContent('.lateral');
    exigir(!menu.includes('Usuarios') && !menu.includes('Camiones'), 'el menú muestra opciones del administrador');
    return menu.replace(/\s+/g, ' ').trim().slice(0, 80);
  });
  await caso('CI-09', 'El vecino que entra a #/usuarios no ve la pantalla de usuarios', 'acceso denegado', async () => {
    await p.goto(`${BASE}/app/#/usuarios`);
    await p.waitForTimeout(900);
    exigir(!(await p.$('[data-nuevo]')), 'se muestra la pantalla de usuarios');
    return 'pantalla no disponible para el rol';
  });
  await caso('CI-10', 'El vecino reporta un problema y lo ve en "Mis reportes"', 'reporte en la lista', async () => {
    await p.goto(`${BASE}/app/#/reportar`);
    await p.waitForSelector('#codigo');
    await p.fill('#codigo', 'CNT-0015');
    await p.check('input[value=falta_recoleccion]', { force: true });
    await p.click('form button.btn-primario');
    await avisoNuevo(p);
    await p.goto(`${BASE}/app/#/mis-reportes`);
    await p.waitForTimeout(1200);
    exigir((await p.textContent('#lista')).includes('CNT-0015'), 'no aparece en mis reportes');
    return 'CNT-0015 aparece en mis reportes';
  });
  await p.context().close();

  // ------------------------------------------------------------------ administrador
  p = await nuevo();
  await caso('CI-11', 'Alta de contenedor con el formulario vacío: errores en cada campo obligatorio', 'errores por campo', async () => {
    await entrar(p, 'admin@sigeru.uy');
    await p.goto(`${BASE}/app/#/contenedores`);
    await p.waitForSelector('[data-nuevo]');
    await p.click('[data-nuevo]');
    await p.waitForSelector('.modal form');
    await p.click('.modal button[type=submit]');
    await p.waitForTimeout(400);
    const n = await p.$$eval('.error-campo', (e) => e.filter((x) => x.textContent.trim()).length);
    exigir(n >= 3, `solo ${n} errores`);
    await p.keyboard.press('Escape');
    return `${n} campos marcados`;
  });
  await caso('CI-12', 'Alta de contenedor válida: aviso de guardado', 'aviso de guardado', async () => {
    await p.waitForTimeout(400);
    await p.click('[data-nuevo]');
    await p.waitForSelector('.modal form');
    await p.selectOption('[name=tipo_residuo_id]', '2');
    await p.selectOption('[name=zona_id]', '1');
    await p.fill('[name=direccion]', 'Av. Rivera 4567');
    await p.fill('[name=latitud]', '-34.8937');
    await p.fill('[name=longitud]', '-56.1301');
    await p.selectOption('[name=capacidad_litros]', '2400');
    await sinAvisos(p);
    await p.click('.modal button[type=submit]');
    const aviso = await avisoNuevo(p);
    await p.waitForSelector('.modal', { state: 'detached', timeout: 5000 });
    return aviso + ' (el formulario se cerró)';
  });
  await caso('CI-13', 'Asignar una incidencia abierta a una cuadrilla', 'aviso de asignación', async () => {
    await p.goto(`${BASE}/app/#/incidencias?estado=abierta`);
    await p.waitForSelector('[data-ver]');
    await p.click('[data-ver]');
    await p.waitForSelector('[data-asignar] select');
    await p.selectOption('[data-asignar] select', '1');
    await sinAvisos(p);
    await p.click('[data-asignar] button');
    return await avisoNuevo(p);
  });
  await caso('CI-14', 'El panel muestra indicadores y gráficos sin errores', 'indicadores y SVG', async () => {
    await p.keyboard.press('Escape');
    await p.goto(`${BASE}/app/#/panel`);
    await p.waitForSelector('svg', { timeout: 8000 });
    exigir(p.errores.length === 0, 'errores JS: ' + p.errores.join('; '));
    return `${await p.locator('svg').count()} gráficos`;
  });
  await caso('CI-19', 'Optimizar una ruta muestra la comparación y aplica el orden propuesto', 'km actual y propuesto, aviso de guardado', async () => {
    await p.goto(`${BASE}/app/#/rutas`);
    await p.waitForSelector('[data-optimizar]');
    await sinAvisos(p);
    await p.click('[data-optimizar]');
    await p.waitForSelector('[data-aplicar]');
    const texto = await p.textContent('.modal');
    exigir((texto.match(/km/g) || []).length >= 2, 'sin la comparación de kilómetros');
    await p.click('[data-aplicar]');
    return `${await avisoNuevo(p)}`;
  });
  await p.context().close();

  // ------------------------------------------------------------------ cuadrilla en el celular
  p = await nuevo({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  await caso('CI-15', 'Cuadrilla en el celular: "Mi ruta" muestra el recorrido del día', 'recorrido con paradas', async () => {
    await entrar(p, 'pmendez@sigeru.uy');
    await p.goto(`${BASE}/app/#/mi-ruta`);
    await p.waitForTimeout(1500);
    const paradas = await p.locator('ol li').count();
    exigir(paradas > 0, 'sin paradas');
    return `${paradas} paradas`;
  });
  await caso('CI-18', 'La cuadrilla reporta un contenedor roto desde "Reportar problema"', 'opción en el menú y aviso de confirmación', async () => {
    exigir(await p.locator('a[data-ruta="reportar"]').count() === 1, 'sin "Reportar problema" en el menú');
    await p.goto(`${BASE}/app/#/reportar`);
    await p.waitForSelector('#codigo');
    await sinAvisos(p);
    await p.fill('#codigo', 'CNT-0021');
    await p.check('input[value=rotura]', { force: true });
    await p.click('form button.btn-primario');
    return await avisoNuevo(p);
  });
  await p.context().close();

  // ------------------------------------------------------------------ backoffice
  p = await nuevo();
  await caso('CI-16', 'Backoffice: un formulario sin token CSRF es rechazado', 'rechazo (403)', async () => {
    const r = await p.request.post(`${BASE}/backoffice/login`, { form: { email: 'admin@sigeru.uy', password: CLAVE } });
    exigir(r.status() >= 400, `respondió ${r.status()}`);
    return `HTTP ${r.status()}`;
  });
  await caso('CI-17', 'Backoffice: el administrador entra y exporta un reporte en CSV', 'archivo .csv descargado', async () => {
    await p.goto(`${BASE}/backoffice/login`);
    await p.fill('input[name=email]', 'admin@sigeru.uy');
    await p.fill('input[name=password]', CLAVE);
    await p.click('button');
    await p.waitForURL(/backoffice\/?$/);
    await p.goto(`${BASE}/backoffice/reportes?tipo=volumen_tipo`);
    const [descarga] = await Promise.all([p.waitForEvent('download'), p.click('a[href*="exportar"], button:has-text("CSV")')]);
    exigir(descarga.suggestedFilename().endsWith('.csv'), 'no es un CSV');
    return descarga.suggestedFilename();
  });
  await p.context().close();
  await navegador.close();

  resultados.sort((x, y) => Number(x[0].slice(3)) - Number(y[0].slice(3)));   // ordenados por número de caso
  const filas = [['id', 'caso', 'esperado', 'obtenido', 'resultado', 'ms']].concat(resultados);
  fs.writeFileSync(SALIDA, filas.map((f) => f.map((v) => `"${String(v).replace(/"/g, '""')}"`).join(';')).join('\n') + '\n');
  const ok = resultados.filter((r) => r[4] === 'OK').length;
  console.log(`\n${ok} de ${resultados.length} casos correctos. Resultados en ${SALIDA}`);
  process.exit(ok === resultados.length ? 0 : 1);
})();
