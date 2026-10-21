/* =====================================================================
   TurismoUQ · Proyecto integrador Bases de Datos II · 2026-2
   Script 00 · Creación del esquema propietario (ejecutar UNA sola vez)
   ---------------------------------------------------------------------
   Ejecutar conectado como SYSTEM (o SYS AS SYSDBA) a la PDB XEPDB1:
       sqlplus system/<clave>@localhost:1521/XEPDB1 @00_crear_usuario.sql
   Crea el usuario TURISMOUQ, dueño de todas las tablas del proyecto,
   y le otorga solo los privilegios de sistema que necesita.
   Si el usuario ya existe, el bloque inicial lo elimina para partir
   de una base limpia.
   ===================================================================== */

SET SERVEROUTPUT ON

-- 1. Eliminar el usuario si ya existía (base limpia)
BEGIN
   EXECUTE IMMEDIATE 'DROP USER turismouq CASCADE';
   DBMS_OUTPUT.PUT_LINE('Usuario TURISMOUQ anterior eliminado.');
EXCEPTION
   WHEN OTHERS THEN
      IF SQLCODE = -1918 THEN   -- ORA-01918: el usuario no existe
         DBMS_OUTPUT.PUT_LINE('El usuario TURISMOUQ no existía; se crea nuevo.');
      ELSE
         RAISE;
      END IF;
END;
/

-- 2. Crear el usuario con cuota en el tablespace USERS
CREATE USER turismouq IDENTIFIED BY "TurismoUQ2026"
   DEFAULT TABLESPACE users
   TEMPORARY TABLESPACE temp
   QUOTA UNLIMITED ON users;

-- 3. Privilegios de sistema necesarios para las tres entregas
GRANT CREATE SESSION            TO turismouq;
GRANT CREATE TABLE              TO turismouq;
GRANT CREATE VIEW               TO turismouq;
GRANT CREATE SEQUENCE           TO turismouq;
GRANT CREATE PROCEDURE          TO turismouq;
GRANT CREATE TRIGGER            TO turismouq;
GRANT CREATE MATERIALIZED VIEW  TO turismouq;
GRANT CREATE SYNONYM            TO turismouq;
GRANT CREATE TYPE               TO turismouq;

PROMPT Usuario TURISMOUQ creado. Conéctese como turismouq/TurismoUQ2026@localhost:1521/XEPDB1 y ejecute 01_ddl_turismouq.sql
