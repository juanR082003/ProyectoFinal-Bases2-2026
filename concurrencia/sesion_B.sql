/* =====================================================================
   TurismoUQ · Entrega 3 · Experimento de concurrencia · VENTANA B
   ---------------------------------------------------------------------
   Conectado como TURISMOUQ en una sesión DISTINTA de la ventana A.
   Siga las instrucciones de la ventana A: aquí solo se pulsa ENTER
   cuando A lo indique.
   ===================================================================== */
SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET SQLBLANKLINES ON
SET LINESIZE 200
SET PAGESIZE 100
SET SQLPROMPT "B> "

VARIABLE v_hab NUMBER
VARIABLE v_cli NUMBER

PROMPT ===== B0. Preparación =====
BEGIN
   SELECT MIN(id_habitacion) INTO :v_hab
   FROM  (SELECT h.id_habitacion, ROW_NUMBER() OVER (ORDER BY h.id_habitacion) AS orden
          FROM   habitacion h JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
          WHERE  a.nombre_comercial = 'Hotel Mirador del Parque Sucre' AND h.capacidad_max >= 2)
   WHERE  orden = 2;
   SELECT MIN(id_cliente) INTO :v_cli
   FROM   cliente WHERE id_cliente > (SELECT MIN(id_cliente) FROM cliente);
   DBMS_OUTPUT.PUT_LINE('Ventana B · habitación en disputa: ' || :v_hab || ' · cliente: ' || :v_cli);
END;
/
PAUSE Vuelva a la ventana A y pulse ENTER. Regrese aquí cuando A lo indique (paso B1).

PROMPT
PROMPT ################ EXPERIMENTO 1 · ANTES: sin bloqueo ################
PROMPT ===== B1. B reserva la MISMA habitación y noches (A aún no confirma) =====
DECLARE
   v_id NUMBER;
BEGIN
   pkg_turismouq.sp_crear_reserva(:v_cli, :v_hab, DATE '2027-01-22', DATE '2027-01-24', 2,
                                  v_id, 'CONFIRMADA', 'PRUEBA E3 MANUAL - ventana B sin bloqueo');
END;
/
PAUSE [CAPTURA 1] B también reservó: no vio la reserva sin confirmar de A. Vuelva a A (ENTER allá) y regrese para B2.

PROMPT ===== B2. B confirma =====
COMMIT;
PAUSE Vuelva a la ventana A y pulse ENTER (verá la sobreventa). Regrese aquí cuando A lo indique (paso B3).

PROMPT
PROMPT ################ EXPERIMENTO 2 · DESPUÉS: SELECT ... FOR UPDATE ################
PROMPT ===== B3. B reserva con pkg_reservas_tx y espera indefinida: SE QUEDA BLOQUEADA =====
PROMPT (el control vuelve solo cuando A haga COMMIT; mientras tanto tome las capturas 3 y 4)
DECLARE
   v_id   NUMBER;
   v_pago NUMBER;
BEGIN
   pkg_reservas_tx.sp_reservar_con_pago(
      p_id_cliente => :v_cli, p_id_habitacion => :v_hab,
      p_fecha_in => DATE '2027-01-22', p_fecha_out => DATE '2027-01-24', p_num_huespedes => 2,
      p_monto_pago => 50000, p_metodo => 'EFECTIVO', p_referencia => NULL,
      p_id_reserva => v_id, p_id_pago => v_pago,
      p_espera_seg => NULL,                       -- FOR UPDATE sin WAIT: espera hasta que A termine
      p_observaciones => 'PRUEBA E3 MANUAL - ventana B con bloqueo');
   DBMS_OUTPUT.PUT_LINE('INESPERADO: B reservó (' || v_id || ')');
EXCEPTION
   WHEN pkg_turismouq.ex_no_disponible THEN
      DBMS_OUTPUT.PUT_LINE('B despertó después del COMMIT de A y fue rechazada -> ' || SQLERRM);
END;
/
PAUSE [CAPTURA 5] Vuelva a la ventana A y pulse ENTER. Regrese aquí cuando A lo indique (paso B4).

PROMPT
PROMPT ################ EXPERIMENTO 3 · NOWAIT y WAIT n ################
PROMPT ===== B4. NOWAIT: B no espera, recibe -20010 de inmediato =====
SET TIMING ON
BEGIN
   pkg_reservas_tx.sp_bloquear_habitacion(:v_hab, 0);
   DBMS_OUTPUT.PUT_LINE('INESPERADO: B obtuvo el bloqueo');
   ROLLBACK;
EXCEPTION
   WHEN pkg_reservas_tx.ex_bloqueo THEN DBMS_OUTPUT.PUT_LINE('NOWAIT -> ' || SQLERRM);
END;
/
PAUSE ENTER para probar WAIT 5 (paso B5).

PROMPT ===== B5. WAIT 5: B espera 5 segundos y luego recibe -20010 =====
BEGIN
   pkg_reservas_tx.sp_bloquear_habitacion(:v_hab, 5);
   DBMS_OUTPUT.PUT_LINE('INESPERADO: B obtuvo el bloqueo');
   ROLLBACK;
EXCEPTION
   WHEN pkg_reservas_tx.ex_bloqueo THEN DBMS_OUTPUT.PUT_LINE('WAIT 5 -> ' || SQLERRM);
END;
/
SET TIMING OFF
PROMPT [CAPTURA 6] Compare los tiempos: NOWAIT ~0 s, WAIT 5 ~5 s. Vuelva a la ventana A y pulse ENTER.
SET SQLPROMPT "SQL> "
