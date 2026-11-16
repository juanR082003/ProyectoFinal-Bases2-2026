-- TurismoUQ · Entrega 3 · ventana A: liberar el bloqueo y ver el resultado CON bloqueo
SET SERVEROUTPUT ON
ROLLBACK;
PROMPT Resultado CON bloqueo: una sola reserva para la habitación y las noches en disputa
COLUMN observaciones FORMAT A45
SELECT r.id_reserva, r.estado, rh.id_habitacion, rh.fecha_checkin, rh.fecha_checkout, r.observaciones
FROM   reserva r JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
WHERE  r.observaciones LIKE 'PRUEBA E3 MANUAL%'
ORDER  BY r.id_reserva;
