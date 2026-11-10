-- =====================================================================
-- SiGeRU - Usuarios de la base de datos con privilegios mínimos
--
-- Cada aplicación se conecta con su propio usuario y solo puede tocar las
-- tablas que le corresponden. Donde un servicio necesita actualizar datos
-- de otro, se le da permiso solamente sobre las columnas necesarias.
--
-- Este archivo es una plantilla: el módulo bd.sh del script del servidor
-- reemplaza {{HOST_APP}} por la IP del servidor de aplicaciones y las
-- {{CLAVE_...}} por contraseñas generadas al azar.
-- =====================================================================

-- ---------------------------------------------------------- API de Usuarios
CREATE USER IF NOT EXISTS 'api_usuarios'@'{{HOST_APP}}' IDENTIFIED BY '{{CLAVE_API_USUARIOS}}';
GRANT SELECT ON sigeru.roles TO 'api_usuarios'@'{{HOST_APP}}';
GRANT SELECT, INSERT, UPDATE ON sigeru.usuarios TO 'api_usuarios'@'{{HOST_APP}}';
GRANT SELECT, INSERT, UPDATE, DELETE ON sigeru.sesiones TO 'api_usuarios'@'{{HOST_APP}}';
GRANT SELECT, INSERT, UPDATE, DELETE ON sigeru.notificaciones TO 'api_usuarios'@'{{HOST_APP}}';
GRANT SELECT, UPDATE ON sigeru.parametros TO 'api_usuarios'@'{{HOST_APP}}';
GRANT INSERT ON sigeru.auditoria TO 'api_usuarios'@'{{HOST_APP}}';
GRANT SELECT ON sigeru.centros TO 'api_usuarios'@'{{HOST_APP}}';
GRANT SELECT ON sigeru.cuadrillas TO 'api_usuarios'@'{{HOST_APP}}';
GRANT SELECT ON sigeru.cuadrilla_integrante TO 'api_usuarios'@'{{HOST_APP}}';

-- ----------------------------------------------------------- API de Gestión
CREATE USER IF NOT EXISTS 'api_gestion'@'{{HOST_APP}}' IDENTIFIED BY '{{CLAVE_API_GESTION}}';
GRANT SELECT, INSERT, UPDATE, DELETE ON sigeru.zonas TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT, INSERT, UPDATE, DELETE ON sigeru.tipos_residuo TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT, INSERT, UPDATE, DELETE ON sigeru.contenedores TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT, INSERT, UPDATE, DELETE ON sigeru.centros TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT, INSERT, UPDATE, DELETE ON sigeru.centro_tipo_residuo TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT, INSERT, UPDATE, DELETE ON sigeru.maquinaria TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT, INSERT, UPDATE, DELETE ON sigeru.repuestos TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT, INSERT ON sigeru.movimientos_stock TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT, INSERT, UPDATE, DELETE ON sigeru.incidencias TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT, INSERT ON sigeru.incidencia_historial TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT, INSERT ON sigeru.movimientos_centro TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT ON sigeru.v_incidencias_detalle TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT ON sigeru.v_ocupacion_centros TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT ON sigeru.roles TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT ON sigeru.parametros TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT ON sigeru.cuadrillas TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT ON sigeru.cuadrilla_integrante TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT ON sigeru.camiones TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT ON sigeru.recolecciones TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT (id, rol_id, nombre, apellido, email, estado, centro_id, idioma) ON sigeru.usuarios TO 'api_gestion'@'{{HOST_APP}}';
GRANT SELECT (jti, usuario_id, expira_en, revocado_en) ON sigeru.sesiones TO 'api_gestion'@'{{HOST_APP}}';
GRANT INSERT ON sigeru.notificaciones TO 'api_gestion'@'{{HOST_APP}}';
GRANT INSERT ON sigeru.auditoria TO 'api_gestion'@'{{HOST_APP}}';

-- -------------------------------------------------------- API de Recolección
CREATE USER IF NOT EXISTS 'api_recoleccion'@'{{HOST_APP}}' IDENTIFIED BY '{{CLAVE_API_RECOLECCION}}';
GRANT SELECT, INSERT, UPDATE, DELETE ON sigeru.camiones TO 'api_recoleccion'@'{{HOST_APP}}';
GRANT SELECT, INSERT, UPDATE, DELETE ON sigeru.mantenimientos TO 'api_recoleccion'@'{{HOST_APP}}';
GRANT SELECT, INSERT, UPDATE, DELETE ON sigeru.cuadrillas TO 'api_recoleccion'@'{{HOST_APP}}';
GRANT SELECT, INSERT, UPDATE, DELETE ON sigeru.cuadrilla_integrante TO 'api_recoleccion'@'{{HOST_APP}}';
GRANT SELECT, INSERT, UPDATE, DELETE ON sigeru.rutas TO 'api_recoleccion'@'{{HOST_APP}}';
GRANT SELECT, INSERT, UPDATE, DELETE ON sigeru.ruta_contenedor TO 'api_recoleccion'@'{{HOST_APP}}';
GRANT SELECT, INSERT, UPDATE, DELETE ON sigeru.asignaciones TO 'api_recoleccion'@'{{HOST_APP}}';
GRANT SELECT, INSERT, UPDATE, DELETE ON sigeru.recolecciones TO 'api_recoleccion'@'{{HOST_APP}}';
GRANT SELECT ON sigeru.zonas TO 'api_recoleccion'@'{{HOST_APP}}';
GRANT SELECT ON sigeru.tipos_residuo TO 'api_recoleccion'@'{{HOST_APP}}';
GRANT SELECT ON sigeru.roles TO 'api_recoleccion'@'{{HOST_APP}}';
GRANT SELECT ON sigeru.parametros TO 'api_recoleccion'@'{{HOST_APP}}';
GRANT SELECT ON sigeru.centros TO 'api_recoleccion'@'{{HOST_APP}}';
GRANT SELECT, UPDATE (estado, nivel_llenado, ultima_recoleccion) ON sigeru.contenedores TO 'api_recoleccion'@'{{HOST_APP}}';
-- para ordenar el recorrido por urgencia: solo las columnas necesarias de las incidencias (lectura)
GRANT SELECT (id, contenedor_id, tipo, estado, cantidad_reportes) ON sigeru.incidencias TO 'api_recoleccion'@'{{HOST_APP}}';
GRANT SELECT, UPDATE (stock) ON sigeru.repuestos TO 'api_recoleccion'@'{{HOST_APP}}';
GRANT SELECT, INSERT ON sigeru.movimientos_stock TO 'api_recoleccion'@'{{HOST_APP}}';
GRANT SELECT (id, rol_id, nombre, apellido, email, estado) ON sigeru.usuarios TO 'api_recoleccion'@'{{HOST_APP}}';
GRANT SELECT (jti, usuario_id, expira_en, revocado_en) ON sigeru.sesiones TO 'api_recoleccion'@'{{HOST_APP}}';
GRANT INSERT ON sigeru.notificaciones TO 'api_recoleccion'@'{{HOST_APP}}';
GRANT INSERT ON sigeru.auditoria TO 'api_recoleccion'@'{{HOST_APP}}';

-- -------------------------------------------------------------- Backoffice
CREATE USER IF NOT EXISTS 'backoffice'@'{{HOST_APP}}' IDENTIFIED BY '{{CLAVE_BACKOFFICE}}';
GRANT SELECT ON sigeru.* TO 'backoffice'@'{{HOST_APP}}';
GRANT INSERT, UPDATE ON sigeru.usuarios TO 'backoffice'@'{{HOST_APP}}';
GRANT INSERT, UPDATE ON sigeru.parametros TO 'backoffice'@'{{HOST_APP}}';
GRANT INSERT, UPDATE ON sigeru.zonas TO 'backoffice'@'{{HOST_APP}}';
GRANT INSERT, UPDATE ON sigeru.tipos_residuo TO 'backoffice'@'{{HOST_APP}}';
GRANT UPDATE ON sigeru.sesiones TO 'backoffice'@'{{HOST_APP}}';
GRANT UPDATE (estado, prioridad, cuadrilla_id, asignado_en, resuelto_en, resolucion) ON sigeru.incidencias TO 'backoffice'@'{{HOST_APP}}';
GRANT INSERT ON sigeru.incidencia_historial TO 'backoffice'@'{{HOST_APP}}';
GRANT INSERT ON sigeru.notificaciones TO 'backoffice'@'{{HOST_APP}}';
GRANT INSERT ON sigeru.auditoria TO 'backoffice'@'{{HOST_APP}}';

-- --------------------------------------------- Usuario local para respaldos
CREATE USER IF NOT EXISTS 'respaldo'@'localhost' IDENTIFIED BY '{{CLAVE_RESPALDO}}';
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER ON sigeru.* TO 'respaldo'@'localhost';
GRANT PROCESS ON *.* TO 'respaldo'@'localhost';

FLUSH PRIVILEGES;
