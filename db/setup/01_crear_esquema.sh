#!/bin/bash
# =============================================================================
# SICAC - Preparacion inicial de la base (FREEPDB1)
#
# La imagen oficial ejecuta los scripts de /opt/oracle/scripts/setup UNA sola
# vez, justo despues de crear la base (cuando el volumen esta vacio).
# El script es idempotente: se puede volver a lanzar a mano sin romper nada:
#   docker exec sicac-oracle bash /opt/oracle/scripts/setup/01_crear_esquema.sh
#
# Crea:
#   - Tablespace SICAC_DATA (dentro del volumen persistente, tope de 4 GB)
#   - SICAC      : duena del esquema (tablas, vistas, PL/SQL)
#   - SICAC_APP  : cuenta de conexion de la aplicacion (solo CREATE SESSION;
#                  los permisos sobre objetos se dan despues mediante roles)
#   - Directorio SICAC_BACKUP para los respaldos con Data Pump
#
# OJO: la imagen carga este archivo con "source"; por eso NO usa "exit" ni
# "set -e" (cortarian el arranque del contenedor).
# =============================================================================

if [ -z "${SICAC_OWNER_PWD:-}" ] || [ -z "${SICAC_APP_PWD:-}" ]; then
  echo "[SICAC] ERROR: faltan SICAC_OWNER_PWD o SICAC_APP_PWD. No se creo el esquema."
else
  echo "[SICAC] Preparando tablespace, usuarios y directorio de respaldo..."
  mkdir -p /opt/oracle/oradata/backup

  sqlplus -s / as sysdba <<EOF
WHENEVER SQLERROR EXIT FAILURE
SET DEFINE OFF
SET SERVEROUTPUT ON
SET FEEDBACK OFF

ALTER SESSION SET CONTAINER = FREEPDB1;

DECLARE
  v_n   NUMBER;
  v_dir VARCHAR2(512);
BEGIN
  -- 1) Tablespace propio. El datafile va en la misma carpeta que los demas
  --    datafiles de la PDB, es decir, dentro del volumen persistente.
  SELECT COUNT(*) INTO v_n FROM dba_tablespaces WHERE tablespace_name = 'SICAC_DATA';
  IF v_n = 0 THEN
    SELECT SUBSTR(file_name, 1, INSTR(file_name, '/', -1))
      INTO v_dir
      FROM dba_data_files
     WHERE tablespace_name = 'SYSTEM' AND ROWNUM = 1;
    EXECUTE IMMEDIATE 'CREATE TABLESPACE sicac_data DATAFILE ''' || v_dir ||
      'sicac_data01.dbf'' SIZE 256M AUTOEXTEND ON NEXT 64M MAXSIZE 4G';
    DBMS_OUTPUT.PUT_LINE('[SICAC] Tablespace SICAC_DATA creado en ' || v_dir);
  END IF;

  -- 2) Duena del esquema: solo los privilegios que necesita para crear objetos.
  SELECT COUNT(*) INTO v_n FROM dba_users WHERE username = 'SICAC';
  IF v_n = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER sicac IDENTIFIED BY "${SICAC_OWNER_PWD}" ' ||
      'DEFAULT TABLESPACE sicac_data QUOTA UNLIMITED ON sicac_data';
    DBMS_OUTPUT.PUT_LINE('[SICAC] Usuario SICAC creado');
  END IF;
  EXECUTE IMMEDIATE 'GRANT CREATE SESSION, CREATE TABLE, CREATE VIEW, ' ||
    'CREATE MATERIALIZED VIEW, CREATE SEQUENCE, CREATE PROCEDURE, ' ||
    'CREATE TRIGGER TO sicac';

  -- 3) Cuenta de la aplicacion: por ahora solo puede conectarse.
  SELECT COUNT(*) INTO v_n FROM dba_users WHERE username = 'SICAC_APP';
  IF v_n = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER sicac_app IDENTIFIED BY "${SICAC_APP_PWD}"';
    DBMS_OUTPUT.PUT_LINE('[SICAC] Usuario SICAC_APP creado');
  END IF;
  EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO sicac_app';
  -- 3b) Roles de seguridad usados en 04_vistas_permisos.sql
  SELECT COUNT(*) INTO v_n FROM dba_roles WHERE role = 'ROL_SICAC_APP';
  IF v_n = 0 THEN
    EXECUTE IMMEDIATE 'CREATE ROLE rol_sicac_app';
    DBMS_OUTPUT.PUT_LINE('[SICAC] Rol ROL_SICAC_APP creado');
  END IF;
  EXECUTE IMMEDIATE 'GRANT rol_sicac_app TO sicac_app';

  SELECT COUNT(*) INTO v_n FROM dba_roles WHERE role = 'ROL_SICAC_AUDITOR';
  IF v_n = 0 THEN
    EXECUTE IMMEDIATE 'CREATE ROLE rol_sicac_auditor';
    DBMS_OUTPUT.PUT_LINE('[SICAC] Rol ROL_SICAC_AUDITOR creado');
  END IF;
END;
/

-- 4) Directorio para Data Pump (lo usan scripts/backup.sh y scripts/restore.sh)
CREATE OR REPLACE DIRECTORY sicac_backup AS '/opt/oracle/oradata/backup';
GRANT READ, WRITE ON DIRECTORY sicac_backup TO system;

SET FEEDBACK ON
COLUMN username FORMAT A12
COLUMN account_status FORMAT A16
COLUMN default_tablespace FORMAT A20
SELECT username, account_status, default_tablespace
  FROM dba_users
 WHERE username IN ('SICAC', 'SICAC_APP')
 ORDER BY username;
EOF

  if [ $? -eq 0 ]; then
    echo "[SICAC] Preparacion inicial completada."
  else
    echo "[SICAC] ERROR en la preparacion inicial: revisar los mensajes ORA- de arriba."
  fi
fi
