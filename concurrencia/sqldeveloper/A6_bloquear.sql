-- TurismoUQ · Entrega 3 · ventana A: solo bloquear la habitación (para probar NOWAIT y WAIT n)
SET SERVEROUTPUT ON
SET ECHO ON
DECLARE
   v_hab NUMBER;
BEGIN
   SELECT id_habitacion INTO v_hab
   FROM  (SELECT h.id_habitacion, ROW_NUMBER() OVER (ORDER BY h.id_habitacion) AS orden
          FROM   habitacion h JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
          WHERE  a.nombre_comercial = 'Hotel Mirador del Parque Sucre' AND h.capacidad_max >= 2)
   WHERE  orden = 2;
   pkg_reservas_tx.sp_bloquear_habitacion(v_hab);       -- SELECT ... FOR UPDATE WAIT 10
   DBMS_OUTPUT.PUT_LINE('Ventana A: habitación ' || v_hab || ' bloqueada (sin COMMIT)');
END;
/
