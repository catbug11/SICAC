-- ============================================================================
-- FASE 5: DATOS SINTÉTICOS MÍNIMOS (AVANCE 3)
-- 1.000 personas, 1.500 vehículos, 20 estaciones y 50.000 cargas
-- Ejecutar conectado a FREEPDB1 (como SYSDBA)
-- ============================================================================

ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = SICAC;

SET SERVEROUTPUT ON

DECLARE
    v_cnt NUMBER;
    v_id_mun NUMBER;
    v_id_gas NUMBER;
    v_id_die NUMBER;
    v_id_liv NUMBER;
    v_id_pes NUMBER;
    v_id_mot NUMBER;
    v_id_sub_gas NUMBER;
    v_id_sub_die NUMBER;
    v_id_ta_vol NUMBER;
    v_id_ta_fre NUMBER;
    v_id_ta_tan NUMBER;
    v_id_per NUMBER;
    v_id_veh NUMBER;
    v_id_est NUMBER;
    v_id_sur NUMBER;
    v_id_fun NUMBER;
    v_id_comb_sur NUMBER;
    v_id_sub_sur NUMBER;
    v_cant NUMBER;
    v_metodo VARCHAR2(15);
    v_fecha TIMESTAMP;
BEGIN
    -- 1. Municipios
    MERGE INTO municipio dst
    USING (
        SELECT 'Cochabamba' AS nombre, 'Cochabamba' AS departamento FROM dual UNION ALL
        SELECT 'Quillacollo', 'Cochabamba' FROM dual UNION ALL
        SELECT 'Sacaba', 'Cochabamba' FROM dual UNION ALL
        SELECT 'Colcapirhua', 'Cochabamba' FROM dual UNION ALL
        SELECT 'Santa Cruz de la Sierra', 'Santa Cruz' FROM dual UNION ALL
        SELECT 'La Paz', 'La Paz' FROM dual
    ) src
    ON (dst.nombre = src.nombre AND dst.departamento = src.departamento)
    WHEN NOT MATCHED THEN
        INSERT (nombre, departamento) VALUES (src.nombre, src.departamento);

    SELECT id_municipio INTO v_id_mun FROM municipio WHERE nombre = 'Cochabamba' AND ROWNUM = 1;

    -- 2. Combustibles
    MERGE INTO combustible dst
    USING (
        SELECT 'GAS_ESP' AS codigo, 'Gasolina Especial' AS nombre, 85 AS octanaje, 'LITROS' AS unidad_medida, 'Gasolina subvencionada especial' AS descripcion FROM dual UNION ALL
        SELECT 'DIESEL_OIL', 'Diesel Oil', NULL, 'LITROS', 'Diesel subvencionado para transporte' FROM dual
    ) src
    ON (dst.codigo = src.codigo)
    WHEN NOT MATCHED THEN
        INSERT (codigo, nombre, octanaje, unidad_medida, descripcion, estado)
        VALUES (src.codigo, src.nombre, src.octanaje, src.unidad_medida, src.descripcion, 'ACTIVO');

    SELECT id_combustible INTO v_id_gas FROM combustible WHERE codigo = 'GAS_ESP';
    SELECT id_combustible INTO v_id_die FROM combustible WHERE codigo = 'DIESEL_OIL';

    -- 3. Tipos de vehículo
    MERGE INTO tipo_vehiculo dst
    USING (
        SELECT 'LIVIANO' AS nombre, 25 AS consumo_prom_diario, 5 AS cargas_semana_normal, 60 AS volumen_max_diario, 'Automovil y vagoneta' AS descripcion FROM dual UNION ALL
        SELECT 'PESADO', 140, 6, 450, 'Camion y bus de alto tonelaje' FROM dual UNION ALL
        SELECT 'MOTOCICLETA', 6, 7, 15, 'Motocicleta de dos ruedas' FROM dual
    ) src
    ON (dst.nombre = src.nombre)
    WHEN NOT MATCHED THEN
        INSERT (nombre, consumo_prom_diario, cargas_semana_normal, volumen_max_diario, descripcion)
        VALUES (src.nombre, src.consumo_prom_diario, src.cargas_semana_normal, src.volumen_max_diario, src.descripcion);

    SELECT id_tipo_vehiculo INTO v_id_liv FROM tipo_vehiculo WHERE nombre = 'LIVIANO';
    SELECT id_tipo_vehiculo INTO v_id_pes FROM tipo_vehiculo WHERE nombre = 'PESADO';
    SELECT id_tipo_vehiculo INTO v_id_mot FROM tipo_vehiculo WHERE nombre = 'MOTOCICLETA';

    -- 4. Subvenciones vigentes
    SELECT COUNT(*) INTO v_cnt FROM subvencion_combustible WHERE id_combustible = v_id_gas AND segmento = 'GENERAL';
    IF v_cnt = 0 THEN
        INSERT INTO subvencion_combustible (id_combustible, fecha_inicio, segmento, precio_internacional, precio_venta, cupo_mensual_litros, decreto_referencia)
        VALUES (v_id_gas, DATE '2026-01-01', 'GENERAL', 7.80, 3.74, 1500, 'DS-SICAC-001');
    END IF;

    SELECT COUNT(*) INTO v_cnt FROM subvencion_combustible WHERE id_combustible = v_id_die AND segmento = 'GENERAL';
    IF v_cnt = 0 THEN
        INSERT INTO subvencion_combustible (id_combustible, fecha_inicio, segmento, precio_internacional, precio_venta, cupo_mensual_litros, decreto_referencia)
        VALUES (v_id_die, DATE '2026-01-01', 'GENERAL', 8.50, 3.72, 4000, 'DS-SICAC-002');
    END IF;

    SELECT id_subvencion INTO v_id_sub_gas FROM subvencion_combustible WHERE id_combustible = v_id_gas AND segmento = 'GENERAL' AND ROWNUM = 1;
    SELECT id_subvencion INTO v_id_sub_die FROM subvencion_combustible WHERE id_combustible = v_id_die AND segmento = 'GENERAL' AND ROWNUM = 1;

    -- 5. Tipos de alerta y reglas de detección
    MERGE INTO tipo_alerta dst
    USING (
        SELECT 'VOL_MAX' AS codigo, 'Exceso de Volumen en Ventana' AS nombre, 'Supera litros permitidos en el periodo' AS descripcion, 'ALTO' AS nivel_riesgo FROM dual UNION ALL
        SELECT 'FREC_MAX', 'Frecuencia Anormal de Cargas', 'Demasiadas cargas en ventana corta' AS descripcion, 'MEDIO' AS nivel_riesgo FROM dual UNION ALL
        SELECT 'TANQUE_EXC', 'Supera Capacidad de Tanque', 'Litros cargados exceden capacidad declarada' AS descripcion, 'CRITICO' AS nivel_riesgo FROM dual
    ) src
    ON (dst.codigo = src.codigo)
    WHEN NOT MATCHED THEN
        INSERT (codigo, nombre, descripcion, nivel_riesgo)
        VALUES (src.codigo, src.nombre, src.descripcion, src.nivel_riesgo);

    SELECT id_tipo_alerta INTO v_id_ta_vol FROM tipo_alerta WHERE codigo = 'VOL_MAX';
    SELECT id_tipo_alerta INTO v_id_ta_fre FROM tipo_alerta WHERE codigo = 'FREC_MAX';
    SELECT id_tipo_alerta INTO v_id_ta_tan FROM tipo_alerta WHERE codigo = 'TANQUE_EXC';

    MERGE INTO regla_deteccion dst
    USING (
        SELECT 'R-VOL-24H' AS codigo, 'Volumen diario excedido' AS nombre, 'Supera volumen maximo en 24h' AS descripcion, v_id_ta_vol AS id_tipo_alerta, 'VEHICULO' AS ambito, 'VOLUMEN_VENTANA' AS parametro, 120 AS valor_umbral, 24 AS ventana_horas, 1 AS prioridad FROM dual UNION ALL
        SELECT 'R-FRE-24H', 'Frecuencia diaria elevada', 'Mas de 4 cargas en 24h' AS descripcion, v_id_ta_fre AS id_tipo_alerta, 'VEHICULO' AS ambito, 'FRECUENCIA_VENTANA' AS parametro, 4 AS valor_umbral, 24 AS ventana_horas, 2 AS prioridad FROM dual UNION ALL
        SELECT 'R-TAN-100', 'Carga sobre capacidad de tanque', 'Supera el 100% de la capacidad del tanque' AS descripcion, v_id_ta_tan AS id_tipo_alerta, 'VEHICULO' AS ambito, 'EXCESO_TANQUE_PCT' AS parametro, 100 AS valor_umbral, 1 AS ventana_horas, 1 AS prioridad FROM dual
    ) src
    ON (dst.codigo = src.codigo)
    WHEN NOT MATCHED THEN
        INSERT (codigo, nombre, descripcion, id_tipo_alerta, ambito, parametro, valor_umbral, ventana_horas, prioridad, activa)
        VALUES (src.codigo, src.nombre, src.descripcion, src.id_tipo_alerta, src.ambito, src.parametro, src.valor_umbral, src.ventana_horas, src.prioridad, 'S');

    -- 6. 1.000 personas y huellas
    SELECT COUNT(*) INTO v_cnt FROM persona WHERE ci LIKE 'SEED-%';
    IF v_cnt < 1000 THEN
        FOR i IN (v_cnt + 1)..1000 LOOP
            INSERT INTO persona (
                ci, expedido, nombres, apellido_paterno, apellido_materno,
                fecha_nacimiento, telefono, email, direccion, id_municipio, estado
            ) VALUES (
                'SEED-' || LPAD(i, 5, '0'),
                'CB',
                'Usuario' || i,
                'ApellidoP' || MOD(i, 97),
                'ApellidoM' || MOD(i, 53),
                DATE '1970-01-01' + MOD(i * 137, 12000),
                '7' || LPAD(MOD(i * 7919, 9999999), 7, '0'),
                'usuario' || i || '@sicac.bo',
                'Av. Principal Nro ' || i,
                v_id_mun,
                'ACTIVO'
            ) RETURNING id_persona INTO v_id_per;

            INSERT INTO huella_digital (id_persona, dedo, plantilla_hash, algoritmo, calidad, estado)
            VALUES (v_id_per, 'INDICE_DER', RAWTOHEX(STANDARD_HASH('HUELLA-' || i, 'SHA256')), 'SHA-256', 85 + MOD(i, 15), 'ACTIVA');
        END LOOP;
    END IF;

    -- 7. 1.500 vehículos y propiedad vigente
    SELECT COUNT(*) INTO v_cnt FROM vehiculo WHERE placa LIKE 'SD%';
    IF v_cnt < 1500 THEN
        FOR j IN (v_cnt + 1)..1500 LOOP
            SELECT id_persona INTO v_id_per
              FROM (SELECT id_persona FROM persona WHERE ci LIKE 'SEED-%' ORDER BY DBMS_RANDOM.VALUE)
             WHERE ROWNUM = 1;

            INSERT INTO vehiculo (
                placa, codigo_rfid, nro_chasis, marca, modelo, anio, cilindrada, color,
                id_tipo_vehiculo, id_combustible, capacidad_tanque, uso, estado
            ) VALUES (
                'SD' || LPAD(j, 4, '0') || CHR(65 + MOD(j, 26)) || CHR(65 + MOD(j * 3, 26)),
                'RFID-' || LPAD(j, 6, '0'),
                'CHS-SICAC-' || LPAD(j, 7, '0'),
                CASE MOD(j, 4) WHEN 0 THEN 'Toyota' WHEN 1 THEN 'Nissan' WHEN 2 THEN 'Volvo' ELSE 'Honda' END,
                CASE MOD(j, 4) WHEN 0 THEN 'Corolla' WHEN 1 THEN 'Frontier' WHEN 2 THEN 'FH16' ELSE 'CG150' END,
                2005 + MOD(j, 21),
                CASE MOD(j, 3) WHEN 0 THEN 1800 WHEN 1 THEN 9500 ELSE 150 END,
                CASE MOD(j, 3) WHEN 0 THEN 'Blanco' WHEN 1 THEN 'Plata' ELSE 'Negro' END,
                CASE MOD(j, 3) WHEN 0 THEN v_id_liv WHEN 1 THEN v_id_pes ELSE v_id_mot END,
                CASE MOD(j, 3) WHEN 1 THEN v_id_die ELSE v_id_gas END,
                CASE MOD(j, 3) WHEN 0 THEN 55 WHEN 1 THEN 350 ELSE 14 END,
                CASE MOD(j, 3) WHEN 1 THEN 'COMERCIAL' ELSE 'PARTICULAR' END,
                'ACTIVO'
            ) RETURNING id_vehiculo INTO v_id_veh;

            INSERT INTO propiedad_vehiculo (id_persona, id_vehiculo, fecha_inicio, documento_respaldo)
            VALUES (v_id_per, v_id_veh, DATE '2025-01-01', 'RUAT-SEED-' || LPAD(j, 6, '0'));
        END LOOP;
    END IF;

    -- 8. 20 estaciones, surtidores, funcionarios y recepciones iniciales
    SELECT COUNT(*) INTO v_cnt FROM estacion WHERE codigo_anh LIKE 'ANH-SEED-%';
    IF v_cnt < 20 THEN
        FOR e_idx IN (v_cnt + 1)..20 LOOP
            INSERT INTO estacion (
                codigo_anh, nombre, razon_social, nit, direccion, id_municipio,
                latitud, longitud, telefono, estado
            ) VALUES (
                'ANH-SEED-' || LPAD(e_idx, 3, '0'),
                'Estacion de Servicio SICAC ' || e_idx,
                'Surtidor y Combustibles S.R.L. ' || e_idx,
                TO_CHAR(1000000000 + e_idx),
                'Zona Central Calle ' || e_idx,
                v_id_mun,
                -17.390000 + (e_idx * 0.002),
                -66.150000 + (e_idx * 0.002),
                '4' || LPAD(4000000 + e_idx, 7, '0'),
                'ACTIVA'
            ) RETURNING id_estacion INTO v_id_est;

            SELECT id_persona INTO v_id_per
              FROM (SELECT id_persona FROM persona WHERE ci LIKE 'SEED-%' ORDER BY DBMS_RANDOM.VALUE)
             WHERE ROWNUM = 1;

            INSERT INTO funcionario (
                id_persona, usuario, clave_hash, rol, institucion, cargo, id_estacion, estado
            ) VALUES (
                v_id_per,
                'op_seed_' || e_idx,
                RAWTOHEX(STANDARD_HASH('CLAVE-' || e_idx, 'SHA256')),
                'OPERADOR',
                'ANH',
                'Operador de Surtidor',
                v_id_est,
                'ACTIVO'
            );

            INSERT INTO surtidor (id_estacion, numero, lado, id_combustible, nro_serie, estado)
            VALUES (v_id_est, 1, 'A', v_id_gas, 'SER-GAS-' || e_idx || '-A', 'OPERATIVO');

            INSERT INTO surtidor (id_estacion, numero, lado, id_combustible, nro_serie, estado)
            VALUES (v_id_est, 2, 'A', v_id_die, 'SER-DIE-' || e_idx || '-A', 'OPERATIVO');

            INSERT INTO recepcion_combustible (id_estacion, id_combustible, cantidad_litros, nro_guia, placa_cisterna, tipo_registro)
            VALUES (v_id_est, v_id_gas, 500000, 'GUIA-SEED-G-' || LPAD(e_idx, 3, '0'), 'CIST-G' || LPAD(e_idx, 2, '0'), 'SALDO_INICIAL');

            INSERT INTO recepcion_combustible (id_estacion, id_combustible, cantidad_litros, nro_guia, placa_cisterna, tipo_registro)
            VALUES (v_id_est, v_id_die, 800000, 'GUIA-SEED-D-' || LPAD(e_idx, 3, '0'), 'CIST-D' || LPAD(e_idx, 2, '0'), 'SALDO_INICIAL');
        END LOOP;
    END IF;

    SELECT id_funcionario INTO v_id_fun FROM funcionario WHERE usuario LIKE 'op_seed_%' AND ROWNUM = 1;

    -- 9. 50.000 cargas sintéticas (incluyendo casos anómalos cada 250 registros)
    SELECT COUNT(*) INTO v_cnt FROM carga WHERE nro_factura LIKE 'FAC-SEED-%';
    IF v_cnt < 50000 THEN
        FOR c_idx IN (v_cnt + 1)..50000 LOOP
            SELECT id_vehiculo INTO v_id_veh
              FROM (SELECT id_vehiculo FROM vehiculo WHERE placa LIKE 'SD%' ORDER BY DBMS_RANDOM.VALUE)
             WHERE ROWNUM = 1;

            SELECT id_persona INTO v_id_per
              FROM (SELECT id_persona FROM persona WHERE ci LIKE 'SEED-%' ORDER BY DBMS_RANDOM.VALUE)
             WHERE ROWNUM = 1;

            SELECT s.id_surtidor, s.id_combustible
              INTO v_id_sur, v_id_comb_sur
              FROM (
                  SELECT s.id_surtidor, s.id_combustible
                    FROM surtidor s
                    JOIN estacion e ON e.id_estacion = s.id_estacion
                   WHERE e.codigo_anh LIKE 'ANH-SEED-%'
                   ORDER BY DBMS_RANDOM.VALUE
              ) s
             WHERE ROWNUM = 1;

            v_id_sub_sur := CASE WHEN v_id_comb_sur = v_id_die THEN v_id_sub_die ELSE v_id_sub_gas END;
            v_fecha := SYSTIMESTAMP - NUMTODSINTERVAL(MOD(c_idx * 7, 43200), 'MINUTE');
            v_metodo := CASE MOD(c_idx, 3) WHEN 0 THEN 'HUELLA' WHEN 1 THEN 'RFID' ELSE 'MANUAL' END;

            IF MOD(c_idx, 250) = 0 THEN
                v_cant := 600;
            ELSE
                v_cant := ROUND(10 + DBMS_RANDOM.VALUE(5, 45), 2);
            END IF;

            INSERT INTO carga (
                id_vehiculo, id_persona, id_surtidor, id_subvencion, id_funcionario,
                fecha_hora, cantidad_litros, metodo_verificacion, nro_factura, estado
            ) VALUES (
                v_id_veh, v_id_per, v_id_sur, v_id_sub_sur, v_id_fun,
                v_fecha, v_cant, v_metodo, 'FAC-SEED-' || LPAD(c_idx, 6, '0'), 'VALIDA'
            );

            IF MOD(c_idx, 5000) = 0 THEN
                COMMIT;
            END IF;
        END LOOP;
    END IF;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[SICAC] Carga sintetica completada.');
END;
/
