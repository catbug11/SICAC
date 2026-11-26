-- ============================================================================
-- FASE 4: VERIFICACIÓN PL/SQL, VISTAS ANALÍTICAS, ENMASCARAMIENTO Y PERMISOS
-- Ejecutar conectado como: SICAC (Con delimitador ; normal)
-- ============================================================================
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
ALTER SESSION SET CURRENT_SCHEMA = SICAC;

-- 1. VERIFICAR QUE TODOS LOS OBJETOS PL/SQL ESTÉN VÁLIDOS
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_type IN ('FUNCTION', 'TRIGGER')
 ORDER BY object_type, object_name;

-- 2. VISTA DE ENMASCARAMIENTO DE DATOS SENSIBLES (PII - Seguridad)
CREATE OR REPLACE VIEW vw_persona_enmascarada AS
SELECT id_persona,
       SUBSTR(ci, 1, 2) || '****' || SUBSTR(ci, -2) AS ci_enmascarado,
       expedido,
       nombres,
       apellido_paterno,
       SUBSTR(apellido_materno, 1, 1) || '.' AS inicial_materno,
       CASE WHEN telefono IS NOT NULL THEN '****' || SUBSTR(telefono, -4) ELSE NULL END AS telefono_enmascarado,
       id_municipio,
       estado
  FROM persona;

-- 3. VISTA ANALÍTICA: SUBVENCIÓN POR ESTACIÓN Y COMBUSTIBLE (RF-13)
CREATE OR REPLACE VIEW vw_resumen_subvencion_estacion AS
SELECT e.codigo_anh,
       e.nombre AS estacion,
       m.departamento,
       m.nombre AS municipio,
       cb.nombre AS combustible,
       COUNT(c.id_carga) AS total_cargas_validas,
       NVL(SUM(c.cantidad_litros), 0) AS total_litros_despachados,
       NVL(SUM(c.cantidad_litros * sc.precio_venta), 0) AS monto_cobrado_bs,
       NVL(SUM(c.cantidad_litros * sc.monto_subvencion), 0) AS monto_subvencionado_bs
  FROM carga c
  JOIN surtidor s ON s.id_surtidor = c.id_surtidor
  JOIN estacion e ON e.id_estacion = s.id_estacion
  JOIN municipio m ON m.id_municipio = e.id_municipio
  JOIN combustible cb ON cb.id_combustible = s.id_combustible
  JOIN subvencion_combustible sc ON sc.id_subvencion = c.id_subvencion
 WHERE c.estado = 'VALIDA'
 GROUP BY e.codigo_anh, e.nombre, m.departamento, m.nombre, cb.nombre;

-- 4. VISTA OPERATIVA: ALERTAS ACTIVAS CON CONTEXTO DE VEHÍCULO Y REGLA
CREATE OR REPLACE VIEW vw_alertas_detalle AS
SELECT a.id_alerta,
       a.fecha_hora AS fecha_alerta,
       ta.nivel_riesgo,
       rd.codigo AS codigo_regla,
       rd.nombre AS regla,
       v.placa,
       tv.nombre AS tipo_vehiculo,
       p.ci || '-' || p.expedido AS ci_conductor,
       p.nombres || ' ' || p.apellido_paterno AS conductor,
       e.nombre AS estacion,
       c.cantidad_litros,
       a.valor_detectado,
       a.valor_umbral,
       a.estado AS estado_alerta,
       a.observacion
  FROM alerta a
  JOIN regla_deteccion rd ON rd.id_regla = a.id_regla
  JOIN tipo_alerta ta ON ta.id_tipo_alerta = rd.id_tipo_alerta
  JOIN carga c ON c.id_carga = a.id_carga
  JOIN vehiculo v ON v.id_vehiculo = c.id_vehiculo
  JOIN tipo_vehiculo tv ON tv.id_tipo_vehiculo = v.id_tipo_vehiculo
  JOIN persona p ON p.id_persona = c.id_persona
  JOIN surtidor s ON s.id_surtidor = c.id_surtidor
  JOIN estacion e ON e.id_estacion = s.id_estacion;

-- 5. VISTA DE BALANCE DE INVENTARIO POR ESTACIÓN (Conciliación Recepciones vs Cargas)
CREATE OR REPLACE VIEW vw_balance_inventario_estacion AS
SELECT e.id_estacion,
       e.codigo_anh,
       e.nombre AS estacion,
       cb.nombre AS combustible,
       NVL(rec.total_recibido, 0) AS litros_ingresados,
       NVL(desp.total_despachado, 0) AS litros_despachados,
       (NVL(rec.total_recibido, 0) - NVL(desp.total_despachado, 0)) AS saldo_teorico_litros
  FROM estacion e
  CROSS JOIN combustible cb
  LEFT JOIN (
      SELECT id_estacion, id_combustible, SUM(cantidad_litros) AS total_recibido
        FROM recepcion_combustible
       GROUP BY id_estacion, id_combustible
  ) rec ON rec.id_estacion = e.id_estacion AND rec.id_combustible = cb.id_combustible
  LEFT JOIN (
      SELECT s.id_estacion, s.id_combustible, SUM(c.cantidad_litros) AS total_despachado
        FROM carga c
        JOIN surtidor s ON s.id_surtidor = c.id_surtidor
       WHERE c.estado = 'VALIDA'
       GROUP BY s.id_estacion, s.id_combustible
  ) desp ON desp.id_estacion = e.id_estacion AND desp.id_combustible = cb.id_combustible
 WHERE rec.total_recibido IS NOT NULL OR desp.total_despachado IS NOT NULL;

-- 6. PERMISOS DE SEGURIDAD POR ROL (Principio de Mínimo Privilegio)
GRANT SELECT, INSERT, UPDATE ON municipio TO ROL_SICAC_APP;
GRANT SELECT, INSERT, UPDATE ON combustible TO ROL_SICAC_APP;
GRANT SELECT, INSERT, UPDATE ON tipo_vehiculo TO ROL_SICAC_APP;
GRANT SELECT, INSERT, UPDATE ON tipo_alerta TO ROL_SICAC_APP;
GRANT SELECT, INSERT, UPDATE ON persona TO ROL_SICAC_APP;
GRANT SELECT, INSERT, UPDATE ON huella_digital TO ROL_SICAC_APP;
GRANT SELECT, INSERT, UPDATE ON vehiculo TO ROL_SICAC_APP;
GRANT SELECT, INSERT, UPDATE ON propiedad_vehiculo TO ROL_SICAC_APP;
GRANT SELECT, INSERT, UPDATE ON estacion TO ROL_SICAC_APP;
GRANT SELECT, INSERT, UPDATE ON funcionario TO ROL_SICAC_APP;
GRANT SELECT, INSERT, UPDATE ON surtidor TO ROL_SICAC_APP;
GRANT SELECT, INSERT, UPDATE ON recepcion_combustible TO ROL_SICAC_APP;
GRANT SELECT, INSERT, UPDATE ON subvencion_combustible TO ROL_SICAC_APP;
GRANT SELECT, INSERT, UPDATE ON carga TO ROL_SICAC_APP;
GRANT SELECT, INSERT, UPDATE ON regla_deteccion TO ROL_SICAC_APP;
GRANT SELECT, INSERT, UPDATE ON alerta TO ROL_SICAC_APP;
GRANT SELECT ON historial TO ROL_SICAC_APP;
GRANT SELECT ON vw_resumen_subvencion_estacion TO ROL_SICAC_APP;
GRANT SELECT ON vw_alertas_detalle TO ROL_SICAC_APP;
GRANT SELECT ON vw_balance_inventario_estacion TO ROL_SICAC_APP;

-- Permisos de solo lectura y enmascaramiento para el Auditor
GRANT SELECT ON historial TO ROL_SICAC_AUDITOR;
GRANT SELECT ON alerta TO ROL_SICAC_AUDITOR;
GRANT SELECT ON carga TO ROL_SICAC_AUDITOR;
GRANT SELECT ON vw_persona_enmascarada TO ROL_SICAC_AUDITOR;
GRANT SELECT ON vw_resumen_subvencion_estacion TO ROL_SICAC_AUDITOR;
GRANT SELECT ON vw_alertas_detalle TO ROL_SICAC_AUDITOR;
GRANT SELECT ON vw_balance_inventario_estacion TO ROL_SICAC_AUDITOR;
