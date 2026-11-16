/* =====================================================================
   TurismoUQ · Proyecto integrador Bases de Datos II · 2026-2
   Script 10 · Concurrencia: dos sesiones sobre la misma habitación (Entrega 3)
   ---------------------------------------------------------------------
   Ejecutar como TURISMOUQ con F5 (Ejecutar script), después de 09.

   El problema
     Oracle no deja ver a una sesión lo que otra todavía no confirma
     (lectura consistente, nivel READ COMMITTED). La validación de
     disponibilidad de sp_crear_reserva y el disparador TRG_RH_NO_SOLAPE
     LEEN las reservas existentes: si dos recepcionistas reservan la misma
     habitación al mismo tiempo, ninguna ve la reserva de la otra, las dos
     validaciones pasan y la habitación queda vendida dos veces.
     Leer no bloquea; hace falta un bloqueo explícito.

   La solución
     SELECT ... FOR UPDATE sobre la fila de HABITACION antes de validar
     (pkg_reservas_tx.sp_bloquear_habitacion, script 09). La segunda
     sesión queda esperando ese bloqueo de fila (TX); cuando la primera
     confirma, la segunda continúa, su validación YA ve la reserva nueva
     y recibe -20001 (no disponible). Con NOWAIT o WAIT n no se queda
     colgada: recibe -20010 y puede reintentar.

   Este script y el experimento con dos ventanas
     · Aquí (script 10) la "segunda sesión" se simula con una TRANSACCIÓN
       AUTÓNOMA: es una transacción independiente dentro de la misma
       sesión, que no ve lo que la principal no ha confirmado y compite
       por los mismos bloqueos. Así el antes y el después quedan
       reproducibles con un solo F5 y con resultado OK / FALLA.
     · El experimento real con dos ventanas (y una tercera como SYSTEM
       para ver el bloqueo en V$SESSION y V$LOCK) está en la carpeta
       concurrencia/: sesion_A.sql, sesion_B.sql y monitor_system.sql.
       De ahí salen las capturas del documento.

   Datos de prueba: segunda habitación (capacidad >= 2) del "Hotel Mirador
   del Parque Sucre", noches del 18 al 20 de enero de 2027. Las reservas
   llevan observaciones 'PRUEBA E3 CONC...' y se borran al inicio.
   ===================================================================== */

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET SQLBLANKLINES ON
SET LINESIZE 220
SET PAGESIZE 100

VARIABLE v_hab   NUMBER
VARIABLE v_cli_a NUMBER
VARIABLE v_cli_b NUMBER

PROMPT ================================================================
PROMPT  T10.0 Preparación
PROMPT ================================================================
BEGIN
   DELETE FROM pago               WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE observaciones LIKE 'PRUEBA E3 CONC%');
   DELETE FROM reserva_habitacion WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE observaciones LIKE 'PRUEBA E3 CONC%');
   DELETE FROM reserva            WHERE observaciones LIKE 'PRUEBA E3 CONC%';
   COMMIT;

   SELECT MIN(id_habitacion) INTO :v_hab
   FROM  (SELECT h.id_habitacion,
                 ROW_NUMBER() OVER (ORDER BY h.id_habitacion) AS orden
          FROM   habitacion h JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
          WHERE  a.nombre_comercial = 'Hotel Mirador del Parque Sucre' AND h.capacidad_max >= 2)
   WHERE  orden = 2;

   SELECT MIN(id_cliente) INTO :v_cli_a FROM cliente;
   SELECT MIN(id_cliente) INTO :v_cli_b FROM cliente WHERE id_cliente > :v_cli_a;

   DBMS_OUTPUT.PUT_LINE('Habitación en disputa: ' || :v_hab || '   cliente A: ' || :v_cli_a || '   cliente B: ' || :v_cli_b);
END;
/

PROMPT ================================================================
PROMPT  T10.1 ANTES (sin bloqueo): las dos transacciones reservan la misma habitación
PROMPT        A reserva y NO confirma; B valida, no ve la reserva de A y también reserva.
PROMPT ================================================================
DECLARE
   v_res_a  NUMBER;
   v_res_b  NUMBER;
   v_n      NUMBER;

   -- "Sesión B": transacción independiente de la principal
   PROCEDURE sesion_b IS
      PRAGMA AUTONOMOUS_TRANSACTION;
   BEGIN
      pkg_turismouq.sp_crear_reserva(:v_cli_b, :v_hab, DATE '2027-01-18', DATE '2027-01-20', 2,
                                     v_res_b, 'CONFIRMADA', 'PRUEBA E3 CONC - sesion B sin bloqueo');
      COMMIT;
   EXCEPTION
      WHEN OTHERS THEN
         ROLLBACK;
         DBMS_OUTPUT.PUT_LINE('Sesión B rechazada -> ' || SQLERRM);
   END;
BEGIN
   -- Sesión A: reserva, todavía sin COMMIT
   pkg_turismouq.sp_crear_reserva(:v_cli_a, :v_hab, DATE '2027-01-18', DATE '2027-01-20', 2,
                                  v_res_a, 'CONFIRMADA', 'PRUEBA E3 CONC - sesion A sin bloqueo');
   -- Sesión B: llega mientras A sigue abierta
   sesion_b;
   -- Sesión A: confirma
   COMMIT;

   SELECT COUNT(*) INTO v_n
   FROM   reserva_habitacion rh JOIN reserva r ON r.id_reserva = rh.id_reserva
   WHERE  rh.id_habitacion = :v_hab AND rh.fecha_checkin = DATE '2027-01-18'
   AND    r.estado <> 'CANCELADA';

   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_n = 2 THEN 'OK (anomalía reproducida)' ELSE 'FALLA' END
      || ': reservas activas de la habitación ' || :v_hab || ' para el 18-ene = ' || v_n
      || '  -> SOBREVENTA: ni el procedimiento ni el disparador la detectaron');
EXCEPTION
   WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('FALLA: ' || SQLERRM);
END;
/

PROMPT La misma habitación, las mismas noches, dos reservas CONFIRMADAS:
SELECT r.id_reserva, r.estado, rh.id_habitacion, rh.fecha_checkin, rh.fecha_checkout, r.observaciones
FROM   reserva r JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
WHERE  r.observaciones LIKE 'PRUEBA E3 CONC%'
ORDER  BY r.id_reserva;

PROMPT Se limpia la sobreventa para repetir el experimento con bloqueo
BEGIN
   DELETE FROM reserva_habitacion WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE observaciones LIKE 'PRUEBA E3 CONC%');
   DELETE FROM reserva            WHERE observaciones LIKE 'PRUEBA E3 CONC%';
   COMMIT;
END;
/

PROMPT ================================================================
PROMPT  T10.2 DESPUÉS (SELECT ... FOR UPDATE): A bloquea la habitación; B no puede pasar.
PROMPT        B usa NOWAIT, así que en vez de quedarse esperando recibe -20010 de inmediato.
PROMPT ================================================================
DECLARE
   v_res_a   NUMBER;
   v_pago_a  NUMBER;
   v_res_b   NUMBER;
   v_pago_b  NUMBER;
   v_cod_b   NUMBER := 0;
   v_n       NUMBER;

   PROCEDURE sesion_b (p_espera NUMBER) IS
      PRAGMA AUTONOMOUS_TRANSACTION;
   BEGIN
      pkg_reservas_tx.sp_reservar_con_pago(
         p_id_cliente    => :v_cli_b,
         p_id_habitacion => :v_hab,
         p_fecha_in      => DATE '2027-01-18',
         p_fecha_out     => DATE '2027-01-20',
         p_num_huespedes => 2,
         p_monto_pago    => 50000,
         p_metodo        => 'EFECTIVO',
         p_referencia    => NULL,
         p_id_reserva    => v_res_b,
         p_id_pago       => v_pago_b,
         p_confirmar     => 'S',
         p_espera_seg    => p_espera,
         p_observaciones => 'PRUEBA E3 CONC - sesion B con bloqueo');
      DBMS_OUTPUT.PUT_LINE('Sesión B: reserva ' || v_res_b || ' creada');
   EXCEPTION
      WHEN OTHERS THEN
         v_cod_b := SQLCODE;
         ROLLBACK;
         DBMS_OUTPUT.PUT_LINE('Sesión B rechazada -> ' || SQLERRM);
   END;
BEGIN
   -- Sesión A: bloquea la habitación (FOR UPDATE), reserva y paga; aún sin COMMIT
   pkg_reservas_tx.sp_reservar_con_pago(
      p_id_cliente    => :v_cli_a,
      p_id_habitacion => :v_hab,
      p_fecha_in      => DATE '2027-01-18',
      p_fecha_out     => DATE '2027-01-20',
      p_num_huespedes => 2,
      p_monto_pago    => 50000,
      p_metodo        => 'EFECTIVO',
      p_referencia    => NULL,
      p_id_reserva    => v_res_a,
      p_id_pago       => v_pago_a,
      p_confirmar     => 'N',
      p_observaciones => 'PRUEBA E3 CONC - sesion A con bloqueo');
   DBMS_OUTPUT.PUT_LINE('Sesión A: reserva ' || v_res_a || ' creada, transacción abierta (tiene el bloqueo)');

   -- Sesión B: intenta mientras A tiene el bloqueo
   sesion_b(0);
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_cod_b = -20010 THEN 'OK' ELSE 'FALLA' END
      || ': B encontró la habitación bloqueada (código ' || v_cod_b || ')');

   -- Sesión A: confirma y libera el bloqueo
   COMMIT;
   DBMS_OUTPUT.PUT_LINE('Sesión A: COMMIT');

   -- Sesión B: reintenta; ahora obtiene el bloqueo, pero su validación ya VE la reserva de A
   v_cod_b := 0;
   sesion_b(0);
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_cod_b = -20001 THEN 'OK' ELSE 'FALLA' END
      || ': en el reintento B recibió "no disponible" (código ' || v_cod_b || ')');

   SELECT COUNT(*) INTO v_n
   FROM   reserva_habitacion rh JOIN reserva r ON r.id_reserva = rh.id_reserva
   WHERE  rh.id_habitacion = :v_hab AND rh.fecha_checkin = DATE '2027-01-18'
   AND    r.estado <> 'CANCELADA';
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_n = 1 THEN 'OK' ELSE 'FALLA' END
      || ': reservas activas de la habitación ' || :v_hab || ' para el 18-ene = ' || v_n || '  -> sin sobreventa');
EXCEPTION
   WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('FALLA: ' || SQLERRM);
END;
/

PROMPT Resultado con bloqueo: una sola reserva
SELECT r.id_reserva, r.estado, rh.id_habitacion, rh.fecha_checkin, rh.fecha_checkout, r.observaciones
FROM   reserva r JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
WHERE  r.observaciones LIKE 'PRUEBA E3 CONC%'
ORDER  BY r.id_reserva;

PROMPT ================================================================
PROMPT  T10.3 El bloqueo es por habitación: otra habitación del mismo hotel no espera a nadie
PROMPT ================================================================
DECLARE
   v_otra  NUMBER;
   v_cod   NUMBER := 0;

   PROCEDURE sesion_b IS
      PRAGMA AUTONOMOUS_TRANSACTION;
   BEGIN
      pkg_reservas_tx.sp_bloquear_habitacion(v_otra, 0);
      ROLLBACK;
   EXCEPTION
      WHEN OTHERS THEN
         v_cod := SQLCODE;
         ROLLBACK;
   END;
BEGIN
   SELECT MIN(h.id_habitacion) INTO v_otra
   FROM   habitacion h
   WHERE  h.id_alojamiento = (SELECT id_alojamiento FROM habitacion WHERE id_habitacion = :v_hab)
   AND    h.id_habitacion  > :v_hab;

   pkg_reservas_tx.sp_bloquear_habitacion(:v_hab);     -- A tiene bloqueada la habitación en disputa
   sesion_b;                                           -- B bloquea OTRA habitación
   ROLLBACK;
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_cod = 0 THEN 'OK' ELSE 'FALLA' END
      || ': con la habitación ' || :v_hab || ' bloqueada, la ' || v_otra || ' se pudo bloquear sin esperar (código ' || v_cod || ')');
EXCEPTION
   WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('FALLA: ' || SQLERRM);
END;
/

PROMPT ================================================================
PROMPT  Fin del script 10. Revise que no aparezca ninguna línea "FALLA".
PROMPT  El experimento con dos ventanas está en la carpeta concurrencia/.
PROMPT ================================================================
