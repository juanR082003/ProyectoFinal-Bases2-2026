/* =====================================================================
   TurismoUQ · Entrega 3 · Experimento de concurrencia · VENTANA M (monitor)
   ---------------------------------------------------------------------
   Conectado como SYSTEM a XEPDB1. Ejecutar mientras la ventana B está
   esperando (paso B3). Muestra el bloqueo real en el diccionario.
   ===================================================================== */
SET LINESIZE 220
SET PAGESIZE 100
COLUMN usuario   FORMAT A12
COLUMN estado    FORMAT A9
COLUMN evento    FORMAT A32
COLUMN sentencia FORMAT A70
COLUMN objeto    FORMAT A22
COLUMN modo      FORMAT A22
COLUMN pide      FORMAT A22

PROMPT ===== M1. Sesiones de TURISMOUQ: quién espera y quién la bloquea =====
SELECT s.sid,
       s.serial#,
       s.username          AS usuario,
       s.status            AS estado,
       s.blocking_session  AS bloqueada_por_sid,
       s.seconds_in_wait   AS seg_esperando,
       s.event             AS evento,
       SUBSTR(q.sql_text, 1, 70) AS sentencia
FROM   v$session s
LEFT   JOIN v$sql q ON q.sql_id = s.sql_id AND q.child_number = s.sql_child_number
WHERE  s.username = 'TURISMOUQ'
ORDER  BY s.blocking_session NULLS FIRST, s.sid;

PROMPT ===== M2. Bloqueos TX (fila) y TM (tabla) de esas sesiones =====
PROMPT BLOCK = 1: esta sesión tiene un bloqueo por el que otra espera. REQUEST > 0: está pidiendo un bloqueo.
SELECT l.sid,
       l.type,
       DECODE(l.lmode,   0, '0 ninguno', 2, '2 fila compartido (RS)', 3, '3 fila exclusivo (RX)',
                         4, '4 compartido (S)', 5, '5 S/RX', 6, '6 exclusivo (X)', TO_CHAR(l.lmode)) AS modo,
       DECODE(l.request, 0, '0 ninguno', 6, '6 exclusivo (X)', TO_CHAR(l.request))                    AS pide,
       l.block,
       l.ctime AS segundos,
       CASE WHEN l.type = 'TM' THEN (SELECT o.object_name FROM dba_objects o WHERE o.object_id = l.id1) END AS objeto
FROM   v$lock l
WHERE  l.type IN ('TX', 'TM')
AND    l.sid IN (SELECT sid FROM v$session WHERE username = 'TURISMOUQ')
ORDER  BY l.block DESC, l.sid, l.type;

PROMPT ===== M3. Resumen: bloqueadora -> bloqueada =====
SELECT b.sid AS sid_bloqueadora, w.sid AS sid_bloqueada, w.seconds_in_wait AS seg_esperando, w.event AS evento
FROM   v$session w
JOIN   v$session b ON b.sid = w.blocking_session
WHERE  w.username = 'TURISMOUQ';
