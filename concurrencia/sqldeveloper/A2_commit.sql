-- TurismoUQ · Entrega 3 · ventana A: confirmar
SET SERVEROUTPUT ON
COMMIT;
EXEC DBMS_OUTPUT.PUT_LINE('Ventana A: COMMIT a las ' || TO_CHAR(SYSTIMESTAMP, 'HH24:MI:SS'))
