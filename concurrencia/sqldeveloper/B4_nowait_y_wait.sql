-- TurismoUQ · Entrega 3 · ventana B: NOWAIT y WAIT 5 mientras A tiene el bloqueo
SET SERVEROUTPUT ON
SET ECHO ON
DECLARE
   v_hab NUMBER;
   v_t0  TIMESTAMP WITH TIME ZONE;

   PROCEDURE intentar (p_espera NUMBER, p_nombre VARCHAR2) IS
   BEGIN
      v_t0 := SYSTIMESTAMP;
      pkg_reservas_tx.sp_bloquear_habitacion(v_hab, p_espera);
      DBMS_OUTPUT.PUT_LINE(p_nombre || ': INESPERADO, obtuvo el bloqueo');
      ROLLBACK;
   EXCEPTION
      WHEN pkg_reservas_tx.ex_bloqueo THEN
         DBMS_OUTPUT.PUT_LINE(RPAD(p_nombre, 8) || ' -> respondió en '
            || TO_CHAR(EXTRACT(SECOND FROM (SYSTIMESTAMP - v_t0)), 'FM90.00') || ' s: ' || SQLERRM);
   END;
BEGIN
   SELECT id_habitacion INTO v_hab
   FROM  (SELECT h.id_habitacion, ROW_NUMBER() OVER (ORDER BY h.id_habitacion) AS orden
          FROM   habitacion h JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
          WHERE  a.nombre_comercial = 'Hotel Mirador del Parque Sucre' AND h.capacidad_max >= 2)
   WHERE  orden = 2;
   intentar(0, 'NOWAIT');
   intentar(5, 'WAIT 5');
END;
/
