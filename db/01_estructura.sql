-- =====================================================================
-- SiGeRU - Sistema de Gestión de Residuos Urbanos
-- Aplec Software - Proyecto de pasaje de grado ESI 2026
-- Script DDL de creación de la base de datos (MySQL 8)
--
-- Convenciones:
--   * nombres de tablas y columnas en minúscula, en español y en plural
--   * cada columna en su propia línea (lo usa tools/mysql_a_sqlite.py)
--   * los índices se crean aparte con CREATE INDEX
--   * baja lógica con la columna "activo" donde hay historial asociado
-- =====================================================================

-- Los archivos están en UTF-8: el cliente de MySQL tiene que leerlos así (sin esto, los acentos
-- quedaban mal cargados al crear la base en el contenedor; defecto D-20).
SET NAMES utf8mb4;

CREATE DATABASE IF NOT EXISTS sigeru
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

USE sigeru;

SET FOREIGN_KEY_CHECKS = 0;
DROP VIEW IF EXISTS v_ocupacion_centros;
DROP VIEW IF EXISTS v_incidencias_detalle;
DROP TABLE IF EXISTS movimientos_centro;
DROP TABLE IF EXISTS incidencia_historial;
DROP TABLE IF EXISTS incidencias;
DROP TABLE IF EXISTS movimientos_stock;
DROP TABLE IF EXISTS repuestos;
DROP TABLE IF EXISTS recolecciones;
DROP TABLE IF EXISTS asignaciones;
DROP TABLE IF EXISTS ruta_contenedor;
DROP TABLE IF EXISTS rutas;
DROP TABLE IF EXISTS cuadrilla_integrante;
DROP TABLE IF EXISTS cuadrillas;
DROP TABLE IF EXISTS mantenimientos;
DROP TABLE IF EXISTS camiones;
DROP TABLE IF EXISTS maquinaria;
DROP TABLE IF EXISTS centro_tipo_residuo;
DROP TABLE IF EXISTS contenedores;
DROP TABLE IF EXISTS auditoria;
DROP TABLE IF EXISTS parametros;
DROP TABLE IF EXISTS notificaciones;
DROP TABLE IF EXISTS sesiones;
DROP TABLE IF EXISTS usuarios;
DROP TABLE IF EXISTS centros;
DROP TABLE IF EXISTS tipos_residuo;
DROP TABLE IF EXISTS zonas;
DROP TABLE IF EXISTS roles;
SET FOREIGN_KEY_CHECKS = 1;

-- ---------------------------------------------------------------------
-- Catálogos generales
-- ---------------------------------------------------------------------

CREATE TABLE roles (
  id TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(30) NOT NULL,
  descripcion VARCHAR(150) NOT NULL,
  CONSTRAINT uq_roles_nombre UNIQUE (nombre)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE zonas (
  id SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(60) NOT NULL,
  descripcion VARCHAR(200) NULL,
  latitud DECIMAL(9,6) NULL,
  longitud DECIMAL(9,6) NULL,
  activa TINYINT(1) NOT NULL DEFAULT 1,
  CONSTRAINT uq_zonas_nombre UNIQUE (nombre)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE tipos_residuo (
  id SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(50) NOT NULL,
  color CHAR(7) NOT NULL DEFAULT '#6B7280',
  reciclable TINYINT(1) NOT NULL DEFAULT 0,
  descripcion VARCHAR(200) NULL,
  activo TINYINT(1) NOT NULL DEFAULT 1,
  CONSTRAINT uq_tipos_residuo_nombre UNIQUE (nombre)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- Centros de acopio, clasificación y vertederos (API de Gestión)
-- ---------------------------------------------------------------------

CREATE TABLE centros (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(100) NOT NULL,
  tipo ENUM('acopio','clasificacion','vertedero') NOT NULL,
  zona_id SMALLINT UNSIGNED NOT NULL,
  direccion VARCHAR(150) NOT NULL,
  latitud DECIMAL(9,6) NOT NULL,
  longitud DECIMAL(9,6) NOT NULL,
  capacidad_ton DECIMAL(10,2) NOT NULL,
  ocupacion_ton DECIMAL(10,2) NOT NULL DEFAULT 0,
  telefono VARCHAR(20) NULL,
  activo TINYINT(1) NOT NULL DEFAULT 1,
  creado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uq_centros_nombre UNIQUE (nombre),
  CONSTRAINT fk_centros_zona FOREIGN KEY (zona_id) REFERENCES zonas (id),
  CONSTRAINT ck_centros_capacidad CHECK (capacidad_ton > 0),
  CONSTRAINT ck_centros_ocupacion CHECK (ocupacion_ton >= 0 AND ocupacion_ton <= capacidad_ton)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- Usuarios, sesiones y notificaciones (API de Usuarios)
-- ---------------------------------------------------------------------

CREATE TABLE usuarios (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  rol_id TINYINT UNSIGNED NOT NULL,
  nombre VARCHAR(60) NOT NULL,
  apellido VARCHAR(60) NOT NULL,
  documento VARCHAR(8) NULL,
  email VARCHAR(120) NOT NULL,
  telefono VARCHAR(20) NULL,
  password_hash VARCHAR(255) NOT NULL,
  estado ENUM('pendiente','activo','inactivo','rechazado') NOT NULL DEFAULT 'pendiente',
  idioma CHAR(2) NOT NULL DEFAULT 'es',
  centro_id INT UNSIGNED NULL,
  intentos_fallidos TINYINT UNSIGNED NOT NULL DEFAULT 0,
  bloqueado_hasta DATETIME NULL,
  ultimo_acceso DATETIME NULL,
  creado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  actualizado_en DATETIME NULL ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT uq_usuarios_email UNIQUE (email),
  CONSTRAINT uq_usuarios_documento UNIQUE (documento),
  CONSTRAINT fk_usuarios_rol FOREIGN KEY (rol_id) REFERENCES roles (id) ON DELETE RESTRICT,
  CONSTRAINT fk_usuarios_centro FOREIGN KEY (centro_id) REFERENCES centros (id) ON DELETE SET NULL,
  CONSTRAINT ck_usuarios_idioma CHECK (idioma IN ('es','en'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE sesiones (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  usuario_id INT UNSIGNED NOT NULL,
  jti CHAR(32) NOT NULL,
  ip VARCHAR(45) NULL,
  agente VARCHAR(255) NULL,
  emitido_en DATETIME NOT NULL,
  expira_en DATETIME NOT NULL,
  revocado_en DATETIME NULL,
  CONSTRAINT uq_sesiones_jti UNIQUE (jti),
  CONSTRAINT fk_sesiones_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE notificaciones (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  usuario_id INT UNSIGNED NOT NULL,
  tipo VARCHAR(40) NOT NULL,
  titulo VARCHAR(120) NOT NULL,
  mensaje VARCHAR(255) NOT NULL,
  enlace VARCHAR(150) NULL,
  leida TINYINT(1) NOT NULL DEFAULT 0,
  creado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_notificaciones_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Parámetros del sistema: permiten cambiar el comportamiento sin tocar el código
CREATE TABLE parametros (
  clave VARCHAR(60) PRIMARY KEY,
  valor VARCHAR(255) NOT NULL,
  tipo ENUM('entero','decimal','texto','booleano') NOT NULL DEFAULT 'texto',
  descripcion VARCHAR(200) NOT NULL,
  publico TINYINT(1) NOT NULL DEFAULT 0,
  actualizado_en DATETIME NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Registro de auditoría compartido por todos los servicios
CREATE TABLE auditoria (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  usuario_id INT UNSIGNED NULL,
  servicio VARCHAR(20) NOT NULL,
  accion VARCHAR(40) NOT NULL,
  entidad VARCHAR(40) NOT NULL,
  entidad_id VARCHAR(40) NULL,
  detalle VARCHAR(500) NULL,
  ip VARCHAR(45) NULL,
  creado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_auditoria_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- Elementos fijos e inventario (API de Gestión)
-- ---------------------------------------------------------------------

CREATE TABLE contenedores (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  codigo VARCHAR(12) NOT NULL,
  tipo_residuo_id SMALLINT UNSIGNED NOT NULL,
  zona_id SMALLINT UNSIGNED NOT NULL,
  direccion VARCHAR(150) NOT NULL,
  latitud DECIMAL(9,6) NOT NULL,
  longitud DECIMAL(9,6) NOT NULL,
  capacidad_litros SMALLINT UNSIGNED NOT NULL DEFAULT 2400,
  estado ENUM('funcional','desbordado','roto','fuera_servicio') NOT NULL DEFAULT 'funcional',
  nivel_llenado TINYINT UNSIGNED NOT NULL DEFAULT 0,
  fecha_instalacion DATE NULL,
  ultima_recoleccion DATETIME NULL,
  activo TINYINT(1) NOT NULL DEFAULT 1,
  creado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  actualizado_en DATETIME NULL ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT uq_contenedores_codigo UNIQUE (codigo),
  CONSTRAINT fk_contenedores_tipo FOREIGN KEY (tipo_residuo_id) REFERENCES tipos_residuo (id),
  CONSTRAINT fk_contenedores_zona FOREIGN KEY (zona_id) REFERENCES zonas (id),
  CONSTRAINT ck_contenedores_nivel CHECK (nivel_llenado <= 100),
  CONSTRAINT ck_contenedores_coord CHECK (latitud BETWEEN -90 AND 90 AND longitud BETWEEN -180 AND 180)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tipos de residuo que acepta cada centro (relación N:M)
CREATE TABLE centro_tipo_residuo (
  centro_id INT UNSIGNED NOT NULL,
  tipo_residuo_id SMALLINT UNSIGNED NOT NULL,
  PRIMARY KEY (centro_id, tipo_residuo_id),
  CONSTRAINT fk_ctr_centro FOREIGN KEY (centro_id) REFERENCES centros (id) ON DELETE CASCADE,
  CONSTRAINT fk_ctr_tipo FOREIGN KEY (tipo_residuo_id) REFERENCES tipos_residuo (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE maquinaria (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  centro_id INT UNSIGNED NOT NULL,
  codigo VARCHAR(20) NOT NULL,
  descripcion VARCHAR(100) NOT NULL,
  tipo ENUM('compactadora','prensa','balanza','cargadora','trituradora','cinta','otro') NOT NULL,
  estado ENUM('operativa','mantenimiento','fuera_servicio') NOT NULL DEFAULT 'operativa',
  fecha_adquisicion DATE NULL,
  ultimo_mantenimiento DATE NULL,
  activo TINYINT(1) NOT NULL DEFAULT 1,
  CONSTRAINT uq_maquinaria_codigo UNIQUE (codigo),
  CONSTRAINT fk_maquinaria_centro FOREIGN KEY (centro_id) REFERENCES centros (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- Flota, cuadrillas y rutas (API de Recolección)
-- ---------------------------------------------------------------------

CREATE TABLE camiones (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  matricula VARCHAR(10) NOT NULL,
  marca VARCHAR(40) NOT NULL,
  modelo VARCHAR(40) NOT NULL,
  anio SMALLINT UNSIGNED NOT NULL,
  tipo ENUM('compactador','carga_lateral','caja_abierta','grua') NOT NULL,
  capacidad_ton DECIMAL(5,2) NOT NULL,
  estado ENUM('disponible','en_ruta','mantenimiento','fuera_servicio') NOT NULL DEFAULT 'disponible',
  kilometraje INT UNSIGNED NOT NULL DEFAULT 0,
  ultima_latitud DECIMAL(9,6) NULL,
  ultima_longitud DECIMAL(9,6) NULL,
  ultima_posicion_en DATETIME NULL,
  activo TINYINT(1) NOT NULL DEFAULT 1,
  creado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uq_camiones_matricula UNIQUE (matricula),
  CONSTRAINT ck_camiones_anio CHECK (anio BETWEEN 1990 AND 2100),
  CONSTRAINT ck_camiones_capacidad CHECK (capacidad_ton > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE mantenimientos (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  camion_id INT UNSIGNED NOT NULL,
  tipo ENUM('preventivo','correctivo') NOT NULL,
  descripcion VARCHAR(200) NOT NULL,
  fecha_programada DATE NOT NULL,
  fecha_realizada DATE NULL,
  kilometraje INT UNSIGNED NULL,
  costo DECIMAL(10,2) NULL,
  estado ENUM('programado','realizado','cancelado') NOT NULL DEFAULT 'programado',
  creado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_mantenimientos_camion FOREIGN KEY (camion_id) REFERENCES camiones (id) ON DELETE CASCADE,
  CONSTRAINT ck_mantenimientos_costo CHECK (costo IS NULL OR costo >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE cuadrillas (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(60) NOT NULL,
  zona_id SMALLINT UNSIGNED NOT NULL,
  turno ENUM('matutino','vespertino','nocturno') NOT NULL,
  activa TINYINT(1) NOT NULL DEFAULT 1,
  CONSTRAINT uq_cuadrillas_nombre UNIQUE (nombre),
  CONSTRAINT fk_cuadrillas_zona FOREIGN KEY (zona_id) REFERENCES zonas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Integrantes de cada cuadrilla: un usuario integra como máximo una cuadrilla
CREATE TABLE cuadrilla_integrante (
  cuadrilla_id INT UNSIGNED NOT NULL,
  usuario_id INT UNSIGNED NOT NULL,
  es_responsable TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (cuadrilla_id, usuario_id),
  CONSTRAINT uq_integrante_usuario UNIQUE (usuario_id),
  CONSTRAINT fk_integrante_cuadrilla FOREIGN KEY (cuadrilla_id) REFERENCES cuadrillas (id) ON DELETE CASCADE,
  CONSTRAINT fk_integrante_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE rutas (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(80) NOT NULL,
  zona_id SMALLINT UNSIGNED NOT NULL,
  frecuencia ENUM('diaria','lun_mie_vie','mar_jue_sab','semanal') NOT NULL DEFAULT 'diaria',
  descripcion VARCHAR(200) NULL,
  activa TINYINT(1) NOT NULL DEFAULT 1,
  CONSTRAINT uq_rutas_nombre UNIQUE (nombre),
  CONSTRAINT fk_rutas_zona FOREIGN KEY (zona_id) REFERENCES zonas (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Contenedores que recorre cada ruta y en qué orden
CREATE TABLE ruta_contenedor (
  ruta_id INT UNSIGNED NOT NULL,
  contenedor_id INT UNSIGNED NOT NULL,
  orden SMALLINT UNSIGNED NOT NULL,
  PRIMARY KEY (ruta_id, contenedor_id),
  CONSTRAINT uq_ruta_orden UNIQUE (ruta_id, orden),
  CONSTRAINT fk_rc_ruta FOREIGN KEY (ruta_id) REFERENCES rutas (id) ON DELETE CASCADE,
  CONSTRAINT fk_rc_contenedor FOREIGN KEY (contenedor_id) REFERENCES contenedores (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Asignación de una ruta a una cuadrilla y un camión en una fecha y turno
CREATE TABLE asignaciones (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  ruta_id INT UNSIGNED NOT NULL,
  cuadrilla_id INT UNSIGNED NOT NULL,
  camion_id INT UNSIGNED NOT NULL,
  fecha DATE NOT NULL,
  turno ENUM('matutino','vespertino','nocturno') NOT NULL,
  estado ENUM('planificada','en_curso','completada','cancelada') NOT NULL DEFAULT 'planificada',
  iniciada_en DATETIME NULL,
  finalizada_en DATETIME NULL,
  observaciones VARCHAR(300) NULL,
  creado_en DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT uq_asig_camion_turno UNIQUE (camion_id, fecha, turno),
  CONSTRAINT uq_asig_cuadrilla_turno UNIQUE (cuadrilla_id, fecha, turno),
  CONSTRAINT fk_asig_ruta FOREIGN KEY (ruta_id) REFERENCES rutas (id),
  CONSTRAINT fk_asig_cuadrilla FOREIGN KEY (cuadrilla_id) REFERENCES cuadrillas (id),
  CONSTRAINT fk_asig_camion FOREIGN KEY (camion_id) REFERENCES camiones (id),
  CONSTRAINT ck_asig_fechas CHECK (finalizada_en IS NULL OR iniciada_en IS NULL OR finalizada_en >= iniciada_en)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Cada vaciado de contenedor registrado durante una asignación
CREATE TABLE recolecciones (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  asignacion_id INT UNSIGNED NOT NULL,
  contenedor_id INT UNSIGNED NOT NULL,
  nivel_previo TINYINT UNSIGNED NOT NULL,
  peso_kg DECIMAL(7,2) NOT NULL,
  observacion VARCHAR(200) NULL,
  creado_en DATETIME NOT NULL,
  CONSTRAINT uq_recoleccion_asig_cont UNIQUE (asignacion_id, contenedor_id),
  CONSTRAINT fk_recoleccion_asig FOREIGN KEY (asignacion_id) REFERENCES asignaciones (id) ON DELETE CASCADE,
  CONSTRAINT fk_recoleccion_cont FOREIGN KEY (contenedor_id) REFERENCES contenedores (id),
  CONSTRAINT ck_recoleccion_nivel CHECK (nivel_previo <= 100),
  CONSTRAINT ck_recoleccion_peso CHECK (peso_kg >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- Stock de repuestos y consumo de recursos (API de Gestión / Recolección)
-- ---------------------------------------------------------------------

CREATE TABLE repuestos (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  codigo VARCHAR(20) NOT NULL,
  nombre VARCHAR(100) NOT NULL,
  categoria ENUM('contenedor','pieza_contenedor','pieza_camion','herramienta','insumo') NOT NULL,
  unidad VARCHAR(15) NOT NULL DEFAULT 'unidad',
  stock INT UNSIGNED NOT NULL DEFAULT 0,
  stock_minimo INT UNSIGNED NOT NULL DEFAULT 0,
  activo TINYINT(1) NOT NULL DEFAULT 1,
  CONSTRAINT uq_repuestos_codigo UNIQUE (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE movimientos_stock (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  repuesto_id INT UNSIGNED NOT NULL,
  tipo ENUM('entrada','salida') NOT NULL,
  cantidad INT UNSIGNED NOT NULL,
  motivo VARCHAR(150) NOT NULL,
  usuario_id INT UNSIGNED NOT NULL,
  asignacion_id INT UNSIGNED NULL,
  creado_en DATETIME NOT NULL,
  CONSTRAINT fk_mov_repuesto FOREIGN KEY (repuesto_id) REFERENCES repuestos (id),
  CONSTRAINT fk_mov_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios (id),
  CONSTRAINT fk_mov_asignacion FOREIGN KEY (asignacion_id) REFERENCES asignaciones (id) ON DELETE SET NULL,
  CONSTRAINT ck_mov_cantidad CHECK (cantidad > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- Incidencias y su historial (API de Gestión)
-- ---------------------------------------------------------------------

CREATE TABLE incidencias (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  contenedor_id INT UNSIGNED NOT NULL,
  tipo ENUM('desborde','rotura','quema','falta_recoleccion','otro') NOT NULL,
  descripcion VARCHAR(500) NULL,
  estado ENUM('abierta','en_curso','resuelta','descartada') NOT NULL DEFAULT 'abierta',
  prioridad ENUM('baja','media','alta') NOT NULL DEFAULT 'media',
  origen ENUM('vecino','qr','cuadrilla','administrador') NOT NULL,
  reportado_por INT UNSIGNED NULL,
  cuadrilla_id INT UNSIGNED NULL,
  cantidad_reportes SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  ip_hash CHAR(64) NULL,
  creado_en DATETIME NOT NULL,
  asignado_en DATETIME NULL,
  resuelto_en DATETIME NULL,
  resolucion VARCHAR(300) NULL,
  CONSTRAINT fk_incidencias_contenedor FOREIGN KEY (contenedor_id) REFERENCES contenedores (id),
  CONSTRAINT fk_incidencias_usuario FOREIGN KEY (reportado_por) REFERENCES usuarios (id) ON DELETE SET NULL,
  CONSTRAINT fk_incidencias_cuadrilla FOREIGN KEY (cuadrilla_id) REFERENCES cuadrillas (id) ON DELETE SET NULL,
  CONSTRAINT ck_incidencias_fechas CHECK (resuelto_en IS NULL OR resuelto_en >= creado_en)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE incidencia_historial (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  incidencia_id INT UNSIGNED NOT NULL,
  estado_anterior VARCHAR(12) NULL,
  estado_nuevo VARCHAR(12) NOT NULL,
  usuario_id INT UNSIGNED NULL,
  comentario VARCHAR(300) NULL,
  creado_en DATETIME NOT NULL,
  CONSTRAINT fk_historial_incidencia FOREIGN KEY (incidencia_id) REFERENCES incidencias (id) ON DELETE CASCADE,
  CONSTRAINT fk_historial_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Movimientos de residuos en los centros (los registra el operario):
-- ingreso = llega un camión con residuos; egreso = sale material hacia reciclaje o disposición
CREATE TABLE movimientos_centro (
  id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  centro_id INT UNSIGNED NOT NULL,
  tipo_movimiento ENUM('ingreso','egreso') NOT NULL DEFAULT 'ingreso',
  tipo_residuo_id SMALLINT UNSIGNED NOT NULL,
  camion_id INT UNSIGNED NULL,
  peso_ton DECIMAL(8,2) NOT NULL,
  destino VARCHAR(100) NULL,
  usuario_id INT UNSIGNED NOT NULL,
  observacion VARCHAR(200) NULL,
  creado_en DATETIME NOT NULL,
  CONSTRAINT fk_movcentro_centro FOREIGN KEY (centro_id) REFERENCES centros (id),
  CONSTRAINT fk_movcentro_tipo FOREIGN KEY (tipo_residuo_id) REFERENCES tipos_residuo (id),
  CONSTRAINT fk_movcentro_camion FOREIGN KEY (camion_id) REFERENCES camiones (id) ON DELETE SET NULL,
  CONSTRAINT fk_movcentro_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios (id),
  CONSTRAINT ck_movcentro_peso CHECK (peso_ton > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- Índices para las consultas más frecuentes (filtros y reportes)
-- ---------------------------------------------------------------------

CREATE INDEX ix_usuarios_estado ON usuarios (estado);
CREATE INDEX ix_sesiones_usuario ON sesiones (usuario_id);
CREATE INDEX ix_notificaciones_usuario ON notificaciones (usuario_id, leida);
CREATE INDEX ix_auditoria_fecha ON auditoria (creado_en);
CREATE INDEX ix_contenedores_estado ON contenedores (estado);
CREATE INDEX ix_incidencias_estado ON incidencias (estado);
CREATE INDEX ix_incidencias_fecha ON incidencias (creado_en);
CREATE INDEX ix_incidencias_cont_tipo ON incidencias (contenedor_id, tipo, estado);
CREATE INDEX ix_asignaciones_fecha ON asignaciones (fecha);
CREATE INDEX ix_recolecciones_fecha ON recolecciones (creado_en);
CREATE INDEX ix_movcentro_fecha ON movimientos_centro (creado_en);
CREATE INDEX ix_mantenimientos_fecha ON mantenimientos (fecha_programada, estado);

-- ---------------------------------------------------------------------
-- Vistas para reportes
-- ---------------------------------------------------------------------

CREATE VIEW v_incidencias_detalle AS
SELECT i.id, i.tipo, i.estado, i.prioridad, i.origen, i.cantidad_reportes,
       i.creado_en, i.asignado_en, i.resuelto_en, i.cuadrilla_id,
       c.id AS contenedor_id, c.codigo AS contenedor_codigo, c.direccion,
       c.latitud, c.longitud, z.id AS zona_id, z.nombre AS zona,
       t.nombre AS tipo_residuo
FROM incidencias i
JOIN contenedores c ON c.id = i.contenedor_id
JOIN zonas z ON z.id = c.zona_id
JOIN tipos_residuo t ON t.id = c.tipo_residuo_id;

CREATE VIEW v_ocupacion_centros AS
SELECT ce.id, ce.nombre, ce.tipo, ce.capacidad_ton, ce.ocupacion_ton,
       ROUND(ce.ocupacion_ton * 100 / ce.capacidad_ton, 1) AS porcentaje,
       z.nombre AS zona
FROM centros ce
JOIN zonas z ON z.id = ce.zona_id
WHERE ce.activo = 1;
