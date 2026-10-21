/* =====================================================================
   TurismoUQ · Proyecto integrador Bases de Datos II · 2026-2
   Script 08 · Evidencia de pruebas de la Entrega 2
   ---------------------------------------------------------------------
   Ejecutar como TURISMOUQ con F5 (Ejecutar script), después de 04 a 07.
   Cada prueba imprime "OK" o "FALLA" y el mensaje obtenido; la salida
   completa del script es la evidencia que se entrega (y de la que se
   toman las capturas).

   Datos de prueba
     · Habitación de prueba: la de menor id del "Hotel Torre Cafetera"
       con capacidad >= 2 (y una segunda del mismo hotel para el grupo).
     · Fechas de reserva en la segunda quincena de enero de 2027: el
       calendario las cubre y la carga no tiene reservas allí, así que
       los resultados no dependen del azar de la carga.
     · Todas las reservas de prueba llevan observaciones 'PRUEBA E2 ...'
       y se borran al inicio: el script se puede ejecutar varias veces.

   Pruebas
     T1  fn_valor_estadia (una, dos y tres temporadas; errores)
     T2  sp_crear_reserva y sp_agregar_habitacion (éxito y cada excepción)
     T3  disparador de fila anti-solape (INSERT directo, borde y UPDATE)
     T4  cursor con parámetros: liquidación mensual
     T5  disparador de sentencia: auditoría de TARIFA
     T6  regla de cancelación (80 % / sin reembolso) y reserva pagada
     T7  tablespace e histórico
     T8  vista materializada: desactualización y refresco
   ===================================================================== */

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET SQLBLANKLINES ON
SET LINESIZE 220
SET PAGESIZE 100

VARIABLE v_hab   NUMBER
VARIABLE v_hab2  NUMBER
VARIABLE v_aloj  NUMBER
VARIABLE v_cli   NUMBER
VARIABLE v_res   NUMBER
VARIABLE v_res2  NUMBER
VARIABLE v_res3  NUMBER
VARIABLE v_res4  NUMBER
VARIABLE v_op    NUMBER

PROMPT ================================================================
PROMPT  T0. Preparación: limpiar pruebas anteriores y elegir datos
PROMPT ================================================================
BEGIN
   DELETE FROM pago               WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE observaciones LIKE 'PRUEBA E2%');
   DELETE FROM reserva_servicio   WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE observaciones LIKE 'PRUEBA E2%');
   DELETE FROM reserva_habitacion WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE observaciones LIKE 'PRUEBA E2%');
   DELETE FROM reserva            WHERE observaciones LIKE 'PRUEBA E2%';
   COMMIT;

   -- la vista materializada arranca sin las reservas de prueba (para que T8 muestre el antes y el después)
   DBMS_MVIEW.REFRESH(list => 'MV_OCUPACION_MENSUAL', method => 'C');

   SELECT MIN(h.id_habitacion) INTO :v_hab
   FROM   habitacion h JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
   WHERE  a.nombre_comercial = 'Hotel Torre Cafetera' AND h.capacidad_max >= 2;

   SELECT MIN(h.id_habitacion) INTO :v_hab2
   FROM   habitacion h JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
   WHERE  a.nombre_comercial = 'Hotel Torre Cafetera' AND h.capacidad_max >= 2
   AND    h.id_habitacion > :v_hab;

   SELECT id_alojamiento INTO :v_aloj FROM habitacion WHERE id_habitacion = :v_hab;
   SELECT MIN(id_cliente) INTO :v_cli FROM cliente;

   DBMS_OUTPUT.PUT_LINE('Habitación de prueba: ' || :v_hab || ', segunda habitación: ' || :v_hab2
                        || ', alojamiento: ' || :v_aloj || ', cliente: ' || :v_cli);
END;
/

PROMPT ================================================================
PROMPT  T1. fn_valor_estadia
PROMPT ================================================================

PROMPT T1.1 Estadía 12-dic-2026 a 17-dic-2026: cruza de MEDIA a ALTA el 15-dic
DECLARE
   v_fn    NUMBER;
   v_cal   NUMBER;
   v_plano NUMBER;
BEGIN
   pkg_turismouq.sp_desglose_estadia(:v_hab, DATE '2026-12-12', DATE '2026-12-17');
   v_fn := pkg_turismouq.fn_valor_estadia(:v_hab, DATE '2026-12-12', DATE '2026-12-17');

   -- cálculo independiente noche por noche con CALENDARIO
   SELECT SUM(t.valor_noche) INTO v_cal
   FROM   calendario c
   JOIN   tarifa t ON t.id_temporada = c.id_temporada AND t.id_habitacion = :v_hab
   WHERE  c.fecha >= DATE '2026-12-12' AND c.fecha < DATE '2026-12-17';

   -- lo que daría (mal) cobrar las 5 noches a la tarifa del día de llegada
   SELECT 5 * t.valor_noche INTO v_plano
   FROM   calendario c
   JOIN   tarifa t ON t.id_temporada = c.id_temporada AND t.id_habitacion = :v_hab
   WHERE  c.fecha = DATE '2026-12-12';

   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_fn = v_cal THEN 'OK' ELSE 'FALLA' END
      || ': función = ' || v_fn || '  |  cálculo independiente por CALENDARIO = ' || v_cal);
   DBMS_OUTPUT.PUT_LINE('   (con una sola tarifa, la del check-in, habría dado ' || v_plano
      || ': diferencia de ' || (v_fn - v_plano) || ')');
END;
/

PROMPT T1.2 Estadía dentro de una sola temporada (18 al 21 de enero de 2027, BAJA)
DECLARE
   v_fn  NUMBER;
   v_cal NUMBER;
BEGIN
   pkg_turismouq.sp_desglose_estadia(:v_hab, DATE '2027-01-18', DATE '2027-01-21');
   v_fn := pkg_turismouq.fn_valor_estadia(:v_hab, DATE '2027-01-18', DATE '2027-01-21');
   SELECT SUM(t.valor_noche) INTO v_cal
   FROM   calendario c JOIN tarifa t ON t.id_temporada = c.id_temporada AND t.id_habitacion = :v_hab
   WHERE  c.fecha >= DATE '2027-01-18' AND c.fecha < DATE '2027-01-21';
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_fn = v_cal THEN 'OK' ELSE 'FALLA' END || ': ' || v_fn || ' = ' || v_cal);
END;
/

PROMPT T1.3 Estadía que atraviesa TRES tramos (29-oct a 03-nov-2026: BAJA, puente ALTA, BAJA)
DECLARE
   v_fn  NUMBER;
   v_cal NUMBER;
BEGIN
   pkg_turismouq.sp_desglose_estadia(:v_hab, DATE '2026-10-29', DATE '2026-11-03');
   v_fn := pkg_turismouq.fn_valor_estadia(:v_hab, DATE '2026-10-29', DATE '2026-11-03');
   SELECT SUM(t.valor_noche) INTO v_cal
   FROM   calendario c JOIN tarifa t ON t.id_temporada = c.id_temporada AND t.id_habitacion = :v_hab
   WHERE  c.fecha >= DATE '2026-10-29' AND c.fecha < DATE '2026-11-03';
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_fn = v_cal THEN 'OK' ELSE 'FALLA' END || ': ' || v_fn || ' = ' || v_cal);
END;
/

PROMPT T1.4 La función también se puede usar dentro de SQL
SELECT pkg_turismouq.fn_valor_estadia(:v_hab, DATE '2026-12-12', DATE '2026-12-17') AS valor_12_al_17_dic
FROM   dual;

PROMPT T1.5 Error esperado -20002: check-out igual al check-in
DECLARE
   v NUMBER;
BEGIN
   v := pkg_turismouq.fn_valor_estadia(:v_hab, DATE '2027-01-18', DATE '2027-01-18');
   DBMS_OUTPUT.PUT_LINE('FALLA: no se lanzó el error');
EXCEPTION
   WHEN pkg_turismouq.ex_fechas THEN DBMS_OUTPUT.PUT_LINE('OK (error esperado) -> ' || SQLERRM);
   WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FALLA: error inesperado -> ' || SQLERRM);
END;
/

PROMPT T1.6 Error esperado -20005: noches fuera del calendario (30-ene a 03-feb-2027)
DECLARE
   v NUMBER;
BEGIN
   v := pkg_turismouq.fn_valor_estadia(:v_hab, DATE '2027-01-30', DATE '2027-02-03');
   DBMS_OUTPUT.PUT_LINE('FALLA: no se lanzó el error');
EXCEPTION
   WHEN pkg_turismouq.ex_sin_tarifa THEN DBMS_OUTPUT.PUT_LINE('OK (error esperado) -> ' || SQLERRM);
   WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FALLA: error inesperado -> ' || SQLERRM);
END;
/

PROMPT ================================================================
PROMPT  T2. sp_crear_reserva y sp_agregar_habitacion
PROMPT ================================================================

PROMPT T2.1 Reserva válida: habitación de prueba, 18 al 21 de enero de 2027, 2 huéspedes
DECLARE
   v_id NUMBER;
BEGIN
   pkg_turismouq.sp_crear_reserva(:v_cli, :v_hab, DATE '2027-01-18', DATE '2027-01-21', 2,
                                  v_id, 'PENDIENTE', 'PRUEBA E2 - reserva valida');
   :v_res := v_id;
   COMMIT;
   DBMS_OUTPUT.PUT_LINE('OK: reserva ' || v_id || ' creada');
EXCEPTION
   WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FALLA: ' || SQLERRM);
END;
/

PROMPT T2.2 Error esperado -20001: misma habitación, 20 al 23 de enero (se cruza con T2.1)
DECLARE
   v_id NUMBER;
BEGIN
   pkg_turismouq.sp_crear_reserva(:v_cli, :v_hab, DATE '2027-01-20', DATE '2027-01-23', 2,
                                  v_id, 'PENDIENTE', 'PRUEBA E2 - no debe crearse');
   DBMS_OUTPUT.PUT_LINE('FALLA: se creó la reserva ' || v_id);
EXCEPTION
   WHEN pkg_turismouq.ex_no_disponible THEN DBMS_OUTPUT.PUT_LINE('OK (error esperado) -> ' || SQLERRM);
   WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FALLA: error inesperado -> ' || SQLERRM);
END;
/

PROMPT T2.3 Error esperado -20002: check-out anterior al check-in
DECLARE
   v_id NUMBER;
BEGIN
   pkg_turismouq.sp_crear_reserva(:v_cli, :v_hab, DATE '2027-01-27', DATE '2027-01-25', 2,
                                  v_id, 'PENDIENTE', 'PRUEBA E2 - no debe crearse');
   DBMS_OUTPUT.PUT_LINE('FALLA: se creó la reserva ' || v_id);
EXCEPTION
   WHEN pkg_turismouq.ex_fechas THEN DBMS_OUTPUT.PUT_LINE('OK (error esperado) -> ' || SQLERRM);
   WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FALLA: error inesperado -> ' || SQLERRM);
END;
/

PROMPT T2.4 Error esperado -20003: más huéspedes que la capacidad máxima
DECLARE
   v_id  NUMBER;
   v_cap NUMBER;
BEGIN
   SELECT capacidad_max INTO v_cap FROM habitacion WHERE id_habitacion = :v_hab;
   pkg_turismouq.sp_crear_reserva(:v_cli, :v_hab, DATE '2027-01-25', DATE '2027-01-27', v_cap + 1,
                                  v_id, 'PENDIENTE', 'PRUEBA E2 - no debe crearse');
   DBMS_OUTPUT.PUT_LINE('FALLA: se creó la reserva ' || v_id);
EXCEPTION
   WHEN pkg_turismouq.ex_capacidad THEN DBMS_OUTPUT.PUT_LINE('OK (error esperado) -> ' || SQLERRM);
   WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FALLA: error inesperado -> ' || SQLERRM);
END;
/

PROMPT T2.5 Error esperado -20007: check-in en el pasado
DECLARE
   v_id NUMBER;
BEGIN
   pkg_turismouq.sp_crear_reserva(:v_cli, :v_hab, DATE '2025-01-10', DATE '2025-01-12', 2,
                                  v_id, 'PENDIENTE', 'PRUEBA E2 - no debe crearse');
   DBMS_OUTPUT.PUT_LINE('FALLA: se creó la reserva ' || v_id);
EXCEPTION
   WHEN pkg_turismouq.ex_fecha_pasada THEN DBMS_OUTPUT.PUT_LINE('OK (error esperado) -> ' || SQLERRM);
   WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FALLA: error inesperado -> ' || SQLERRM);
END;
/

PROMPT T2.6 Grupo: se agrega otra habitación a la reserva T2.1, llegando un día después (19 al 22)
BEGIN
   pkg_turismouq.sp_agregar_habitacion(:v_res, :v_hab2, DATE '2027-01-19', DATE '2027-01-22', 2);
   COMMIT;
   DBMS_OUTPUT.PUT_LINE('OK: total de la reserva = ' || pkg_turismouq.fn_total_reserva(:v_res));
EXCEPTION
   WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FALLA: ' || SQLERRM);
END;
/

PROMPT Estado de la reserva de grupo (el rango general pasó a 18-22 de enero)
SELECT r.id_reserva, r.estado, r.fecha_checkin, r.fecha_checkout,
       rh.id_habitacion, rh.fecha_checkin AS linea_in, rh.fecha_checkout AS linea_out,
       rh.num_huespedes, rh.valor_estadia
FROM   reserva r
JOIN   reserva_habitacion rh ON rh.id_reserva = r.id_reserva
WHERE  r.id_reserva = :v_res
ORDER  BY rh.fecha_checkin;

PROMPT ================================================================
PROMPT  T3. Disparador de fila TRG_RH_NO_SOLAPE (sin pasar por el paquete)
PROMPT ================================================================

PROMPT Se crea a mano un encabezado CONFIRMADO del 19 al 23 de enero
BEGIN
   INSERT INTO reserva (id_cliente, id_alojamiento, fecha_checkin, fecha_checkout, estado, observaciones)
   VALUES (:v_cli, :v_aloj, DATE '2027-01-19', DATE '2027-01-23', 'CONFIRMADA', 'PRUEBA E2 - insercion directa')
   RETURNING id_reserva INTO :v_res2;
   COMMIT;
   DBMS_OUTPUT.PUT_LINE('Encabezado ' || :v_res2 || ' creado');
END;
/

PROMPT T3.1 Error esperado -20001: INSERT directo de la habitación de prueba del 19 al 20 (choca con T2.1)
BEGIN
   INSERT INTO reserva_habitacion (id_reserva, id_alojamiento, id_habitacion, fecha_checkin,
                                   fecha_checkout, num_huespedes, valor_estadia)
   VALUES (:v_res2, :v_aloj, :v_hab, DATE '2027-01-19', DATE '2027-01-20', 1,
           pkg_turismouq.fn_valor_estadia(:v_hab, DATE '2027-01-19', DATE '2027-01-20'));
   DBMS_OUTPUT.PUT_LINE('FALLA: el disparador dejó pasar el solape');
EXCEPTION
   WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE(CASE WHEN SQLCODE = -20001 THEN 'OK (bloqueado por el disparador) -> '
                                ELSE 'FALLA: error inesperado -> ' END || SQLERRM);
END;
/

PROMPT T3.2 Caso borde: entrar el 21 (el día en que sale T2.1) SÍ se permite
BEGIN
   INSERT INTO reserva_habitacion (id_reserva, id_alojamiento, id_habitacion, fecha_checkin,
                                   fecha_checkout, num_huespedes, valor_estadia)
   VALUES (:v_res2, :v_aloj, :v_hab, DATE '2027-01-21', DATE '2027-01-23', 1,
           pkg_turismouq.fn_valor_estadia(:v_hab, DATE '2027-01-21', DATE '2027-01-23'));
   COMMIT;
   DBMS_OUTPUT.PUT_LINE('OK: línea del 21 al 23 registrada (no hay solape)');
EXCEPTION
   WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FALLA: ' || SQLERRM);
END;
/

PROMPT T3.3 Error esperado -20001: UPDATE que corre esa línea al 20 (también se valida, sin ORA-04091)
BEGIN
   UPDATE reserva_habitacion
   SET    fecha_checkin = DATE '2027-01-20'
   WHERE  id_reserva = :v_res2;
   DBMS_OUTPUT.PUT_LINE('FALLA: el disparador dejó pasar el solape');
EXCEPTION
   WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE(CASE WHEN SQLCODE = -20001 THEN 'OK (bloqueado por el disparador) -> '
                                ELSE 'FALLA: error inesperado -> ' END || SQLERRM);
END;
/

PROMPT ================================================================
PROMPT  T4. Cursor explícito con parámetros: liquidación mensual
PROMPT ================================================================

PROMPT T4.1 Liquidación de diciembre de 2025 para todos los alojamientos
BEGIN
   pkg_turismouq.sp_liquidacion_mensual(2025, 12);
END;
/

PROMPT T4.2 Control cruzado: el hospedaje liquidado coincide con la vista materializada
DECLARE
   v_liq NUMBER;
   v_mv  NUMBER;
   v_n   NUMBER;
BEGIN
   SELECT SUM(ingreso_hospedaje), COUNT(*) INTO v_liq, v_n
   FROM   liquidacion_mensual WHERE anio = 2025 AND mes = 12;
   SELECT SUM(ingreso_hospedaje) INTO v_mv
   FROM   mv_ocupacion_mensual WHERE anio = 2025 AND mes = 12;
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_liq = v_mv AND v_n = 60 THEN 'OK' ELSE 'FALLA' END
      || ': ' || v_n || ' alojamientos liquidados, hospedaje ' || v_liq || ' = ' || v_mv);
END;
/

PROMPT T4.3 Los 5 alojamientos con mayor neto en diciembre de 2025
SELECT *
FROM  (SELECT a.nombre_comercial, l.reservas, l.noches_vendidas, l.ingreso_hospedaje,
              l.ingreso_servicios, l.ingreso_cancelaciones, l.total_bruto,
              l.comision_plataforma, l.neto_alojamiento
       FROM   liquidacion_mensual l
       JOIN   alojamiento a ON a.id_alojamiento = l.id_alojamiento
       WHERE  l.anio = 2025 AND l.mes = 12
       ORDER  BY l.neto_alojamiento DESC)
WHERE ROWNUM <= 5;

PROMPT T4.4 Reliquidar un solo alojamiento (parámetro opcional) no duplica filas
BEGIN
   pkg_turismouq.sp_liquidacion_mensual(2025, 12, :v_aloj);
END;
/
SELECT COUNT(*) AS filas_dic_2025 FROM liquidacion_mensual WHERE anio = 2025 AND mes = 12;

PROMPT ================================================================
PROMPT  T5. Disparador de sentencia: auditoría de TARIFA
PROMPT ================================================================

PROMPT T5.1 Subir 10.000 la tarifa de la habitación de prueba en las temporadas ALTA de 2026
UPDATE tarifa
SET    valor_noche = valor_noche + 10000
WHERE  id_habitacion = :v_hab
AND    id_temporada IN (SELECT id_temporada FROM temporada WHERE anio = 2026 AND categoria = 'ALTA');
COMMIT;

BEGIN
   SELECT MAX(id_operacion) INTO :v_op FROM auditoria_tarifa_operacion;
END;
/

PROMPT Encabezado de la operación (quién, cuándo, desde dónde, cuántas filas)
SELECT id_operacion, operacion, filas_afectadas, usuario_bd, usuario_so, equipo, programa,
       TO_CHAR(fecha_hora, 'YYYY-MM-DD HH24:MI:SS.FF3') AS fecha_hora
FROM   auditoria_tarifa_operacion
WHERE  id_operacion = :v_op;

PROMPT Detalle: valor anterior y nuevo de cada tarifa
SELECT d.id_tarifa, t.nombre AS temporada, d.valor_anterior, d.valor_nuevo, d.diferencia
FROM   auditoria_tarifa_detalle d
JOIN   temporada t ON t.id_temporada = d.id_temporada
WHERE  d.id_operacion = :v_op
ORDER  BY t.fecha_inicio;

PROMPT T5.2 Un UPDATE que no cambia nada también queda auditado (0 filas)
UPDATE tarifa SET valor_noche = valor_noche WHERE id_tarifa = -1;
COMMIT;

PROMPT T5.3 Restaurar las tarifas usando la propia auditoría (también se audita)
UPDATE tarifa t
SET    t.valor_noche = (SELECT d.valor_anterior
                        FROM   auditoria_tarifa_detalle d
                        WHERE  d.id_operacion = :v_op
                        AND    d.id_tarifa    = t.id_tarifa)
WHERE  t.id_tarifa IN (SELECT id_tarifa FROM auditoria_tarifa_detalle WHERE id_operacion = :v_op);
COMMIT;

DECLARE
   v_filas1 NUMBER;
   v_det    NUMBER;
BEGIN
   SELECT filas_afectadas INTO v_filas1 FROM auditoria_tarifa_operacion WHERE id_operacion = :v_op;
   SELECT COUNT(*) INTO v_det FROM auditoria_tarifa_detalle WHERE id_operacion = :v_op;
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_filas1 = v_det AND v_det > 0 THEN 'OK' ELSE 'FALLA' END
      || ': la operación ' || :v_op || ' registró ' || v_filas1 || ' filas y ' || v_det || ' detalles');
END;
/

PROMPT Últimas operaciones auditadas
SELECT *
FROM  (SELECT id_operacion, operacion, filas_afectadas, usuario_bd,
              TO_CHAR(fecha_hora, 'YYYY-MM-DD HH24:MI:SS') AS fecha_hora
       FROM   auditoria_tarifa_operacion
       ORDER  BY id_operacion DESC)
WHERE ROWNUM <= 3;

PROMPT ================================================================
PROMPT  T6. Cancelación (regla del 80 %) y reserva pagada
PROMPT ================================================================

PROMPT T6.1 Pago de anticipo y cancelación con más de 5 días -> reembolso del 80 %
BEGIN
   INSERT INTO pago (id_reserva, fecha_pago, monto, metodo, estado, concepto, referencia)
   VALUES (:v_res, SYSDATE, 300000, 'PSE', 'EXITOSO', 'ANTICIPO', 'PRUEBA-E2-' || :v_res || '-1');
   pkg_turismouq.sp_cancelar_reserva(:v_res);
   COMMIT;
END;
/
SELECT id_pago, monto, estado, monto_reembolsado, fecha_reembolso,
       CASE WHEN estado = 'REEMBOLSADO' AND monto_reembolsado = ROUND(monto * 0.8, 2)
            THEN 'OK' ELSE 'FALLA' END AS verificacion
FROM   pago WHERE id_reserva = :v_res;

PROMPT T6.2 Reserva nueva (25-27 ene), pago y cancelación el 23 de enero (2 días antes) -> sin reembolso
DECLARE
   v_id NUMBER;
BEGIN
   pkg_turismouq.sp_crear_reserva(:v_cli, :v_hab, DATE '2027-01-25', DATE '2027-01-27', 2,
                                  v_id, 'CONFIRMADA', 'PRUEBA E2 - cancelacion tardia');
   :v_res3 := v_id;
   INSERT INTO pago (id_reserva, fecha_pago, monto, metodo, estado, concepto, referencia)
   VALUES (v_id, SYSDATE, 200000, 'TARJETA_CREDITO', 'EXITOSO', 'ANTICIPO', 'PRUEBA-E2-' || v_id || '-1');
   pkg_turismouq.sp_cancelar_reserva(v_id, DATE '2027-01-23' + 10 / 24);
   COMMIT;
END;
/
SELECT id_pago, monto, estado, monto_reembolsado,
       CASE WHEN estado = 'EXITOSO' AND monto_reembolsado = 0 THEN 'OK' ELSE 'FALLA' END AS verificacion
FROM   pago WHERE id_reserva = :v_res3;

PROMPT T6.3 Error esperado -20006: cancelar otra vez una reserva cancelada
BEGIN
   pkg_turismouq.sp_cancelar_reserva(:v_res);
   DBMS_OUTPUT.PUT_LINE('FALLA: no se lanzó el error');
EXCEPTION
   WHEN pkg_turismouq.ex_estado THEN DBMS_OUTPUT.PUT_LINE('OK (error esperado) -> ' || SQLERRM);
   WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FALLA: error inesperado -> ' || SQLERRM);
END;
/

PROMPT T6.4 Una reserva cancelada libera la habitación: 18-21 ene se puede volver a reservar
DECLARE
   v_id NUMBER;
BEGIN
   pkg_turismouq.sp_crear_reserva(:v_cli, :v_hab, DATE '2027-01-18', DATE '2027-01-21', 2,
                                  v_id, 'CONFIRMADA', 'PRUEBA E2 - habitacion liberada');
   :v_res4 := v_id;
   DBMS_OUTPUT.PUT_LINE('Pagada antes de pagar: ' || pkg_turismouq.fn_esta_pagada(v_id));
   INSERT INTO pago (id_reserva, fecha_pago, monto, metodo, estado, concepto, referencia)
   VALUES (v_id, SYSDATE, pkg_turismouq.fn_total_reserva(v_id), 'TRANSFERENCIA', 'EXITOSO', 'TOTAL',
           'PRUEBA-E2-' || v_id || '-1');
   COMMIT;
   DBMS_OUTPUT.PUT_LINE(CASE WHEN pkg_turismouq.fn_esta_pagada(v_id) = 'S' THEN 'OK' ELSE 'FALLA' END
      || ': reserva ' || v_id || ' total ' || pkg_turismouq.fn_total_reserva(v_id)
      || ', pagado ' || pkg_turismouq.fn_total_pagado(v_id) || ', pagada = ' || pkg_turismouq.fn_esta_pagada(v_id));
EXCEPTION
   WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FALLA: ' || SQLERRM);
END;
/

PROMPT ================================================================
PROMPT  T7. Tablespace propio e histórico
PROMPT ================================================================
SELECT table_name, tablespace_name FROM user_tables
WHERE  table_name IN ('RESERVA', 'RESERVA_HISTORICO') ORDER BY table_name;

SELECT segment_name, segment_type, tablespace_name, ROUND(bytes / 1024 / 1024, 2) AS mb
FROM   user_segments
WHERE  tablespace_name = 'TS_TURISMOUQ_HIST'
ORDER  BY segment_name;

PROMPT T7.1 Archivar de nuevo 2024 no duplica (debe reportar 0 líneas)
BEGIN
   sp_archivar_reservas(2024);
END;
/

PROMPT T7.2 Lo archivado coincide con las líneas cerradas de 2024 en las tablas operativas
DECLARE
   v_hist NUMBER;
   v_oper NUMBER;
BEGIN
   SELECT COUNT(*) INTO v_hist FROM reserva_historico WHERE anio_cierre = 2024;
   SELECT COUNT(*) INTO v_oper
   FROM   reserva r JOIN reserva_habitacion rh ON rh.id_reserva = r.id_reserva
   WHERE  r.estado IN ('COMPLETADA', 'CANCELADA')
   AND    r.fecha_checkout >= DATE '2024-01-01' AND r.fecha_checkout < DATE '2025-01-01';
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_hist = v_oper THEN 'OK' ELSE 'FALLA' END
      || ': histórico 2024 = ' || v_hist || ' líneas, operativas cerradas 2024 = ' || v_oper);
END;
/

PROMPT T7.3 Error esperado -20008: no se archiva el año en curso
BEGIN
   sp_archivar_reservas(EXTRACT(YEAR FROM SYSDATE));
   DBMS_OUTPUT.PUT_LINE('FALLA: no se lanzó el error');
EXCEPTION
   WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE(CASE WHEN SQLCODE = -20008 THEN 'OK (error esperado) -> '
                                ELSE 'FALLA: error inesperado -> ' END || SQLERRM);
END;
/

PROMPT ================================================================
PROMPT  T8. Vista materializada MV_OCUPACION_MENSUAL
PROMPT ================================================================

PROMPT T8.1 Las reservas de prueba de enero de 2027 todavía NO están en la vista (ON DEMAND)
DECLARE
   v_mv    NUMBER;
   v_base  NUMBER;
   v_stale VARCHAR2(30);
BEGIN
   SELECT noches_ocupadas INTO v_mv
   FROM   mv_ocupacion_mensual WHERE id_alojamiento = :v_aloj AND anio = 2027 AND mes = 1;

   SELECT COUNT(*) INTO v_base
   FROM   reserva_habitacion rh
   JOIN   reserva r    ON r.id_reserva = rh.id_reserva
   JOIN   calendario c ON c.fecha >= rh.fecha_checkin AND c.fecha < rh.fecha_checkout
   WHERE  rh.id_alojamiento = :v_aloj AND r.estado IN ('CONFIRMADA', 'COMPLETADA')
   AND    c.anio = 2027 AND c.mes = 1;

   SELECT staleness INTO v_stale FROM user_mviews WHERE mview_name = 'MV_OCUPACION_MENSUAL';
   DBMS_OUTPUT.PUT_LINE('Antes del refresco: vista = ' || v_mv || ' noches, tablas base = ' || v_base
                        || ', staleness = ' || v_stale);
END;
/

PROMPT T8.2 Refresco completo manual y comparación
DECLARE
   v_mv   NUMBER;
   v_base NUMBER;
   v_t0   NUMBER := DBMS_UTILITY.GET_TIME;
BEGIN
   DBMS_MVIEW.REFRESH(list => 'MV_OCUPACION_MENSUAL', method => 'C');
   DBMS_OUTPUT.PUT_LINE('Refresco completo en ' || (DBMS_UTILITY.GET_TIME - v_t0) / 100 || ' s');

   SELECT noches_ocupadas INTO v_mv
   FROM   mv_ocupacion_mensual WHERE id_alojamiento = :v_aloj AND anio = 2027 AND mes = 1;
   SELECT COUNT(*) INTO v_base
   FROM   reserva_habitacion rh
   JOIN   reserva r    ON r.id_reserva = rh.id_reserva
   JOIN   calendario c ON c.fecha >= rh.fecha_checkin AND c.fecha < rh.fecha_checkout
   WHERE  rh.id_alojamiento = :v_aloj AND r.estado IN ('CONFIRMADA', 'COMPLETADA')
   AND    c.anio = 2027 AND c.mes = 1;
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_mv = v_base THEN 'OK' ELSE 'FALLA' END
      || ': después del refresco, vista = ' || v_mv || ' noches, tablas base = ' || v_base);
END;
/

SELECT mview_name, refresh_method, refresh_mode, last_refresh_date, staleness
FROM   user_mviews WHERE mview_name = 'MV_OCUPACION_MENSUAL';

PROMPT T8.3 Ocupación mensual de 2025 del alojamiento de prueba leída de la vista (rápido)
SET TIMING ON
SELECT mes, habitaciones, noches_disponibles, noches_ocupadas, pct_ocupacion, ingreso_hospedaje
FROM   mv_ocupacion_mensual
WHERE  id_alojamiento = :v_aloj AND anio = 2025
ORDER  BY mes;
SET TIMING OFF

PROMPT ================================================================
PROMPT  Fin de las pruebas. Revise que no aparezca ninguna línea "FALLA".
PROMPT ================================================================
