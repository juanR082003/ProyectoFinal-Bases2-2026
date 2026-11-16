-- TurismoUQ · Entrega 3 · ventana B: confirmar y ver el resultado SIN bloqueo
SET SERVEROUTPUT ON
COMMIT;
PROMPT Resultado SIN bloqueo: la misma habitación y las mismas noches quedaron vendidas dos veces
COLUMN observaciones FORMAT A45
SELECT r.id_reserva, r.estado, rh.id_habitacion, rh.fecha_checkin, rh.fecha_checkout, r.observaciones
FROM   reserva r JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
WHERE  r.observaciones LIKE 'PRUEBA E3 MANUAL%'
ORDER  BY r.id_reserva;
