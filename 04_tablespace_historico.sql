/* =====================================================================
   TurismoUQ · Proyecto integrador Bases de Datos II · 2026-2
   Script 04 · Tablespace propio para el histórico de reservas (Entrega 2)
   ---------------------------------------------------------------------
   EJECUTAR CONECTADO COMO SYSTEM A XEPDB1 (no como TURISMOUQ):
   crear tablespaces y otorgar cuotas son privilegios de administrador.

   Qué hace
     1. Borra el tablespace TS_TURISMOUQ_HIST si ya existía (base limpia).
     2. Lo crea con un datafile propio, ubicado en la MISMA carpeta en que
        Oracle guarda el datafile del tablespace USERS de esta PDB (así el
        script funciona en Windows y en Linux sin escribir rutas a mano).
     3. Da cuota al usuario TURISMOUQ sobre él.
     4. Otorga CREATE JOB, necesario para programar el refresco de la
        vista materializada y la liquidación mensual (script 07).

   ¿Por qué un tablespace separado para el histórico?
     · Ciclo de vida distinto: las reservas cerradas (completadas o
       canceladas de años anteriores) ya no cambian. Separadas, el
       tablespace puede ponerse READ ONLY al cerrar cada año y respaldarse
       una sola vez, en lugar de copiarlo en cada backup diario.
     · Crecimiento controlado: el histórico crece todos los años y sin
       límite; con su propio datafile (AUTOEXTEND con MAXSIZE) ese
       crecimiento no consume el espacio de las tablas operativas (USERS)
       ni puede llenarlo.
     · Rendimiento de E/S: las consultas analíticas pesadas sobre años
       viejos leen otro archivo, que en un servidor real puede ir en un
       disco más barato y lento sin afectar las reservas en línea.
     · Administración: se puede mover, desconectar (OFFLINE) o restaurar
       el histórico sin tocar la operación diaria.
   ===================================================================== */

SET SERVEROUTPUT ON

-- 1. Base limpia: eliminar el tablespace si existía
BEGIN
   EXECUTE IMMEDIATE 'DROP TABLESPACE ts_turismouq_hist INCLUDING CONTENTS AND DATAFILES CASCADE CONSTRAINTS';
   DBMS_OUTPUT.PUT_LINE('Tablespace TS_TURISMOUQ_HIST anterior eliminado.');
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE = -959 THEN      -- ORA-00959: el tablespace no existe
         DBMS_OUTPUT.PUT_LINE('TS_TURISMOUQ_HIST no existía; se crea nuevo.');
      ELSE
         RAISE;
      END IF;
END;
/

-- 2. Crear el tablespace junto al datafile de USERS
DECLARE
   v_archivo  dba_data_files.file_name%TYPE;
   v_carpeta  VARCHAR2(600);
   v_sep      PLS_INTEGER;
   v_ruta     VARCHAR2(700);
BEGIN
   SELECT file_name INTO v_archivo
   FROM   dba_data_files
   WHERE  tablespace_name = 'USERS'
   AND    ROWNUM = 1;

   -- carpeta = todo lo que va antes del último separador (\ en Windows, / en Linux)
   v_sep     := GREATEST(INSTR(v_archivo, '\', -1), INSTR(v_archivo, '/', -1));
   v_carpeta := SUBSTR(v_archivo, 1, v_sep);
   v_ruta    := v_carpeta || 'TS_TURISMOUQ_HIST01.DBF';

   EXECUTE IMMEDIATE
      'CREATE TABLESPACE ts_turismouq_hist '
   || 'DATAFILE ''' || v_ruta || ''' SIZE 50M '
   || 'AUTOEXTEND ON NEXT 10M MAXSIZE 1G '
   || 'EXTENT MANAGEMENT LOCAL AUTOALLOCATE '
   || 'SEGMENT SPACE MANAGEMENT AUTO';

   DBMS_OUTPUT.PUT_LINE('Tablespace creado. Datafile: ' || v_ruta);
END;
/

-- 3. Cuota del dueño del esquema sobre el nuevo tablespace
ALTER USER turismouq QUOTA UNLIMITED ON ts_turismouq_hist;

-- 4. Privilegio para crear jobs de DBMS_SCHEDULER (script 07)
GRANT CREATE JOB TO turismouq;

-- 5. Evidencia
SELECT t.tablespace_name, t.status, t.contents, t.extent_management,
       d.file_name, ROUND(d.bytes / 1024 / 1024) AS mb, d.autoextensible,
       ROUND(d.maxbytes / 1024 / 1024) AS max_mb
FROM   dba_tablespaces t
JOIN   dba_data_files d ON d.tablespace_name = t.tablespace_name
WHERE  t.tablespace_name = 'TS_TURISMOUQ_HIST';

SELECT username, tablespace_name,
       CASE max_bytes WHEN -1 THEN 'ILIMITADA' ELSE TO_CHAR(max_bytes) END AS cuota
FROM   dba_ts_quotas
WHERE  username = 'TURISMOUQ';

PROMPT Tablespace listo. Conéctese como TURISMOUQ y ejecute 05_paquete_turismouq.sql
