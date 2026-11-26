-- ============================================================================
-- FASE 3: OBJETOS PL/SQL (FUNCIONES, TRIGGERS DE AUDITORÍA/ALERTAS Y PROCESOS)
-- Ejecutar conectado a FREEPDB1 (como SYSDBA)
-- ============================================================================

ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = SICAC;

-- ----------------------------------------------------------------------------
-- 1. FUNCIÓN AUXILIAR: OBTENER SUBVENCIÓN VIGENTE POR COMBUSTIBLE Y SEGMENTO
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_obtener_subvencion_vigente (
    p_id_combustible IN NUMBER,
    p_segmento       IN VARCHAR2 DEFAULT 'GENERAL',
    p_fecha          IN DATE     DEFAULT SYSDATE
) RETURN NUMBER IS
    v_id_subvencion subvencion_combustible.id_subvencion%TYPE;
BEGIN
    SELECT id_subvencion
      INTO v_id_subvencion
      FROM subvencion_combustible
     WHERE id_combustible = p_id_combustible
       AND segmento = NVL(p_segmento, 'GENERAL')
       AND fecha_inicio <= TRUNC(p_fecha)
       AND (fecha_fin IS NULL OR fecha_fin >= TRUNC(p_fecha))
     ORDER BY fecha_inicio DESC
     FETCH FIRST 1 ROWS ONLY;

    RETURN v_id_subvencion;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20001, 'No existe subvencion vigente para el combustible y segmento indicados.');
END fn_obtener_subvencion_vigente;
/

-- ----------------------------------------------------------------------------
-- 2. TRIGGERS DE AUDITORÍA AUTOMÁTICA (TABLA HISTORIAL)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_aud_carga
AFTER INSERT OR UPDATE OR DELETE ON carga
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        INSERT INTO historial (tabla_afectada, id_registro, operacion, columna, valor_anterior, valor_nuevo, id_funcionario)
        VALUES ('CARGA', :NEW.id_carga, 'INSERT', 'CANTIDAD_LITROS', NULL, TO_CHAR(:NEW.cantidad_litros), :NEW.id_funcionario);
    ELSIF UPDATING THEN
        IF NVL(:OLD.estado, '-') <> NVL(:NEW.estado, '-') THEN
            INSERT INTO historial (tabla_afectada, id_registro, operacion, columna, valor_anterior, valor_nuevo, id_funcionario)
            VALUES ('CARGA', :NEW.id_carga, 'UPDATE', 'ESTADO', :OLD.estado, :NEW.estado, :NEW.id_funcionario);
        END IF;
    ELSIF DELETING THEN
        INSERT INTO historial (tabla_afectada, id_registro, operacion, columna, valor_anterior, valor_nuevo, id_funcionario)
        VALUES ('CARGA', :OLD.id_carga, 'DELETE', 'REGISTRO', 'NRO_FACTURA=' || :OLD.nro_factura, NULL, :OLD.id_funcionario);
    END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_aud_alerta
AFTER INSERT OR UPDATE ON alerta
FOR EACH ROW
BEGIN
    IF INSERTING THEN
        INSERT INTO historial (tabla_afectada, id_registro, operacion, columna, valor_anterior, valor_nuevo)
        VALUES ('ALERTA', :NEW.id_alerta, 'INSERT', 'ESTADO', NULL, :NEW.estado);
    ELSIF UPDATING AND NVL(:OLD.estado, '-') <> NVL(:NEW.estado, '-') THEN
        INSERT INTO historial (tabla_afectada, id_registro, operacion, columna, valor_anterior, valor_nuevo, id_funcionario)
        VALUES ('ALERTA', :NEW.id_alerta, 'UPDATE', 'ESTADO', :OLD.estado, :NEW.estado, :NEW.id_funcionario_revisor);
    END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_aud_vehiculo
AFTER UPDATE ON vehiculo
FOR EACH ROW
BEGIN
    IF NVL(:OLD.estado, '-') <> NVL(:NEW.estado, '-') THEN
        INSERT INTO historial (tabla_afectada, id_registro, operacion, columna, valor_anterior, valor_nuevo)
        VALUES ('VEHICULO', :NEW.id_vehiculo, 'UPDATE', 'ESTADO', :OLD.estado, :NEW.estado);
    END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_aud_persona
AFTER UPDATE ON persona
FOR EACH ROW
BEGIN
    IF NVL(:OLD.estado, '-') <> NVL(:NEW.estado, '-') THEN
        INSERT INTO historial (tabla_afectada, id_registro, operacion, columna, valor_anterior, valor_nuevo)
        VALUES ('PERSONA', :NEW.id_persona, 'UPDATE', 'ESTADO', :OLD.estado, :NEW.estado);
    END IF;
END;
/

-- ----------------------------------------------------------------------------
-- 3. TRIGGER DE DETECCIÓN AUTOMÁTICA DE ANOMALÍAS (REGLA_DETECCION -> ALERTA)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_carga_evaluar_alertas
AFTER INSERT ON carga
FOR EACH ROW
WHEN (NEW.estado = 'VALIDA')
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
    v_id_tipo_vehiculo vehiculo.id_tipo_vehiculo%TYPE;
    v_capacidad_tanque vehiculo.capacidad_tanque%TYPE;
    v_placa            vehiculo.placa%TYPE;
    v_valor_medido     NUMBER(12,2);
    v_umbral_efectivo  NUMBER(12,2);
    v_existe           NUMBER;
BEGIN
    SELECT id_tipo_vehiculo, capacidad_tanque, placa
      INTO v_id_tipo_vehiculo, v_capacidad_tanque, v_placa
      FROM vehiculo
     WHERE id_vehiculo = :NEW.id_vehiculo;

    FOR r IN (
        SELECT id_regla, codigo, nombre, ambito, parametro, valor_umbral, ventana_horas, margen_error_pct
          FROM regla_deteccion
         WHERE activa = 'S'
           AND fecha_inicio <= TRUNC(:NEW.fecha_hora)
           AND (fecha_fin IS NULL OR fecha_fin >= TRUNC(:NEW.fecha_hora))
           AND (id_tipo_vehiculo IS NULL OR id_tipo_vehiculo = v_id_tipo_vehiculo)
         ORDER BY prioridad ASC
    ) LOOP
        v_valor_medido := NULL;

        IF r.parametro = 'VOLUMEN_VENTANA' THEN
            IF r.ambito = 'VEHICULO' THEN
                SELECT NVL(SUM(cantidad_litros), 0) + :NEW.cantidad_litros
                  INTO v_valor_medido
                  FROM carga
                 WHERE id_vehiculo = :NEW.id_vehiculo
                   AND id_carga <> :NEW.id_carga
                   AND estado = 'VALIDA'
                   AND fecha_hora >= (:NEW.fecha_hora - NUMTODSINTERVAL(r.ventana_horas, 'HOUR'))
                   AND fecha_hora <= :NEW.fecha_hora;
            ELSE
                SELECT NVL(SUM(cantidad_litros), 0) + :NEW.cantidad_litros
                  INTO v_valor_medido
                  FROM carga
                 WHERE id_persona = :NEW.id_persona
                   AND id_carga <> :NEW.id_carga
                   AND estado = 'VALIDA'
                   AND fecha_hora >= (:NEW.fecha_hora - NUMTODSINTERVAL(r.ventana_horas, 'HOUR'))
                   AND fecha_hora <= :NEW.fecha_hora;
            END IF;

        ELSIF r.parametro = 'FRECUENCIA_VENTANA' THEN
            IF r.ambito = 'VEHICULO' THEN
                SELECT COUNT(*) + 1
                  INTO v_valor_medido
                  FROM carga
                 WHERE id_vehiculo = :NEW.id_vehiculo
                   AND id_carga <> :NEW.id_carga
                   AND estado = 'VALIDA'
                   AND fecha_hora >= (:NEW.fecha_hora - NUMTODSINTERVAL(r.ventana_horas, 'HOUR'))
                   AND fecha_hora <= :NEW.fecha_hora;
            ELSE
                SELECT COUNT(*) + 1
                  INTO v_valor_medido
                  FROM carga
                 WHERE id_persona = :NEW.id_persona
                   AND id_carga <> :NEW.id_carga
                   AND estado = 'VALIDA'
                   AND fecha_hora >= (:NEW.fecha_hora - NUMTODSINTERVAL(r.ventana_horas, 'HOUR'))
                   AND fecha_hora <= :NEW.fecha_hora;
            END IF;

        ELSIF r.parametro = 'EXCESO_TANQUE_PCT' THEN
            v_valor_medido := ROUND((:NEW.cantidad_litros / v_capacidad_tanque) * 100, 2);
        END IF;

        IF v_valor_medido IS NOT NULL THEN
            v_umbral_efectivo := r.valor_umbral * (1 + (NVL(r.margen_error_pct, 0) / 100));

            IF v_valor_medido > v_umbral_efectivo THEN
                SELECT COUNT(*) INTO v_existe
                  FROM alerta
                 WHERE id_carga = :NEW.id_carga
                   AND id_regla = r.id_regla;

                IF v_existe = 0 THEN
                    INSERT INTO alerta (
                        id_carga, id_regla, fecha_hora, valor_detectado, valor_umbral, detalle, estado
                    ) VALUES (
                        :NEW.id_carga,
                        r.id_regla,
                        :NEW.fecha_hora,
                        v_valor_medido,
                        r.valor_umbral,
                        'Regla ' || r.codigo || ' (' || r.nombre || ') excedida para placa ' || v_placa ||
                        ': detectado=' || TO_CHAR(v_valor_medido) || ', umbral=' || TO_CHAR(r.valor_umbral),
                        'PENDIENTE'
                    );
                END IF;
            END IF;
        END IF;
    END LOOP;

    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

-- ----------------------------------------------------------------------------
-- 4. PROCEDIMIENTOS ALMACENADOS DE OPERACIÓN
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_carga (
    p_id_vehiculo         IN  NUMBER,
    p_id_persona          IN  NUMBER,
    p_id_surtidor         IN  NUMBER,
    p_id_funcionario      IN  NUMBER,
    p_cantidad_litros     IN  NUMBER,
    p_metodo_verificacion IN  VARCHAR2,
    p_nro_factura         IN  VARCHAR2,
    p_segmento            IN  VARCHAR2 DEFAULT 'GENERAL',
    p_id_carga_out        OUT NUMBER
) IS
    v_estado_veh   vehiculo.estado%TYPE;
    v_estado_per   persona.estado%TYPE;
    v_estado_sur   surtidor.estado%TYPE;
    v_estado_est   estacion.estado%TYPE;
    v_id_comb      surtidor.id_combustible%TYPE;
    v_id_subv      subvencion_combustible.id_subvencion%TYPE;
BEGIN
    SELECT estado INTO v_estado_veh FROM vehiculo WHERE id_vehiculo = p_id_vehiculo;
    IF v_estado_veh <> 'ACTIVO' THEN
        RAISE_APPLICATION_ERROR(-20010, 'El vehiculo no se encuentra ACTIVO (estado: ' || v_estado_veh || ').');
    END IF;

    SELECT estado INTO v_estado_per FROM persona WHERE id_persona = p_id_persona;
    IF v_estado_per <> 'ACTIVO' THEN
        RAISE_APPLICATION_ERROR(-20011, 'La persona no se encuentra ACTIVA (estado: ' || v_estado_per || ').');
    END IF;

    SELECT s.estado, e.estado, s.id_combustible
      INTO v_estado_sur, v_estado_est, v_id_comb
      FROM surtidor s
      JOIN estacion e ON e.id_estacion = s.id_estacion
     WHERE s.id_surtidor = p_id_surtidor;

    IF v_estado_sur <> 'OPERATIVO' OR v_estado_est <> 'ACTIVA' THEN
        RAISE_APPLICATION_ERROR(-20012, 'El surtidor o la estacion no estan operativos.');
    END IF;

    v_id_subv := fn_obtener_subvencion_vigente(v_id_comb, p_segmento, SYSDATE);

    INSERT INTO carga (
        id_vehiculo, id_persona, id_surtidor, id_subvencion, id_funcionario,
        fecha_hora, cantidad_litros, metodo_verificacion, nro_factura, estado
    ) VALUES (
        p_id_vehiculo, p_id_persona, p_id_surtidor, v_id_subv, p_id_funcionario,
        SYSTIMESTAMP, p_cantidad_litros, UPPER(p_metodo_verificacion), p_nro_factura, 'VALIDA'
    )
    RETURNING id_carga INTO p_id_carga_out;
END sp_registrar_carga;
/

CREATE OR REPLACE PROCEDURE sp_gestionar_alerta (
    p_id_alerta     IN NUMBER,
    p_nuevo_estado  IN VARCHAR2,
    p_id_revisor    IN NUMBER,
    p_observacion   IN VARCHAR2
) IS
    v_estado VARCHAR2(15) := UPPER(TRIM(p_nuevo_estado));
BEGIN
    IF v_estado IN ('ATENDIDA', 'DESCARTADA') AND (p_id_revisor IS NULL OR TRIM(p_observacion) IS NULL) THEN
        RAISE_APPLICATION_ERROR(-20020, 'Para cerrar o descartar una alerta debe indicar revisor y observacion.');
    END IF;

    UPDATE alerta
       SET estado                 = v_estado,
           id_funcionario_revisor = p_id_revisor,
           fecha_revision         = SYSTIMESTAMP,
           observacion            = p_observacion
     WHERE id_alerta = p_id_alerta;

    IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20021, 'No existe la alerta indicada.');
    END IF;
END sp_gestionar_alerta;
/

-- ----------------------------------------------------------------------------
-- 5. PERMISOS DE EJECUCIÓN PARA LA APLICACIÓN
-- ----------------------------------------------------------------------------
GRANT EXECUTE ON fn_obtener_subvencion_vigente TO ROL_SICAC_APP;
GRANT EXECUTE ON sp_registrar_carga TO ROL_SICAC_APP;
GRANT EXECUTE ON sp_gestionar_alerta TO ROL_SICAC_APP;
