/* =====================================================================
   TurismoUQ · Proyecto integrador Bases de Datos II · 2026-2
   ENTREGA 2 · CAPA PL/SQL · ARCHIVO ÚNICO
   ---------------------------------------------------------------------
   Integrantes: Juan Camilo López · José Luis Rivadeneira · Juan Manuel Rincón
   Docente: Carolina Londoño Idárraga

   Este archivo reúne, en orden de ejecución, los scripts 04 a 08 del
   repositorio. Contiene:
     · Funciones ......... fn_valor_estadia, fn_habitacion_disponible,
                           fn_total_reserva, fn_total_pagado, fn_esta_pagada
     · Procedimientos .... sp_crear_reserva, sp_agregar_habitacion,
                           sp_cancelar_reserva, sp_desglose_estadia,
                           sp_liquidacion_mensual, sp_archivar_reservas
     · Cursores .......... explícitos con parámetros (c_tramos,
                           c_alojamientos, c_hospedaje, c_servicios,
                           c_cancelaciones)
     · Excepciones ....... -20001 a -20008 con RAISE_APPLICATION_ERROR y
                           excepciones con nombre (PRAGMA EXCEPTION_INIT)
     · Paquetes .......... PKG_TURISMOUQ y PKG_AUDITORIA_TARIFA
     · Disparadores ...... de sentencia (auditoría de TARIFA) y de fila
                           (anti-solape de reservas, COMPOUND TRIGGER)
     · Tablespace ........ TS_TURISMOUQ_HIST para el histórico
     · Vista materializada MV_OCUPACION_MENSUAL y jobs de DBMS_SCHEDULER
     · Pruebas ........... evidencia de cada componente (OK / FALLA)

   CÓMO EJECUTARLO
     Requisito: esquema TURISMOUQ creado y cargado (scripts 00 a 02).
     1. PARTE 0 (como SYSTEM): el tablespace exige privilegios de
        administrador. Ejecute 04_tablespace_historico.sql conectado como
        SYSTEM a XEPDB1 (o copie la Parte 0, que está comentada abajo, a
        una hoja con la conexión SYSTEM y quítele los "--").
     2. PARTES 1 a 4 (como TURISMOUQ): ejecute el resto de este archivo
        con F5 (Ejecutar script) en la conexión TURISMOUQ.
   ===================================================================== */


/* #####################################################################
   PARTE 0 · TABLESPACE PARA EL HISTÓRICO · EJECUTAR COMO SYSTEM (ver instrucciones)
   ##################################################################### */

-- /* =====================================================================
--    TurismoUQ · Proyecto integrador Bases de Datos II · 2026-2
--    Script 04 · Tablespace propio para el histórico de reservas (Entrega 2)
--    ---------------------------------------------------------------------
--    EJECUTAR CONECTADO COMO SYSTEM A XEPDB1 (no como TURISMOUQ):
--    crear tablespaces y otorgar cuotas son privilegios de administrador.
--
--    Qué hace
--      1. Borra el tablespace TS_TURISMOUQ_HIST si ya existía (base limpia).
--      2. Lo crea con un datafile propio, ubicado en la MISMA carpeta en que
--         Oracle guarda el datafile del tablespace USERS de esta PDB (así el
--         script funciona en Windows y en Linux sin escribir rutas a mano).
--      3. Da cuota al usuario TURISMOUQ sobre él.
--      4. Otorga CREATE JOB, necesario para programar el refresco de la
--         vista materializada y la liquidación mensual (script 07).
--
--    ¿Por qué un tablespace separado para el histórico?
--      · Ciclo de vida distinto: las reservas cerradas (completadas o
--        canceladas de años anteriores) ya no cambian. Separadas, el
--        tablespace puede ponerse READ ONLY al cerrar cada año y respaldarse
--        una sola vez, en lugar de copiarlo en cada backup diario.
--      · Crecimiento controlado: el histórico crece todos los años y sin
--        límite; con su propio datafile (AUTOEXTEND con MAXSIZE) ese
--        crecimiento no consume el espacio de las tablas operativas (USERS)
--        ni puede llenarlo.
--      · Rendimiento de E/S: las consultas analíticas pesadas sobre años
--        viejos leen otro archivo, que en un servidor real puede ir en un
--        disco más barato y lento sin afectar las reservas en línea.
--      · Administración: se puede mover, desconectar (OFFLINE) o restaurar
--        el histórico sin tocar la operación diaria.
--    ===================================================================== */
--
-- SET SERVEROUTPUT ON
--
-- -- 1. Base limpia: eliminar el tablespace si existía
-- BEGIN
--    EXECUTE IMMEDIATE 'DROP TABLESPACE ts_turismouq_hist INCLUDING CONTENTS AND DATAFILES CASCADE CONSTRAINTS';
--    DBMS_OUTPUT.PUT_LINE('Tablespace TS_TURISMOUQ_HIST anterior eliminado.');
-- EXCEPTION
--    WHEN OTHERS THEN
--       IF SQLCODE = -959 THEN      -- ORA-00959: el tablespace no existe
--          DBMS_OUTPUT.PUT_LINE('TS_TURISMOUQ_HIST no existía; se crea nuevo.');
--       ELSE
--          RAISE;
--       END IF;
-- END;
-- /
--
-- -- 2. Crear el tablespace junto al datafile de USERS
-- DECLARE
--    v_archivo  dba_data_files.file_name%TYPE;
--    v_carpeta  VARCHAR2(600);
--    v_sep      PLS_INTEGER;
--    v_ruta     VARCHAR2(700);
-- BEGIN
--    SELECT file_name INTO v_archivo
--    FROM   dba_data_files
--    WHERE  tablespace_name = 'USERS'
--    AND    ROWNUM = 1;
--
--    -- carpeta = todo lo que va antes del último separador (\ en Windows, / en Linux)
--    v_sep     := GREATEST(INSTR(v_archivo, '\', -1), INSTR(v_archivo, '/', -1));
--    v_carpeta := SUBSTR(v_archivo, 1, v_sep);
--    v_ruta    := v_carpeta || 'TS_TURISMOUQ_HIST01.DBF';
--
--    EXECUTE IMMEDIATE
--       'CREATE TABLESPACE ts_turismouq_hist '
--    || 'DATAFILE ''' || v_ruta || ''' SIZE 50M '
--    || 'AUTOEXTEND ON NEXT 10M MAXSIZE 1G '
--    || 'EXTENT MANAGEMENT LOCAL AUTOALLOCATE '
--    || 'SEGMENT SPACE MANAGEMENT AUTO';
--
--    DBMS_OUTPUT.PUT_LINE('Tablespace creado. Datafile: ' || v_ruta);
-- END;
-- /
--
-- -- 3. Cuota del dueño del esquema sobre el nuevo tablespace
-- ALTER USER turismouq QUOTA UNLIMITED ON ts_turismouq_hist;
--
-- -- 4. Privilegio para crear jobs de DBMS_SCHEDULER (script 07)
-- GRANT CREATE JOB TO turismouq;
--
-- -- 5. Evidencia
-- SELECT t.tablespace_name, t.status, t.contents, t.extent_management,
--        d.file_name, ROUND(d.bytes / 1024 / 1024) AS mb, d.autoextensible,
--        ROUND(d.maxbytes / 1024 / 1024) AS max_mb
-- FROM   dba_tablespaces t
-- JOIN   dba_data_files d ON d.tablespace_name = t.tablespace_name
-- WHERE  t.tablespace_name = 'TS_TURISMOUQ_HIST';
--
-- SELECT username, tablespace_name,
--        CASE max_bytes WHEN -1 THEN 'ILIMITADA' ELSE TO_CHAR(max_bytes) END AS cuota
-- FROM   dba_ts_quotas
-- WHERE  username = 'TURISMOUQ';
--
-- PROMPT Tablespace listo. Conéctese como TURISMOUQ y ejecute 05_paquete_turismouq.sql


/* #####################################################################
   PARTE 1 · PAQUETE PKG_TURISMOUQ: funciones, procedimientos, cursores y excepciones
   ##################################################################### */

/* =====================================================================
   TurismoUQ · Proyecto integrador Bases de Datos II · 2026-2
   Script 05 · Capa PL/SQL: paquete PKG_TURISMOUQ (Entrega 2)
   ---------------------------------------------------------------------
   Ejecutar como TURISMOUQ, después de 01, 02 y 04.

   Contenido
     Sección 1. Tabla LIQUIDACION_MENSUAL (resultado del proceso masivo).
     Sección 2. Especificación del paquete: constantes, códigos de error,
                excepciones con nombre y la interfaz pública.
     Sección 3. Cuerpo del paquete:
        · fn_valor_estadia ....... valor de una estadía cruzando temporadas
        · sp_desglose_estadia .... muestra el cálculo tramo por tramo
        · fn_habitacion_disponible
        · sp_crear_reserva ....... con excepciones propias (RAISE_APPLICATION_ERROR)
        · sp_agregar_habitacion .. reservas de grupo (varias líneas)
        · fn_total_reserva / fn_total_pagado / fn_esta_pagada
        · sp_cancelar_reserva .... regla de reembolso del 80 %
        · sp_liquidacion_mensual . CURSORES EXPLÍCITOS CON PARÁMETROS
     Sección 4. Verificación de compilación.

   Códigos de error propios
     -20001 habitación no disponible (solape con otra reserva activa)
     -20002 fechas inválidas (check-out <= check-in, más de 30 noches...)
     -20003 capacidad excedida (o número de huéspedes no válido)
     -20004 cliente, habitación o reserva inexistente / inactiva
     -20005 noches sin temporada o sin tarifa definida
     -20006 estado de la reserva no permite la operación
     -20007 check-in en el pasado
     -20008 parámetro obligatorio nulo o inválido

   Control transaccional: los procedimientos de reservas NO hacen COMMIT;
   la decisión de confirmar o deshacer queda en quien los llama (así en la
   Entrega 3 se podrán combinar reserva + pago en una sola transacción con
   SAVEPOINT). El proceso masivo de liquidación sí confirma al final.
   ===================================================================== */

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET SQLBLANKLINES ON

/* =====================================================================
   Sección 1. Tabla de resultados de la liquidación mensual
   ===================================================================== */
BEGIN
   EXECUTE IMMEDIATE 'DROP TABLE liquidacion_mensual CASCADE CONSTRAINTS PURGE';
EXCEPTION
   WHEN OTHERS THEN IF SQLCODE <> -942 THEN RAISE; END IF;
END;
/

CREATE TABLE liquidacion_mensual (
   id_liquidacion         NUMBER(8) GENERATED BY DEFAULT AS IDENTITY,
   anio                   NUMBER(4)      NOT NULL,
   mes                    NUMBER(2)      NOT NULL,
   id_alojamiento         NUMBER(6)      NOT NULL,
   reservas               NUMBER(6)      NOT NULL,
   noches_vendidas        NUMBER(7)      NOT NULL,
   ingreso_hospedaje      NUMBER(14,2)   NOT NULL,
   ingreso_servicios      NUMBER(14,2)   NOT NULL,
   ingreso_cancelaciones  NUMBER(14,2)   NOT NULL,
   total_bruto            NUMBER(14,2)   NOT NULL,
   comision_plataforma    NUMBER(14,2)   NOT NULL,
   neto_alojamiento       NUMBER(14,2)   NOT NULL,
   fecha_generacion       DATE           DEFAULT SYSDATE NOT NULL,
   generado_por           VARCHAR2(128)  DEFAULT USER NOT NULL,
   CONSTRAINT pk_liquidacion_mensual PRIMARY KEY (id_liquidacion),
   CONSTRAINT fk_liquidacion_aloj    FOREIGN KEY (id_alojamiento)
                                     REFERENCES alojamiento (id_alojamiento),
   CONSTRAINT uq_liquidacion_periodo UNIQUE (anio, mes, id_alojamiento),
   CONSTRAINT ck_liquidacion_mes     CHECK (mes BETWEEN 1 AND 12),
   CONSTRAINT ck_liquidacion_totales CHECK (total_bruto = ingreso_hospedaje + ingreso_servicios + ingreso_cancelaciones
                                            AND neto_alojamiento = total_bruto - comision_plataforma)
);

COMMENT ON TABLE liquidacion_mensual IS 'Resultado del proceso masivo de liquidación: lo que TurismoUQ le debe a cada alojamiento por mes.';
COMMENT ON COLUMN liquidacion_mensual.ingreso_hospedaje     IS 'Noches del mes valoradas con la tarifa de su temporada (reservas CONFIRMADA/COMPLETADA).';
COMMENT ON COLUMN liquidacion_mensual.ingreso_cancelaciones IS 'Dinero retenido por cancelaciones del mes (100 % si <= 5 días, 20 % si > 5 días).';
COMMENT ON COLUMN liquidacion_mensual.comision_plataforma   IS '12 % del hospedaje y de lo retenido + 8 % de los servicios.';

/* =====================================================================
   Sección 2. Especificación del paquete
   ===================================================================== */
CREATE OR REPLACE PACKAGE pkg_turismouq AS

   -- Códigos de error propios (usados con RAISE_APPLICATION_ERROR)
   c_err_no_disponible CONSTANT PLS_INTEGER := -20001;
   c_err_fechas        CONSTANT PLS_INTEGER := -20002;
   c_err_capacidad     CONSTANT PLS_INTEGER := -20003;
   c_err_no_existe     CONSTANT PLS_INTEGER := -20004;
   c_err_sin_tarifa    CONSTANT PLS_INTEGER := -20005;
   c_err_estado        CONSTANT PLS_INTEGER := -20006;
   c_err_fecha_pasada  CONSTANT PLS_INTEGER := -20007;
   c_err_parametro     CONSTANT PLS_INTEGER := -20008;

   -- Las mismas condiciones como excepciones con nombre, para quien llame
   ex_no_disponible EXCEPTION;  PRAGMA EXCEPTION_INIT(ex_no_disponible, -20001);
   ex_fechas        EXCEPTION;  PRAGMA EXCEPTION_INIT(ex_fechas,        -20002);
   ex_capacidad     EXCEPTION;  PRAGMA EXCEPTION_INIT(ex_capacidad,     -20003);
   ex_no_existe     EXCEPTION;  PRAGMA EXCEPTION_INIT(ex_no_existe,     -20004);
   ex_sin_tarifa    EXCEPTION;  PRAGMA EXCEPTION_INIT(ex_sin_tarifa,    -20005);
   ex_estado        EXCEPTION;  PRAGMA EXCEPTION_INIT(ex_estado,        -20006);
   ex_fecha_pasada  EXCEPTION;  PRAGMA EXCEPTION_INIT(ex_fecha_pasada,  -20007);
   ex_parametro     EXCEPTION;  PRAGMA EXCEPTION_INIT(ex_parametro,     -20008);

   -- Parámetros del negocio
   c_max_noches          CONSTANT PLS_INTEGER := 30;
   c_dias_reembolso      CONSTANT PLS_INTEGER := 5;     -- más de 5 días => reembolso
   c_pct_reembolso       CONSTANT NUMBER      := 0.80;
   c_comision_hospedaje  CONSTANT NUMBER      := 0.12;
   c_comision_servicios  CONSTANT NUMBER      := 0.08;

   -- Valor de una estadía aplicando la tarifa de CADA temporada que atraviesa.
   -- Las noches cobradas son las de p_fecha_in hasta p_fecha_out - 1.
   FUNCTION fn_valor_estadia (
      p_id_habitacion IN habitacion.id_habitacion%TYPE,
      p_fecha_in      IN DATE,
      p_fecha_out     IN DATE
   ) RETURN NUMBER;

   -- Igual que la anterior, pero imprime el cálculo por tramo de temporada.
   PROCEDURE sp_desglose_estadia (
      p_id_habitacion IN habitacion.id_habitacion%TYPE,
      p_fecha_in      IN DATE,
      p_fecha_out     IN DATE
   );

   -- 'S' si ninguna reserva no cancelada ocupa la habitación en esas noches.
   FUNCTION fn_habitacion_disponible (
      p_id_habitacion   IN habitacion.id_habitacion%TYPE,
      p_fecha_in        IN DATE,
      p_fecha_out       IN DATE,
      p_excluir_reserva IN reserva.id_reserva%TYPE DEFAULT NULL
   ) RETURN VARCHAR2;

   -- Crea una reserva (encabezado + primera habitación).
   PROCEDURE sp_crear_reserva (
      p_id_cliente     IN  cliente.id_cliente%TYPE,
      p_id_habitacion  IN  habitacion.id_habitacion%TYPE,
      p_fecha_in       IN  DATE,
      p_fecha_out      IN  DATE,
      p_num_huespedes  IN  NUMBER,
      p_id_reserva     OUT reserva.id_reserva%TYPE,
      p_estado         IN  VARCHAR2 DEFAULT 'PENDIENTE',
      p_observaciones  IN  VARCHAR2 DEFAULT NULL
   );

   -- Agrega otra habitación del mismo alojamiento a una reserva existente.
   PROCEDURE sp_agregar_habitacion (
      p_id_reserva     IN reserva.id_reserva%TYPE,
      p_id_habitacion  IN habitacion.id_habitacion%TYPE,
      p_fecha_in       IN DATE,
      p_fecha_out      IN DATE,
      p_num_huespedes  IN NUMBER
   );

   FUNCTION fn_total_reserva (p_id_reserva IN reserva.id_reserva%TYPE) RETURN NUMBER;
   FUNCTION fn_total_pagado  (p_id_reserva IN reserva.id_reserva%TYPE) RETURN NUMBER;
   FUNCTION fn_esta_pagada   (p_id_reserva IN reserva.id_reserva%TYPE) RETURN VARCHAR2;

   -- Cancela y aplica la regla: > 5 días antes del check-in => reembolso del 80 %.
   PROCEDURE sp_cancelar_reserva (
      p_id_reserva        IN reserva.id_reserva%TYPE,
      p_fecha_cancelacion IN DATE DEFAULT SYSDATE
   );

   -- Proceso masivo: liquidación de un mes para todos los alojamientos
   -- (o para uno solo si se indica p_id_alojamiento).
   PROCEDURE sp_liquidacion_mensual (
      p_anio           IN NUMBER,
      p_mes            IN NUMBER,
      p_id_alojamiento IN alojamiento.id_alojamiento%TYPE DEFAULT NULL
   );

END pkg_turismouq;
/

/* =====================================================================
   Sección 3. Cuerpo del paquete
   ===================================================================== */
CREATE OR REPLACE PACKAGE BODY pkg_turismouq AS

   /* ------------------------------------------------------------------
      Cursor explícito con parámetros (privado): tramos de temporada que
      se cruzan con la estadía [p_in, p_out) y la tarifa de la habitación
      en cada uno. Lo comparten fn_valor_estadia y sp_desglose_estadia.
      Una temporada se cruza con la estadía si empieza antes del check-out
      y termina (inclusive) en o después del check-in.
      ------------------------------------------------------------------ */
   CURSOR c_tramos (p_hab NUMBER, p_in DATE, p_out DATE) IS
      SELECT t.id_temporada, t.nombre, t.categoria, t.fecha_inicio, t.fecha_fin,
             tf.valor_noche
      FROM   temporada t
      LEFT   JOIN tarifa tf ON tf.id_temporada  = t.id_temporada
                           AND tf.id_habitacion = p_hab
      WHERE  t.fecha_inicio <  p_out
      AND    t.fecha_fin    >= p_in
      ORDER  BY t.fecha_inicio;

   /* ------------------------------------------------------------------
      Validaciones comunes de parámetros de fecha
      ------------------------------------------------------------------ */
   PROCEDURE p_validar_fechas (p_fecha_in IN DATE, p_fecha_out IN DATE) IS
   BEGIN
      IF p_fecha_in IS NULL OR p_fecha_out IS NULL THEN
         RAISE_APPLICATION_ERROR(c_err_parametro, 'Las fechas de check-in y check-out son obligatorias.');
      END IF;
      IF TRUNC(p_fecha_out) <= TRUNC(p_fecha_in) THEN
         RAISE_APPLICATION_ERROR(c_err_fechas,
            'El check-out (' || TO_CHAR(p_fecha_out, 'DD/MM/YYYY') || ') debe ser posterior al check-in ('
            || TO_CHAR(p_fecha_in, 'DD/MM/YYYY') || ').');
      END IF;
      IF TRUNC(p_fecha_out) - TRUNC(p_fecha_in) > c_max_noches THEN
         RAISE_APPLICATION_ERROR(c_err_fechas,
            'Una estadía no puede superar ' || c_max_noches || ' noches.');
      END IF;
   END p_validar_fechas;

   /* ------------------------------------------------------------------
      fn_valor_estadia
      Recorre los tramos de temporada que toca la estadía y, para cada
      uno, cuenta cuántas noches de la estadía caen dentro:
         noches_tramo = LEAST(check-out, fin_tramo + 1) - GREATEST(check-in, inicio_tramo)
      y las multiplica por la tarifa de la habitación en esa temporada.
      Ejemplo: 12-dic a 17-dic con corte MEDIA/ALTA el 15-dic
         tramo MEDIA: LEAST(17, 15) - GREATEST(12, 01) = 3 noches (12, 13, 14)
         tramo ALTA : LEAST(17, 11-ene) - GREATEST(12, 15) = 2 noches (15, 16)
      Si la suma de noches de los tramos no da el total de noches, hay
      días sin temporada definida: se rechaza en lugar de cobrar de menos.
      ------------------------------------------------------------------ */
   FUNCTION fn_valor_estadia (
      p_id_habitacion IN habitacion.id_habitacion%TYPE,
      p_fecha_in      IN DATE,
      p_fecha_out     IN DATE
   ) RETURN NUMBER IS
      v_in      DATE := TRUNC(p_fecha_in);
      v_out     DATE := TRUNC(p_fecha_out);
      v_existe  PLS_INTEGER;
      v_noches  PLS_INTEGER := 0;
      v_n       PLS_INTEGER;
      v_total   NUMBER := 0;
   BEGIN
      p_validar_fechas(p_fecha_in, p_fecha_out);

      SELECT COUNT(*) INTO v_existe FROM habitacion WHERE id_habitacion = p_id_habitacion;
      IF v_existe = 0 THEN
         RAISE_APPLICATION_ERROR(c_err_no_existe, 'La habitación ' || p_id_habitacion || ' no existe.');
      END IF;

      FOR r IN c_tramos(p_id_habitacion, v_in, v_out) LOOP
         v_n := LEAST(v_out, r.fecha_fin + 1) - GREATEST(v_in, r.fecha_inicio);
         IF r.valor_noche IS NULL THEN
            RAISE_APPLICATION_ERROR(c_err_sin_tarifa,
               'La habitación ' || p_id_habitacion || ' no tiene tarifa para la temporada "' || r.nombre || '".');
         END IF;
         v_total  := v_total + v_n * r.valor_noche;
         v_noches := v_noches + v_n;
      END LOOP;

      IF v_noches <> v_out - v_in THEN
         RAISE_APPLICATION_ERROR(c_err_sin_tarifa,
            'Hay ' || (v_out - v_in - v_noches) || ' noche(s) sin temporada definida entre el '
            || TO_CHAR(v_in, 'DD/MM/YYYY') || ' y el ' || TO_CHAR(v_out, 'DD/MM/YYYY') || '.');
      END IF;

      RETURN v_total;
   END fn_valor_estadia;

   /* ------------------------------------------------------------------
      sp_desglose_estadia: el mismo cálculo, mostrado tramo por tramo
      ------------------------------------------------------------------ */
   PROCEDURE sp_desglose_estadia (
      p_id_habitacion IN habitacion.id_habitacion%TYPE,
      p_fecha_in      IN DATE,
      p_fecha_out     IN DATE
   ) IS
      v_in  DATE := TRUNC(p_fecha_in);
      v_out DATE := TRUNC(p_fecha_out);
      v_n   PLS_INTEGER;
   BEGIN
      DBMS_OUTPUT.PUT_LINE('Habitación ' || p_id_habitacion || ' del ' || TO_CHAR(v_in, 'DD/MM/YYYY')
                           || ' al ' || TO_CHAR(v_out, 'DD/MM/YYYY') || ' (' || (v_out - v_in) || ' noches)');
      FOR r IN c_tramos(p_id_habitacion, v_in, v_out) LOOP
         v_n := LEAST(v_out, r.fecha_fin + 1) - GREATEST(v_in, r.fecha_inicio);
         DBMS_OUTPUT.PUT_LINE('   ' || RPAD(r.categoria, 6) || RPAD(r.nombre, 45) || LPAD(v_n, 3) || ' noche(s) x '
                              || TO_CHAR(r.valor_noche, 'FM999G999G999G990') || ' = '
                              || TO_CHAR(v_n * r.valor_noche, 'FM999G999G999G990'));
      END LOOP;
      DBMS_OUTPUT.PUT_LINE('   TOTAL = ' || TO_CHAR(fn_valor_estadia(p_id_habitacion, v_in, v_out), 'FM999G999G999G990'));
   END sp_desglose_estadia;

   /* ------------------------------------------------------------------
      fn_habitacion_disponible
      Dos rangos [a1, a2) y [b1, b2) se solapan si a1 < b2 AND b1 < a2.
      Así una reserva que entra el mismo día en que otra sale NO choca.
      ------------------------------------------------------------------ */
   FUNCTION fn_habitacion_disponible (
      p_id_habitacion   IN habitacion.id_habitacion%TYPE,
      p_fecha_in        IN DATE,
      p_fecha_out       IN DATE,
      p_excluir_reserva IN reserva.id_reserva%TYPE DEFAULT NULL
   ) RETURN VARCHAR2 IS
      v_choques PLS_INTEGER;
   BEGIN
      SELECT COUNT(*) INTO v_choques
      FROM   reserva_habitacion rh
      JOIN   reserva r ON r.id_reserva = rh.id_reserva
      WHERE  rh.id_habitacion  = p_id_habitacion
      AND    r.estado         <> 'CANCELADA'
      AND    rh.fecha_checkin  < TRUNC(p_fecha_out)
      AND    TRUNC(p_fecha_in) < rh.fecha_checkout
      AND    (p_excluir_reserva IS NULL OR rh.id_reserva <> p_excluir_reserva);
      RETURN CASE WHEN v_choques = 0 THEN 'S' ELSE 'N' END;
   END fn_habitacion_disponible;

   /* ------------------------------------------------------------------
      Validación de una línea de reserva (privada). Orden:
        1) fechas  2) habitación existe y está activa  3) capacidad
        4) disponibilidad. Devuelve el alojamiento de la habitación.
      ------------------------------------------------------------------ */
   PROCEDURE p_validar_linea (
      p_id_habitacion  IN  NUMBER,
      p_fecha_in       IN  DATE,
      p_fecha_out      IN  DATE,
      p_num_huespedes  IN  NUMBER,
      p_id_alojamiento OUT NUMBER
   ) IS
      v_cap     habitacion.capacidad_max%TYPE;
      v_activa  habitacion.activa%TYPE;
      v_otra    reserva.id_reserva%TYPE;
   BEGIN
      p_validar_fechas(p_fecha_in, p_fecha_out);
      IF TRUNC(p_fecha_in) < TRUNC(SYSDATE) THEN
         RAISE_APPLICATION_ERROR(c_err_fecha_pasada,
            'No se puede reservar con check-in en el pasado (' || TO_CHAR(p_fecha_in, 'DD/MM/YYYY') || ').');
      END IF;

      BEGIN
         SELECT id_alojamiento, capacidad_max, activa
         INTO   p_id_alojamiento, v_cap, v_activa
         FROM   habitacion
         WHERE  id_habitacion = p_id_habitacion;
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(c_err_no_existe, 'La habitación ' || p_id_habitacion || ' no existe.');
      END;
      IF v_activa = 'N' THEN
         RAISE_APPLICATION_ERROR(c_err_no_existe, 'La habitación ' || p_id_habitacion || ' está inactiva.');
      END IF;

      IF p_num_huespedes IS NULL OR p_num_huespedes < 1 OR p_num_huespedes > v_cap THEN
         RAISE_APPLICATION_ERROR(c_err_capacidad,
            'Capacidad excedida: la habitación ' || p_id_habitacion || ' admite máximo ' || v_cap
            || ' huésped(es) y se solicitaron ' || NVL(TO_CHAR(p_num_huespedes), 'NULL') || '.');
      END IF;

      SELECT MIN(rh.id_reserva) INTO v_otra
      FROM   reserva_habitacion rh
      JOIN   reserva r ON r.id_reserva = rh.id_reserva
      WHERE  rh.id_habitacion  = p_id_habitacion
      AND    r.estado         <> 'CANCELADA'
      AND    rh.fecha_checkin  < TRUNC(p_fecha_out)
      AND    TRUNC(p_fecha_in) < rh.fecha_checkout;
      IF v_otra IS NOT NULL THEN
         RAISE_APPLICATION_ERROR(c_err_no_disponible,
            'Habitación ' || p_id_habitacion || ' no disponible del ' || TO_CHAR(p_fecha_in, 'DD/MM/YYYY')
            || ' al ' || TO_CHAR(p_fecha_out, 'DD/MM/YYYY') || ': ya está ocupada por la reserva ' || v_otra || '.');
      END IF;
   END p_validar_linea;

   /* ------------------------------------------------------------------
      sp_crear_reserva
      ------------------------------------------------------------------ */
   PROCEDURE sp_crear_reserva (
      p_id_cliente     IN  cliente.id_cliente%TYPE,
      p_id_habitacion  IN  habitacion.id_habitacion%TYPE,
      p_fecha_in       IN  DATE,
      p_fecha_out      IN  DATE,
      p_num_huespedes  IN  NUMBER,
      p_id_reserva     OUT reserva.id_reserva%TYPE,
      p_estado         IN  VARCHAR2 DEFAULT 'PENDIENTE',
      p_observaciones  IN  VARCHAR2 DEFAULT NULL
   ) IS
      v_existe  PLS_INTEGER;
      v_aloj    alojamiento.id_alojamiento%TYPE;
      v_valor   NUMBER;
   BEGIN
      IF p_estado NOT IN ('PENDIENTE', 'CONFIRMADA') OR p_estado IS NULL THEN
         RAISE_APPLICATION_ERROR(c_err_parametro,
            'Una reserva nueva solo puede nacer PENDIENTE o CONFIRMADA (se recibió ' || NVL(p_estado, 'NULL') || ').');
      END IF;

      SELECT COUNT(*) INTO v_existe FROM cliente WHERE id_cliente = p_id_cliente;
      IF v_existe = 0 THEN
         RAISE_APPLICATION_ERROR(c_err_no_existe, 'El cliente ' || NVL(TO_CHAR(p_id_cliente), 'NULL') || ' no existe.');
      END IF;

      -- fechas, existencia, capacidad y disponibilidad
      p_validar_linea(p_id_habitacion, p_fecha_in, p_fecha_out, p_num_huespedes, v_aloj);

      -- valor noche por noche, cruzando temporadas
      v_valor := fn_valor_estadia(p_id_habitacion, p_fecha_in, p_fecha_out);

      INSERT INTO reserva (id_cliente, id_alojamiento, fecha_reserva, fecha_checkin,
                           fecha_checkout, estado, observaciones)
      VALUES (p_id_cliente, v_aloj, SYSDATE, TRUNC(p_fecha_in), TRUNC(p_fecha_out),
              p_estado, p_observaciones)
      RETURNING id_reserva INTO p_id_reserva;

      INSERT INTO reserva_habitacion (id_reserva, id_alojamiento, id_habitacion, fecha_checkin,
                                      fecha_checkout, num_huespedes, valor_estadia)
      VALUES (p_id_reserva, v_aloj, p_id_habitacion, TRUNC(p_fecha_in), TRUNC(p_fecha_out),
              p_num_huespedes, v_valor);

      DBMS_OUTPUT.PUT_LINE('Reserva ' || p_id_reserva || ' creada (' || p_estado || '): habitación '
                           || p_id_habitacion || ', ' || (TRUNC(p_fecha_out) - TRUNC(p_fecha_in))
                           || ' noches, valor ' || TO_CHAR(v_valor, 'FM$999G999G990'));
   END sp_crear_reserva;

   /* ------------------------------------------------------------------
      sp_agregar_habitacion: segunda, tercera... habitación de un grupo.
      La línea puede tener fechas propias; el rango general de la reserva
      se amplía para seguir siendo el mínimo check-in y el máximo check-out.
      ------------------------------------------------------------------ */
   PROCEDURE sp_agregar_habitacion (
      p_id_reserva     IN reserva.id_reserva%TYPE,
      p_id_habitacion  IN habitacion.id_habitacion%TYPE,
      p_fecha_in       IN DATE,
      p_fecha_out      IN DATE,
      p_num_huespedes  IN NUMBER
   ) IS
      v_aloj_res  reserva.id_alojamiento%TYPE;
      v_estado    reserva.estado%TYPE;
      v_aloj_hab  habitacion.id_alojamiento%TYPE;
      v_valor     NUMBER;
   BEGIN
      BEGIN
         SELECT id_alojamiento, estado INTO v_aloj_res, v_estado
         FROM   reserva
         WHERE  id_reserva = p_id_reserva
         FOR UPDATE;                                  -- bloquea el encabezado mientras se agrega la línea
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(c_err_no_existe, 'La reserva ' || p_id_reserva || ' no existe.');
      END;
      IF v_estado NOT IN ('PENDIENTE', 'CONFIRMADA') THEN
         RAISE_APPLICATION_ERROR(c_err_estado,
            'No se pueden agregar habitaciones a una reserva ' || v_estado || '.');
      END IF;

      p_validar_linea(p_id_habitacion, p_fecha_in, p_fecha_out, p_num_huespedes, v_aloj_hab);
      IF v_aloj_hab <> v_aloj_res THEN
         RAISE_APPLICATION_ERROR(c_err_parametro,
            'La habitación ' || p_id_habitacion || ' pertenece a otro alojamiento distinto al de la reserva.');
      END IF;

      v_valor := fn_valor_estadia(p_id_habitacion, p_fecha_in, p_fecha_out);

      INSERT INTO reserva_habitacion (id_reserva, id_alojamiento, id_habitacion, fecha_checkin,
                                      fecha_checkout, num_huespedes, valor_estadia)
      VALUES (p_id_reserva, v_aloj_res, p_id_habitacion, TRUNC(p_fecha_in), TRUNC(p_fecha_out),
              p_num_huespedes, v_valor);

      UPDATE reserva
      SET    fecha_checkin  = LEAST(fecha_checkin, TRUNC(p_fecha_in)),
             fecha_checkout = GREATEST(fecha_checkout, TRUNC(p_fecha_out))
      WHERE  id_reserva = p_id_reserva;

      DBMS_OUTPUT.PUT_LINE('Habitación ' || p_id_habitacion || ' agregada a la reserva ' || p_id_reserva
                           || ', valor ' || TO_CHAR(v_valor, 'FM$999G999G990'));
   END sp_agregar_habitacion;

   /* ------------------------------------------------------------------
      Totales de una reserva
      ------------------------------------------------------------------ */
   FUNCTION fn_total_reserva (p_id_reserva IN reserva.id_reserva%TYPE) RETURN NUMBER IS
      v_estadia   NUMBER;
      v_servicios NUMBER;
   BEGIN
      SELECT NVL(SUM(valor_estadia), 0) INTO v_estadia
      FROM   reserva_habitacion WHERE id_reserva = p_id_reserva;
      SELECT NVL(SUM(subtotal), 0) INTO v_servicios
      FROM   reserva_servicio WHERE id_reserva = p_id_reserva;
      RETURN v_estadia + v_servicios;
   END fn_total_reserva;

   FUNCTION fn_total_pagado (p_id_reserva IN reserva.id_reserva%TYPE) RETURN NUMBER IS
      v_pagado NUMBER;
   BEGIN
      SELECT NVL(SUM(monto), 0) INTO v_pagado
      FROM   pago
      WHERE  id_reserva = p_id_reserva
      AND    estado = 'EXITOSO';
      RETURN v_pagado;
   END fn_total_pagado;

   -- Regla R9: pagada si los pagos EXITOSOS cubren estadía + servicios
   FUNCTION fn_esta_pagada (p_id_reserva IN reserva.id_reserva%TYPE) RETURN VARCHAR2 IS
      v_total NUMBER := fn_total_reserva(p_id_reserva);
   BEGIN
      RETURN CASE WHEN v_total > 0 AND fn_total_pagado(p_id_reserva) >= v_total THEN 'S' ELSE 'N' END;
   END fn_esta_pagada;

   /* ------------------------------------------------------------------
      sp_cancelar_reserva: regla R1
        días de anticipación = check-in - fecha de cancelación
        > 5 días  -> los pagos EXITOSOS pasan a REEMBOLSADO con el 80 %
        <= 5 días -> no hay reembolso (los pagos quedan EXITOSOS)
        Los pagos PENDIENTES se anulan (FALLIDO).
      p_fecha_cancelacion permite simular la fecha en las pruebas.
      ------------------------------------------------------------------ */
   PROCEDURE sp_cancelar_reserva (
      p_id_reserva        IN reserva.id_reserva%TYPE,
      p_fecha_cancelacion IN DATE DEFAULT SYSDATE
   ) IS
      v_estado    reserva.estado%TYPE;
      v_checkin   reserva.fecha_checkin%TYPE;
      v_freserva  reserva.fecha_reserva%TYPE;
      v_dias      NUMBER;
      v_reemb     NUMBER := 0;
   BEGIN
      BEGIN
         SELECT estado, fecha_checkin, fecha_reserva
         INTO   v_estado, v_checkin, v_freserva
         FROM   reserva
         WHERE  id_reserva = p_id_reserva
         FOR UPDATE;
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(c_err_no_existe, 'La reserva ' || p_id_reserva || ' no existe.');
      END;

      IF v_estado IN ('CANCELADA', 'COMPLETADA') THEN
         RAISE_APPLICATION_ERROR(c_err_estado, 'La reserva ' || p_id_reserva || ' ya está ' || v_estado || '.');
      END IF;
      IF p_fecha_cancelacion IS NULL OR p_fecha_cancelacion < v_freserva
         OR TRUNC(p_fecha_cancelacion) > v_checkin THEN
         RAISE_APPLICATION_ERROR(c_err_fechas,
            'La cancelación debe registrarse entre la fecha de la reserva y el día del check-in.');
      END IF;

      v_dias := v_checkin - TRUNC(p_fecha_cancelacion);

      UPDATE reserva
      SET    estado = 'CANCELADA', fecha_cancelacion = p_fecha_cancelacion
      WHERE  id_reserva = p_id_reserva;

      IF v_dias > c_dias_reembolso THEN
         UPDATE pago
         SET    estado            = 'REEMBOLSADO',
                monto_reembolsado = ROUND(monto * c_pct_reembolso, 2),
                fecha_reembolso   = GREATEST(p_fecha_cancelacion, fecha_pago)
         WHERE  id_reserva = p_id_reserva
         AND    estado     = 'EXITOSO';

         SELECT NVL(SUM(monto_reembolsado), 0) INTO v_reemb
         FROM   pago WHERE id_reserva = p_id_reserva AND estado = 'REEMBOLSADO';
      END IF;

      UPDATE pago SET estado = 'FALLIDO'
      WHERE  id_reserva = p_id_reserva AND estado = 'PENDIENTE';

      DBMS_OUTPUT.PUT_LINE('Reserva ' || p_id_reserva || ' cancelada con ' || v_dias || ' día(s) de anticipación: '
                           || CASE WHEN v_dias > c_dias_reembolso
                                   THEN 'reembolso del 80 % = ' || TO_CHAR(v_reemb, 'FM$999G999G990')
                                   ELSE 'sin reembolso (5 días o menos)' END);
   END sp_cancelar_reserva;

   /* ------------------------------------------------------------------
      sp_liquidacion_mensual · PROCESO MASIVO CON CURSORES EXPLÍCITOS
      CON PARÁMETROS
        c_alojamientos(cp_id)            -> alojamientos a liquidar
        c_hospedaje(cp_aloj, cp_ini, cp_fin)   -> noches del mes y su valor
        c_servicios(cp_aloj, cp_ini, cp_fin)   -> servicios prestados en el mes
        c_cancelaciones(cp_aloj, cp_ini, cp_fin) -> dinero retenido por
                                                  cancelaciones del mes
      Por cada alojamiento: total bruto, comisión de TurismoUQ (12 % del
      hospedaje y de lo retenido, 8 % de servicios) y neto a girar.
      El resultado queda en LIQUIDACION_MENSUAL (se reemplaza si el mes ya
      se había liquidado) y se imprime un resumen.
      ------------------------------------------------------------------ */
   PROCEDURE sp_liquidacion_mensual (
      p_anio           IN NUMBER,
      p_mes            IN NUMBER,
      p_id_alojamiento IN alojamiento.id_alojamiento%TYPE DEFAULT NULL
   ) IS
      CURSOR c_alojamientos (cp_id NUMBER) IS
         SELECT a.id_alojamiento, a.nombre_comercial, m.nombre AS municipio
         FROM   alojamiento a
         JOIN   municipio m ON m.id_municipio = a.id_municipio
         WHERE  cp_id IS NULL OR a.id_alojamiento = cp_id
         ORDER  BY m.nombre, a.nombre_comercial;

      CURSOR c_hospedaje (cp_aloj NUMBER, cp_ini DATE, cp_fin DATE) IS
         SELECT COUNT(*)                       AS noches,
                NVL(SUM(tf.valor_noche), 0)    AS valor,
                COUNT(DISTINCT rh.id_reserva)  AS reservas
         FROM   reserva_habitacion rh
         JOIN   reserva r     ON r.id_reserva = rh.id_reserva
         JOIN   calendario c  ON c.fecha >= rh.fecha_checkin
                             AND c.fecha <  rh.fecha_checkout
         JOIN   tarifa tf     ON tf.id_habitacion = rh.id_habitacion
                             AND tf.id_temporada  = c.id_temporada
         WHERE  rh.id_alojamiento = cp_aloj
         AND    r.estado IN ('CONFIRMADA', 'COMPLETADA')
         AND    c.fecha BETWEEN cp_ini AND cp_fin;

      CURSOR c_servicios (cp_aloj NUMBER, cp_ini DATE, cp_fin DATE) IS
         SELECT NVL(SUM(rs.subtotal), 0) AS valor
         FROM   reserva_servicio rs
         JOIN   reserva r ON r.id_reserva = rs.id_reserva
         WHERE  rs.id_alojamiento = cp_aloj
         AND    r.estado IN ('CONFIRMADA', 'COMPLETADA')
         AND    rs.fecha_servicio BETWEEN cp_ini AND cp_fin;

      CURSOR c_cancelaciones (cp_aloj NUMBER, cp_ini DATE, cp_fin DATE) IS
         SELECT NVL(SUM(CASE p.estado WHEN 'EXITOSO'     THEN p.monto
                                      WHEN 'REEMBOLSADO' THEN p.monto - p.monto_reembolsado
                                      ELSE 0 END), 0) AS valor
         FROM   reserva r
         JOIN   pago p ON p.id_reserva = r.id_reserva
         WHERE  r.id_alojamiento = cp_aloj
         AND    r.estado = 'CANCELADA'
         AND    r.fecha_cancelacion >= cp_ini
         AND    r.fecha_cancelacion <  cp_fin + 1;

      r_aloj    c_alojamientos%ROWTYPE;
      r_hosp    c_hospedaje%ROWTYPE;
      v_serv    NUMBER;
      v_canc    NUMBER;
      v_bruto   NUMBER;
      v_comis   NUMBER;
      v_ini     DATE;
      v_fin     DATE;
      v_existe  PLS_INTEGER;
      v_n       PLS_INTEGER := 0;
      v_tot_b   NUMBER := 0;
      v_tot_c   NUMBER := 0;
      v_tot_n   NUMBER := 0;
   BEGIN
      IF p_anio IS NULL OR p_mes IS NULL OR p_mes NOT BETWEEN 1 AND 12 THEN
         RAISE_APPLICATION_ERROR(c_err_parametro, 'Año y mes (1-12) son obligatorios.');
      END IF;
      v_ini := TO_DATE(p_anio || '-' || LPAD(p_mes, 2, '0') || '-01', 'YYYY-MM-DD');
      v_fin := LAST_DAY(v_ini);

      SELECT COUNT(*) INTO v_existe FROM calendario WHERE fecha = v_ini;
      IF v_existe = 0 THEN
         RAISE_APPLICATION_ERROR(c_err_sin_tarifa, 'El mes ' || TO_CHAR(v_ini, 'MM/YYYY') || ' está fuera del calendario.');
      END IF;

      -- el proceso es repetible: si el mes ya se liquidó, se reemplaza
      DELETE FROM liquidacion_mensual
      WHERE  anio = p_anio AND mes = p_mes
      AND    (p_id_alojamiento IS NULL OR id_alojamiento = p_id_alojamiento);

      DBMS_OUTPUT.PUT_LINE('LIQUIDACIÓN ' || TO_CHAR(v_ini, 'MM/YYYY'));
      DBMS_OUTPUT.PUT_LINE(RPAD('Municipio', 13) || RPAD('Alojamiento', 40) || LPAD('Noches', 7)
                           || LPAD('Bruto', 17) || LPAD('Comisión', 15) || LPAD('Neto', 17));

      OPEN c_alojamientos(p_id_alojamiento);
      LOOP
         FETCH c_alojamientos INTO r_aloj;
         EXIT WHEN c_alojamientos%NOTFOUND;

         OPEN c_hospedaje(r_aloj.id_alojamiento, v_ini, v_fin);
         FETCH c_hospedaje INTO r_hosp;
         CLOSE c_hospedaje;

         OPEN c_servicios(r_aloj.id_alojamiento, v_ini, v_fin);
         FETCH c_servicios INTO v_serv;
         CLOSE c_servicios;

         OPEN c_cancelaciones(r_aloj.id_alojamiento, v_ini, v_fin);
         FETCH c_cancelaciones INTO v_canc;
         CLOSE c_cancelaciones;

         v_bruto := r_hosp.valor + v_serv + v_canc;
         v_comis := ROUND(r_hosp.valor * c_comision_hospedaje
                        + v_serv       * c_comision_servicios
                        + v_canc       * c_comision_hospedaje, 2);

         INSERT INTO liquidacion_mensual (anio, mes, id_alojamiento, reservas, noches_vendidas,
                                          ingreso_hospedaje, ingreso_servicios, ingreso_cancelaciones,
                                          total_bruto, comision_plataforma, neto_alojamiento)
         VALUES (p_anio, p_mes, r_aloj.id_alojamiento, r_hosp.reservas, r_hosp.noches,
                 r_hosp.valor, v_serv, v_canc, v_bruto, v_comis, v_bruto - v_comis);

         DBMS_OUTPUT.PUT_LINE(RPAD(r_aloj.municipio, 13) || RPAD(SUBSTR(r_aloj.nombre_comercial, 1, 39), 40)
                              || LPAD(r_hosp.noches, 7)
                              || LPAD(TO_CHAR(v_bruto, 'FM999G999G999G990'), 17)
                              || LPAD(TO_CHAR(v_comis, 'FM999G999G999G990'), 15)
                              || LPAD(TO_CHAR(v_bruto - v_comis, 'FM999G999G999G990'), 17));
         v_n     := v_n + 1;
         v_tot_b := v_tot_b + v_bruto;
         v_tot_c := v_tot_c + v_comis;
         v_tot_n := v_tot_n + (v_bruto - v_comis);
      END LOOP;
      CLOSE c_alojamientos;

      IF v_n = 0 THEN
         RAISE_APPLICATION_ERROR(c_err_no_existe, 'No hay alojamientos para liquidar con ese filtro.');
      END IF;

      COMMIT;   -- proceso batch: se confirma completo al final
      DBMS_OUTPUT.PUT_LINE(RPAD('TOTAL (' || v_n || ' alojamientos)', 60)
                           || LPAD(TO_CHAR(v_tot_b, 'FM999G999G999G990'), 17)
                           || LPAD(TO_CHAR(v_tot_c, 'FM999G999G999G990'), 15)
                           || LPAD(TO_CHAR(v_tot_n, 'FM999G999G999G990'), 17));
   EXCEPTION
      WHEN OTHERS THEN
         IF c_alojamientos%ISOPEN  THEN CLOSE c_alojamientos;  END IF;
         IF c_hospedaje%ISOPEN     THEN CLOSE c_hospedaje;     END IF;
         IF c_servicios%ISOPEN     THEN CLOSE c_servicios;     END IF;
         IF c_cancelaciones%ISOPEN THEN CLOSE c_cancelaciones; END IF;
         ROLLBACK;
         RAISE;
   END sp_liquidacion_mensual;

END pkg_turismouq;
/

/* =====================================================================
   Sección 4. Verificación: el paquete debe quedar VALID
   ===================================================================== */
SHOW ERRORS PACKAGE pkg_turismouq
SHOW ERRORS PACKAGE BODY pkg_turismouq

SELECT object_name, object_type, status
FROM   user_objects
WHERE  object_name = 'PKG_TURISMOUQ'
ORDER  BY object_type;


/* #####################################################################
   PARTE 2 · DISPARADORES: auditoría de TARIFA (sentencia) y anti-solape (fila)
   ##################################################################### */

/* =====================================================================
   TurismoUQ · Proyecto integrador Bases de Datos II · 2026-2
   Script 06 · Disparadores (Entrega 2)
   ---------------------------------------------------------------------
   Ejecutar como TURISMOUQ, después de 05.

   Parte A · Auditoría de TARIFA con disparador A NIVEL DE SENTENCIA
     Registra quién, cuándo, desde dónde, qué operación, cuántas filas y,
     para cada tarifa afectada, el valor anterior y el nuevo.

     Problema técnico: un disparador de sentencia se ejecuta UNA vez por
     instrucción y NO tiene acceso a :OLD ni a :NEW. Solución clásica en
     tres piezas que trabajan juntas:
       1. trg_tarifa_aud_inicio  (BEFORE, sentencia) limpia el buffer.
       2. trg_tarifa_aud_fila    (AFTER, fila) solo ANOTA en memoria el
          valor anterior y el nuevo de cada fila (no hace DML).
       3. trg_tarifa_auditoria   (AFTER, SENTENCIA) es el que AUDITA:
          inserta un encabezado por instrucción (usuario, equipo,
          programa, fecha y hora, operación, filas afectadas) y vuelca
          el detalle anotado con FORALL, en una sola pasada.
     Ventajas: un único registro por instrucción con una sola marca de
     tiempo; se audita también un UPDATE que no afectó filas (alguien lo
     intentó); y el volcado masivo es más eficiente que insertar fila a
     fila desde el disparador de fila.

   Parte B · Anti-solape de reservas con disparador A NIVEL DE FILA
     Impide registrar (o modificar) una línea de RESERVA_HABITACION cuyas
     noches se crucen con otra línea no cancelada de la misma habitación.

     Problema técnico: un disparador FOR EACH ROW no puede consultar la
     misma tabla que está modificando (ORA-04091, tabla mutante) en un
     UPDATE o en un INSERT ... SELECT. Se implementa como COMPOUND
     TRIGGER, la forma que Oracle recomienda desde 11g:
       · BEFORE EACH ROW : valida la fila (fechas).
       · AFTER EACH ROW  : toma nota del id de la fila escrita.
       · AFTER STATEMENT : cuando la tabla ya no está "mutando", revisa
                           cada fila anotada contra las demás y lanza
                           RAISE_APPLICATION_ERROR(-20001) si hay solape,
                           lo que deshace la instrucción completa.
     Funciona igual para INSERT ... VALUES, INSERT ... SELECT y UPDATE.
     sp_crear_reserva ya valida antes de insertar; el disparador es la
     red de seguridad para cualquier otro programa o un INSERT manual.
   ===================================================================== */

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET SQLBLANKLINES ON

/* =====================================================================
   Parte A · Auditoría de TARIFA
   ===================================================================== */

-- A.1 Limpieza
BEGIN
   FOR t IN (SELECT 'AUDITORIA_TARIFA_DETALLE' AS n FROM dual UNION ALL
             SELECT 'AUDITORIA_TARIFA_OPERACION' FROM dual) LOOP
      BEGIN
         EXECUTE IMMEDIATE 'DROP TABLE ' || t.n || ' CASCADE CONSTRAINTS PURGE';
      EXCEPTION
         WHEN OTHERS THEN IF SQLCODE <> -942 THEN RAISE; END IF;
      END;
   END LOOP;
END;
/

-- A.2 Tablas de auditoría: encabezado (una fila por instrucción) y detalle (una por tarifa)
CREATE TABLE auditoria_tarifa_operacion (
   id_operacion     NUMBER(10) GENERATED BY DEFAULT AS IDENTITY,
   operacion        VARCHAR2(6)    NOT NULL,
   filas_afectadas  NUMBER(8)      NOT NULL,
   usuario_bd       VARCHAR2(128)  NOT NULL,
   usuario_so       VARCHAR2(128),
   equipo           VARCHAR2(128),
   programa         VARCHAR2(128),
   fecha_hora       TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
   CONSTRAINT pk_aud_tarifa_operacion PRIMARY KEY (id_operacion),
   CONSTRAINT ck_aud_tarifa_operacion CHECK (operacion IN ('INSERT', 'UPDATE', 'DELETE')),
   CONSTRAINT ck_aud_tarifa_filas     CHECK (filas_afectadas >= 0)
);

CREATE TABLE auditoria_tarifa_detalle (
   id_detalle       NUMBER(12) GENERATED BY DEFAULT AS IDENTITY,
   id_operacion     NUMBER(10)     NOT NULL,
   id_tarifa        NUMBER(8)      NOT NULL,
   id_habitacion    NUMBER(6)      NOT NULL,
   id_temporada     NUMBER(4)      NOT NULL,
   valor_anterior   NUMBER(10,2),                 -- NULL en un INSERT
   valor_nuevo      NUMBER(10,2),                 -- NULL en un DELETE
   diferencia       NUMBER(12,2) GENERATED ALWAYS AS (valor_nuevo - valor_anterior) VIRTUAL,
   CONSTRAINT pk_aud_tarifa_detalle PRIMARY KEY (id_detalle),
   CONSTRAINT fk_aud_detalle_oper   FOREIGN KEY (id_operacion)
                                    REFERENCES auditoria_tarifa_operacion (id_operacion)
);
-- Sin FK hacia TARIFA a propósito: la auditoría debe sobrevivir al borrado de la tarifa.

COMMENT ON TABLE auditoria_tarifa_operacion IS 'Una fila por instrucción INSERT/UPDATE/DELETE sobre TARIFA: quién, cuándo, desde dónde y cuántas filas.';
COMMENT ON TABLE auditoria_tarifa_detalle   IS 'Valor anterior y nuevo de cada tarifa afectada por una operación auditada.';

-- A.3 Paquete de apoyo: buffer en memoria compartido por los tres disparadores
CREATE OR REPLACE PACKAGE pkg_auditoria_tarifa AS
   PROCEDURE iniciar;
   PROCEDURE anotar (p_id_tarifa     IN NUMBER,
                     p_id_habitacion IN NUMBER,
                     p_id_temporada  IN NUMBER,
                     p_anterior      IN NUMBER,
                     p_nuevo         IN NUMBER);
   PROCEDURE registrar (p_operacion IN VARCHAR2);
END pkg_auditoria_tarifa;
/

CREATE OR REPLACE PACKAGE BODY pkg_auditoria_tarifa AS

   TYPE t_cambio IS RECORD (
      id_tarifa     NUMBER,
      id_habitacion NUMBER,
      id_temporada  NUMBER,
      anterior      NUMBER,
      nuevo         NUMBER
   );
   TYPE t_cambios IS TABLE OF t_cambio INDEX BY PLS_INTEGER;
   g_cambios t_cambios;                         -- vive mientras dura la sesión

   PROCEDURE iniciar IS
   BEGIN
      g_cambios.DELETE;
   END iniciar;

   PROCEDURE anotar (p_id_tarifa     IN NUMBER,
                     p_id_habitacion IN NUMBER,
                     p_id_temporada  IN NUMBER,
                     p_anterior      IN NUMBER,
                     p_nuevo         IN NUMBER) IS
      v_i PLS_INTEGER := g_cambios.COUNT + 1;
   BEGIN
      g_cambios(v_i).id_tarifa     := p_id_tarifa;
      g_cambios(v_i).id_habitacion := p_id_habitacion;
      g_cambios(v_i).id_temporada  := p_id_temporada;
      g_cambios(v_i).anterior      := p_anterior;
      g_cambios(v_i).nuevo         := p_nuevo;
   END anotar;

   PROCEDURE registrar (p_operacion IN VARCHAR2) IS
      v_id    auditoria_tarifa_operacion.id_operacion%TYPE;
      v_filas PLS_INTEGER := g_cambios.COUNT;   -- un método de colección no se puede usar dentro de SQL
   BEGIN
      INSERT INTO auditoria_tarifa_operacion (operacion, filas_afectadas, usuario_bd,
                                              usuario_so, equipo, programa, fecha_hora)
      VALUES (p_operacion, v_filas, USER,
              SYS_CONTEXT('USERENV', 'OS_USER'),
              SYS_CONTEXT('USERENV', 'HOST'),
              SYS_CONTEXT('USERENV', 'MODULE'),
              SYSTIMESTAMP)
      RETURNING id_operacion INTO v_id;

      FORALL i IN 1 .. g_cambios.COUNT
         INSERT INTO auditoria_tarifa_detalle (id_operacion, id_tarifa, id_habitacion,
                                               id_temporada, valor_anterior, valor_nuevo)
         VALUES (v_id, g_cambios(i).id_tarifa, g_cambios(i).id_habitacion,
                 g_cambios(i).id_temporada, g_cambios(i).anterior, g_cambios(i).nuevo);

      g_cambios.DELETE;
   END registrar;

END pkg_auditoria_tarifa;
/

-- A.4 Disparador de sentencia previo: arranca con el buffer vacío
CREATE OR REPLACE TRIGGER trg_tarifa_aud_inicio
BEFORE INSERT OR UPDATE OF valor_noche OR DELETE ON tarifa
BEGIN
   pkg_auditoria_tarifa.iniciar;
END trg_tarifa_aud_inicio;
/

-- A.5 Disparador de fila: solo anota valor anterior / nuevo (un UPDATE que
--     deja el mismo valor no se anota porque no es un cambio real)
CREATE OR REPLACE TRIGGER trg_tarifa_aud_fila
AFTER INSERT OR UPDATE OF valor_noche OR DELETE ON tarifa
FOR EACH ROW
BEGIN
   IF INSERTING OR DELETING OR (:OLD.valor_noche <> :NEW.valor_noche) THEN
      pkg_auditoria_tarifa.anotar(NVL(:NEW.id_tarifa,     :OLD.id_tarifa),
                                  NVL(:NEW.id_habitacion, :OLD.id_habitacion),
                                  NVL(:NEW.id_temporada,  :OLD.id_temporada),
                                  :OLD.valor_noche,
                                  :NEW.valor_noche);
   END IF;
END trg_tarifa_aud_fila;
/

-- A.6 DISPARADOR A NIVEL DE SENTENCIA: registra la auditoría de la instrucción
CREATE OR REPLACE TRIGGER trg_tarifa_auditoria
AFTER INSERT OR UPDATE OF valor_noche OR DELETE ON tarifa
BEGIN
   pkg_auditoria_tarifa.registrar(
      CASE WHEN INSERTING THEN 'INSERT'
           WHEN UPDATING  THEN 'UPDATE'
           ELSE                'DELETE' END);
END trg_tarifa_auditoria;
/

/* =====================================================================
   Parte B · Anti-solape de reservas (nivel de fila, COMPOUND TRIGGER)
   Dos líneas se solapan si a.checkin < b.checkout AND b.checkin < a.checkout.
   Una reserva que entra el día en que otra sale no choca.
   Solo cuentan reservas no canceladas: una reserva CANCELADA libera la
   habitación (el enunciado exige bloquear contra las confirmadas; se
   bloquea también contra PENDIENTE y COMPLETADA porque igual tienen la
   habitación asignada).
   ===================================================================== */
CREATE OR REPLACE TRIGGER trg_rh_no_solape
FOR INSERT OR UPDATE OF id_habitacion, fecha_checkin, fecha_checkout ON reserva_habitacion
COMPOUND TRIGGER

   TYPE t_ids IS TABLE OF reserva_habitacion.id_reserva_habitacion%TYPE INDEX BY PLS_INTEGER;
   g_ids t_ids;

   BEFORE STATEMENT IS
   BEGIN
      g_ids.DELETE;
   END BEFORE STATEMENT;

   -- Validación propia de cada fila (antes de escribirla)
   BEFORE EACH ROW IS
   BEGIN
      IF :NEW.fecha_checkout <= :NEW.fecha_checkin THEN
         RAISE_APPLICATION_ERROR(-20002,
            'Línea de reserva inválida: el check-out debe ser posterior al check-in.');
      END IF;
   END BEFORE EACH ROW;

   -- Registro del id de cada fila escrita (ya con su identidad asignada)
   AFTER EACH ROW IS
   BEGIN
      g_ids(g_ids.COUNT + 1) := :NEW.id_reserva_habitacion;
   END AFTER EACH ROW;

   -- Verificación contra la tabla, cuando ya no está mutando
   AFTER STATEMENT IS
      v_otra    reserva.id_reserva%TYPE;
      v_hab     reserva_habitacion.id_habitacion%TYPE;
      v_in      DATE;
      v_out     DATE;
      v_estado  reserva.estado%TYPE;
   BEGIN
      FOR i IN 1 .. g_ids.COUNT LOOP
         SELECT n.id_habitacion, n.fecha_checkin, n.fecha_checkout, rn.estado
         INTO   v_hab, v_in, v_out, v_estado
         FROM   reserva_habitacion n
         JOIN   reserva rn ON rn.id_reserva = n.id_reserva
         WHERE  n.id_reserva_habitacion = g_ids(i);

         IF v_estado <> 'CANCELADA' THEN
            SELECT MIN(o.id_reserva) INTO v_otra
            FROM   reserva_habitacion o
            JOIN   reserva ro ON ro.id_reserva = o.id_reserva
            WHERE  o.id_habitacion          = v_hab
            AND    o.id_reserva_habitacion <> g_ids(i)
            AND    ro.estado               <> 'CANCELADA'
            AND    o.fecha_checkin          < v_out
            AND    v_in                     < o.fecha_checkout;

            IF v_otra IS NOT NULL THEN
               RAISE_APPLICATION_ERROR(-20001,
                  'Solape de reservas: la habitación ' || v_hab || ' ya está ocupada por la reserva '
                  || v_otra || ' entre el ' || TO_CHAR(v_in, 'DD/MM/YYYY') || ' y el '
                  || TO_CHAR(v_out, 'DD/MM/YYYY') || '.');
            END IF;
         END IF;
      END LOOP;
      g_ids.DELETE;
   END AFTER STATEMENT;

END trg_rh_no_solape;
/

/* =====================================================================
   Verificación: los disparadores deben quedar ENABLED y VALID
   ===================================================================== */
SHOW ERRORS TRIGGER trg_rh_no_solape

SELECT t.trigger_name, t.trigger_type, t.triggering_event, t.table_name, t.status, o.status AS compilacion
FROM   user_triggers t
JOIN   user_objects o ON o.object_name = t.trigger_name AND o.object_type = 'TRIGGER'
WHERE  t.table_name IN ('TARIFA', 'RESERVA_HABITACION')
ORDER  BY t.table_name, t.trigger_name;


/* #####################################################################
   PARTE 3 · HISTÓRICO EN EL TABLESPACE PROPIO Y VISTA MATERIALIZADA
   ##################################################################### */

/* =====================================================================
   TurismoUQ · Proyecto integrador Bases de Datos II · 2026-2
   Script 07 · Histórico de reservas y vista materializada (Entrega 2)
   ---------------------------------------------------------------------
   Ejecutar como TURISMOUQ, después de 04 (tablespace), 05 y 06.

   Parte A · RESERVA_HISTORICO en el tablespace TS_TURISMOUQ_HIST
     Una fila por línea de reserva CERRADA (COMPLETADA o CANCELADA) de un
     año ya terminado, desnormalizada: cliente, alojamiento, municipio,
     tipo, habitación, fechas, valores y pagos quedan "congelados" tal
     como estaban al archivar, aunque luego cambien los catálogos.
     sp_archivar_reservas(p_anio) copia un año completo y es repetible.
     En producción, después de archivar y verificar, se purgarían esas
     reservas de las tablas operativas; aquí se conservan para que las
     consultas de la Entrega 1 sigan mostrando 2024-2026 completos.

   Parte B · MV_OCUPACION_MENSUAL (vista materializada)
     Precalcula, por alojamiento y mes, habitaciones, noches disponibles,
     noches ocupadas, % de ocupación, reservas e ingreso de hospedaje.
     La consulta base cruza ~650 habitaciones x ~1.100 días y valora las
     noches con TARIFA; materializarla convierte un cálculo de varios
     segundos en una lectura de ~2.200 filas.

     POLÍTICA DE REFRESCO: COMPLETE, ON DEMAND, programada cada noche
     a las 2:00 a. m. con DBMS_SCHEDULER.
       · ¿Por qué no FAST? El refresco rápido exige logs de vista
         materializada y una consulta "simple"; esta usa un join por
         RANGO de fechas (c.fecha >= checkin AND c.fecha < checkout),
         subconsultas agregadas, COUNT(DISTINCT) y un CROSS JOIN, que
         Oracle no admite para refresco rápido.
       · ¿Por qué no ON COMMIT? Cada reserva, pago o cambio de tarifa
         tendría que recalcular la vista dentro de la misma transacción:
         haría lenta la operación en línea, que es lo prioritario.
       · ¿Por qué diario? Es un indicador de gestión mensual; a la
         gerencia le basta el dato del cierre de ayer. Un refresco
         completo tarda segundos y a las 2:00 a. m. no compite con las
         reservas. Si se necesita al instante (por ejemplo antes de una
         junta), se refresca a mano con DBMS_MVIEW.REFRESH.

   Parte C · Job mensual de liquidación (día 1 a las 3:00 a. m.) que usa
     el cursor con parámetros de pkg_turismouq para el mes anterior.
   ===================================================================== */

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET SQLBLANKLINES ON

/* =====================================================================
   Parte A · Histórico en el tablespace propio
   ===================================================================== */
BEGIN
   EXECUTE IMMEDIATE 'DROP TABLE reserva_historico CASCADE CONSTRAINTS PURGE';
EXCEPTION
   WHEN OTHERS THEN IF SQLCODE <> -942 THEN RAISE; END IF;
END;
/

CREATE TABLE reserva_historico (
   id_historico           NUMBER(10) GENERATED BY DEFAULT AS IDENTITY,
   anio_cierre            NUMBER(4)      NOT NULL,
   id_reserva             NUMBER(8)      NOT NULL,
   id_reserva_habitacion  NUMBER(9)      NOT NULL,
   estado                 VARCHAR2(10)   NOT NULL,
   fecha_reserva          DATE           NOT NULL,
   fecha_checkin          DATE           NOT NULL,
   fecha_checkout         DATE           NOT NULL,
   noches                 NUMBER(3)      NOT NULL,
   fecha_cancelacion      DATE,
   id_cliente             NUMBER(7)      NOT NULL,
   documento_cliente      VARCHAR2(25)   NOT NULL,
   nombre_cliente         VARCHAR2(125)  NOT NULL,
   ciudad_origen          VARCHAR2(60)   NOT NULL,
   pais_origen            VARCHAR2(40)   NOT NULL,
   id_alojamiento         NUMBER(6)      NOT NULL,
   alojamiento            VARCHAR2(80)   NOT NULL,
   municipio              VARCHAR2(40)   NOT NULL,
   tipo_alojamiento       VARCHAR2(30)   NOT NULL,
   numero_habitacion      VARCHAR2(10)   NOT NULL,
   tipo_habitacion        VARCHAR2(10)   NOT NULL,
   num_huespedes          NUMBER(2)      NOT NULL,
   valor_estadia          NUMBER(12,2)   NOT NULL,
   total_servicios        NUMBER(12,2)   NOT NULL,   -- de toda la reserva
   total_pagado           NUMBER(12,2)   NOT NULL,   -- pagos EXITOSOS + REEMBOLSADOS (bruto)
   total_reembolsado      NUMBER(12,2)   NOT NULL,
   calificacion           NUMBER(1),
   fecha_archivo          DATE           DEFAULT SYSDATE NOT NULL,
   CONSTRAINT pk_reserva_historico  PRIMARY KEY (id_historico)
      USING INDEX TABLESPACE ts_turismouq_hist,
   CONSTRAINT uq_historico_linea    UNIQUE (id_reserva_habitacion)
      USING INDEX TABLESPACE ts_turismouq_hist,
   CONSTRAINT ck_historico_estado   CHECK (estado IN ('COMPLETADA', 'CANCELADA'))
)
TABLESPACE ts_turismouq_hist;

CREATE INDEX ix_historico_anio_aloj ON reserva_historico (anio_cierre, id_alojamiento)
   TABLESPACE ts_turismouq_hist;

COMMENT ON TABLE reserva_historico IS 'Histórico desnormalizado de líneas de reserva cerradas, en el tablespace TS_TURISMOUQ_HIST.';
COMMENT ON COLUMN reserva_historico.anio_cierre IS 'Año del check-out: unidad de archivado (un año cerrado no vuelve a cambiar).';

-- Procedimiento de archivado (repetible: no duplica líneas ya archivadas)
CREATE OR REPLACE PROCEDURE sp_archivar_reservas (p_anio IN NUMBER) IS
   v_filas PLS_INTEGER;
BEGIN
   IF p_anio IS NULL OR p_anio >= EXTRACT(YEAR FROM SYSDATE) THEN
      RAISE_APPLICATION_ERROR(-20008,
         'Solo se archivan años cerrados (anteriores a ' || EXTRACT(YEAR FROM SYSDATE) || ').');
   END IF;

   INSERT INTO reserva_historico (
          anio_cierre, id_reserva, id_reserva_habitacion, estado, fecha_reserva,
          fecha_checkin, fecha_checkout, noches, fecha_cancelacion,
          id_cliente, documento_cliente, nombre_cliente, ciudad_origen, pais_origen,
          id_alojamiento, alojamiento, municipio, tipo_alojamiento,
          numero_habitacion, tipo_habitacion, num_huespedes, valor_estadia,
          total_servicios, total_pagado, total_reembolsado, calificacion)
   SELECT p_anio, r.id_reserva, rh.id_reserva_habitacion, r.estado, r.fecha_reserva,
          rh.fecha_checkin, rh.fecha_checkout, rh.fecha_checkout - rh.fecha_checkin, r.fecha_cancelacion,
          c.id_cliente, c.tipo_documento || ' ' || c.numero_documento,
          c.nombres || ' ' || c.apellidos, c.ciudad_origen, c.pais_origen,
          a.id_alojamiento, a.nombre_comercial, m.nombre, ta.nombre,
          h.numero, h.tipo_habitacion, rh.num_huespedes, rh.valor_estadia,
          NVL((SELECT SUM(rs.subtotal) FROM reserva_servicio rs WHERE rs.id_reserva = r.id_reserva), 0),
          NVL((SELECT SUM(p.monto) FROM pago p
               WHERE p.id_reserva = r.id_reserva AND p.estado IN ('EXITOSO', 'REEMBOLSADO')), 0),
          NVL((SELECT SUM(p.monto_reembolsado) FROM pago p WHERE p.id_reserva = r.id_reserva), 0),
          (SELECT re.calificacion FROM resena re WHERE re.id_reserva = r.id_reserva)
   FROM   reserva r
   JOIN   reserva_habitacion rh ON rh.id_reserva     = r.id_reserva
   JOIN   cliente c             ON c.id_cliente      = r.id_cliente
   JOIN   alojamiento a         ON a.id_alojamiento  = r.id_alojamiento
   JOIN   municipio m           ON m.id_municipio    = a.id_municipio
   JOIN   tipo_alojamiento ta   ON ta.id_tipo        = a.id_tipo
   JOIN   habitacion h          ON h.id_habitacion   = rh.id_habitacion
   WHERE  r.estado IN ('COMPLETADA', 'CANCELADA')
   AND    r.fecha_checkout >= TO_DATE(p_anio || '-01-01', 'YYYY-MM-DD')
   AND    r.fecha_checkout <  TO_DATE((p_anio + 1) || '-01-01', 'YYYY-MM-DD')
   AND    NOT EXISTS (SELECT 1 FROM reserva_historico x
                      WHERE  x.id_reserva_habitacion = rh.id_reserva_habitacion);

   v_filas := SQL%ROWCOUNT;
   COMMIT;
   DBMS_OUTPUT.PUT_LINE('Año ' || p_anio || ': ' || v_filas || ' líneas de reserva archivadas en TS_TURISMOUQ_HIST.');
END sp_archivar_reservas;
/
SHOW ERRORS PROCEDURE sp_archivar_reservas

-- Archivar el año 2024 (cerrado)
BEGIN
   sp_archivar_reservas(2024);
END;
/

/* =====================================================================
   Parte B · Vista materializada de ocupación mensual
   ===================================================================== */
BEGIN
   EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_ocupacion_mensual';
EXCEPTION
   WHEN OTHERS THEN IF SQLCODE <> -12003 THEN RAISE; END IF;   -- ORA-12003: no existe
END;
/

CREATE MATERIALIZED VIEW mv_ocupacion_mensual
   BUILD IMMEDIATE
   REFRESH COMPLETE ON DEMAND
AS
SELECT d.id_alojamiento,
       a.nombre_comercial                                         AS alojamiento,
       m.nombre                                                   AS municipio,
       ta.nombre                                                  AS tipo_alojamiento,
       d.anio,
       d.mes,
       d.habitaciones,
       d.noches_disponibles,
       NVL(o.noches_ocupadas, 0)                                  AS noches_ocupadas,
       ROUND(100 * NVL(o.noches_ocupadas, 0) / d.noches_disponibles, 2) AS pct_ocupacion,
       NVL(o.reservas, 0)                                         AS reservas,
       NVL(o.ingreso_hospedaje, 0)                                AS ingreso_hospedaje
FROM  (SELECT h.id_alojamiento, c.anio, c.mes,
              COUNT(DISTINCT h.id_habitacion) AS habitaciones,
              COUNT(*)                        AS noches_disponibles
       FROM   habitacion h
       CROSS  JOIN calendario c
       GROUP  BY h.id_alojamiento, c.anio, c.mes) d
JOIN   alojamiento a         ON a.id_alojamiento = d.id_alojamiento
JOIN   municipio m           ON m.id_municipio   = a.id_municipio
JOIN   tipo_alojamiento ta   ON ta.id_tipo       = a.id_tipo
LEFT   JOIN
      (SELECT rh.id_alojamiento, c.anio, c.mes,
              COUNT(*)                       AS noches_ocupadas,
              COUNT(DISTINCT rh.id_reserva)  AS reservas,
              SUM(tf.valor_noche)            AS ingreso_hospedaje
       FROM   reserva_habitacion rh
       JOIN   reserva r    ON r.id_reserva = rh.id_reserva
       JOIN   calendario c ON c.fecha >= rh.fecha_checkin
                          AND c.fecha <  rh.fecha_checkout
       JOIN   tarifa tf    ON tf.id_habitacion = rh.id_habitacion
                          AND tf.id_temporada  = c.id_temporada
       WHERE  r.estado IN ('CONFIRMADA', 'COMPLETADA')
       GROUP  BY rh.id_alojamiento, c.anio, c.mes) o
       ON  o.id_alojamiento = d.id_alojamiento
       AND o.anio           = d.anio
       AND o.mes            = d.mes;

CREATE INDEX ix_mv_ocupacion_periodo ON mv_ocupacion_mensual (anio, mes);

COMMENT ON MATERIALIZED VIEW mv_ocupacion_mensual IS
   'Ocupación mensual por alojamiento. REFRESH COMPLETE ON DEMAND, job diario 2:00 a. m. (JOB_REFRESCO_MV_OCUPACION).';

-- Job diario de refresco completo
BEGIN
   DBMS_SCHEDULER.DROP_JOB('JOB_REFRESCO_MV_OCUPACION', force => TRUE);
EXCEPTION
   WHEN OTHERS THEN IF SQLCODE <> -27475 THEN RAISE; END IF;   -- ORA-27475: el job no existe
END;
/

BEGIN
   DBMS_SCHEDULER.CREATE_JOB(
      job_name        => 'JOB_REFRESCO_MV_OCUPACION',
      job_type        => 'PLSQL_BLOCK',
      job_action      => 'BEGIN DBMS_MVIEW.REFRESH(list => ''MV_OCUPACION_MENSUAL'', method => ''C''); END;',
      start_date      => SYSTIMESTAMP,
      repeat_interval => 'FREQ=DAILY;BYHOUR=2;BYMINUTE=0;BYSECOND=0',
      enabled         => TRUE,
      comments        => 'Refresco completo diario de MV_OCUPACION_MENSUAL (TurismoUQ)');
END;
/

/* =====================================================================
   Parte C · Job mensual de liquidación (mes anterior, día 1 a las 3:00)
   ===================================================================== */
BEGIN
   DBMS_SCHEDULER.DROP_JOB('JOB_LIQUIDACION_MENSUAL', force => TRUE);
EXCEPTION
   WHEN OTHERS THEN IF SQLCODE <> -27475 THEN RAISE; END IF;
END;
/

BEGIN
   DBMS_SCHEDULER.CREATE_JOB(
      job_name        => 'JOB_LIQUIDACION_MENSUAL',
      job_type        => 'PLSQL_BLOCK',
      job_action      => 'BEGIN pkg_turismouq.sp_liquidacion_mensual('
                      || 'EXTRACT(YEAR FROM ADD_MONTHS(SYSDATE, -1)), '
                      || 'EXTRACT(MONTH FROM ADD_MONTHS(SYSDATE, -1))); END;',
      start_date      => SYSTIMESTAMP,
      repeat_interval => 'FREQ=MONTHLY;BYMONTHDAY=1;BYHOUR=3;BYMINUTE=0;BYSECOND=0',
      enabled         => TRUE,
      comments        => 'Liquidación mensual por alojamiento del mes anterior (TurismoUQ)');
END;
/

/* =====================================================================
   Evidencia
   ===================================================================== */
SELECT table_name, tablespace_name
FROM   user_tables
WHERE  table_name IN ('RESERVA_HISTORICO', 'RESERVA', 'RESERVA_HABITACION')
ORDER  BY table_name;

SELECT anio_cierre, estado, COUNT(*) AS lineas, SUM(valor_estadia) AS valor
FROM   reserva_historico
GROUP  BY anio_cierre, estado
ORDER  BY anio_cierre, estado;

SELECT mview_name, refresh_mode, refresh_method, build_mode, last_refresh_date, staleness
FROM   user_mviews
WHERE  mview_name = 'MV_OCUPACION_MENSUAL';

SELECT job_name, enabled, state, repeat_interval, next_run_date
FROM   user_scheduler_jobs
WHERE  job_name IN ('JOB_REFRESCO_MV_OCUPACION', 'JOB_LIQUIDACION_MENSUAL');

-- Ocupación 2025 por municipio leída directamente de la vista materializada
SELECT municipio,
       SUM(noches_ocupadas)                                         AS noches_ocupadas,
       SUM(noches_disponibles)                                      AS noches_disponibles,
       ROUND(100 * SUM(noches_ocupadas) / SUM(noches_disponibles), 1) AS pct_ocupacion
FROM   mv_ocupacion_mensual
WHERE  anio = 2025
GROUP  BY municipio
ORDER  BY pct_ocupacion DESC;


/* #####################################################################
   PARTE 4 · PRUEBAS (EVIDENCIA)
   ##################################################################### */

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
