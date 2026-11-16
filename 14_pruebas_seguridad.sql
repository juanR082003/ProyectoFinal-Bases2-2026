/* =====================================================================
   TurismoUQ · Proyecto integrador Bases de Datos II · 2026-2
   Script 14 · Pruebas de seguridad: qué puede y qué no puede cada rol (Entrega 3)
   ---------------------------------------------------------------------
   Ejecutar con F5 después de 12 y 13, desde SQL*Plus, SQLcl o SQL Developer.
   El script se CONECTA por turnos como cada usuario (comando CONNECT), así
   que no importa con qué usuario se lance. Al terminar queda conectado
   como TURISMOUQ.

   Si la base no está en localhost:1521/FREEPDB1 (Oracle Free 23ai/26ai),
   cambie la línea DEFINE (en Oracle XE 21c el servicio es XEPDB1).
   (Este script usa variables de sustitución: no escribir el signo
   "ampersand" en comentarios ni en textos.)

   Cada prueba dice qué se esperaba:
        OK     el resultado fue el esperado (permitido o denegado)
        FALLA  el resultado no fue el esperado
   Códigos de rechazo esperados
        ORA-00942  el objeto "no existe" para quien no tiene ningún permiso
        ORA-01031  privilegios insuficientes (puede leer, pero no escribir);
                   en Oracle 23ai / 26ai el mismo caso sale como ORA-41900
                   ("missing UPDATE/DELETE privilege") y se acepta igual
        ORA-06550  PLS-00201: no puede ejecutar el paquete
        ORA-01402  violación de WITH CHECK OPTION en una vista
        ORA-20011  fuera de su ámbito (otro alojamiento)

   Datos de prueba: reserva con observaciones 'PRUEBA E3 SEG...' del 18 al
   20 de enero de 2027 en la ÚLTIMA habitación (capacidad >= 2) del Hotel
   Mirador del Parque Sucre; se borra al inicio para poder repetir.
   ===================================================================== */

DEFINE conexion = localhost:1521/FREEPDB1

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE ON
SET VERIFY OFF
SET SQLBLANKLINES ON
SET LINESIZE 200
SET PAGESIZE 100
COLUMN resource_name    FORMAT A28
COLUMN limit            FORMAT A14
COLUMN role             FORMAT A24
COLUMN nombre_comercial FORMAT A36
COLUMN municipio        FORMAT A14
COLUMN usuario_bd       FORMAT A18
COLUMN observaciones    FORMAT A40

VARIABLE v_hab_propia  NUMBER
VARIABLE v_hab_ajena   NUMBER
VARIABLE v_aloj_ajeno  NUMBER
VARIABLE v_temp        NUMBER
VARIABLE v_cli         NUMBER
VARIABLE v_res         NUMBER

PROMPT ================================================================
PROMPT  T14.0 Preparación (como TURISMOUQ)
PROMPT ================================================================
CONNECT turismouq/TurismoUQ2026@&conexion
SET SERVEROUTPUT ON SIZE UNLIMITED
BEGIN
   DELETE FROM pago               WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE observaciones LIKE 'PRUEBA E3 SEG%');
   DELETE FROM reserva_habitacion WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE observaciones LIKE 'PRUEBA E3 SEG%');
   DELETE FROM reserva            WHERE observaciones LIKE 'PRUEBA E3 SEG%';
   COMMIT;

   SELECT MAX(h.id_habitacion) INTO :v_hab_propia
   FROM   habitacion h JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
   WHERE  a.nombre_comercial = 'Hotel Mirador del Parque Sucre' AND h.capacidad_max >= 2;

   SELECT MIN(h.id_habitacion), MIN(h.id_alojamiento) INTO :v_hab_ajena, :v_aloj_ajeno
   FROM   habitacion h JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
   WHERE  a.nombre_comercial = 'Hotel Torre Cafetera' AND h.capacidad_max >= 2;

   SELECT id_temporada INTO :v_temp FROM calendario WHERE fecha = DATE '2027-01-18';
   SELECT MIN(id_cliente) INTO :v_cli FROM cliente;

   DBMS_OUTPUT.PUT_LINE('Habitación propia (Mirador del Parque Sucre): ' || :v_hab_propia
      || ' · habitación ajena (Torre Cafetera): ' || :v_hab_ajena
      || ' · alojamiento ajeno: ' || :v_aloj_ajeno || ' · temporada: ' || :v_temp);
END;
/

PROMPT ================================================================
PROMPT  T14.1 RECEP_HOTEL1 (ROL_RECEPCION): solo vistas y PKG_RECEPCION
PROMPT ================================================================
CONNECT recep_hotel1/Recepcion_2026@&conexion
SET SERVEROUTPUT ON SIZE UNLIMITED

PROMPT Roles activos y límites del perfil que ve el propio usuario
SELECT role FROM session_roles ORDER BY role;
SELECT resource_name, limit FROM user_resource_limits
WHERE  resource_name IN ('SESSIONS_PER_USER', 'IDLE_TIME', 'CONNECT_TIME');
SELECT resource_name, limit FROM user_password_limits
WHERE  resource_name IN ('FAILED_LOGIN_ATTEMPTS', 'PASSWORD_LOCK_TIME', 'PASSWORD_LIFE_TIME', 'PASSWORD_GRACE_TIME');

PROMPT La vista le muestra SU alojamiento
SELECT id_alojamiento, nombre_comercial, municipio FROM turismouq.v_rec_mi_alojamiento;

DECLARE
   -- p_esperado: 0 = debe permitirse; otro valor = código ORA con el que debe rechazarse
   PROCEDURE probar (p_desc VARCHAR2, p_sql VARCHAR2, p_esperado NUMBER) IS
      v_cod NUMBER := 0;
      v_msg VARCHAR2(120);
   BEGIN
      BEGIN
         EXECUTE IMMEDIATE p_sql;
      EXCEPTION
         WHEN OTHERS THEN
            v_cod := SQLCODE;
            v_msg := SUBSTR(REPLACE(SQLERRM, CHR(10), ' '), 1, 100);
      END;
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE(CASE WHEN v_cod = p_esperado OR (p_esperado = -1031 AND v_cod = -41900) THEN 'OK    ' ELSE 'FALLA ' END
         || RPAD(p_desc, 58)
         || CASE WHEN v_cod = 0 THEN 'permitido' ELSE 'denegado: ' || v_msg END);
   END;
BEGIN
   probar('Leer la vista V_REC_RESERVAS',            'SELECT COUNT(*) FROM turismouq.v_rec_reservas', 0);
   probar('Leer la vista V_REC_HABITACIONES',        'SELECT COUNT(*) FROM turismouq.v_rec_habitaciones', 0);
   probar('Leer la vista V_REC_CLIENTES',            'SELECT COUNT(*) FROM turismouq.v_rec_clientes', 0);
   probar('Leer la TABLA RESERVA',                   'SELECT COUNT(*) FROM turismouq.reserva', -942);
   probar('Leer la TABLA CLIENTE',                   'SELECT COUNT(*) FROM turismouq.cliente', -942);
   probar('Leer la TABLA PAGO',                      'SELECT COUNT(*) FROM turismouq.pago', -942);
   probar('Insertar directo en la TABLA RESERVA',
          'INSERT INTO turismouq.reserva (id_cliente, id_alojamiento, fecha_checkin, fecha_checkout) '
          || 'VALUES (1, 1, DATE ''2027-01-18'', DATE ''2027-01-19'')', -942);
   probar('Cambiar una tarifa en la TABLA TARIFA',   'UPDATE turismouq.tarifa SET valor_noche = 1', -942);
   probar('Leer la vista del encargado V_ADM_TARIFAS', 'SELECT COUNT(*) FROM turismouq.v_adm_tarifas', -942);
   probar('Leer la auditoría de tarifas',            'SELECT COUNT(*) FROM turismouq.auditoria_tarifa_operacion', -942);
   probar('Ejecutar PKG_TURISMOUQ directamente',     'BEGIN turismouq.pkg_turismouq.sp_cancelar_reserva(1); END;', -6550);
   probar('Ejecutar PKG_ADMIN_ALOJAMIENTO',          'BEGIN turismouq.pkg_admin_alojamiento.sp_cambiar_tarifa(1, 1, 1); END;', -6550);
   probar('Crear una tabla propia',                  'CREATE TABLE prueba_recepcion (x NUMBER)', -1031);
END;
/

PROMPT Reserva + pago por PKG_RECEPCION en una habitación de SU hotel (debe permitirse)
DECLARE
   v_res  NUMBER;
   v_pago NUMBER;
BEGIN
   turismouq.pkg_recepcion.sp_reservar_con_pago(:v_cli, :v_hab_propia, DATE '2027-01-18', DATE '2027-01-20',
                                                2, 50000, 'EFECTIVO', NULL, v_res, v_pago,
                                                'PRUEBA E3 SEG - creada por recepcion');
   :v_res := v_res;
   DBMS_OUTPUT.PUT_LINE('OK    reserva ' || v_res || ' y pago ' || v_pago || ' creados por RECEP_HOTEL1');
EXCEPTION
   WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FALLA ' || SQLERRM);
END;
/

PROMPT La misma operación sobre una habitación de OTRO hotel (debe rechazarse con -20011)
DECLARE
   v_res  NUMBER;
   v_pago NUMBER;
BEGIN
   turismouq.pkg_recepcion.sp_reservar_con_pago(:v_cli, :v_hab_ajena, DATE '2027-01-18', DATE '2027-01-20',
                                                2, 50000, 'EFECTIVO', NULL, v_res, v_pago,
                                                'PRUEBA E3 SEG - no debe quedar');
   DBMS_OUTPUT.PUT_LINE('FALLA se creó la reserva ' || v_res || ' en otro alojamiento');
EXCEPTION
   WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE(CASE WHEN SQLCODE = -20011 THEN 'OK    ' ELSE 'FALLA ' END || SQLERRM);
END;
/

PROMPT La reserva recién creada vista por la vista de recepción
SELECT id_reserva, cliente, fecha_checkin, fecha_checkout, estado, total, pagado, saldo
FROM   turismouq.v_rec_reservas
WHERE  id_reserva = :v_res;

PROMPT ================================================================
PROMPT  T14.2 RECEP_SALENTO (ROL_RECEPCION en otro alojamiento): mismas vistas, otras filas
PROMPT ================================================================
CONNECT recep_salento/Recepcion_2026@&conexion
SET SERVEROUTPUT ON SIZE UNLIMITED

SELECT id_alojamiento, nombre_comercial, municipio FROM turismouq.v_rec_mi_alojamiento;

DECLARE
   v_n    NUMBER;
   v_pago NUMBER;
BEGIN
   SELECT COUNT(*) INTO v_n FROM turismouq.v_rec_reservas WHERE id_reserva = :v_res;
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_n = 0 THEN 'OK    ' ELSE 'FALLA ' END
      || 'la reserva ' || :v_res || ' del otro hotel no aparece en su vista (filas = ' || v_n || ')');

   SELECT COUNT(*) INTO v_n FROM turismouq.v_rec_habitaciones WHERE id_habitacion = :v_hab_propia;
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_n = 0 THEN 'OK    ' ELSE 'FALLA ' END
      || 'la habitación ' || :v_hab_propia || ' del otro hotel no aparece en su vista (filas = ' || v_n || ')');

   BEGIN
      turismouq.pkg_recepcion.sp_registrar_pago(:v_res, 10000, 'EFECTIVO', NULL, v_pago);
      DBMS_OUTPUT.PUT_LINE('FALLA registró un pago en una reserva de otro alojamiento');
   EXCEPTION
      WHEN OTHERS THEN
         DBMS_OUTPUT.PUT_LINE(CASE WHEN SQLCODE = -20011 THEN 'OK    ' ELSE 'FALLA ' END
            || 'pago sobre reserva ajena -> ' || SQLERRM);
   END;
END;
/

PROMPT ================================================================
PROMPT  T14.3 ENC_HOTEL (ROL_ADMIN_ALOJAMIENTO): hereda recepción y administra lo suyo
PROMPT ================================================================
CONNECT enc_hotel/Encargado_2026@&conexion
SET SERVEROUTPUT ON SIZE UNLIMITED

SELECT role FROM session_roles ORDER BY role;

DECLARE
   v_valor  NUMBER;
   v_nuevo  NUMBER;
   v_filas  NUMBER;

   PROCEDURE probar (p_desc VARCHAR2, p_sql VARCHAR2, p_esperado NUMBER) IS
      v_cod NUMBER := 0;
      v_msg VARCHAR2(120);
   BEGIN
      BEGIN
         EXECUTE IMMEDIATE p_sql;
      EXCEPTION
         WHEN OTHERS THEN
            v_cod := SQLCODE;
            v_msg := SUBSTR(REPLACE(SQLERRM, CHR(10), ' '), 1, 100);
      END;
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE(CASE WHEN v_cod = p_esperado OR (p_esperado = -1031 AND v_cod = -41900) THEN 'OK    ' ELSE 'FALLA ' END
         || RPAD(p_desc, 58)
         || CASE WHEN v_cod = 0 THEN 'permitido' ELSE 'denegado: ' || v_msg END);
   END;
BEGIN
   probar('Leer vistas de recepción (rol heredado)',  'SELECT COUNT(*) FROM turismouq.v_rec_reservas', 0);
   probar('Leer sus tarifas (V_ADM_TARIFAS)',          'SELECT COUNT(*) FROM turismouq.v_adm_tarifas', 0);
   probar('Leer su liquidación y su ocupación',        'SELECT COUNT(*) FROM turismouq.v_adm_liquidacion l, turismouq.v_adm_ocupacion o', 0);
   probar('Leer la TABLA TARIFA',                      'SELECT COUNT(*) FROM turismouq.tarifa', -942);
   probar('Leer la TABLA RESERVA',                     'SELECT COUNT(*) FROM turismouq.reserva', -942);
   probar('Leer la auditoría de tarifas',              'SELECT COUNT(*) FROM turismouq.auditoria_tarifa_detalle', -942);
   probar('Borrar una habitación por la vista',        'DELETE FROM turismouq.v_adm_habitaciones', -1031);
   probar('Crear una habitación en OTRO alojamiento',
          'INSERT INTO turismouq.v_adm_habitaciones (id_alojamiento, numero, tipo_habitacion, capacidad_max) '
          || 'VALUES (' || :v_aloj_ajeno || ', ''X-999'', ''DOBLE'', 2)', -1402);
   probar('Cambiar la tarifa de una habitación AJENA',
          'BEGIN turismouq.pkg_admin_alojamiento.sp_cambiar_tarifa(' || :v_hab_ajena || ', ' || :v_temp || ', 1000); END;', -20011);

   -- Actualizar una habitación propia por la vista (se deshace: solo se prueba el permiso)
   UPDATE turismouq.v_adm_habitaciones SET descripcion = descripcion WHERE id_habitacion = :v_hab_propia;
   v_filas := SQL%ROWCOUNT;
   ROLLBACK;
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_filas = 1 THEN 'OK    ' ELSE 'FALLA ' END
      || 'UPDATE de una habitación propia por la vista: ' || v_filas || ' fila');

   -- La habitación ajena ni siquiera es visible: el UPDATE no encuentra filas
   UPDATE turismouq.v_adm_habitaciones SET descripcion = descripcion WHERE id_habitacion = :v_hab_ajena;
   v_filas := SQL%ROWCOUNT;
   ROLLBACK;
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_filas = 0 THEN 'OK    ' ELSE 'FALLA ' END
      || 'UPDATE de una habitación ajena por la vista: ' || v_filas || ' filas');

   -- Cambiar una tarifa propia por el paquete: sube 1.000 y la devuelve (dos operaciones auditadas)
   SELECT valor_noche INTO v_valor
   FROM   turismouq.v_adm_tarifas
   WHERE  id_habitacion = :v_hab_propia AND id_temporada = :v_temp;

   turismouq.pkg_admin_alojamiento.sp_cambiar_tarifa(:v_hab_propia, :v_temp, v_valor + 1000);
   SELECT valor_noche INTO v_nuevo
   FROM   turismouq.v_adm_tarifas
   WHERE  id_habitacion = :v_hab_propia AND id_temporada = :v_temp;
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_nuevo = v_valor + 1000 THEN 'OK    ' ELSE 'FALLA ' END
      || 'tarifa propia cambiada por el paquete: ' || v_valor || ' -> ' || v_nuevo);

   turismouq.pkg_admin_alojamiento.sp_cambiar_tarifa(:v_hab_propia, :v_temp, v_valor);
   DBMS_OUTPUT.PUT_LINE('      tarifa restaurada a ' || v_valor);
EXCEPTION
   WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('FALLA ' || SQLERRM);
END;
/

PROMPT ================================================================
PROMPT  T14.4 GERENTE_GENERAL (ROL_GERENTE): lee todo el negocio, no modifica nada
PROMPT ================================================================
CONNECT gerente_general/Gerencia_2026@&conexion
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
   PROCEDURE probar (p_desc VARCHAR2, p_sql VARCHAR2, p_esperado NUMBER) IS
      v_cod NUMBER := 0;
      v_msg VARCHAR2(120);
   BEGIN
      BEGIN
         EXECUTE IMMEDIATE p_sql;
      EXCEPTION
         WHEN OTHERS THEN
            v_cod := SQLCODE;
            v_msg := SUBSTR(REPLACE(SQLERRM, CHR(10), ' '), 1, 100);
      END;
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE(CASE WHEN v_cod = p_esperado OR (p_esperado = -1031 AND v_cod = -41900) THEN 'OK    ' ELSE 'FALLA ' END
         || RPAD(p_desc, 58)
         || CASE WHEN v_cod = 0 THEN 'permitido' ELSE 'denegado: ' || v_msg END);
   END;
BEGIN
   probar('Leer la vista materializada de ocupación', 'SELECT COUNT(*) FROM turismouq.mv_ocupacion_mensual', 0);
   probar('Leer RESERVA de todos los alojamientos',   'SELECT COUNT(*) FROM turismouq.reserva', 0);
   probar('Leer PAGO y LIQUIDACION_MENSUAL',          'SELECT COUNT(*) FROM turismouq.pago p, turismouq.liquidacion_mensual l WHERE 1 = 0', 0);
   probar('Leer clientes SIN datos personales',       'SELECT COUNT(*) FROM turismouq.v_ger_clientes', 0);
   probar('Leer la TABLA CLIENTE (datos personales)', 'SELECT COUNT(*) FROM turismouq.cliente', -942);
   probar('Leer la auditoría de tarifas',             'SELECT COUNT(*) FROM turismouq.auditoria_tarifa_operacion', -942);
   probar('Leer USUARIO_SISTEMA',                     'SELECT COUNT(*) FROM turismouq.usuario_sistema', -942);
   probar('Modificar una reserva',                    'UPDATE turismouq.reserva SET observaciones = ''x'' WHERE 1 = 0', -1031);
   probar('Borrar pagos',                             'DELETE FROM turismouq.pago WHERE 1 = 0', -1031);
   probar('Cambiar una tarifa',                       'UPDATE turismouq.tarifa SET valor_noche = 1 WHERE 1 = 0', -1031);
   probar('Ejecutar PKG_RECEPCION',                   'BEGIN turismouq.pkg_recepcion.sp_cancelar_reserva(1); END;', -6550);
END;
/

PROMPT Lo que la gerencia sí puede ver: ocupación 2025 por municipio (de la vista materializada)
SELECT municipio,
       ROUND(100 * SUM(noches_ocupadas) / SUM(noches_disponibles), 1) AS pct_ocupacion_2025
FROM   turismouq.mv_ocupacion_mensual
WHERE  anio = 2025
GROUP  BY municipio
ORDER  BY pct_ocupacion_2025 DESC
FETCH  FIRST 5 ROWS ONLY;

PROMPT ================================================================
PROMPT  T14.5 AUDITOR_INTERNO (ROL_AUDITOR): lee la auditoría, no modifica nada
PROMPT ================================================================
CONNECT auditor_interno/Auditoria_2026@&conexion
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
   PROCEDURE probar (p_desc VARCHAR2, p_sql VARCHAR2, p_esperado NUMBER) IS
      v_cod NUMBER := 0;
      v_msg VARCHAR2(120);
   BEGIN
      BEGIN
         EXECUTE IMMEDIATE p_sql;
      EXCEPTION
         WHEN OTHERS THEN
            v_cod := SQLCODE;
            v_msg := SUBSTR(REPLACE(SQLERRM, CHR(10), ' '), 1, 100);
      END;
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE(CASE WHEN v_cod = p_esperado OR (p_esperado = -1031 AND v_cod = -41900) THEN 'OK    ' ELSE 'FALLA ' END
         || RPAD(p_desc, 58)
         || CASE WHEN v_cod = 0 THEN 'permitido' ELSE 'denegado: ' || v_msg END);
   END;
BEGIN
   probar('Leer la auditoría de tarifas (operaciones)', 'SELECT COUNT(*) FROM turismouq.auditoria_tarifa_operacion', 0);
   probar('Leer la auditoría de tarifas (detalle)',     'SELECT COUNT(*) FROM turismouq.auditoria_tarifa_detalle', 0);
   probar('Leer PAGO, RESERVA y USUARIO_SISTEMA',
          'SELECT COUNT(*) FROM turismouq.pago p, turismouq.reserva r, turismouq.usuario_sistema u WHERE 1 = 0', 0);
   probar('Leer la TABLA CLIENTE',                      'SELECT COUNT(*) FROM turismouq.cliente', -942);
   probar('Leer vistas de recepción',                   'SELECT COUNT(*) FROM turismouq.v_rec_reservas', -942);
   probar('Borrar registros de auditoría',              'DELETE FROM turismouq.auditoria_tarifa_detalle WHERE 1 = 0', -1031);
   probar('Alterar un registro de auditoría',           'UPDATE turismouq.auditoria_tarifa_operacion SET usuario_bd = ''x'' WHERE 1 = 0', -1031);
   probar('Cambiar una tarifa',                         'UPDATE turismouq.tarifa SET valor_noche = 1 WHERE 1 = 0', -1031);
   probar('Modificar un pago',                          'UPDATE turismouq.pago SET monto = 1 WHERE 1 = 0', -1031);
END;
/

PROMPT El auditor ve QUIÉN cambió la tarifa en T14.3 (usuario real de la sesión, no TURISMOUQ)
SELECT o.id_operacion, o.operacion, o.usuario_bd, TO_CHAR(o.fecha_hora, 'DD/MM/YYYY HH24:MI:SS') AS cuando,
       d.id_habitacion, d.valor_anterior, d.valor_nuevo
FROM   turismouq.auditoria_tarifa_operacion o
JOIN   turismouq.auditoria_tarifa_detalle d ON d.id_operacion = o.id_operacion
WHERE  d.id_habitacion = :v_hab_propia
AND    d.id_temporada  = :v_temp
ORDER  BY o.id_operacion DESC
FETCH  FIRST 2 ROWS ONLY;

PROMPT ================================================================
PROMPT  T14.6 Cierre (como TURISMOUQ)
PROMPT ================================================================
CONNECT turismouq/TurismoUQ2026@&conexion
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
   v_usuario VARCHAR2(128);
   v_n       NUMBER;
BEGIN
   SELECT MAX(o.usuario_bd) KEEP (DENSE_RANK LAST ORDER BY o.id_operacion) INTO v_usuario
   FROM   auditoria_tarifa_operacion o
   JOIN   auditoria_tarifa_detalle d ON d.id_operacion = o.id_operacion
   WHERE  d.id_habitacion = :v_hab_propia AND d.id_temporada = :v_temp;
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_usuario = 'ENC_HOTEL' THEN 'OK    ' ELSE 'FALLA ' END
      || 'la auditoría registró al usuario que se conectó: ' || v_usuario);

   SELECT COUNT(*) INTO v_n FROM reserva WHERE observaciones LIKE 'PRUEBA E3 SEG%';
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_n = 1 THEN 'OK    ' ELSE 'FALLA ' END
      || 'reservas de prueba que quedaron (solo la del hotel propio): ' || v_n);
END;
/

SELECT r.id_reserva, r.estado, a.nombre_comercial, r.fecha_checkin, r.fecha_checkout, r.observaciones
FROM   reserva r JOIN alojamiento a ON a.id_alojamiento = r.id_alojamiento
WHERE  r.observaciones LIKE 'PRUEBA E3 SEG%';

PROMPT ================================================================
PROMPT  Fin del script 14. Revise que no aparezca ninguna línea "FALLA".
PROMPT  Prueba manual del perfil: abra tres sesiones como RECEP_HOTEL1; la
PROMPT  tercera debe fallar con ORA-02391 (SESSIONS_PER_USER = 2).
PROMPT ================================================================
UNDEFINE conexion
