/* =====================================================================
   TurismoUQ · Proyecto integrador Bases de Datos II · 2026-2
   Script 09 · Transacciones: reserva + pago atómicos con SAVEPOINT (Entrega 3)
   ---------------------------------------------------------------------
   Ejecutar como TURISMOUQ con F5 (Ejecutar script), después de 01 a 07.

   Contenido
     Sección 1. Paquete PKG_RESERVAS_TX
        · sp_bloquear_habitacion .. SELECT ... FOR UPDATE [WAIT n | NOWAIT]
        · sp_registrar_pago ....... valida y registra un pago de una reserva
        · sp_reservar_con_pago .... TRANSACCIÓN: reserva + pago con SAVEPOINT
     Sección 2. Disparador TRG_RESERVA_REACTIVACION: cierra un límite que
                quedó anotado en la Entrega 2 (reactivar una reserva
                cancelada no volvía a validar el solape).
     Sección 3. Pruebas T9: éxito, todo o nada, ROLLBACK PARCIAL,
                demostración paso a paso y reactivación.

   Cómo está armada la transacción (sp_reservar_con_pago)

        SAVEPOINT sv_inicio            <- punto de retorno "nada pasó"
           bloquear la habitación (FOR UPDATE)
           crear la reserva PENDIENTE (pkg_turismouq.sp_crear_reserva)
        SAVEPOINT sv_reserva           <- punto de retorno "reserva sin pago"
           registrar el pago
           si el pago cubre el anticipo mínimo -> reserva CONFIRMADA
        COMMIT (opcional)

     Si falla la RESERVA  -> ROLLBACK TO sv_inicio y se relanza el error.
     Si falla el PAGO, depende de p_si_falla_pago:
        'DESHACER_TODO'     -> ROLLBACK TO sv_inicio: no queda ni reserva
                               ni pago (reserva y pago son atómicos).
        'CONSERVAR_RESERVA' -> ROLLBACK TO sv_reserva: ROLLBACK PARCIAL;
                               se deshace solo el intento de pago y la
                               reserva queda PENDIENTE para reintentar.
     En ambos casos se usa ROLLBACK TO SAVEPOINT y no ROLLBACK: lo que
     quien llama hubiera hecho ANTES en su transacción no se pierde.

   Códigos de error nuevos (continúan la numeración del script 05)
     -20009 pago inválido (monto, método, referencia, estado de la reserva)
     -20010 habitación bloqueada por otra sesión que la está reservando
   ===================================================================== */

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET SQLBLANKLINES ON
SET LINESIZE 220
SET PAGESIZE 100

/* =====================================================================
   Sección 1. Paquete PKG_RESERVAS_TX
   ===================================================================== */
CREATE OR REPLACE PACKAGE pkg_reservas_tx AS

   c_err_pago     CONSTANT PLS_INTEGER := -20009;
   c_err_bloqueo  CONSTANT PLS_INTEGER := -20010;

   ex_pago     EXCEPTION;  PRAGMA EXCEPTION_INIT(ex_pago,    -20009);
   ex_bloqueo  EXCEPTION;  PRAGMA EXCEPTION_INIT(ex_bloqueo, -20010);

   c_espera_seg        CONSTANT PLS_INTEGER := 10;    -- espera máxima por el bloqueo de la habitación
   c_pct_anticipo_min  CONSTANT NUMBER      := 0.30;  -- con el 30 % pagado la reserva queda CONFIRMADA

   -- Bloquea la fila de la habitación para serializar las reservas sobre ella.
   --   p_espera_seg = 0   -> FOR UPDATE NOWAIT (falla de inmediato si está ocupada)
   --   p_espera_seg = n   -> FOR UPDATE WAIT n (espera hasta n segundos)
   --   p_espera_seg NULL  -> FOR UPDATE (espera indefinida)
   PROCEDURE sp_bloquear_habitacion (
      p_id_habitacion IN habitacion.id_habitacion%TYPE,
      p_espera_seg    IN NUMBER DEFAULT c_espera_seg
   );

   -- Registra un pago EXITOSO sobre una reserva PENDIENTE o CONFIRMADA.
   -- No hace COMMIT.
   PROCEDURE sp_registrar_pago (
      p_id_reserva  IN  reserva.id_reserva%TYPE,
      p_monto       IN  NUMBER,
      p_metodo      IN  VARCHAR2,
      p_referencia  IN  VARCHAR2,
      p_id_pago     OUT pago.id_pago%TYPE
   );

   -- Transacción completa: reserva + pago.
   PROCEDURE sp_reservar_con_pago (
      p_id_cliente     IN  cliente.id_cliente%TYPE,
      p_id_habitacion  IN  habitacion.id_habitacion%TYPE,
      p_fecha_in       IN  DATE,
      p_fecha_out      IN  DATE,
      p_num_huespedes  IN  NUMBER,
      p_monto_pago     IN  NUMBER,
      p_metodo         IN  VARCHAR2,
      p_referencia     IN  VARCHAR2,
      p_id_reserva     OUT reserva.id_reserva%TYPE,
      p_id_pago        OUT pago.id_pago%TYPE,
      p_si_falla_pago  IN  VARCHAR2 DEFAULT 'DESHACER_TODO',
      p_confirmar      IN  VARCHAR2 DEFAULT 'S',
      p_espera_seg     IN  NUMBER   DEFAULT c_espera_seg,
      p_observaciones  IN  VARCHAR2 DEFAULT NULL
   );

END pkg_reservas_tx;
/

CREATE OR REPLACE PACKAGE BODY pkg_reservas_tx AS

   /* ------------------------------------------------------------------
      sp_bloquear_habitacion
      El disparador anti-solape y sp_crear_reserva validan leyendo las
      reservas CONFIRMADAS (commit) más las de la propia sesión: no ven
      lo que otra sesión todavía no confirma. Dos recepcionistas podrían
      pasar la validación al tiempo y vender la misma habitación.
      No se puede bloquear una fila que aún no existe (la reserva nueva),
      así que se bloquea su "dueño": la fila de HABITACION. Quien llegue
      segundo espera a que el primero termine y, al despertar, su
      validación ya ve la reserva del primero.
      WAIT / NOWAIT no admiten variables de enlace: se arma con SQL
      dinámico (el número se valida antes, no hay riesgo de inyección).
      ------------------------------------------------------------------ */
   PROCEDURE sp_bloquear_habitacion (
      p_id_habitacion IN habitacion.id_habitacion%TYPE,
      p_espera_seg    IN NUMBER DEFAULT c_espera_seg
   ) IS
      v_id        habitacion.id_habitacion%TYPE;
      v_clausula  VARCHAR2(20);
      ex_ocupado  EXCEPTION;  PRAGMA EXCEPTION_INIT(ex_ocupado, -54);     -- ORA-00054 (NOWAIT)
      ex_tiempo   EXCEPTION;  PRAGMA EXCEPTION_INIT(ex_tiempo,  -30006);  -- ORA-30006 (WAIT agotado)
   BEGIN
      IF p_espera_seg < 0 OR p_espera_seg > 300 OR p_espera_seg <> TRUNC(p_espera_seg) THEN
         RAISE_APPLICATION_ERROR(pkg_turismouq.c_err_parametro,
            'La espera del bloqueo debe ser un entero entre 0 y 300 segundos.');
      END IF;
      v_clausula := CASE
                       WHEN p_espera_seg IS NULL THEN ''
                       WHEN p_espera_seg = 0     THEN ' NOWAIT'
                       ELSE ' WAIT ' || TO_CHAR(p_espera_seg)
                    END;

      EXECUTE IMMEDIATE
         'SELECT id_habitacion FROM habitacion WHERE id_habitacion = :1 FOR UPDATE' || v_clausula
         INTO v_id USING p_id_habitacion;
   EXCEPTION
      WHEN NO_DATA_FOUND THEN
         RAISE_APPLICATION_ERROR(pkg_turismouq.c_err_no_existe,
            'La habitación ' || NVL(TO_CHAR(p_id_habitacion), 'NULL') || ' no existe.');
      WHEN ex_ocupado OR ex_tiempo THEN
         RAISE_APPLICATION_ERROR(c_err_bloqueo,
            'La habitación ' || p_id_habitacion || ' está siendo reservada por otra sesión'
            || CASE WHEN p_espera_seg > 0 THEN ' (se esperó ' || p_espera_seg || ' s)' END
            || '. Intente de nuevo en unos segundos.');
   END sp_bloquear_habitacion;

   /* ------------------------------------------------------------------
      sp_registrar_pago
      Reglas:
        · la reserva existe y está PENDIENTE o CONFIRMADA;
        · monto > 0 y no mayor que el saldo (total - pagos exitosos);
        · método válido; EFECTIVO no lleva referencia y los demás sí;
        · la referencia electrónica no se repite (uq_pago_referencia):
          dos veces la misma referencia = el mismo cobro enviado dos veces.
      Concepto: TOTAL si paga todo de una vez, SALDO si completa lo que
      faltaba, ANTICIPO en otro caso. Si con este pago lo pagado llega al
      30 % del total, una reserva PENDIENTE pasa a CONFIRMADA.
      ------------------------------------------------------------------ */
   PROCEDURE sp_registrar_pago (
      p_id_reserva  IN  reserva.id_reserva%TYPE,
      p_monto       IN  NUMBER,
      p_metodo      IN  VARCHAR2,
      p_referencia  IN  VARCHAR2,
      p_id_pago     OUT pago.id_pago%TYPE
   ) IS
      v_estado    reserva.estado%TYPE;
      v_total     NUMBER;
      v_pagado    NUMBER;
      v_saldo     NUMBER;
      v_concepto  pago.concepto%TYPE;
   BEGIN
      BEGIN
         SELECT estado INTO v_estado
         FROM   reserva
         WHERE  id_reserva = p_id_reserva
         FOR UPDATE;                       -- nadie más cambia la reserva mientras se paga
      EXCEPTION
         WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(pkg_turismouq.c_err_no_existe,
               'La reserva ' || NVL(TO_CHAR(p_id_reserva), 'NULL') || ' no existe.');
      END;
      IF v_estado NOT IN ('PENDIENTE', 'CONFIRMADA') THEN
         RAISE_APPLICATION_ERROR(c_err_pago,
            'No se reciben pagos de una reserva ' || v_estado || '.');
      END IF;

      IF p_metodo IS NULL
         OR p_metodo NOT IN ('TARJETA_CREDITO', 'TARJETA_DEBITO', 'PSE', 'TRANSFERENCIA', 'EFECTIVO') THEN
         RAISE_APPLICATION_ERROR(c_err_pago, 'Método de pago no válido: ' || NVL(p_metodo, 'NULL') || '.');
      END IF;
      IF p_metodo = 'EFECTIVO' AND p_referencia IS NOT NULL THEN
         RAISE_APPLICATION_ERROR(c_err_pago, 'Un pago en efectivo no lleva referencia electrónica.');
      END IF;
      IF p_metodo <> 'EFECTIVO' AND p_referencia IS NULL THEN
         RAISE_APPLICATION_ERROR(c_err_pago, 'El método ' || p_metodo || ' exige la referencia de la transacción.');
      END IF;

      v_total  := pkg_turismouq.fn_total_reserva(p_id_reserva);
      v_pagado := pkg_turismouq.fn_total_pagado(p_id_reserva);
      v_saldo  := v_total - v_pagado;

      IF p_monto IS NULL OR p_monto <= 0 THEN
         RAISE_APPLICATION_ERROR(c_err_pago, 'El monto del pago debe ser mayor que cero.');
      END IF;
      IF p_monto > v_saldo THEN
         RAISE_APPLICATION_ERROR(c_err_pago,
            'El pago (' || TO_CHAR(p_monto, 'FM999G999G999G990D00') || ') supera el saldo de la reserva ('
            || TO_CHAR(v_saldo, 'FM999G999G999G990D00') || ').');
      END IF;

      v_concepto := CASE
                       WHEN p_monto = v_total THEN 'TOTAL'
                       WHEN p_monto = v_saldo THEN 'SALDO'
                       ELSE 'ANTICIPO'
                    END;

      BEGIN
         INSERT INTO pago (id_reserva, fecha_pago, monto, metodo, estado, concepto, referencia)
         VALUES (p_id_reserva, SYSDATE, p_monto, p_metodo, 'EXITOSO', v_concepto, p_referencia)
         RETURNING id_pago INTO p_id_pago;
      EXCEPTION
         WHEN DUP_VAL_ON_INDEX THEN
            RAISE_APPLICATION_ERROR(c_err_pago,
               'La referencia ' || p_referencia || ' ya fue registrada en otro pago (cobro duplicado).');
      END;

      IF v_estado = 'PENDIENTE' AND v_pagado + p_monto >= ROUND(v_total * c_pct_anticipo_min, 2) THEN
         UPDATE reserva SET estado = 'CONFIRMADA' WHERE id_reserva = p_id_reserva;
         v_estado := 'CONFIRMADA';
      END IF;

      DBMS_OUTPUT.PUT_LINE('Pago ' || p_id_pago || ' (' || v_concepto || ', ' || p_metodo || ') de '
                           || TO_CHAR(p_monto, 'FM$999G999G990') || ' registrado en la reserva '
                           || p_id_reserva || '; queda ' || v_estado || ' con saldo '
                           || TO_CHAR(v_saldo - p_monto, 'FM$999G999G990'));
   END sp_registrar_pago;

   /* ------------------------------------------------------------------
      sp_reservar_con_pago · la transacción de la Entrega 3
      ------------------------------------------------------------------ */
   PROCEDURE sp_reservar_con_pago (
      p_id_cliente     IN  cliente.id_cliente%TYPE,
      p_id_habitacion  IN  habitacion.id_habitacion%TYPE,
      p_fecha_in       IN  DATE,
      p_fecha_out      IN  DATE,
      p_num_huespedes  IN  NUMBER,
      p_monto_pago     IN  NUMBER,
      p_metodo         IN  VARCHAR2,
      p_referencia     IN  VARCHAR2,
      p_id_reserva     OUT reserva.id_reserva%TYPE,
      p_id_pago        OUT pago.id_pago%TYPE,
      p_si_falla_pago  IN  VARCHAR2 DEFAULT 'DESHACER_TODO',
      p_confirmar      IN  VARCHAR2 DEFAULT 'S',
      p_espera_seg     IN  NUMBER   DEFAULT c_espera_seg,
      p_observaciones  IN  VARCHAR2 DEFAULT NULL
   ) IS
   BEGIN
      IF p_si_falla_pago IS NULL OR p_si_falla_pago NOT IN ('DESHACER_TODO', 'CONSERVAR_RESERVA') THEN
         RAISE_APPLICATION_ERROR(pkg_turismouq.c_err_parametro,
            'p_si_falla_pago debe ser DESHACER_TODO o CONSERVAR_RESERVA.');
      END IF;
      IF p_confirmar IS NULL OR p_confirmar NOT IN ('S', 'N') THEN
         RAISE_APPLICATION_ERROR(pkg_turismouq.c_err_parametro, 'p_confirmar debe ser S o N.');
      END IF;

      -- ---------- Paso 1: reserva ----------
      SAVEPOINT sv_inicio;
      BEGIN
         sp_bloquear_habitacion(p_id_habitacion, p_espera_seg);
         pkg_turismouq.sp_crear_reserva(p_id_cliente, p_id_habitacion, p_fecha_in, p_fecha_out,
                                        p_num_huespedes, p_id_reserva, 'PENDIENTE', p_observaciones);
      EXCEPTION
         WHEN OTHERS THEN
            ROLLBACK TO sv_inicio;          -- suelta también el bloqueo de la habitación
            RAISE;
      END;

      -- ---------- Paso 2: pago ----------
      SAVEPOINT sv_reserva;
      BEGIN
         sp_registrar_pago(p_id_reserva, p_monto_pago, p_metodo, p_referencia, p_id_pago);
      EXCEPTION
         WHEN OTHERS THEN
            IF p_si_falla_pago = 'CONSERVAR_RESERVA' THEN
               -- ROLLBACK PARCIAL: se deshace solo lo hecho después de sv_reserva
               ROLLBACK TO sv_reserva;
               p_id_pago := NULL;
               DBMS_OUTPUT.PUT_LINE('ROLLBACK PARCIAL (TO sv_reserva): el pago falló -> ' || SQLERRM);
               DBMS_OUTPUT.PUT_LINE('   La reserva ' || p_id_reserva || ' se conserva PENDIENTE y sin pago.');
            ELSE
               -- Atómico: sin pago no hay reserva
               ROLLBACK TO sv_inicio;
               RAISE;
            END IF;
      END;

      -- ---------- Paso 3: confirmar ----------
      IF p_confirmar = 'S' THEN
         COMMIT;
      END IF;
   END sp_reservar_con_pago;

END pkg_reservas_tx;
/
SHOW ERRORS PACKAGE pkg_reservas_tx
SHOW ERRORS PACKAGE BODY pkg_reservas_tx

/* =====================================================================
   Sección 2. Reactivar una reserva cancelada vuelve a validar el solape
   ---------------------------------------------------------------------
   TRG_RH_NO_SOLAPE (script 06) vigila RESERVA_HABITACION. Faltaba el otro
   camino: una reserva CANCELADA libera la habitación; si después alguien
   reserva esas noches y luego se "des-cancela" la primera con un UPDATE
   de RESERVA.estado, quedarían dos reservas activas sobre la habitación.
   Es un COMPOUND TRIGGER por la misma razón que el del script 06: la
   verificación se hace en AFTER STATEMENT, cuando ya se puede consultar
   RESERVA sin ORA-04091 (tabla mutante).
   ===================================================================== */
CREATE OR REPLACE TRIGGER trg_reserva_reactivacion
FOR UPDATE OF estado ON reserva
COMPOUND TRIGGER

   TYPE t_ids IS TABLE OF reserva.id_reserva%TYPE INDEX BY PLS_INTEGER;
   g_ids t_ids;

   BEFORE STATEMENT IS
   BEGIN
      g_ids.DELETE;
   END BEFORE STATEMENT;

   AFTER EACH ROW IS
   BEGIN
      IF :OLD.estado = 'CANCELADA' AND :NEW.estado <> 'CANCELADA' THEN
         g_ids(g_ids.COUNT + 1) := :NEW.id_reserva;
      END IF;
   END AFTER EACH ROW;

   AFTER STATEMENT IS
      v_hab   reserva_habitacion.id_habitacion%TYPE;
      v_otra  reserva.id_reserva%TYPE;
   BEGIN
      FOR i IN 1 .. g_ids.COUNT LOOP
         SELECT MIN(n.id_habitacion), MIN(o.id_reserva)
         INTO   v_hab, v_otra
         FROM   reserva_habitacion n
         JOIN   reserva_habitacion o  ON  o.id_habitacion  = n.id_habitacion
                                      AND o.id_reserva    <> n.id_reserva
                                      AND o.fecha_checkin  < n.fecha_checkout
                                      AND n.fecha_checkin  < o.fecha_checkout
         JOIN   reserva ro            ON  ro.id_reserva    = o.id_reserva
         WHERE  n.id_reserva = g_ids(i)
         AND    ro.estado   <> 'CANCELADA';

         IF v_otra IS NOT NULL THEN
            RAISE_APPLICATION_ERROR(-20001,
               'No se puede reactivar la reserva ' || g_ids(i) || ': la habitación ' || v_hab
               || ' ya fue tomada por la reserva ' || v_otra || ' en esas noches.');
         END IF;
      END LOOP;
      g_ids.DELETE;
   END AFTER STATEMENT;

END trg_reserva_reactivacion;
/
SHOW ERRORS TRIGGER trg_reserva_reactivacion

SELECT object_name, object_type, status
FROM   user_objects
WHERE  object_name IN ('PKG_RESERVAS_TX', 'TRG_RESERVA_REACTIVACION')
ORDER  BY object_name, object_type;

/* =====================================================================
   Sección 3. Pruebas T9 (evidencia de la entrega)
   ---------------------------------------------------------------------
   Datos de prueba
     · Habitación: la de menor id del "Hotel Mirador del Parque Sucre"
       con capacidad >= 2 (las pruebas de la Entrega 2 usan otro hotel).
     · Fechas: 18 al 28 de enero de 2027 (temporada BAJA, sin reservas
       en la carga). Las reservas llevan observaciones 'PRUEBA E3 TX...'
       y se borran al inicio: el script se puede repetir.
   Cada prueba imprime OK o FALLA.
   ===================================================================== */
VARIABLE v_hab    NUMBER
VARIABLE v_cli    NUMBER
VARIABLE v_res1   NUMBER
VARIABLE v_res3   NUMBER
VARIABLE v_total  NUMBER

PROMPT ================================================================
PROMPT  T9.0 Preparación
PROMPT ================================================================
BEGIN
   DELETE FROM pago               WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE observaciones LIKE 'PRUEBA E3 TX%');
   DELETE FROM reserva_servicio   WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE observaciones LIKE 'PRUEBA E3 TX%');
   DELETE FROM reserva_habitacion WHERE id_reserva IN (SELECT id_reserva FROM reserva WHERE observaciones LIKE 'PRUEBA E3 TX%');
   DELETE FROM reserva            WHERE observaciones LIKE 'PRUEBA E3 TX%';
   COMMIT;

   SELECT MIN(h.id_habitacion) INTO :v_hab
   FROM   habitacion h JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
   WHERE  a.nombre_comercial = 'Hotel Mirador del Parque Sucre' AND h.capacidad_max >= 2;

   SELECT MIN(id_cliente) INTO :v_cli FROM cliente;

   :v_total := pkg_turismouq.fn_valor_estadia(:v_hab, DATE '2027-01-18', DATE '2027-01-21');
   DBMS_OUTPUT.PUT_LINE('Habitación de prueba: ' || :v_hab || ', cliente: ' || :v_cli
                        || ', valor de 18 al 21 de enero: ' || :v_total);
END;
/

PROMPT ================================================================
PROMPT  T9.1 Camino feliz: reserva + anticipo del 50 % en una sola transacción
PROMPT ================================================================
DECLARE
   v_res  NUMBER;
   v_pago NUMBER;
   v_est  reserva.estado%TYPE;
   v_n    NUMBER;
BEGIN
   pkg_reservas_tx.sp_reservar_con_pago(
      p_id_cliente    => :v_cli,
      p_id_habitacion => :v_hab,
      p_fecha_in      => DATE '2027-01-18',
      p_fecha_out     => DATE '2027-01-21',
      p_num_huespedes => 2,
      p_monto_pago    => ROUND(:v_total * 0.5),
      p_metodo        => 'TRANSFERENCIA',
      p_referencia    => 'E3-TX-0001',
      p_id_reserva    => v_res,
      p_id_pago       => v_pago,
      p_observaciones => 'PRUEBA E3 TX - camino feliz');
   :v_res1 := v_res;

   SELECT estado INTO v_est FROM reserva WHERE id_reserva = v_res;
   SELECT COUNT(*) INTO v_n FROM pago WHERE id_reserva = v_res AND estado = 'EXITOSO';
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_est = 'CONFIRMADA' AND v_n = 1 THEN 'OK' ELSE 'FALLA' END
      || ': reserva ' || v_res || ' ' || v_est || ' con ' || v_n || ' pago exitoso (pago ' || v_pago || ')');
EXCEPTION
   WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FALLA: ' || SQLERRM);
END;
/

PROMPT ================================================================
PROMPT  T9.2 Todo o nada: el pago falla (referencia duplicada) y NO queda la reserva.
PROMPT       Lo hecho antes en la misma transacción SÍ se conserva.
PROMPT ================================================================
DECLARE
   v_res    NUMBER;
   v_pago   NUMBER;
   v_previo NUMBER;
   v_n_res  NUMBER;
   v_n_prev NUMBER;
BEGIN
   -- trabajo previo de la misma transacción: un abono en efectivo a la reserva de T9.1 (sin COMMIT)
   pkg_reservas_tx.sp_registrar_pago(:v_res1, 10000, 'EFECTIVO', NULL, v_previo);

   BEGIN
      pkg_reservas_tx.sp_reservar_con_pago(
         p_id_cliente    => :v_cli,
         p_id_habitacion => :v_hab,
         p_fecha_in      => DATE '2027-01-22',
         p_fecha_out     => DATE '2027-01-24',
         p_num_huespedes => 2,
         p_monto_pago    => 50000,
         p_metodo        => 'PSE',
         p_referencia    => 'E3-TX-0001',          -- la misma referencia de T9.1: cobro duplicado
         p_id_reserva    => v_res,
         p_id_pago       => v_pago,
         p_si_falla_pago => 'DESHACER_TODO',
         p_observaciones => 'PRUEBA E3 TX - no debe quedar');
      DBMS_OUTPUT.PUT_LINE('FALLA: la transacción no debió terminar bien');
   EXCEPTION
      WHEN pkg_reservas_tx.ex_pago THEN
         DBMS_OUTPUT.PUT_LINE('Error esperado -> ' || SQLERRM);
   END;

   SELECT COUNT(*) INTO v_n_res
   FROM   reserva_habitacion
   WHERE  id_habitacion = :v_hab AND fecha_checkin = DATE '2027-01-22';
   SELECT COUNT(*) INTO v_n_prev FROM pago WHERE id_pago = v_previo;

   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_n_res = 0 THEN 'OK' ELSE 'FALLA' END
      || ': reservas del 22 al 24 que quedaron = ' || v_n_res || ' (se deshizo hasta sv_inicio)');
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_n_prev = 1 THEN 'OK' ELSE 'FALLA' END
      || ': el abono previo (pago ' || v_previo || ') sigue en la transacción = ' || v_n_prev
      || ' (ROLLBACK TO SAVEPOINT no toca lo anterior al savepoint)');
   COMMIT;
EXCEPTION
   WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('FALLA: ' || SQLERRM);
END;
/

PROMPT ================================================================
PROMPT  T9.3 ROLLBACK PARCIAL: el pago falla (supera el saldo) pero la reserva se conserva PENDIENTE
PROMPT ================================================================
DECLARE
   v_res   NUMBER;
   v_pago  NUMBER;
   v_est   reserva.estado%TYPE;
   v_n     NUMBER;
BEGIN
   pkg_reservas_tx.sp_reservar_con_pago(
      p_id_cliente    => :v_cli,
      p_id_habitacion => :v_hab,
      p_fecha_in      => DATE '2027-01-22',
      p_fecha_out     => DATE '2027-01-24',
      p_num_huespedes => 2,
      p_monto_pago    => 999999999,                -- mayor que el total: el pago se rechaza
      p_metodo        => 'TARJETA_CREDITO',
      p_referencia    => 'E3-TX-0003',
      p_id_reserva    => v_res,
      p_id_pago       => v_pago,
      p_si_falla_pago => 'CONSERVAR_RESERVA',
      p_observaciones => 'PRUEBA E3 TX - rollback parcial');
   :v_res3 := v_res;

   SELECT estado INTO v_est FROM reserva WHERE id_reserva = v_res;
   SELECT COUNT(*) INTO v_n FROM pago WHERE id_reserva = v_res;
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_est = 'PENDIENTE' AND v_n = 0 AND v_pago IS NULL THEN 'OK' ELSE 'FALLA' END
      || ': reserva ' || v_res || ' quedó ' || v_est || ' con ' || v_n || ' pagos');
EXCEPTION
   WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FALLA: ' || SQLERRM);
END;
/

PROMPT Estado de las reservas de prueba después de T9.1 a T9.3
SELECT r.id_reserva, r.estado, r.fecha_checkin, r.fecha_checkout, r.observaciones,
       pkg_turismouq.fn_total_reserva(r.id_reserva) AS total,
       pkg_turismouq.fn_total_pagado(r.id_reserva)  AS pagado,
       (SELECT COUNT(*) FROM pago p WHERE p.id_reserva = r.id_reserva) AS pagos
FROM   reserva r
WHERE  r.observaciones LIKE 'PRUEBA E3 TX%'
ORDER  BY r.id_reserva;

PROMPT ================================================================
PROMPT  T9.4 Demostración paso a paso de SAVEPOINT / ROLLBACK TO (sin el procedimiento)
PROMPT       Se cuentan las filas de la habitación del 25 al 27 de enero en cada paso.
PROMPT ================================================================
DECLARE
   v_res   NUMBER;
   v_pago  NUMBER;
   v_r     NUMBER;
   v_p     NUMBER;
   v_ok    BOOLEAN := TRUE;

   PROCEDURE contar (p_paso VARCHAR2, p_esp_r NUMBER, p_esp_p NUMBER) IS
   BEGIN
      SELECT COUNT(*) INTO v_r
      FROM   reserva_habitacion
      WHERE  id_habitacion = :v_hab AND fecha_checkin = DATE '2027-01-25';
      SELECT COUNT(*) INTO v_p
      FROM   pago
      WHERE  referencia = 'E3-TX-0004';
      DBMS_OUTPUT.PUT_LINE(RPAD(p_paso, 46) || ' reservas = ' || v_r || '   pagos = ' || v_p
                           || CASE WHEN v_r = p_esp_r AND v_p = p_esp_p THEN '   (esperado)' ELSE '   <<< INESPERADO' END);
      IF v_r <> p_esp_r OR v_p <> p_esp_p THEN v_ok := FALSE; END IF;
   END;
BEGIN
   contar('0. Estado inicial', 0, 0);

   SAVEPOINT sv_a;
   pkg_turismouq.sp_crear_reserva(:v_cli, :v_hab, DATE '2027-01-25', DATE '2027-01-27', 2,
                                  v_res, 'PENDIENTE', 'PRUEBA E3 TX - paso a paso');
   contar('1. SAVEPOINT sv_a + reserva', 1, 0);

   SAVEPOINT sv_b;
   pkg_reservas_tx.sp_registrar_pago(v_res, 20000, 'PSE', 'E3-TX-0004', v_pago);
   contar('2. SAVEPOINT sv_b + pago', 1, 1);

   ROLLBACK TO sv_b;
   contar('3. ROLLBACK TO sv_b (parcial: se va el pago)', 1, 0);

   ROLLBACK TO sv_a;
   contar('4. ROLLBACK TO sv_a (se va la reserva)', 0, 0);

   ROLLBACK;
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_ok THEN 'OK' ELSE 'FALLA' END || ': cada ROLLBACK TO deshizo solo su tramo');
EXCEPTION
   WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('FALLA: ' || SQLERRM);
END;
/

PROMPT ================================================================
PROMPT  T9.5 Si falla la RESERVA (habitación ocupada) no se intenta el pago y no queda nada
PROMPT ================================================================
DECLARE
   v_res  NUMBER;
   v_pago NUMBER;
   v_n    NUMBER;
BEGIN
   pkg_reservas_tx.sp_reservar_con_pago(
      p_id_cliente    => :v_cli,
      p_id_habitacion => :v_hab,
      p_fecha_in      => DATE '2027-01-20',        -- se cruza con T9.1 (18 al 21)
      p_fecha_out     => DATE '2027-01-22',
      p_num_huespedes => 2,
      p_monto_pago    => 50000,
      p_metodo        => 'PSE',
      p_referencia    => 'E3-TX-0005',
      p_id_reserva    => v_res,
      p_id_pago       => v_pago,
      p_observaciones => 'PRUEBA E3 TX - no debe quedar');
   DBMS_OUTPUT.PUT_LINE('FALLA: se creó la reserva ' || v_res);
EXCEPTION
   WHEN pkg_turismouq.ex_no_disponible THEN
      SELECT COUNT(*) INTO v_n FROM pago WHERE referencia = 'E3-TX-0005';
      DBMS_OUTPUT.PUT_LINE(CASE WHEN v_n = 0 THEN 'OK' ELSE 'FALLA' END || ' (error esperado) -> ' || SQLERRM);
   WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('FALLA: error inesperado -> ' || SQLERRM);
END;
/

PROMPT ================================================================
PROMPT  T9.6 Reactivar una reserva cancelada cuya habitación ya se volvió a vender -> -20001
PROMPT ================================================================
DECLARE
   v_nueva NUMBER;
BEGIN
   -- se cancela la reserva de T9.3 (22 al 24) y otro cliente toma esas noches
   pkg_turismouq.sp_cancelar_reserva(:v_res3);
   pkg_turismouq.sp_crear_reserva(:v_cli, :v_hab, DATE '2027-01-22', DATE '2027-01-24', 2,
                                  v_nueva, 'CONFIRMADA', 'PRUEBA E3 TX - toma la habitacion liberada');
   COMMIT;

   BEGIN
      UPDATE reserva
      SET    estado = 'PENDIENTE', fecha_cancelacion = NULL
      WHERE  id_reserva = :v_res3;
      DBMS_OUTPUT.PUT_LINE('FALLA: se reactivó la reserva ' || :v_res3);
      ROLLBACK;
   EXCEPTION
      WHEN pkg_turismouq.ex_no_disponible THEN
         DBMS_OUTPUT.PUT_LINE('OK (error esperado) -> ' || SQLERRM);
   END;
EXCEPTION
   WHEN OTHERS THEN
      ROLLBACK;
      DBMS_OUTPUT.PUT_LINE('FALLA: ' || SQLERRM);
END;
/

PROMPT ================================================================
PROMPT  Fin del script 09. Revise que no aparezca ninguna línea "FALLA".
PROMPT ================================================================
