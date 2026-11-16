-- TurismoUQ · Entrega 3 · ventana A: borrar la sobreventa para repetir con bloqueo
SET FEEDBACK OFF
DELETE FROM pago               WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE observaciones LIKE 'PRUEBA E3 MANUAL%');
DELETE FROM reserva_habitacion WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE observaciones LIKE 'PRUEBA E3 MANUAL%');
DELETE FROM reserva            WHERE observaciones LIKE 'PRUEBA E3 MANUAL%';
COMMIT;
PROMPT Sobreventa borrada.
