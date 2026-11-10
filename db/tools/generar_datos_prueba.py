#!/usr/bin/env python3
"""
Genera 03_datos_prueba.sql con datos simulados para probar SiGeRU.

Los datos son ficticios pero coherentes entre sí (contenedores dentro de su
barrio, recolecciones que siguen las rutas, incidencias con su historial, etc.)
para que los reportes y el panel muestren información con sentido.
Se usa una semilla fija, así cada ejecución genera exactamente lo mismo.

Uso:
    python3 generar_datos_prueba.py > ../03_datos_prueba.sql
"""
import random
import subprocess
from datetime import date, datetime, timedelta

random.seed(2026)
HOY = date(2026, 10, 30)          # fecha de referencia de los datos
INICIO = date(2026, 8, 17)         # primer día con actividad simulada
CLAVE_PRUEBA = "Sigeru2026!"


def hash_clave(clave):
    """Usa PHP para generar el hash bcrypt con costo 12, el mismo que usa la API de Usuarios."""
    cmd = ["php", "-r", f"echo password_hash('{clave}', PASSWORD_BCRYPT, ['cost' => 12]);"]
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout.strip()


def q(v):
    """Convierte un valor de Python a literal SQL."""
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return "1" if v else "0"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, (datetime,)):
        return "'" + v.strftime("%Y-%m-%d %H:%M:%S") + "'"
    if isinstance(v, date):
        return "'" + v.isoformat() + "'"
    return "'" + str(v).replace("'", "''") + "'"


def insert(tabla, columnas, filas, bloque=150):
    out = []
    for i in range(0, len(filas), bloque):
        parte = filas[i:i + bloque]
        valores = ",\n  ".join("(" + ", ".join(q(v) for v in f) + ")" for f in parte)
        out.append(f"INSERT INTO {tabla} ({', '.join(columnas)}) VALUES\n  {valores};\n")
    return "".join(out)


def ci_valida(base7):
    """Agrega el dígito verificador a una cédula uruguaya de 7 dígitos."""
    digitos = [int(c) for c in f"{base7:07d}"]
    suma = sum(d * p for d, p in zip(digitos, [2, 9, 8, 7, 6, 3, 4]))
    return f"{base7:07d}{(10 - suma % 10) % 10}"


def momento(dia, hora_min=7, hora_max=20):
    return datetime(dia.year, dia.month, dia.day, random.randint(hora_min, hora_max),
                    random.randint(0, 59), random.randint(0, 59))


def dias_habiles(desde, hasta):
    d = desde
    while d <= hasta:
        if d.weekday() < 6:   # lunes a sábado
            yield d
        d += timedelta(days=1)


sql = ["-- =====================================================================\n",
       "-- SiGeRU - Datos de prueba (simulados). Generado por tools/generar_datos_prueba.py\n",
       f"-- Contraseña de todos los usuarios de prueba: {CLAVE_PRUEBA}\n",
       "-- =====================================================================\n\n"]

# --------------------------------------------------------------------- centros
centros = [
    # id, nombre, tipo, zona, direccion, lat, lng, capacidad, ocupacion, telefono
    (1, "Centro de Acopio Malvín Norte", "acopio", 3, "Camino Carrasco 4560", -34.877400, -56.112300, 120, 84.5, "2508 1120"),
    (2, "Planta de Clasificación La Blanqueada", "clasificacion", 6, "Av. Centenario 2890", -34.881900, -56.159800, 350, 192.0, "2481 3305"),
    (3, "Punto Limpio Pocitos", "acopio", 2, "Av. Brasil 3120", -34.909800, -56.146900, 60, 55.4, "2709 4471"),
    (4, "Sitio de Disposición Final Este", "vertedero", 4, "Camino Maldonado 6400", -34.857200, -56.118600, 25000, 15240.0, "2513 0090"),
]
sql.append(insert("centros", ["id", "nombre", "tipo", "zona_id", "direccion", "latitud", "longitud",
                              "capacidad_ton", "ocupacion_ton", "telefono"], centros))
acepta = {1: [2, 3, 6], 2: [2, 3, 4], 3: [2, 3, 5, 6], 4: [1, 5]}
sql.append(insert("centro_tipo_residuo", ["centro_id", "tipo_residuo_id"],
                  [(c, t) for c, ts in acepta.items() for t in ts]))

maquinaria = [
    (1, 1, "MAQ-001", "Prensa enfardadora vertical 20 t", "prensa", "operativa", date(2023, 3, 10), date(2026, 9, 2)),
    (2, 1, "MAQ-002", "Balanza de plataforma 3000 kg", "balanza", "operativa", date(2022, 7, 1), date(2026, 8, 20)),
    (3, 2, "MAQ-003", "Cinta de clasificación 12 m", "cinta", "operativa", date(2021, 5, 18), date(2026, 10, 1)),
    (4, 2, "MAQ-004", "Prensa enfardadora horizontal", "prensa", "mantenimiento", date(2020, 11, 4), date(2026, 10, 22)),
    (5, 2, "MAQ-005", "Autoelevador eléctrico 2,5 t", "cargadora", "operativa", date(2024, 2, 15), date(2026, 9, 15)),
    (6, 3, "MAQ-006", "Balanza de piso 1500 kg", "balanza", "operativa", date(2023, 9, 1), date(2026, 7, 30)),
    (7, 3, "MAQ-007", "Trituradora de ramas", "trituradora", "fuera_servicio", date(2019, 6, 20), date(2026, 5, 12)),
    (8, 4, "MAQ-008", "Compactadora de relleno 25 t", "compactadora", "operativa", date(2018, 4, 9), date(2026, 10, 10)),
    (9, 4, "MAQ-009", "Pala cargadora frontal", "cargadora", "operativa", date(2020, 1, 30), date(2026, 9, 28)),
    (10, 4, "MAQ-010", "Balanza de camiones 60 t", "balanza", "operativa", date(2017, 8, 14), date(2026, 8, 5)),
]
sql.append(insert("maquinaria", ["id", "centro_id", "codigo", "descripcion", "tipo", "estado",
                                 "fecha_adquisicion", "ultimo_mantenimiento"], maquinaria))

# -------------------------------------------------------------------- usuarios
clave = hash_clave(CLAVE_PRUEBA)
personas = [
    # id, rol, nombre, apellido, email, estado, centro
    (1, 1, "Laura", "Fernández", "admin@sigeru.uy", "activo", None),
    (2, 1, "Martín", "Silva", "msilva@sigeru.uy", "activo", None),
    (3, 2, "Jorge", "Pereyra", "jpereyra@sigeru.uy", "activo", None),
    (4, 2, "Andrea", "Castro", "acastro@sigeru.uy", "activo", None),
    (5, 2, "Diego", "Rodríguez", "drodriguez@sigeru.uy", "activo", None),
    (6, 2, "Valeria", "Núñez", "vnunez@sigeru.uy", "activo", None),
    (7, 2, "Pablo", "Méndez", "pmendez@sigeru.uy", "activo", None),
    (8, 2, "Sofía", "Acosta", "sacosta@sigeru.uy", "activo", None),
    (9, 3, "Raúl", "Benítez", "rbenitez@sigeru.uy", "activo", 1),
    (10, 3, "Carolina", "Sosa", "csosa@sigeru.uy", "activo", 2),
    (11, 3, "Federico", "Olivera", "folivera@sigeru.uy", "activo", 3),
    (12, 4, "Ana", "Martínez", "ana.martinez@correo.uy", "activo", None),
    (13, 4, "Luis", "Gómez", "luis.gomez@correo.uy", "activo", None),
    (14, 4, "Mariana", "López", "mariana.lopez@correo.uy", "activo", None),
    (15, 4, "Carlos", "Díaz", "carlos.diaz@correo.uy", "activo", None),
    (16, 4, "Lucía", "Romero", "lucia.romero@correo.uy", "activo", None),
    (17, 4, "Gonzalo", "Suárez", "gonzalo.suarez@correo.uy", "inactivo", None),
    (18, 2, "Matías", "Cabrera", "mcabrera@sigeru.uy", "pendiente", None),
    (19, 3, "Florencia", "Ramos", "framos@sigeru.uy", "pendiente", None),
    (20, 2, "Nicolás", "Ferreira", "nferreira@correo.uy", "rechazado", None),
]
usuarios = []
for (uid, rol, nom, ape, mail, est, centro) in personas:
    documento = ci_valida(random.randint(3000000, 6400000)) if rol != 4 else None
    tel = f"09{random.randint(1, 9)} {random.randint(100, 999)} {random.randint(100, 999)}"
    creado = momento(INICIO - timedelta(days=random.randint(5, 40)))
    ultimo = momento(HOY - timedelta(days=random.randint(0, 6))) if est == "activo" else None
    usuarios.append((uid, rol, nom, ape, documento, mail, tel, clave, est, "es", centro, creado, ultimo))
sql.append(insert("usuarios", ["id", "rol_id", "nombre", "apellido", "documento", "email", "telefono",
                               "password_hash", "estado", "idioma", "centro_id", "creado_en", "ultimo_acceso"],
                  usuarios))

# ---------------------------------------------------------------- contenedores
calles = {
    1: [("Av. Rivera", 4100, 4900), ("Av. Comercio", 1000, 1600), ("Av. Luis A. de Herrera", 1100, 1500),
        ("José Serrato", 2200, 2700), ("Iturriaga", 3300, 3700)],
    2: [("Av. Brasil", 2400, 3200), ("Benito Blanco", 600, 1200), ("Juan Benito Blanco", 900, 1400),
        ("Av. Gral. Rivera", 2600, 3200), ("Libertad", 2500, 2900)],
    3: [("Av. Italia", 4600, 5400), ("Michigan", 1300, 1700), ("Orinoco", 4900, 5200),
        ("Estanislao López", 4600, 5000), ("Av. Rivera", 5100, 5600)],
    4: [("Av. 8 de Octubre", 3700, 4400), ("Pan de Azúcar", 2600, 3100), ("Larravide", 3600, 4000),
        ("Asilo", 3600, 3900), ("Felipe Contucci", 3500, 3900)],
    5: [("Av. Italia", 2800, 3300), ("Av. Alfredo Navarro", 3000, 3300), ("Ricaldoni", 2400, 2700),
        ("Av. Ricaldoni", 2700, 2900), ("Lorenzo Merola", 2600, 2900)],
    6: [("Av. 8 de Octubre", 2900, 3500), ("Av. Centenario", 2700, 3100), ("Mariano Moreno", 2700, 3000),
        ("Comercio", 2000, 2400), ("Jaime Cibils", 2800, 3000)],
    7: [("Av. 18 de Julio", 1800, 2300), ("Gaboto", 1400, 1800), ("Colonia", 1700, 2100),
        ("Mercedes", 1700, 2100), ("Constituyente", 1600, 2000)],
    8: [("Av. 18 de Julio", 900, 1500), ("San José", 900, 1400), ("Soriano", 900, 1300),
        ("Colonia", 900, 1500), ("Paraguay", 1200, 1500)],
}
zonas_coord = {1: (-34.8955, -56.1330), 2: (-34.9110, -56.1505), 3: (-34.8890, -56.1080),
               4: (-34.8710, -56.1390), 5: (-34.8960, -56.1560), 6: (-34.8840, -56.1560),
               7: (-34.9020, -56.1780), 8: (-34.9060, -56.1915)}
tipos_dist = [1] * 12 + [2] * 4 + [3] * 3 + [4] * 2
contenedores = []
cont_por_zona = {}
cid = 0
for zona in range(1, 9):
    for _ in range(6):
        cid += 1
        calle, n1, n2 = random.choice(calles[zona])
        lat0, lng0 = zonas_coord[zona]
        lat = round(lat0 + random.uniform(-0.0045, 0.0045), 6)
        lng = round(lng0 + random.uniform(-0.0055, 0.0055), 6)
        tipo = random.choice(tipos_dist)
        cap = {1: 2400, 2: 2400, 3: 1100, 4: 1100}[tipo]
        contenedores.append([cid, f"CNT-{cid:04d}", tipo, zona, f"{calle} {random.randint(n1, n2)}",
                             lat, lng, cap, "funcional", random.randint(10, 70),
                             date(2019 + random.randint(0, 6), random.randint(1, 12), random.randint(1, 28)),
                             None, 1])
        cont_por_zona.setdefault(zona, []).append(cid)

# estados actuales variados para que el mapa y el panel muestren alertas
for c in random.sample(range(48), 6):
    contenedores[c][8], contenedores[c][9] = "desbordado", 100
for c in random.sample(range(48), 3):
    contenedores[c][8] = "roto"
contenedores[47][8], contenedores[47][12] = "fuera_servicio", 0   # dado de baja

# ------------------------------------------------------------------- camiones
camiones = [
    (1, "SIM 3101", "Mercedes-Benz", "Atego 1726", 2019, "compactador", 9.0, "disponible", 128450),
    (2, "SIM 3102", "Mercedes-Benz", "Atego 1726", 2019, "compactador", 9.0, "disponible", 131200),
    (3, "SIM 3103", "Volkswagen", "Constellation 17.280", 2021, "compactador", 10.5, "disponible", 86340),
    (4, "SIM 3104", "Volkswagen", "Constellation 17.280", 2021, "compactador", 10.5, "en_ruta", 90215),
    (5, "SIM 3105", "Iveco", "Tector 170E28", 2018, "carga_lateral", 8.5, "mantenimiento", 162870),
    (6, "SIM 3106", "Iveco", "Tector 170E28", 2022, "carga_lateral", 8.5, "disponible", 54330),
    (7, "SIM 3107", "Ford", "Cargo 1723", 2016, "caja_abierta", 7.0, "disponible", 201540),
    (8, "SIM 3108", "Ford", "Cargo 1723", 2015, "grua", 6.0, "fuera_servicio", 238900),
]
sql.append(insert("camiones", ["id", "matricula", "marca", "modelo", "anio", "tipo", "capacidad_ton", "estado",
                               "kilometraje"], camiones))

mant = []
mid = 0
for (cam, *_r) in camiones:
    for mes in (8, 9, 10):
        if random.random() < 0.55:
            mid += 1
            f = date(2026, mes, random.randint(1, 26))
            tipo = random.choice(["preventivo", "preventivo", "correctivo"])
            desc = "Service de motor, filtros y engrase" if tipo == "preventivo" else random.choice(
                ["Reparación del sistema hidráulico de la caja", "Cambio de pastillas de freno",
                 "Reparación del levantacontenedores", "Cambio de neumático trasero"])
            mant.append((mid, cam, tipo, desc, f, f, None, round(random.uniform(9000, 68000), 2), "realizado"))
for cam, dias in ((1, 2), (3, 1), (6, 9), (5, 0)):
    mid += 1
    f = HOY + timedelta(days=dias)
    mant.append((mid, cam, "preventivo", "Service programado de 10.000 km", f, None, None, None, "programado"))
sql.append(insert("mantenimientos", ["id", "camion_id", "tipo", "descripcion", "fecha_programada",
                                     "fecha_realizada", "kilometraje", "costo", "estado"], mant))

# ------------------------------------------------------- cuadrillas y rutas
cuadrillas = [(1, "Cuadrilla Este 1", 1, "matutino"), (2, "Cuadrilla Costa 2", 2, "vespertino"),
              (3, "Cuadrilla Norte 3", 4, "matutino")]
sql.append(insert("cuadrillas", ["id", "nombre", "zona_id", "turno"], cuadrillas))
sql.append(insert("cuadrilla_integrante", ["cuadrilla_id", "usuario_id", "es_responsable"],
                  [(1, 3, 1), (1, 4, 0), (2, 5, 1), (2, 6, 0), (3, 7, 1), (3, 8, 0)]))

rutas = [(1, "Ruta Buceo - Malvín", 1, "diaria", "Recorrido por Av. Rivera, Comercio y Malvín"),
         (2, "Ruta Pocitos - Parque Batlle", 2, "diaria", "Costa de Pocitos y alrededores del Parque Batlle"),
         (3, "Ruta Unión - La Blanqueada", 4, "diaria", "Eje de Av. 8 de Octubre"),
         (4, "Ruta Cordón - Centro", 7, "lun_mie_vie", "Av. 18 de Julio y calles paralelas")]
sql.append(insert("rutas", ["id", "nombre", "zona_id", "frecuencia", "descripcion"], rutas))
ruta_cont = {1: cont_por_zona[1] + cont_por_zona[3], 2: cont_por_zona[2] + cont_por_zona[5],
             3: cont_por_zona[4] + cont_por_zona[6], 4: cont_por_zona[7] + cont_por_zona[8][:5]}
sql_ruta_contenedor = insert("ruta_contenedor", ["ruta_id", "contenedor_id", "orden"],
                             [(r, c, i + 1) for r, cs in ruta_cont.items() for i, c in enumerate(cs)])

# ----------------------------------------- asignaciones y recolecciones (pasado)
asig, reco = [], []
aid = rid = 0
ultima_reco = {}
plan = [(1, 1, [1, 2], "matutino"), (2, 2, [3, 6], "vespertino"), (3, 3, [4, 7], "matutino")]
for dia in dias_habiles(INICIO, HOY - timedelta(days=1)):
    for ruta, cuad, cams, turno in plan:
        aid += 1
        cam = random.choice(cams)
        h0 = 6 if turno == "matutino" else 14
        ini = datetime(dia.year, dia.month, dia.day, h0, random.randint(0, 30))
        fin = ini + timedelta(hours=random.randint(5, 7), minutes=random.randint(0, 50))
        asig.append((aid, ruta, cuad, cam, dia, turno, "completada", ini, fin, None))
        t = ini
        for c in ruta_cont[ruta]:
            if contenedores[c - 1][12] == 0:
                continue
            t += timedelta(minutes=random.randint(6, 16))
            nivel = min(100, max(15, int(random.gauss(68, 18))))
            peso = round(nivel / 100 * (420 if contenedores[c - 1][7] == 2400 else 190) * random.uniform(0.8, 1.2), 2)
            rid += 1
            reco.append((rid, aid, c, nivel, peso, None, t))
            ultima_reco[c] = t
    # la ruta de Cordón - Centro se hace lunes, miércoles y viernes con el camión 3
    if dia.weekday() in (0, 2, 4):
        aid += 1
        ini = datetime(dia.year, dia.month, dia.day, 20, 0)
        fin = ini + timedelta(hours=5)
        asig.append((aid, 4, 1, 3, dia, "nocturno", "completada", ini, fin, None))
        t = ini
        for c in ruta_cont[4]:
            t += timedelta(minutes=random.randint(5, 12))
            nivel = min(100, max(20, int(random.gauss(75, 15))))
            rid += 1
            reco.append((rid, aid, c, nivel, round(nivel / 100 * 420 * random.uniform(0.8, 1.2), 2), None, t))
            ultima_reco[c] = t

# asignaciones planificadas desde hoy hasta la semana de la defensa
for dia in dias_habiles(HOY, date(2026, 11, 21)):
    for ruta, cuad, cams, turno in plan:
        aid += 1
        estado = "en_curso" if (dia == HOY and ruta == 3) else "planificada"
        ini = datetime(dia.year, dia.month, dia.day, 6, 5) if estado == "en_curso" else None
        asig.append((aid, ruta, cuad, cams[0] if ruta != 3 else 4, dia, turno, estado, ini, None, None))

for c in contenedores:
    c[11] = ultima_reco.get(c[0])
sql.append(insert("contenedores", ["id", "codigo", "tipo_residuo_id", "zona_id", "direccion", "latitud",
                                   "longitud", "capacidad_litros", "estado", "nivel_llenado",
                                   "fecha_instalacion", "ultima_recoleccion", "activo"], contenedores))
sql.append(sql_ruta_contenedor)
sql.append(insert("asignaciones", ["id", "ruta_id", "cuadrilla_id", "camion_id", "fecha", "turno", "estado",
                                   "iniciada_en", "finalizada_en", "observaciones"], asig))
sql.append(insert("recolecciones", ["id", "asignacion_id", "contenedor_id", "nivel_previo", "peso_kg",
                                    "observacion", "creado_en"], reco))

# ------------------------------------------------------------------ repuestos
repuestos = [
    (1, "REP-001", "Contenedor 2400 L carga lateral", "contenedor", "unidad", 6, 4),
    (2, "REP-002", "Contenedor 1100 L con ruedas", "contenedor", "unidad", 3, 5),
    (3, "REP-003", "Tapa para contenedor 2400 L", "pieza_contenedor", "unidad", 14, 6),
    (4, "REP-004", "Pedal de apertura", "pieza_contenedor", "unidad", 22, 10),
    (5, "REP-005", "Kit de ruedas y eje", "pieza_contenedor", "kit", 5, 4),
    (6, "REP-006", "Aceite hidráulico ISO 68 (20 L)", "insumo", "bidón", 9, 4),
    (7, "REP-007", "Filtro de aceite de motor", "pieza_camion", "unidad", 12, 6),
    (8, "REP-008", "Guantes anticorte", "insumo", "par", 38, 30),
    (9, "REP-009", "Chaleco reflectivo", "insumo", "unidad", 17, 12),
    (10, "REP-010", "Escobillón industrial", "herramienta", "unidad", 7, 6),
]
sql.append(insert("repuestos", ["id", "codigo", "nombre", "categoria", "unidad", "stock", "stock_minimo"],
                  repuestos))
movs = []
for i in range(1, 41):
    rep = random.choice(repuestos)
    tipo = "salida" if random.random() < 0.7 else "entrada"
    asig_ref = random.randint(1, 120) if tipo == "salida" and rep[3] != "contenedor" else None
    motivo = "Reposición de stock" if tipo == "entrada" else random.choice(
        ["Uso durante la ruta", "Reparación de contenedor", "Entrega de EPP", "Reemplazo de contenedor dañado"])
    movs.append((i, rep[0], tipo, random.randint(1, 4), motivo, random.choice([1, 2, 3, 5, 7]), asig_ref,
                 momento(INICIO + timedelta(days=random.randint(0, 70)))))
sql.append(insert("movimientos_stock", ["id", "repuesto_id", "tipo", "cantidad", "motivo", "usuario_id",
                                        "asignacion_id", "creado_en"], movs))

# ---------------------------------------------------------------- incidencias
calientes = random.sample([c[0] for c in contenedores if c[12] == 1], 7)   # contenedores problemáticos
cuad_de_zona = {1: 1, 3: 1, 2: 2, 5: 2, 4: 3, 6: 3, 7: 1, 8: 2}
incid, hist = [], []
iid = hid = 0
dia = INICIO
while dia < HOY:
    for _ in range(random.choice([0, 1, 1, 1, 2, 2] if (HOY - dia).days > 12 else [1, 2, 2, 3])):
        iid += 1
        cont = random.choice(calientes) if random.random() < 0.45 else random.randint(1, 47)
        zona = contenedores[cont - 1][3]
        tipo = random.choices(["desborde", "falta_recoleccion", "rotura", "quema", "otro"], [50, 15, 15, 10, 10])[0]
        origen = random.choices(["vecino", "qr", "cuadrilla", "administrador"], [35, 35, 15, 15])[0]
        reporta = random.randint(12, 16) if origen == "vecino" else (random.randint(3, 8) if origen == "cuadrilla"
                                                                      else (1 if origen == "administrador" else None))
        prioridad = "alta" if tipo in ("quema", "rotura") else random.choice(["media", "media", "baja", "alta"])
        creado = momento(dia, 6, 22)
        desc = {"desborde": "Contenedor lleno, bolsas en la vereda",
                "falta_recoleccion": "No pasó el camión en el horario habitual",
                "rotura": "Tapa rota y rueda trabada", "quema": "Contenedor con restos de quema",
                "otro": "Residuos voluminosos junto al contenedor"}[tipo]
        reportes = random.randint(2, 5) if (tipo == "desborde" and origen == "qr") else 1
        antiguedad = (HOY - dia).days
        cuad = cuad_de_zona[zona]
        azar = random.random()
        if antiguedad > 10 or azar < 0.35:
            asignado = creado + timedelta(hours=random.uniform(0.5, 10))
            resuelto = asignado + timedelta(hours=random.uniform(2, 40 if tipo != "rotura" else 70))
            if resuelto.date() >= HOY:
                estado, resuelto = "en_curso", None
            else:
                estado = "resuelta"
        elif azar < 0.65:
            asignado, resuelto, estado = creado + timedelta(hours=random.uniform(0.5, 6)), None, "en_curso"
        else:
            asignado, resuelto, estado, cuad = None, None, "abierta", None
        if random.random() < 0.03 and estado == "abierta":
            estado = "descartada"
        resolucion = ("Se vació el contenedor y se limpió el entorno" if tipo in ("desborde", "falta_recoleccion")
                      else "Se reparó o sustituyó el contenedor") if estado == "resuelta" else None
        incid.append((iid, cont, tipo, desc, estado, prioridad, origen, reporta, cuad, reportes, None,
                      creado, asignado, resuelto, resolucion))
        hid += 1
        hist.append((hid, iid, None, "abierta", reporta, "Incidencia registrada", creado))
        if asignado:
            hid += 1
            hist.append((hid, iid, "abierta", "en_curso", 1, f"Asignada a la cuadrilla {cuad}", asignado))
        if resuelto:
            hid += 1
            hist.append((hid, iid, "en_curso", "resuelta", random.choice([3, 5, 7]), resolucion, resuelto))
        if estado == "descartada":
            hid += 1
            hist.append((hid, iid, "abierta", "descartada", 1, "Reporte duplicado", creado + timedelta(hours=2)))
    dia += timedelta(days=1)
sql.append(insert("incidencias", ["id", "contenedor_id", "tipo", "descripcion", "estado", "prioridad", "origen",
                                  "reportado_por", "cuadrilla_id", "cantidad_reportes", "ip_hash", "creado_en",
                                  "asignado_en", "resuelto_en", "resolucion"], incid))
sql.append(insert("incidencia_historial", ["id", "incidencia_id", "estado_anterior", "estado_nuevo", "usuario_id",
                                           "comentario", "creado_en"], hist))

# ------------------------------------------------------------ ingresos a centros
ingresos = []
ing = 0
for dia in dias_habiles(INICIO, HOY - timedelta(days=1)):
    for centro, tipos in acepta.items():
        if centro == 4 or random.random() < 0.5:
            ing += 1
            tipo = random.choice(tipos)
            peso = round(random.uniform(18, 46), 2) if centro == 4 else round(random.uniform(0.4, 3.8), 2)
            operario = {1: 9, 2: 10, 3: 11, 4: 1}[centro]
            ingresos.append((ing, centro, tipo, random.choice([1, 2, 3, 4, 6]), peso, operario, None,
                             momento(dia, 8, 18)))
sql.append(insert("movimientos_centro", ["id", "centro_id", "tipo_residuo_id", "camion_id", "peso_ton", "usuario_id",
                                      "observacion", "creado_en"], ingresos))

# --------------------------------------------------------- notificaciones de ejemplo
notif = [
    (1, 1, "stock_bajo", "Stock bajo", "Contenedor 1100 L con ruedas: quedan 3 (mínimo 5)", "#/repuestos", 0,
     datetime(2026, 10, 28, 9, 12)),
    (2, 1, "capacidad_centro", "Centro casi lleno", "Punto Limpio Pocitos está al 92 % de su capacidad",
     "#/centros", 0, datetime(2026, 10, 29, 16, 40)),
    (3, 1, "mantenimiento", "Mantenimiento próximo", "SIM 3103 tiene un service programado para mañana",
     "#/camiones", 1, datetime(2026, 10, 29, 7, 0)),
    (4, 3, "incidencia_asignada", "Nueva tarea", "Se asignó una incidencia de desborde a tu cuadrilla",
     "#/tareas", 0, datetime(2026, 10, 29, 10, 25)),
]
sql.append(insert("notificaciones", ["id", "usuario_id", "tipo", "titulo", "mensaje", "enlace", "leida",
                                     "creado_en"], notif))

print("".join(sql))
import sys
print(f"-- resumen: {len(contenedores)} contenedores, {len(asig)} asignaciones, {len(reco)} recolecciones, "
      f"{len(incid)} incidencias, {len(ingresos)} ingresos", file=sys.stderr)
