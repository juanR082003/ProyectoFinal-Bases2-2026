-- TurismoUQ · Entrega 3 · Experimento de concurrencia en SQL Developer · A0 preparación
-- Ejecutar con F5 en una hoja NO compartida (Ctrl+Shift+N) de la conexión TURISMOUQ (ventana A).
SET SERVEROUTPUT ON
SET FEEDBACK OFF
DELETE FROM pago               WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE observaciones LIKE 'PRUEBA E3 MANUAL%');
DELETE FROM reserva_habitacion WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE observaciones LIKE 'PRUEBA E3 MANUAL%');
DELETE FROM reserva            WHERE observaciones LIKE 'PRUEBA E3 MANUAL%';
COMMIT;
PROMPT Habitación en disputa (22 al 24 de enero de 2027):
SELECT (SELECT id_habitacion FROM (SELECT h.id_habitacion, ROW_NUMBER() OVER (ORDER BY h.id_habitacion) AS orden FROM habitacion h JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento WHERE a.nombre_comercial = 'Hotel Mirador del Parque Sucre' AND h.capacidad_max >= 2) WHERE orden = 2) AS habitacion_en_disputa, SYS_CONTEXT('USERENV','SID') AS sid_ventana_A FROM dual;
