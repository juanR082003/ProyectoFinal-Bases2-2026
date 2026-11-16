/* =====================================================================
   TurismoUQ · Proyecto integrador Bases de Datos II · 2026-2
   Script 12 · Seguridad I: perfil, roles y usuarios (Entrega 3)
   ---------------------------------------------------------------------
   EJECUTAR CONECTADO COMO SYSTEM A XEPDB1 (no como TURISMOUQ): crear
   perfiles, roles y usuarios son privilegios de administrador.
       sqlplus system/<clave>@localhost:1521/XEPDB1 @12_seguridad_roles_usuarios.sql
   Después, como TURISMOUQ, ejecutar 13 (vistas y privilegios de objeto).
   Si este script se repite, hay que repetir también el 13: al borrar un
   rol se pierden los privilegios que TURISMOUQ le había otorgado.

   Qué hace
     1. Limpieza (usuarios, roles y perfil de una ejecución anterior).
     2. Perfil PERFIL_TURISMOUQ con límites de sesión y de contraseña.
     3. Los cuatro roles que pide el enunciado.
     4. Usuarios de base de datos de ejemplo, uno o dos por rol.
     5. Evidencia desde el diccionario.

   Roles
     ROL_RECEPCION          Atiende el mostrador de UN alojamiento. Solo
                            entra por vistas y por el paquete PKG_RECEPCION;
                            no recibe ningún privilegio sobre tablas.
     ROL_ADMIN_ALOJAMIENTO  Encargado de UN alojamiento. Hereda ROL_RECEPCION
                            y además mantiene sus habitaciones, servicios y
                            tarifas.
     ROL_GERENTE            Gerencia de la plataforma. Solo lectura de la
                            operación y de los indicadores de todos los
                            alojamientos; sin datos de contacto de clientes.
     ROL_AUDITOR            Solo lectura de la auditoría de tarifas, pagos,
                            reservas y usuarios; no puede modificar nada.

   Relación con el modelo: cada usuario de base de datos corresponde a una
   fila de USUARIO_SISTEMA (Entrega 1). El usuario de BD RECEP_HOTEL1 es el
   username 'recep.hotel1' (se cambia el punto por guion bajo porque un
   nombre de usuario de Oracle no admite puntos sin comillas). De esa fila
   sale el alojamiento al que cada vista limita lo que el usuario ve.

   Las contraseñas están aquí porque es un entorno académico local; en
   producción se entregarían por otro medio y con cambio obligatorio
   (PASSWORD EXPIRE).
   ===================================================================== */

SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 100
COLUMN profile        FORMAT A18
COLUMN resource_name  FORMAT A28
COLUMN limit          FORMAT A14
COLUMN username       FORMAT A18
COLUMN account_status FORMAT A16
COLUMN granted_role   FORMAT A24
COLUMN grantee        FORMAT A24
COLUMN privilege      FORMAT A20
COLUMN role           FORMAT A24

/* ---------------------------------------------------------------------
   1. Limpieza
   --------------------------------------------------------------------- */
DECLARE
   PROCEDURE quitar (p_sql VARCHAR2, p_codigo NUMBER) IS
   BEGIN
      EXECUTE IMMEDIATE p_sql;
      DBMS_OUTPUT.PUT_LINE('Hecho: ' || p_sql);
   EXCEPTION
      WHEN OTHERS THEN IF SQLCODE <> p_codigo THEN RAISE; END IF;
   END;
BEGIN
   -- ORA-01918: el usuario no existe
   quitar('DROP USER recep_hotel1 CASCADE',    -1918);
   quitar('DROP USER recep_salento CASCADE',   -1918);
   quitar('DROP USER enc_hotel CASCADE',       -1918);
   quitar('DROP USER gerente_general CASCADE', -1918);
   quitar('DROP USER auditor_interno CASCADE', -1918);
   -- ORA-01919: el rol no existe
   quitar('DROP ROLE rol_admin_alojamiento',   -1919);
   quitar('DROP ROLE rol_recepcion',           -1919);
   quitar('DROP ROLE rol_gerente',             -1919);
   quitar('DROP ROLE rol_auditor',             -1919);
   -- ORA-02380: el perfil no existe
   quitar('DROP PROFILE perfil_turismouq CASCADE', -2380);
END;
/

/* ---------------------------------------------------------------------
   2. Perfil con límites de sesión
   Los límites de recursos (SESSIONS_PER_USER, IDLE_TIME, CONNECT_TIME)
   solo se aplican si el parámetro RESOURCE_LIMIT está en TRUE. Los de
   contraseña se aplican siempre.
   --------------------------------------------------------------------- */
ALTER SYSTEM SET resource_limit = TRUE;

-- SESSIONS_PER_USER      máximo 2 sesiones simultáneas por usuario
-- IDLE_TIME              minutos sin actividad antes de cerrar la sesión
-- CONNECT_TIME           una sesión dura como máximo un turno de 8 horas (480 min)
-- FAILED_LOGIN_ATTEMPTS  al tercer intento fallido la cuenta se bloquea...
-- PASSWORD_LOCK_TIME     ...durante 15 minutos (1/96 de día)
-- PASSWORD_LIFE_TIME     la contraseña vence cada 90 días
-- PASSWORD_GRACE_TIME    con 7 días de gracia para cambiarla
-- (sin comentarios dentro de la sentencia: SQL Developer los rompe en CREATE PROFILE)
CREATE PROFILE perfil_turismouq LIMIT
   SESSIONS_PER_USER      2
   IDLE_TIME              15
   CONNECT_TIME           480
   FAILED_LOGIN_ATTEMPTS  3
   PASSWORD_LOCK_TIME     1/96
   PASSWORD_LIFE_TIME     90
   PASSWORD_GRACE_TIME    7;

/* ---------------------------------------------------------------------
   3. Roles
   --------------------------------------------------------------------- */
CREATE ROLE rol_recepcion;
CREATE ROLE rol_admin_alojamiento;
CREATE ROLE rol_gerente;
CREATE ROLE rol_auditor;

-- Único privilegio de sistema: poder conectarse. Ningún rol puede crear objetos.
GRANT CREATE SESSION TO rol_recepcion;
GRANT CREATE SESSION TO rol_admin_alojamiento;
GRANT CREATE SESSION TO rol_gerente;
GRANT CREATE SESSION TO rol_auditor;

-- Jerarquía: el encargado puede hacer todo lo de recepción y algo más
GRANT rol_recepcion TO rol_admin_alojamiento;

/* ---------------------------------------------------------------------
   4. Usuarios (todos con el perfil; sin cuota: no son dueños de nada)
   --------------------------------------------------------------------- */
CREATE USER recep_hotel1    IDENTIFIED BY "Recepcion_2026" PROFILE perfil_turismouq
   DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;
CREATE USER recep_salento   IDENTIFIED BY "Recepcion_2026" PROFILE perfil_turismouq
   DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;
CREATE USER enc_hotel       IDENTIFIED BY "Encargado_2026" PROFILE perfil_turismouq
   DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;
CREATE USER gerente_general IDENTIFIED BY "Gerencia_2026"  PROFILE perfil_turismouq
   DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;
CREATE USER auditor_interno IDENTIFIED BY "Auditoria_2026" PROFILE perfil_turismouq
   DEFAULT TABLESPACE users TEMPORARY TABLESPACE temp;

-- recep_hotel1 y enc_hotel: Hotel Mirador del Parque Sucre · recep_salento: Hostal Calle Real de Salento
GRANT rol_recepcion         TO recep_hotel1;
GRANT rol_recepcion         TO recep_salento;
GRANT rol_admin_alojamiento TO enc_hotel;
GRANT rol_gerente           TO gerente_general;
GRANT rol_auditor           TO auditor_interno;

/* ---------------------------------------------------------------------
   5. Evidencia
   --------------------------------------------------------------------- */
PROMPT Parámetro que activa los límites de recursos
SELECT name, value FROM v$parameter WHERE name = 'resource_limit';

PROMPT Límites del perfil
SELECT profile, resource_name, resource_type, limit
FROM   dba_profiles
WHERE  profile = 'PERFIL_TURISMOUQ'
AND    limit NOT IN ('DEFAULT')
ORDER  BY resource_type, resource_name;

PROMPT Usuarios y su perfil
SELECT username, account_status, profile, default_tablespace
FROM   dba_users
WHERE  username IN ('RECEP_HOTEL1', 'RECEP_SALENTO', 'ENC_HOTEL', 'GERENTE_GENERAL', 'AUDITOR_INTERNO')
ORDER  BY username;

PROMPT Quién tiene cada rol (incluye la jerarquía recepción -> encargado)
SELECT grantee, granted_role
FROM   dba_role_privs
WHERE  granted_role LIKE 'ROL\_%' ESCAPE '\'
AND    grantee <> 'SYSTEM'
ORDER  BY granted_role, grantee;

PROMPT Privilegios de sistema de los roles (solo CREATE SESSION)
SELECT grantee, privilege
FROM   dba_sys_privs
WHERE  grantee LIKE 'ROL\_%' ESCAPE '\'
ORDER  BY grantee;

PROMPT Roles y usuarios listos. Conéctese como TURISMOUQ y ejecute 13_seguridad_vistas_privilegios.sql
