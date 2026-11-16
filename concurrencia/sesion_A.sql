/* =====================================================================
   TurismoUQ · Entrega 3 · Experimento de concurrencia · VENTANA A
   ---------------------------------------------------------------------
   Hacen falta TRES ventanas (SQL*Plus, SQLcl o tres conexiones de SQL
   Developer que NO compartan sesión):
       Ventana A  TURISMOUQ  ->  @concurrencia/sesion_A.sql
       Ventana B  TURISMOUQ  ->  @concurrencia/sesion_B.sql
       Ventana M  SYSTEM     ->  @concurrencia/monitor_system.sql (cuando se indique)

   Cada script se detiene en cada PAUSE y dice qué hacer en la otra
   ventana. Se avanza con ENTER. (En SQL Developer también se puede
   seleccionar el bloque de cada paso y ejecutarlo con Ctrl+Enter / F5.)
   Las capturas del documento se toman donde dice [CAPTURA n].

   Empiece por esta ventana (A). Requiere haber ejecutado el script 09.
   Habitación en disputa: la segunda (capacidad >= 2) del "Hotel Mirador
   del Parque Sucre", noches del 22 al 24 de enero de 2027.
   ===================================================================== */
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET SQLBLANKLINES ON
SET LINESIZE 200
SET PAGESIZE 100
SET SQLPROMPT "A> "

VARIABLE v_hab NUMBER
VARIABLE v_cli NUMBER

PROMPT ===== A0. Preparación (borra restos de un experimento anterior) =====
BEGIN
   DELETE FROM pago               WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE observaciones LIKE 'PRUEBA E3 MANUAL%');
   DELETE FROM reserva_habitacion WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE observaciones LIKE 'PRUEBA E3 MANUAL%');
   DELETE FROM reserva            WHERE observaciones LIKE 'PRUEBA E3 MANUAL%';
   COMMIT;

   SELECT MIN(id_habitacion) INTO :v_hab
   FROM  (SELECT h.id_habitacion, ROW_NUMBER() OVER (ORDER BY h.id_habitacion) AS orden
          FROM   habitacion h JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
          WHERE  a.nombre_comercial = 'Hotel Mirador del Parque Sucre' AND h.capacidad_max >= 2)
   WHERE  orden = 2;
   SELECT MIN(id_cliente) INTO :v_cli FROM cliente;
   DBMS_OUTPUT.PUT_LINE('Ventana A · habitación en disputa: ' || :v_hab || ' · cliente: ' || :v_cli);
END;
/
PAUSE Ahora inicie la ventana B (@concurrencia/sesion_B.sql) hasta su primera pausa. Luego ENTER aquí.

PROMPT
PROMPT ################ EXPERIMENTO 1 · ANTES: sin bloqueo ################
PROMPT ===== A1. A reserva la habitación del 22 al 24 de enero y NO confirma =====
DECLARE
   v_id NUMBER;
BEGIN
   pkg_turismouq.sp_crear_reserva(:v_cli, :v_hab, DATE '2027-01-22', DATE '2027-01-24', 2,
                                  v_id, 'CONFIRMADA', 'PRUEBA E3 MANUAL - ventana A sin bloqueo');
END;
/
PAUSE [CAPTURA 1] Vaya a la ventana B y pulse ENTER (paso B1). B también reservará sin esperar. Luego ENTER aquí.

PROMPT ===== A2. A confirma =====
COMMIT;
PAUSE Vaya a la ventana B y pulse ENTER (paso B2: COMMIT). Luego ENTER aquí.

PROMPT ===== A3. Resultado SIN bloqueo: la habitación quedó vendida dos veces =====
SELECT r.id_reserva, r.estado, rh.id_habitacion, rh.fecha_checkin, rh.fecha_checkout, r.observaciones
FROM   reserva r JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
WHERE  r.observaciones LIKE 'PRUEBA E3 MANUAL%'
ORDER  BY r.id_reserva;
PAUSE [CAPTURA 2] Dos reservas CONFIRMADAS de la misma habitación y noches. ENTER para limpiar y seguir.

BEGIN
   DELETE FROM reserva_habitacion WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE observaciones LIKE 'PRUEBA E3 MANUAL%');
   DELETE FROM reserva            WHERE observaciones LIKE 'PRUEBA E3 MANUAL%';
   COMMIT;
END;
/

PROMPT
PROMPT ################ EXPERIMENTO 2 · DESPUÉS: SELECT ... FOR UPDATE ################
PROMPT ===== A4. A reserva con pkg_reservas_tx (bloquea la habitación) y NO confirma =====
DECLARE
   v_id   NUMBER;
   v_pago NUMBER;
BEGIN
   pkg_reservas_tx.sp_reservar_con_pago(
      p_id_cliente => :v_cli, p_id_habitacion => :v_hab,
      p_fecha_in => DATE '2027-01-22', p_fecha_out => DATE '2027-01-24', p_num_huespedes => 2,
      p_monto_pago => 50000, p_metodo => 'EFECTIVO', p_referencia => NULL,
      p_id_reserva => v_id, p_id_pago => v_pago,
      p_confirmar => 'N',
      p_observaciones => 'PRUEBA E3 MANUAL - ventana A con bloqueo');
END;
/
PROMPT Vaya a la ventana B y pulse ENTER (paso B3). B se quedará ESPERANDO: no devuelve el control.
PROMPT [CAPTURA 3] la ventana B bloqueada.
PROMPT [CAPTURA 4] en la ventana M (SYSTEM) ejecute @concurrencia/monitor_system.sql: muestra quién bloquea a quién.
PAUSE Cuando tenga las dos capturas, ENTER aquí para que A confirme.

PROMPT ===== A5. A confirma: se libera el bloqueo =====
COMMIT;
PAUSE [CAPTURA 5] Mire la ventana B: despertó y recibió ORA-20001 (no disponible). ENTER aquí para seguir.

PROMPT
PROMPT ################ EXPERIMENTO 3 · NOWAIT y WAIT n ################
PROMPT ===== A6. A solo bloquea la habitación (SELECT ... FOR UPDATE) =====
BEGIN
   pkg_reservas_tx.sp_bloquear_habitacion(:v_hab);
END;
/
PAUSE Vaya a la ventana B y pulse ENTER dos veces (pasos B4 NOWAIT y B5 WAIT 5). [CAPTURA 6]. Luego ENTER aquí.

PROMPT ===== A7. A libera el bloqueo =====
ROLLBACK;

PROMPT ===== A8. Resultado CON bloqueo: una sola reserva =====
SELECT r.id_reserva, r.estado, rh.id_habitacion, rh.fecha_checkin, rh.fecha_checkout, r.observaciones
FROM   reserva r JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
WHERE  r.observaciones LIKE 'PRUEBA E3 MANUAL%'
ORDER  BY r.id_reserva;
PROMPT [CAPTURA 7] Fin del experimento en la ventana A.
SET SQLPROMPT "SQL> "
