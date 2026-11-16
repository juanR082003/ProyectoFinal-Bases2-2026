-- TurismoUQ · Entrega 3 · Experimento de concurrencia en SQL Developer · B3 reservar CON bloqueo
-- Ejecutar con F5 en una hoja NO compartida (Ctrl+Shift+N) de la conexión TURISMOUQ (ventana B).
SET SERVEROUTPUT ON
SET FEEDBACK OFF
SET ECHO ON
DECLARE
   v_hab NUMBER;  v_cli NUMBER;  v_id NUMBER;  v_pago NUMBER;
BEGIN
   SELECT (SELECT id_habitacion FROM (SELECT h.id_habitacion, ROW_NUMBER() OVER (ORDER BY h.id_habitacion) AS orden FROM habitacion h JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento WHERE a.nombre_comercial = 'Hotel Mirador del Parque Sucre' AND h.capacidad_max >= 2) WHERE orden = 2) INTO v_hab FROM dual;
   SELECT (SELECT MIN(id_cliente) FROM cliente WHERE id_cliente > (SELECT MIN(id_cliente) FROM cliente)) INTO v_cli FROM dual;
   pkg_reservas_tx.sp_reservar_con_pago(
      p_id_cliente => v_cli, p_id_habitacion => v_hab,
      p_fecha_in => DATE '2027-01-22', p_fecha_out => DATE '2027-01-24', p_num_huespedes => 2,
      p_monto_pago => 50000, p_metodo => 'EFECTIVO', p_referencia => NULL,
      p_id_reserva => v_id, p_id_pago => v_pago,
      p_confirmar => 'S',
      p_espera_seg => NULL,                -- FOR UPDATE sin WAIT: espera a que A termine
      p_observaciones => 'PRUEBA E3 MANUAL - ventana B con bloqueo');
   DBMS_OUTPUT.PUT_LINE('Ventana B: reserva ' || v_id || ' creada (' || TO_CHAR(SYSTIMESTAMP, 'HH24:MI:SS') || ')');
EXCEPTION
   WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Ventana B rechazada a las ' || TO_CHAR(SYSTIMESTAMP, 'HH24:MI:SS') || ' -> ' || SQLERRM);
END;
/
