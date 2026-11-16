/* =====================================================================
   TurismoUQ · Proyecto integrador Bases de Datos II · 2026-2
   Script 11 · Índices: plan de ejecución antes y después (Entrega 3)
   ---------------------------------------------------------------------
   Ejecutar como TURISMOUQ con F5 (Ejecutar script), después de 01 a 09.
   Tarda cerca de un minuto (ejecuta cada consulta cientos de veces para
   medirla). La salida completa es la evidencia: de aquí salen las
   capturas de EXPLAIN PLAN antes / después.

   Punto de partida: RESERVA, RESERVA_HABITACION y PAGO solo tienen los
   índices que Oracle crea para sus PK y UNIQUE. Ninguna de sus FK ni de
   sus columnas de fecha está indexada.

   Las tres consultas lentas (se eligieron por ser las que MÁS se repiten
   en la operación, no por ser las más largas):

     C1  Disponibilidad de una habitación en un rango de noches.
         La ejecutan sp_crear_reserva, sp_agregar_habitacion y el
         disparador anti-solape en CADA reserva.
         -> índice COMPUESTO  ix_rh_hab_fechas
            reserva_habitacion (id_habitacion, fecha_checkin, fecha_checkout)

     C2  Cuadre de caja de un día: pagos exitosos por método.
         La consulta filtra por TRUNC(fecha_pago) porque fecha_pago
         guarda hora; un índice normal sobre fecha_pago no sirve cuando
         la columna va dentro de una función.
         -> índice BASADO EN FUNCIÓN  ix_pago_dia
            pago (TRUNC(fecha_pago))

     C3  Total pagado de una reserva (fn_total_pagado, sp_registrar_pago,
         vistas de recepción). PAGO.id_reserva es una FK sin índice.
         -> índice COMPUESTO que además CUBRE la consulta  ix_pago_reserva
            pago (id_reserva, estado, monto)
            Oracle responde solo con el índice, sin tocar la tabla.
            Indexar la FK evita también el bloqueo de tabla completa
            sobre PAGO cuando se borra o se cambia la PK de una RESERVA.

   El caso donde el índice NO ayuda (sección 6):
     C4  Reservas COMPLETADAS (la gran mayoría de la tabla) con un índice
         sobre RESERVA.estado, columna de solo 4 valores.

   Cómo se mide (procedimiento sp_medir_indice)
     · EXPLAIN PLAN de la consulta -> costo estimado y operaciones.
     · Tiempo real de N ejecuciones con valores distintos del parámetro.
     · Todo queda en la tabla INDICE_MEDICION y al final se compara.
     El plan completo de cada caso se imprime con DBMS_XPLAN.DISPLAY.
   ===================================================================== */

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET SQLBLANKLINES ON
SET LINESIZE 200
SET PAGESIZE 200
SET TRIMSPOOL ON
COLUMN plan_table_output FORMAT A160
COLUMN titulo            FORMAT A60
COLUMN operaciones       FORMAT A90
COLUMN momento           FORMAT A16
COLUMN veredicto         FORMAT A70

/* =====================================================================
   Sección 0. Base limpia: se quitan los índices y tablas de este script
   ===================================================================== */
DECLARE
   PROCEDURE quitar (p_sql VARCHAR2, p_codigo NUMBER) IS
   BEGIN
      EXECUTE IMMEDIATE p_sql;
   EXCEPTION
      WHEN OTHERS THEN IF SQLCODE <> p_codigo THEN RAISE; END IF;
   END;
BEGIN
   quitar('DROP INDEX ix_rh_hab_fechas',  -1418);     -- ORA-01418: el índice no existe
   quitar('DROP INDEX ix_pago_dia',       -1418);
   quitar('DROP INDEX ix_pago_reserva',   -1418);
   quitar('DROP INDEX ix_reserva_estado', -1418);
   quitar('DROP TABLE indice_medicion PURGE', -942);
   quitar('DROP TABLE indice_caso PURGE',     -942);
END;
/

/* =====================================================================
   Sección 1. Catálogo de casos y tabla de mediciones
   ---------------------------------------------------------------------
   sql_texto lleva la marca #B# donde va el parámetro. Para el plan se
   reemplaza por un valor concreto (literal_plan); para medir tiempos se
   reemplaza por una variable de enlace y se ejecuta una vez por cada
   valor que devuelve sql_muestras.
   tipo_bind: N = número, D = fecha, X = la consulta no lleva parámetro.
   ===================================================================== */
CREATE TABLE indice_caso (
   caso          NUMBER(2)       NOT NULL,
   titulo        VARCHAR2(100)   NOT NULL,
   sql_texto     VARCHAR2(1000)  NOT NULL,
   tipo_bind     CHAR(1)         NOT NULL,
   literal_plan  VARCHAR2(60),
   sql_muestras  VARCHAR2(500),
   repeticiones  NUMBER(5)       DEFAULT 1 NOT NULL,
   CONSTRAINT pk_indice_caso      PRIMARY KEY (caso),
   CONSTRAINT ck_indice_caso_tipo CHECK (tipo_bind IN ('N', 'D', 'X'))
);

CREATE TABLE indice_medicion (
   caso          NUMBER(2)       NOT NULL,
   momento       VARCHAR2(16)    NOT NULL,
   costo         NUMBER,
   operaciones   VARCHAR2(600),
   ejecuciones   NUMBER(6),
   milisegundos  NUMBER(10),
   fecha         DATE            DEFAULT SYSDATE NOT NULL,
   CONSTRAINT pk_indice_medicion PRIMARY KEY (caso, momento),
   CONSTRAINT fk_indice_medicion FOREIGN KEY (caso) REFERENCES indice_caso (caso)
);

COMMENT ON TABLE indice_caso     IS 'Entrega 3: consultas que se miden antes y después de crear índices.';
COMMENT ON TABLE indice_medicion IS 'Entrega 3: costo del plan, operaciones y tiempo de cada consulta en cada momento.';

-- C1: disponibilidad de una habitación del 1 al 10 de julio de 2026
INSERT INTO indice_caso (caso, titulo, sql_texto, tipo_bind, literal_plan, sql_muestras)
SELECT 1, 'C1 Disponibilidad de una habitación (compuesto)',
       'SELECT rh.id_reserva, rh.fecha_checkin, rh.fecha_checkout '
    || 'FROM reserva_habitacion rh '
    || 'WHERE rh.id_habitacion = #B# '
    || 'AND rh.fecha_checkin < DATE ''2026-07-10'' '
    || 'AND rh.fecha_checkout > DATE ''2026-07-01''',
       'N',
       TO_CHAR(MIN(h.id_habitacion)),
       'SELECT id_habitacion FROM habitacion WHERE ROWNUM <= 500'
FROM   habitacion h JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
WHERE  a.nombre_comercial = 'Hotel Mirador del Parque Sucre';

-- C2: cuadre de caja de un día
INSERT INTO indice_caso (caso, titulo, sql_texto, tipo_bind, literal_plan, sql_muestras)
VALUES (2, 'C2 Cuadre de caja de un día (basado en función)',
       'SELECT p.metodo, COUNT(*) AS pagos, SUM(p.monto) AS recaudo '
    || 'FROM pago p '
    || 'WHERE TRUNC(p.fecha_pago) = #B# '
    || 'AND p.estado = ''EXITOSO'' '
    || 'GROUP BY p.metodo',
       'D',
       'DATE ''2025-12-20''',
       'SELECT dia FROM (SELECT DISTINCT TRUNC(fecha_pago) AS dia FROM pago) WHERE ROWNUM <= 300');

-- C3: total pagado de una reserva
INSERT INTO indice_caso (caso, titulo, sql_texto, tipo_bind, literal_plan, sql_muestras)
SELECT 3, 'C3 Total pagado de una reserva (compuesto que cubre)',
       'SELECT NVL(SUM(p.monto), 0) AS pagado '
    || 'FROM pago p '
    || 'WHERE p.id_reserva = #B# '
    || 'AND p.estado = ''EXITOSO''',
       'N',
       TO_CHAR(MAX(id_reserva)),
       'SELECT id_reserva FROM reserva WHERE ROWNUM <= 1000'
FROM   reserva
WHERE  estado = 'COMPLETADA';

-- C4: el caso donde el índice no ayuda (estado = COMPLETADA, la mayoría de las filas)
INSERT INTO indice_caso (caso, titulo, sql_texto, tipo_bind, repeticiones)
VALUES (4, 'C4 Reservas COMPLETADAS (índice que NO ayuda)',
       'SELECT COUNT(*) AS reservas, SUM(r.fecha_checkout - r.fecha_checkin) AS noches '
    || 'FROM reserva r '
    || 'WHERE r.estado = ''COMPLETADA''',
       'X', 40);

-- C5: la misma consulta de C4, OBLIGANDO a Oracle a usar el índice con un hint
INSERT INTO indice_caso (caso, titulo, sql_texto, tipo_bind, repeticiones)
VALUES (5, 'C5 La misma C4 forzando el índice con un hint',
       'SELECT /*+ INDEX(r ix_reserva_estado) */ COUNT(*) AS reservas, SUM(r.fecha_checkout - r.fecha_checkin) AS noches '
    || 'FROM reserva r '
    || 'WHERE r.estado = ''COMPLETADA''',
       'X', 40);

-- C6: el mismo índice con un valor poco frecuente (PENDIENTE)
INSERT INTO indice_caso (caso, titulo, sql_texto, tipo_bind, repeticiones)
VALUES (6, 'C6 El mismo índice con un valor escaso (PENDIENTE)',
       'SELECT COUNT(*) AS reservas, SUM(r.fecha_checkout - r.fecha_checkin) AS noches '
    || 'FROM reserva r '
    || 'WHERE r.estado = ''PENDIENTE''',
       'X', 40);
COMMIT;

/* ---------------------------------------------------------------------
   sp_medir_indice: plan (costo + operaciones) y tiempo de un caso
   --------------------------------------------------------------------- */
CREATE OR REPLACE PROCEDURE sp_medir_indice (p_caso IN NUMBER, p_momento IN VARCHAR2) IS
   TYPE t_nums   IS TABLE OF NUMBER;
   TYPE t_fechas IS TABLE OF DATE;
   v_caso     indice_caso%ROWTYPE;
   v_id       VARCHAR2(30) := 'E3_C' || p_caso || '_' || p_momento;
   v_sql_plan VARCHAR2(1200);
   v_sql_exec VARCHAR2(1200);
   v_nums     t_nums;
   v_fechas   t_fechas;
   v_costo    NUMBER;
   v_oper     VARCHAR2(600);
   v_n        PLS_INTEGER := 0;
   v_dummy    NUMBER;
   v_t0       TIMESTAMP WITH TIME ZONE;
   v_dif      INTERVAL DAY TO SECOND;
   v_ms       NUMBER;
BEGIN
   SELECT * INTO v_caso FROM indice_caso WHERE caso = p_caso;

   -- 1. Plan estimado
   v_sql_plan := REPLACE(v_caso.sql_texto, '#B#', v_caso.literal_plan);
   DELETE FROM plan_table WHERE statement_id = v_id;
   EXECUTE IMMEDIATE 'EXPLAIN PLAN SET STATEMENT_ID = ''' || v_id || ''' FOR ' || v_sql_plan;

   SELECT MAX(CASE WHEN id = 0 THEN cost END),
          LISTAGG(CASE WHEN object_name IS NOT NULL
                       THEN operation || ' ' || options || ' (' || object_name || ')' END, ' + ')
             WITHIN GROUP (ORDER BY id)
   INTO   v_costo, v_oper
   FROM   plan_table
   WHERE  statement_id = v_id;

   -- 2. Tiempo real: se ejecuta la consulta completa una vez por valor de muestra
   v_sql_exec := 'SELECT COUNT(*) FROM (' || REPLACE(v_caso.sql_texto, '#B#', ':b') || ')';
   v_t0 := SYSTIMESTAMP;
   IF v_caso.tipo_bind = 'N' THEN
      EXECUTE IMMEDIATE v_caso.sql_muestras BULK COLLECT INTO v_nums;
      v_t0 := SYSTIMESTAMP;
      FOR i IN 1 .. v_nums.COUNT LOOP
         EXECUTE IMMEDIATE v_sql_exec INTO v_dummy USING v_nums(i);
      END LOOP;
      v_n := v_nums.COUNT;
   ELSIF v_caso.tipo_bind = 'D' THEN
      EXECUTE IMMEDIATE v_caso.sql_muestras BULK COLLECT INTO v_fechas;
      v_t0 := SYSTIMESTAMP;
      FOR i IN 1 .. v_fechas.COUNT LOOP
         EXECUTE IMMEDIATE v_sql_exec INTO v_dummy USING v_fechas(i);
      END LOOP;
      v_n := v_fechas.COUNT;
   ELSE
      FOR i IN 1 .. v_caso.repeticiones LOOP
         EXECUTE IMMEDIATE v_sql_exec INTO v_dummy;
      END LOOP;
      v_n := v_caso.repeticiones;
   END IF;
   v_dif := SYSTIMESTAMP - v_t0;
   v_ms  := ROUND(  EXTRACT(DAY    FROM v_dif) * 86400000
                  + EXTRACT(HOUR   FROM v_dif) * 3600000
                  + EXTRACT(MINUTE FROM v_dif) * 60000
                  + EXTRACT(SECOND FROM v_dif) * 1000);

   -- 3. Registro
   DELETE FROM indice_medicion WHERE caso = p_caso AND momento = p_momento;
   INSERT INTO indice_medicion (caso, momento, costo, operaciones, ejecuciones, milisegundos)
   VALUES (p_caso, p_momento, v_costo, v_oper, v_n, v_ms);
   COMMIT;

   DBMS_OUTPUT.PUT_LINE(v_caso.titulo || ' [' || p_momento || ']');
   DBMS_OUTPUT.PUT_LINE('   costo estimado = ' || v_costo || '   |   ' || v_n || ' ejecuciones en ' || v_ms || ' ms');
   DBMS_OUTPUT.PUT_LINE('   acceso: ' || v_oper);
END sp_medir_indice;
/
SHOW ERRORS PROCEDURE sp_medir_indice

-- Estadísticas al día antes de pedir planes
BEGIN
   DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA_HABITACION', cascade => TRUE);
   DBMS_STATS.GATHER_TABLE_STATS(USER, 'PAGO',               cascade => TRUE);
   DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA',            cascade => TRUE);
END;
/

PROMPT Tamaño de las tablas involucradas e índices que existen ANTES
SELECT table_name, num_rows, blocks FROM user_tables
WHERE  table_name IN ('RESERVA', 'RESERVA_HABITACION', 'PAGO')
ORDER  BY table_name;

SELECT i.table_name, i.index_name, i.uniqueness,
       LISTAGG(c.column_name, ', ') WITHIN GROUP (ORDER BY c.column_position) AS columnas
FROM   user_indexes i JOIN user_ind_columns c ON c.index_name = i.index_name
WHERE  i.table_name IN ('RESERVA', 'RESERVA_HABITACION', 'PAGO')
GROUP  BY i.table_name, i.index_name, i.uniqueness
ORDER  BY i.table_name, i.index_name;

/* =====================================================================
   Sección 2. ANTES: plan y tiempo de las tres consultas sin índices
   ===================================================================== */
PROMPT ================================================================
PROMPT  ANTES · C1 Disponibilidad de una habitación
PROMPT ================================================================
SELECT sql_texto FROM indice_caso WHERE caso = 1;
EXEC sp_medir_indice(1, 'ANTES')
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'E3_C1_ANTES', 'TYPICAL'));

PROMPT ================================================================
PROMPT  ANTES · C2 Cuadre de caja de un día
PROMPT ================================================================
SELECT sql_texto FROM indice_caso WHERE caso = 2;
EXEC sp_medir_indice(2, 'ANTES')
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'E3_C2_ANTES', 'TYPICAL'));

PROMPT ================================================================
PROMPT  ANTES · C3 Total pagado de una reserva
PROMPT ================================================================
SELECT sql_texto FROM indice_caso WHERE caso = 3;
EXEC sp_medir_indice(3, 'ANTES')
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'E3_C3_ANTES', 'TYPICAL'));

/* =====================================================================
   Sección 3. Creación de los índices
   ===================================================================== */
PROMPT ================================================================
PROMPT  Creación de los índices
PROMPT ================================================================

-- C1 · COMPUESTO. El orden de las columnas importa: primero la de igualdad
-- (id_habitacion), después las de rango (fechas). Oracle baja por el árbol
-- hasta la habitación y allí recorre solo sus reservas ordenadas por fecha.
CREATE INDEX ix_rh_hab_fechas
   ON reserva_habitacion (id_habitacion, fecha_checkin, fecha_checkout);

-- C2 · BASADO EN FUNCIÓN. Guarda el resultado de TRUNC(fecha_pago) ya
-- calculado y ordenado; el predicado TRUNC(fecha_pago) = :dia lo usa tal cual.
CREATE INDEX ix_pago_dia
   ON pago (TRUNC(fecha_pago));

-- C3 · COMPUESTO que cubre la consulta: id_reserva para llegar, estado para
-- filtrar y monto para sumar. No hace falta leer la tabla (index-only).
CREATE INDEX ix_pago_reserva
   ON pago (id_reserva, estado, monto);

-- Las estadísticas deben incluir los índices nuevos (y la columna oculta
-- que Oracle crea para el índice basado en función)
BEGIN
   DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA_HABITACION', cascade => TRUE);
   DBMS_STATS.GATHER_TABLE_STATS(USER, 'PAGO',               cascade => TRUE);
END;
/

SELECT i.index_name, i.index_type, i.blevel AS altura, i.leaf_blocks AS hojas,
       i.distinct_keys AS claves_distintas, i.clustering_factor,
       LISTAGG(NVL(e.column_expression_txt, c.column_name), ', ') WITHIN GROUP (ORDER BY c.column_position) AS columnas
FROM   user_indexes i
JOIN   user_ind_columns c ON c.index_name = i.index_name
LEFT   JOIN (SELECT index_name, column_position, 'TRUNC(FECHA_PAGO)' AS column_expression_txt
             FROM   user_ind_expressions
             WHERE  index_name = 'IX_PAGO_DIA') e
            ON e.index_name = c.index_name AND e.column_position = c.column_position
WHERE  i.index_name IN ('IX_RH_HAB_FECHAS', 'IX_PAGO_DIA', 'IX_PAGO_RESERVA')
GROUP  BY i.index_name, i.index_type, i.blevel, i.leaf_blocks, i.distinct_keys, i.clustering_factor
ORDER  BY i.index_name;

/* =====================================================================
   Sección 4. DESPUÉS: las mismas consultas con los índices
   ===================================================================== */
PROMPT ================================================================
PROMPT  DESPUÉS · C1 Disponibilidad de una habitación
PROMPT ================================================================
EXEC sp_medir_indice(1, 'DESPUES')
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'E3_C1_DESPUES', 'TYPICAL'));

PROMPT ================================================================
PROMPT  DESPUÉS · C2 Cuadre de caja de un día
PROMPT ================================================================
EXEC sp_medir_indice(2, 'DESPUES')
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'E3_C2_DESPUES', 'TYPICAL'));

PROMPT ================================================================
PROMPT  DESPUÉS · C3 Total pagado de una reserva
PROMPT ================================================================
EXEC sp_medir_indice(3, 'DESPUES')
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'E3_C3_DESPUES', 'TYPICAL'));

/* =====================================================================
   Sección 5. Comparación antes / después
   ===================================================================== */
PROMPT ================================================================
PROMPT  COMPARACIÓN ANTES / DESPUÉS (costo del plan y tiempo real)
PROMPT ================================================================
SELECT c.titulo,
       a.costo                                   AS costo_antes,
       d.costo                                   AS costo_despues,
       ROUND(a.costo / NULLIF(d.costo, 0), 1)    AS veces_menor_costo,
       a.ejecuciones                             AS ejecuciones,
       a.milisegundos                            AS ms_antes,
       d.milisegundos                            AS ms_despues,
       ROUND(a.milisegundos / NULLIF(d.milisegundos, 0), 1) AS veces_mas_rapida
FROM   indice_caso c
JOIN   indice_medicion a ON a.caso = c.caso AND a.momento = 'ANTES'
JOIN   indice_medicion d ON d.caso = c.caso AND d.momento = 'DESPUES'
WHERE  c.caso IN (1, 2, 3)
ORDER  BY c.caso;

SELECT m.caso, m.momento, m.operaciones
FROM   indice_medicion m
WHERE  m.caso IN (1, 2, 3)
ORDER  BY m.caso, m.momento;

/* =====================================================================
   Sección 6. El caso donde el índice NO ayuda
   ---------------------------------------------------------------------
   RESERVA.estado tiene 4 valores y COMPLETADA es la gran mayoría de las
   filas. Se crea un índice sobre estado y se pide el conteo y las noches
   de las COMPLETADAS.

   Por qué no sirve:
     · Selectividad: un índice ayuda cuando descarta casi toda la tabla.
       Aquí el filtro deja pasar la mayoría de las filas.
     · Costo de ir a la tabla: por cada entrada del índice Oracle debe
       visitar el bloque de la tabla donde está la fila (un bloque a la
       vez). Las COMPLETADAS están repartidas por todos los bloques
       (clustering factor alto), así que se terminan leyendo todos los
       bloques de la tabla, varios de ellos muchas veces, MÁS el índice.
     · El recorrido completo (FULL) lee cada bloque una sola vez y de a
       varios bloques por lectura (multibloque).
   Por eso el optimizador ignora el índice (C4) y, si se le obliga con un
   hint (C5), el costo y el tiempo empeoran. El índice no es "malo" en
   sí: para un valor escaso como PENDIENTE (C6) sí puede convenir; lo
   que decide es cuántas filas devuelve el filtro.
   Además un índice no es gratis: ocupa espacio y cada INSERT / UPDATE de
   estado tendría que mantenerlo. Como no aporta, al final se elimina.
   ===================================================================== */
PROMPT ================================================================
PROMPT  CASO DONDE EL ÍNDICE NO AYUDA · reservas por estado
PROMPT ================================================================
SELECT estado, COUNT(*) AS filas, ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS pct
FROM   reserva
GROUP  BY estado
ORDER  BY filas DESC;

PROMPT --- C4 sin índice
EXEC sp_medir_indice(4, 'SIN_INDICE')
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'E3_C4_SIN_INDICE', 'TYPICAL'));
EXEC sp_medir_indice(6, 'SIN_INDICE')

CREATE INDEX ix_reserva_estado ON reserva (estado);

-- Con histograma en ESTADO: el optimizador sabe cuántas filas tiene cada valor
BEGIN
   DBMS_STATS.GATHER_TABLE_STATS(USER, 'RESERVA', cascade => TRUE,
      method_opt => 'FOR ALL COLUMNS SIZE AUTO FOR COLUMNS estado SIZE 254');
END;
/

SELECT index_name, distinct_keys AS claves_distintas, num_rows AS filas, leaf_blocks AS hojas, clustering_factor,
       (SELECT blocks FROM user_tables WHERE table_name = 'RESERVA') AS bloques_tabla
FROM   user_indexes
WHERE  index_name = 'IX_RESERVA_ESTADO';

PROMPT --- C4 con el índice creado: ¿lo usa el optimizador?
EXEC sp_medir_indice(4, 'CON_INDICE')
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'E3_C4_CON_INDICE', 'TYPICAL'));

PROMPT --- C5 la misma consulta OBLIGANDO a usar el índice (hint INDEX)
EXEC sp_medir_indice(5, 'CON_INDICE')
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'E3_C5_CON_INDICE', 'TYPICAL'));

PROMPT --- C6 el mismo índice con un valor escaso (PENDIENTE)
EXEC sp_medir_indice(6, 'CON_INDICE')
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'E3_C6_CON_INDICE', 'TYPICAL'));

PROMPT ================================================================
PROMPT  Veredicto del caso donde el índice no ayuda
PROMPT ================================================================
SELECT m.caso, m.momento, m.costo, m.ejecuciones, m.milisegundos, m.operaciones
FROM   indice_medicion m
WHERE  m.caso IN (4, 5, 6)
ORDER  BY m.caso, m.momento DESC;

SELECT 'C4: con el índice disponible, el optimizador '
       || CASE WHEN c4.operaciones LIKE '%IX_RESERVA_ESTADO%'
               THEN 'SÍ lo usó (revisar estadísticas)'
               ELSE 'lo IGNORÓ y siguió con TABLE ACCESS FULL' END AS veredicto
FROM   indice_medicion c4
WHERE  c4.caso = 4 AND c4.momento = 'CON_INDICE'
UNION ALL
SELECT 'C5: forzarlo cuesta ' || c5.costo || ' contra ' || c4.costo || ' del recorrido completo ('
       || ROUND(c5.costo / NULLIF(c4.costo, 0), 1) || ' veces) y tarda '
       || c5.milisegundos || ' ms contra ' || c4.milisegundos || ' ms'
FROM   indice_medicion c4
JOIN   indice_medicion c5 ON c5.caso = 5 AND c5.momento = 'CON_INDICE'
WHERE  c4.caso = 4 AND c4.momento = 'CON_INDICE'
UNION ALL
SELECT 'C6: para PENDIENTE el costo pasó de ' || s.costo || ' a ' || c.costo || ' y el plan '
       || CASE WHEN c.operaciones LIKE '%IX_RESERVA_ESTADO%' THEN 'SÍ usa el índice' ELSE 'no usa el índice' END
FROM   indice_medicion s
JOIN   indice_medicion c ON c.caso = 6 AND c.momento = 'CON_INDICE'
WHERE  s.caso = 6 AND s.momento = 'SIN_INDICE';

-- El índice sobre ESTADO no se conserva: no mejora la consulta frecuente
-- y habría que mantenerlo en cada cambio de estado de una reserva.
DROP INDEX ix_reserva_estado;

PROMPT ================================================================
PROMPT  Índices que quedan en el esquema después de la Entrega 3
PROMPT ================================================================
SELECT table_name, index_name, index_type, uniqueness, status
FROM   user_indexes
WHERE  index_name LIKE 'IX\_%' ESCAPE '\'
ORDER  BY table_name, index_name;

PROMPT Fin del script 11.
