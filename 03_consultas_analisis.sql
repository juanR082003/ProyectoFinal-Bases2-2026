/* =====================================================================
   TurismoUQ · Proyecto integrador Bases de Datos II · 2026-2
   Script 03 · Las 7 consultas de análisis (Entrega 1)
   ---------------------------------------------------------------------
   Requisito previo: 01_ddl_turismouq.sql y 02_carga_datos.sql.
   Ejecutar como script (F5 en SQL Developer, o @03_consultas_analisis.sql
   en SQL*Plus) para que funcionen las variables de enlace de la consulta 5.

   Definiciones comunes
     · Reserva "efectiva": estado CONFIRMADA o COMPLETADA. Las PENDIENTES
       aún no comprometen la habitación y las CANCELADAS no generan
       hospedaje.
     · Noche ocupada: fecha del CALENDARIO con
         rh.fecha_checkin <= fecha < rh.fecha_checkout
       (la noche del check-out no se cuenta).
     · Ingreso de hospedaje NOCHE POR NOCHE: cada noche se valora con la
       TARIFA de la habitación en la temporada a la que pertenece esa
       noche (CALENDARIO.id_temporada). Así una estadía 20-26 dic que
       cruza de MEDIA a ALTA se reparte correctamente entre temporadas
       y entre meses.
     · Ingreso devengado = hospedaje + servicios de reservas efectivas.
       Recaudo = dinero efectivamente recibido (tabla PAGO).
   ===================================================================== */

SET SQLBLANKLINES ON
SET LINESIZE 250
SET PAGESIZE 200
SET FEEDBACK ON

/* =====================================================================
   CONSULTA 1 · Ocupación por municipio y mes (PIVOT)
   Pregunta: ¿qué porcentaje de las noches-habitación disponibles se
   ocupó en cada municipio, mes a mes, durante 2025?
     ocupación % = noches ocupadas / (habitaciones del municipio x días del mes)
   Técnica: se calcula el % en formato largo (municipio, mes, %) y PIVOT
   gira los 12 meses a columnas. La columna OCUP_ANUAL se calcula con
   funciones de ventana antes del PIVOT; como no participa en el PIVOT,
   queda como columna de agrupación implícita.
   ===================================================================== */
PROMPT === Consulta 1: ocupación (%) por municipio y mes - 2025 (PIVOT) ===

WITH noches_ocupadas AS (
   SELECT a.id_municipio, c.mes, COUNT(*) AS noches
   FROM   reserva r
   JOIN   reserva_habitacion rh ON rh.id_reserva     = r.id_reserva
   JOIN   alojamiento a         ON a.id_alojamiento  = rh.id_alojamiento
   JOIN   calendario c          ON c.fecha >= rh.fecha_checkin
                               AND c.fecha <  rh.fecha_checkout
   WHERE  r.estado IN ('CONFIRMADA', 'COMPLETADA')
   AND    c.anio = 2025
   GROUP  BY a.id_municipio, c.mes
),
noches_disponibles AS (
   SELECT a.id_municipio, c.mes, COUNT(*) AS noches       -- habitaciones x días del mes
   FROM   habitacion h
   JOIN   alojamiento a ON a.id_alojamiento = h.id_alojamiento
   CROSS  JOIN calendario c
   WHERE  c.anio = 2025
   GROUP  BY a.id_municipio, c.mes
),
ocupacion AS (
   SELECT m.nombre AS municipio,
          d.mes,
          ROUND(100 * NVL(o.noches, 0) / d.noches, 1) AS pct,
          ROUND(100 * SUM(NVL(o.noches, 0)) OVER (PARTITION BY m.nombre)
                    / SUM(d.noches)          OVER (PARTITION BY m.nombre), 1) AS ocup_anual
   FROM   noches_disponibles d
   JOIN   municipio m           ON m.id_municipio = d.id_municipio
   LEFT   JOIN noches_ocupadas o ON o.id_municipio = d.id_municipio
                                AND o.mes          = d.mes
)
SELECT *
FROM   ocupacion
PIVOT (
   MAX(pct) FOR mes IN ( 1 AS ene,  2 AS feb,  3 AS mar,  4 AS abr,
                         5 AS may,  6 AS jun,  7 AS jul,  8 AS ago,
                         9 AS sep, 10 AS oct, 11 AS nov, 12 AS dic )
)
ORDER  BY ocup_anual DESC;


/* =====================================================================
   CONSULTA 2 · Ingresos por municipio, tipo de alojamiento y temporada
                (ROLLUP + GROUPING)
   Pregunta: ¿cuánto ingresó en 2025 cada municipio, por tipo de
   alojamiento y por categoría de temporada (ALTA/MEDIA/BAJA), con
   subtotales por tipo, por municipio y total general?
   Ingreso devengado = hospedaje noche por noche (tarifa de la temporada
   de cada noche) + servicios (temporada del día en que se prestan).
   GROUPING(col) = 1 indica que esa columna está "resumida" en la fila,
   lo que permite rotular cada nivel de subtotal. GROUPING_ID resume los
   tres indicadores en un solo número (0 = detalle ... 7 = total).
   ===================================================================== */
PROMPT === Consulta 2: ingresos 2025 por municipio, tipo y temporada (ROLLUP) ===

WITH ingresos AS (
   -- a) hospedaje, noche por noche
   SELECT a.id_municipio, a.id_tipo, t.categoria, tf.valor_noche AS valor
   FROM   reserva r
   JOIN   reserva_habitacion rh ON rh.id_reserva    = r.id_reserva
   JOIN   alojamiento a         ON a.id_alojamiento = rh.id_alojamiento
   JOIN   calendario c          ON c.fecha >= rh.fecha_checkin
                               AND c.fecha <  rh.fecha_checkout
   JOIN   temporada t           ON t.id_temporada   = c.id_temporada
   JOIN   tarifa tf             ON tf.id_habitacion = rh.id_habitacion
                               AND tf.id_temporada  = c.id_temporada
   WHERE  r.estado IN ('CONFIRMADA', 'COMPLETADA')
   AND    c.anio = 2025
   UNION  ALL
   -- b) servicios complementarios, por la temporada del día del servicio
   SELECT a.id_municipio, a.id_tipo, t.categoria, rs.subtotal
   FROM   reserva r
   JOIN   reserva_servicio rs ON rs.id_reserva    = r.id_reserva
   JOIN   alojamiento a       ON a.id_alojamiento = rs.id_alojamiento
   JOIN   calendario c        ON c.fecha          = rs.fecha_servicio
   JOIN   temporada t         ON t.id_temporada   = c.id_temporada
   WHERE  r.estado IN ('CONFIRMADA', 'COMPLETADA')
   AND    c.anio = 2025
)
SELECT CASE WHEN GROUPING(m.nombre) = 1 THEN '*** TOTAL GENERAL ***'
            ELSE m.nombre END                                            AS municipio,
       CASE WHEN GROUPING(m.nombre)  = 1 THEN NULL
            WHEN GROUPING(ta.nombre) = 1 THEN '** Subtotal municipio'
            ELSE ta.nombre END                                           AS tipo_alojamiento,
       CASE WHEN GROUPING(ta.nombre)  = 1 THEN NULL
            WHEN GROUPING(i.categoria) = 1 THEN '* Subtotal tipo'
            ELSE i.categoria END                                         AS temporada,
       SUM(i.valor)                                                      AS ingresos,
       TO_CHAR(SUM(i.valor), 'FM$999G999G999G990')                       AS ingresos_fmt,
       GROUPING_ID(m.nombre, ta.nombre, i.categoria)                     AS nivel
FROM   ingresos i
JOIN   municipio m         ON m.id_municipio = i.id_municipio
JOIN   tipo_alojamiento ta ON ta.id_tipo     = i.id_tipo
GROUP  BY ROLLUP (m.nombre, ta.nombre, i.categoria)
ORDER  BY GROUPING(m.nombre), m.nombre,
          GROUPING(ta.nombre), ta.nombre,
          GROUPING(i.categoria), i.categoria;


/* =====================================================================
   CONSULTA 3 · Los 3 alojamientos de mayor ingreso dentro de cada
                municipio (RANK + PARTITION BY)
   Pregunta: ¿cuáles son los alojamientos más rentables de cada
   municipio en todo el histórico (2024-2026)?
   Ingreso devengado = valor de las estadías (RESERVA_HABITACION.valor_estadia,
   ya calculado noche por noche) + servicios, de reservas efectivas.
   RANK() reinicia la numeración en cada municipio (PARTITION BY) y deja
   huecos si hay empates; RATIO_TO_REPORT da la participación del
   alojamiento en el ingreso de su municipio. Municipios con menos de 3
   alojamientos (Buenavista, Pijao, Génova, Córdoba) muestran los que
   tienen.
   ===================================================================== */
PROMPT === Consulta 3: top 3 de alojamientos por ingreso en cada municipio (RANK) ===

WITH hospedaje AS (
   SELECT rh.id_alojamiento,
          SUM(rh.valor_estadia)          AS valor,
          COUNT(DISTINCT rh.id_reserva)  AS reservas
   FROM   reserva_habitacion rh
   JOIN   reserva r ON r.id_reserva = rh.id_reserva
   WHERE  r.estado IN ('CONFIRMADA', 'COMPLETADA')
   GROUP  BY rh.id_alojamiento
),
servicios AS (
   SELECT rs.id_alojamiento, SUM(rs.subtotal) AS valor
   FROM   reserva_servicio rs
   JOIN   reserva r ON r.id_reserva = rs.id_reserva
   WHERE  r.estado IN ('CONFIRMADA', 'COMPLETADA')
   GROUP  BY rs.id_alojamiento
),
totales AS (
   SELECT m.nombre                                 AS municipio,
          a.nombre_comercial                       AS alojamiento,
          ta.nombre                                AS tipo,
          (SELECT COUNT(*) FROM habitacion h
           WHERE  h.id_alojamiento = a.id_alojamiento) AS habitaciones,
          NVL(h.reservas, 0)                       AS reservas,
          NVL(h.valor, 0)                          AS ingreso_hospedaje,
          NVL(s.valor, 0)                          AS ingreso_servicios,
          NVL(h.valor, 0) + NVL(s.valor, 0)        AS ingreso_total
   FROM   alojamiento a
   JOIN   municipio m         ON m.id_municipio = a.id_municipio
   JOIN   tipo_alojamiento ta ON ta.id_tipo     = a.id_tipo
   LEFT   JOIN hospedaje h    ON h.id_alojamiento = a.id_alojamiento
   LEFT   JOIN servicios s    ON s.id_alojamiento = a.id_alojamiento
),
ranking AS (
   SELECT t.*,
          RANK() OVER (PARTITION BY t.municipio ORDER BY t.ingreso_total DESC)        AS puesto,
          ROUND(100 * RATIO_TO_REPORT(t.ingreso_total) OVER (PARTITION BY t.municipio), 1)
                                                                                       AS pct_del_municipio,
          ROUND(t.ingreso_total / NULLIF(t.habitaciones, 0))                           AS ingreso_por_habitacion
   FROM   totales t
)
SELECT municipio, puesto, alojamiento, tipo, habitaciones, reservas,
       ingreso_hospedaje, ingreso_servicios, ingreso_total,
       pct_del_municipio, ingreso_por_habitacion
FROM   ranking
WHERE  puesto <= 3
ORDER  BY municipio, puesto;


/* =====================================================================
   CONSULTA 4 · Variación de ingresos mes contra mes (LAG)
   Pregunta: ¿cómo cambia el recaudo de la plataforma de un mes al
   siguiente, y frente al mismo mes del año anterior?
   Recaudo neto del mes = pagos EXITOSOS y REEMBOLSADOS recibidos en el
   mes (fecha_pago) menos los reembolsos devueltos en el mes
   (fecha_reembolso). Así el reembolso del 80 % resta en el mes en que
   realmente sale el dinero.
   LAG(x) trae el valor de la fila anterior según ORDER BY mes;
   LAG(x, 12) trae el de 12 meses atrás. Se usan meses completos:
   ene-2024 a sep-2026 (la fecha de corte de los datos es 17-oct-2026).
   ===================================================================== */
PROMPT === Consulta 4: recaudo neto mensual y variación mes contra mes (LAG) ===

WITH movimientos AS (
   SELECT TRUNC(p.fecha_pago, 'MM') AS mes, p.monto AS valor
   FROM   pago p
   WHERE  p.estado IN ('EXITOSO', 'REEMBOLSADO')
   UNION  ALL
   SELECT TRUNC(p.fecha_reembolso, 'MM'), -p.monto_reembolsado
   FROM   pago p
   WHERE  p.estado = 'REEMBOLSADO'
),
mensual AS (
   SELECT mes, SUM(valor) AS recaudo
   FROM   movimientos
   WHERE  mes >= DATE '2024-01-01'
   AND    mes <  DATE '2026-10-01'
   GROUP  BY mes
)
SELECT TO_CHAR(mes, 'YYYY-MM')                                        AS mes,
       recaudo,
       LAG(recaudo) OVER (ORDER BY mes)                                AS recaudo_mes_anterior,
       recaudo - LAG(recaudo) OVER (ORDER BY mes)                      AS variacion,
       ROUND(100 * (recaudo - LAG(recaudo) OVER (ORDER BY mes))
                 / NULLIF(LAG(recaudo) OVER (ORDER BY mes), 0), 1)     AS variacion_pct,
       LAG(recaudo, 12) OVER (ORDER BY mes)                            AS mismo_mes_anio_anterior,
       ROUND(100 * (recaudo - LAG(recaudo, 12) OVER (ORDER BY mes))
                 / NULLIF(LAG(recaudo, 12) OVER (ORDER BY mes), 0), 1) AS variacion_anual_pct,
       CASE
          WHEN LAG(recaudo) OVER (ORDER BY mes) IS NULL THEN 'Primer mes'
          WHEN recaudo > LAG(recaudo) OVER (ORDER BY mes) THEN 'Sube'
          ELSE 'Baja'
       END                                                             AS tendencia
FROM   mensual
ORDER  BY mes;


/* =====================================================================
   CONSULTA 5 · Consulta parametrizada con variables de enlace
   Pregunta: para un rango de fechas que elige el usuario, ¿cómo le fue
   a cada alojamiento? Indicadores hoteleros clásicos:
     · ocupación % = noches vendidas / noches disponibles del rango
     · ADR    (tarifa promedio por noche vendida) = ingreso / noches vendidas
     · RevPAR (ingreso por habitación disponible) = ingreso / noches disponibles
   Solo se cuentan las noches que caen DENTRO del rango, aunque la
   estadía empiece antes o termine después (recorte por calendario).
   Las variables :fecha_ini y :fecha_fin son variables de enlace (bind):
   el optimizador reutiliza el mismo plan para cualquier rango.
   Ejemplo: temporada de fin de año 2025-2026. Para otro rango basta
   cambiar los dos EXEC (o, en SQL Developer con F9, escribir los valores
   en la ventana de variables de enlace).
   ===================================================================== */
PROMPT === Consulta 5: desempeño por alojamiento en un rango de fechas (variables de enlace) ===

VARIABLE fecha_ini VARCHAR2(10)
VARIABLE fecha_fin VARCHAR2(10)
EXEC :fecha_ini := '2025-12-15';
EXEC :fecha_fin := '2026-01-11';

WITH rango AS (
   SELECT TO_DATE(:fecha_ini, 'YYYY-MM-DD') AS f_ini,
          TO_DATE(:fecha_fin, 'YYYY-MM-DD') AS f_fin,
          TO_DATE(:fecha_fin, 'YYYY-MM-DD') - TO_DATE(:fecha_ini, 'YYYY-MM-DD') + 1 AS dias
   FROM   dual
),
vendidas AS (
   SELECT rh.id_alojamiento,
          COUNT(*)                       AS noches,
          SUM(tf.valor_noche)            AS ingreso,
          COUNT(DISTINCT rh.id_reserva)  AS reservas
   FROM   rango g
   JOIN   calendario c          ON c.fecha BETWEEN g.f_ini AND g.f_fin
   JOIN   reserva_habitacion rh ON c.fecha >= rh.fecha_checkin
                               AND c.fecha <  rh.fecha_checkout
   JOIN   reserva r             ON r.id_reserva = rh.id_reserva
   JOIN   tarifa tf             ON tf.id_habitacion = rh.id_habitacion
                               AND tf.id_temporada  = c.id_temporada
   WHERE  r.estado IN ('CONFIRMADA', 'COMPLETADA')
   GROUP  BY rh.id_alojamiento
),
oferta AS (
   SELECT h.id_alojamiento,
          COUNT(*) * g.dias AS noches_disponibles
   FROM   habitacion h
   CROSS  JOIN rango g
   GROUP  BY h.id_alojamiento, g.dias
)
SELECT m.nombre                                              AS municipio,
       a.nombre_comercial                                    AS alojamiento,
       ta.nombre                                             AS tipo,
       NVL(v.reservas, 0)                                    AS reservas,
       o.noches_disponibles,
       NVL(v.noches, 0)                                      AS noches_vendidas,
       ROUND(100 * NVL(v.noches, 0) / o.noches_disponibles, 1) AS ocupacion_pct,
       NVL(v.ingreso, 0)                                     AS ingreso_hospedaje,
       ROUND(v.ingreso / NULLIF(v.noches, 0))                AS adr,
       ROUND(NVL(v.ingreso, 0) / o.noches_disponibles)       AS revpar
FROM   alojamiento a
JOIN   municipio m         ON m.id_municipio   = a.id_municipio
JOIN   tipo_alojamiento ta ON ta.id_tipo       = a.id_tipo
JOIN   oferta o            ON o.id_alojamiento = a.id_alojamiento
LEFT   JOIN vendidas v     ON v.id_alojamiento = a.id_alojamiento
ORDER  BY ocupacion_pct DESC, ingreso_hospedaje DESC;


/* =====================================================================
   CONSULTA 6 · UNPIVOT
   Pregunta: ¿de dónde sale y a dónde va el dinero de las reservas con
   check-in en 2025, por tipo de alojamiento?
   Primero se arma una fila por tipo con cinco columnas numéricas
   (formato ancho); UNPIVOT convierte esas columnas en filas
   (tipo, concepto, valor), el formato largo que necesita un gráfico o
   una tabla dinámica.
     Hospedaje / Servicios ........ devengado de reservas efectivas
     Recaudado reservas activas ... pagos EXITOSOS de reservas no canceladas
     Retenido por cancelaciones ... lo que la plataforma conserva cuando
                                    el cliente cancela (100 % con <= 5 días,
                                    20 % con > 5 días)
     Reembolsado a clientes ....... el 80 % devuelto
   ===================================================================== */
PROMPT === Consulta 6: componentes del dinero por tipo de alojamiento - 2025 (UNPIVOT) ===

WITH reservas_2025 AS (
   SELECT r.id_reserva, r.estado, a.id_tipo
   FROM   reserva r
   JOIN   alojamiento a ON a.id_alojamiento = r.id_alojamiento
   WHERE  r.fecha_checkin >= DATE '2025-01-01'
   AND    r.fecha_checkin <  DATE '2026-01-01'
),
hospedaje AS (
   SELECT x.id_tipo, SUM(rh.valor_estadia) AS valor
   FROM   reservas_2025 x
   JOIN   reserva_habitacion rh ON rh.id_reserva = x.id_reserva
   WHERE  x.estado IN ('CONFIRMADA', 'COMPLETADA')
   GROUP  BY x.id_tipo
),
servicios AS (
   SELECT x.id_tipo, SUM(rs.subtotal) AS valor
   FROM   reservas_2025 x
   JOIN   reserva_servicio rs ON rs.id_reserva = x.id_reserva
   WHERE  x.estado IN ('CONFIRMADA', 'COMPLETADA')
   GROUP  BY x.id_tipo
),
pagos AS (
   SELECT x.id_tipo,
          SUM(CASE WHEN x.estado <> 'CANCELADA' AND p.estado = 'EXITOSO'
                   THEN p.monto ELSE 0 END)                              AS recaudado,
          SUM(CASE WHEN x.estado = 'CANCELADA' AND p.estado = 'EXITOSO'
                   THEN p.monto ELSE 0 END)
        + SUM(CASE WHEN p.estado = 'REEMBOLSADO'
                   THEN p.monto - p.monto_reembolsado ELSE 0 END)        AS retenido,
          SUM(p.monto_reembolsado)                                       AS reembolsado
   FROM   reservas_2025 x
   JOIN   pago p ON p.id_reserva = x.id_reserva
   GROUP  BY x.id_tipo
),
ancho AS (
   SELECT ta.nombre               AS tipo_alojamiento,
          NVL(h.valor, 0)         AS hospedaje,
          NVL(s.valor, 0)         AS servicios,
          NVL(p.recaudado, 0)     AS recaudado,
          NVL(p.retenido, 0)      AS retenido,
          NVL(p.reembolsado, 0)   AS reembolsado
   FROM   tipo_alojamiento ta
   LEFT   JOIN hospedaje h ON h.id_tipo = ta.id_tipo
   LEFT   JOIN servicios s ON s.id_tipo = ta.id_tipo
   LEFT   JOIN pagos p     ON p.id_tipo = ta.id_tipo
)
SELECT tipo_alojamiento,
       concepto,
       valor,
       ROUND(100 * RATIO_TO_REPORT(valor) OVER (PARTITION BY concepto), 1) AS pct_del_concepto
FROM   ancho
UNPIVOT INCLUDE NULLS (
   valor FOR concepto IN ( hospedaje   AS '1. Hospedaje',
                           servicios   AS '2. Servicios complementarios',
                           recaudado   AS '3. Recaudado reservas activas',
                           retenido    AS '4. Retenido por cancelaciones',
                           reembolsado AS '5. Reembolsado a clientes' )
)
ORDER  BY tipo_alojamiento, concepto;


/* =====================================================================
   CONSULTA 7 · Consulta libre (pregunta de negocio propuesta)
   Pregunta: ¿las estrellas que cada alojamiento se AUTOASIGNA coinciden
   con lo que opinan sus huéspedes? ¿Quién está sobrevalorado y quién
   está subvalorado?
   Para cada alojamiento con al menos 20 reseñas: promedio de las
   reseñas, distribución (% de 4-5 y de 1-2 estrellas), tasa de reseña
   (reseñas / estadías completadas) y la BRECHA = promedio - estrellas.
     brecha <= -1,0 -> 'Sobrevalorado' (promete más de lo que entrega)
     brecha >= +0,5 -> 'Subvalorado'   (podría subir su categoría)
     resto          -> 'Coherente'
   DENSE_RANK ordena por promedio sin dejar huecos en los empates.
   Sirve a la gerencia para decidir auditorías de calidad y para no
   mostrar en el buscador estrellas que los huéspedes no respaldan.
   ===================================================================== */
PROMPT === Consulta 7: estrellas autoasignadas vs. calificación real de los huéspedes ===

WITH completadas AS (
   SELECT id_alojamiento, COUNT(*) AS estadias
   FROM   reserva
   WHERE  estado = 'COMPLETADA'
   GROUP  BY id_alojamiento
),
resenas AS (
   SELECT r.id_alojamiento,
          COUNT(*)                                                    AS num_resenas,
          ROUND(AVG(rs.calificacion), 2)                              AS promedio,
          ROUND(100 * AVG(CASE WHEN rs.calificacion >= 4 THEN 1 ELSE 0 END), 1) AS pct_4_5,
          ROUND(100 * AVG(CASE WHEN rs.calificacion <= 2 THEN 1 ELSE 0 END), 1) AS pct_1_2,
          COUNT(rs.comentario)                                        AS con_comentario
   FROM   resena rs
   JOIN   reserva r ON r.id_reserva = rs.id_reserva
   GROUP  BY r.id_alojamiento
   HAVING COUNT(*) >= 20
)
SELECT DENSE_RANK() OVER (ORDER BY x.promedio DESC)                  AS puesto,
       m.nombre                                                       AS municipio,
       a.nombre_comercial                                             AS alojamiento,
       ta.nombre                                                      AS tipo,
       a.estrellas                                                    AS estrellas_autoasignadas,
       x.promedio                                                     AS calificacion_huespedes,
       ROUND(x.promedio - a.estrellas, 2)                             AS brecha,
       CASE WHEN x.promedio - a.estrellas <= -1.0 THEN 'Sobrevalorado'
            WHEN x.promedio - a.estrellas >=  0.5 THEN 'Subvalorado'
            ELSE 'Coherente' END                                      AS diagnostico,
       x.num_resenas,
       ROUND(100 * x.num_resenas / c.estadias, 1)                     AS tasa_resena_pct,
       x.pct_4_5,
       x.pct_1_2,
       x.con_comentario
FROM   resenas x
JOIN   alojamiento a       ON a.id_alojamiento = x.id_alojamiento
JOIN   municipio m         ON m.id_municipio   = a.id_municipio
JOIN   tipo_alojamiento ta ON ta.id_tipo       = a.id_tipo
JOIN   completadas c       ON c.id_alojamiento = x.id_alojamiento
ORDER  BY puesto, brecha DESC;

-- Resumen del diagnóstico (cuántos alojamientos caen en cada grupo, por tipo)
SELECT ta.nombre AS tipo,
       COUNT(CASE WHEN AVG_cal - estrellas <= -1.0 THEN 1 END) AS sobrevalorados,
       COUNT(CASE WHEN AVG_cal - estrellas >  -1.0
                   AND AVG_cal - estrellas <   0.5 THEN 1 END) AS coherentes,
       COUNT(CASE WHEN AVG_cal - estrellas >=  0.5 THEN 1 END) AS subvalorados
FROM  (SELECT a.id_alojamiento, a.id_tipo, a.estrellas, AVG(rs.calificacion) AS avg_cal
       FROM   resena rs
       JOIN   reserva r     ON r.id_reserva     = rs.id_reserva
       JOIN   alojamiento a ON a.id_alojamiento = r.id_alojamiento
       GROUP  BY a.id_alojamiento, a.id_tipo, a.estrellas
       HAVING COUNT(*) >= 20) x
JOIN   tipo_alojamiento ta ON ta.id_tipo = x.id_tipo
GROUP  BY ta.nombre
ORDER  BY ta.nombre;
