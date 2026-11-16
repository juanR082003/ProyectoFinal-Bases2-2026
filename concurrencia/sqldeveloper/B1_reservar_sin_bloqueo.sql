-- TurismoUQ · Entrega 3 · Experimento de concurrencia en SQL Developer · B1 reservar SIN bloqueo
-- Ejecutar con F5 en una hoja NO compartida (Ctrl+Shift+N) de la conexión TURISMOUQ (ventana B).
SET SERVEROUTPUT ON
SET FEEDBACK OFF
SET ECHO ON
DECLARE
   v_hab NUMBER;  v_cli NUMBER;  v_id NUMBER;
BEGIN
   SELECT (SELECT id_habitacion FROM (SELECT h.id_habitacion, ROW_NUMBER() OVER (ORDER BY h.id_habitacion) AS orden FROM habitacion h JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento WHERE a.nombre_comercial = 'Hotel Mirador del Parque Sucre' AND h.capacidad_max >= 2) WHERE orden = 2) INTO v_hab FROM dual;
   SELECT (SELECT MIN(id_cliente) FROM cliente WHERE id_cliente > (SELECT MIN(id_cliente) FROM cliente)) INTO v_cli FROM dual;
   -- validación + INSERT, sin bloquear la habitación; NO se hace COMMIT
   pkg_turismouq.sp_crear_reserva(v_cli, v_hab, DATE '2027-01-22', DATE '2027-01-24', 2,
                                  v_id, 'CONFIRMADA', 'PRUEBA E3 MANUAL - ventana B sin bloqueo');
END;
/
SET ECHO OFF
PROMPT Ventana B: reserva creada SIN COMMIT (transacción abierta, sesión SID:
SELECT SYS_CONTEXT('USERENV','SID') AS sid FROM dual;
