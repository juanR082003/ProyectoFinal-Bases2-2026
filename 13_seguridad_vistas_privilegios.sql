/* =====================================================================
   TurismoUQ · Proyecto integrador Bases de Datos II · 2026-2
   Script 13 · Seguridad II: vistas, paquetes de acceso y privilegios (Entrega 3)
   ---------------------------------------------------------------------
   Ejecutar como TURISMOUQ con F5, después de 09 (paquete de transacciones)
   y de 12 (los roles deben existir para poder otorgarles privilegios).

   Idea central: nadie distinto del dueño toca las tablas para escribir.
     · RECEPCIÓN no tiene NINGÚN privilegio sobre tablas. Lee por vistas
       V_REC_* y escribe solo por el paquete PKG_RECEPCION.
     · El ENCARGADO lee y mantiene lo suyo por vistas V_ADM_* (con
       WITH CHECK OPTION) y cambia tarifas por PKG_ADMIN_ALOJAMIENTO.
     · GERENTE y AUDITOR solo tienen SELECT.

   Seguridad por fila
     Un privilegio sobre una tabla es "todo o nada": no distingue las
     filas del hotel A de las del hotel B. Por eso las vistas filtran por
     el alojamiento del usuario CONECTADO, que se busca en USUARIO_SISTEMA
     con SYS_CONTEXT('USERENV', 'SESSION_USER'). Las vistas y los paquetes
     se ejecutan con los permisos de su dueño (TURISMOUQ), pero
     SESSION_USER sigue siendo quien inició la sesión: así la misma vista
     le muestra a cada recepcionista solo su alojamiento.

   Contenido
     Sección 1. PKG_SEGURIDAD: quién soy y cuál es mi alojamiento.
     Sección 2. Vistas de recepción (solo lectura).
     Sección 3. Vistas del encargado (actualizables con CHECK OPTION) y
                vista de gerencia sin datos personales.
     Sección 4. PKG_RECEPCION y PKG_ADMIN_ALOJAMIENTO.
     Sección 5. Privilegios de objeto por rol.
     Sección 6. Evidencia.

   Código de error nuevo
     -20011 operación fuera del ámbito del usuario (otro alojamiento, o
            usuario sin alojamiento asignado)
   ===================================================================== */

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET SQLBLANKLINES ON
SET LINESIZE 200
SET PAGESIZE 200

/* =====================================================================
   Sección 1. PKG_SEGURIDAD
   ===================================================================== */
CREATE OR REPLACE PACKAGE pkg_seguridad AS

   c_err_ambito CONSTANT PLS_INTEGER := -20011;
   ex_ambito    EXCEPTION;  PRAGMA EXCEPTION_INIT(ex_ambito, -20011);

   -- username de USUARIO_SISTEMA que corresponde al usuario conectado
   -- (RECEP_HOTEL1 -> 'recep.hotel1')
   FUNCTION fn_usuario_app RETURN VARCHAR2;

   -- alojamiento del usuario conectado; NULL si es de plataforma o no está registrado
   FUNCTION fn_alojamiento_sesion RETURN NUMBER;

   -- lanza -20011 si el usuario conectado no pertenece a ese alojamiento
   PROCEDURE sp_exigir_alojamiento (p_id_alojamiento IN NUMBER);

END pkg_seguridad;
/

CREATE OR REPLACE PACKAGE BODY pkg_seguridad AS

   FUNCTION fn_usuario_app RETURN VARCHAR2 IS
   BEGIN
      RETURN REPLACE(LOWER(SYS_CONTEXT('USERENV', 'SESSION_USER')), '_', '.');
   END fn_usuario_app;

   FUNCTION fn_alojamiento_sesion RETURN NUMBER IS
      v_id usuario_sistema.id_alojamiento%TYPE;
   BEGIN
      SELECT id_alojamiento INTO v_id
      FROM   usuario_sistema
      WHERE  username = fn_usuario_app
      AND    activo   = 'S';
      RETURN v_id;
   EXCEPTION
      WHEN NO_DATA_FOUND THEN RETURN NULL;
   END fn_alojamiento_sesion;

   PROCEDURE sp_exigir_alojamiento (p_id_alojamiento IN NUMBER) IS
      v_mio usuario_sistema.id_alojamiento%TYPE := fn_alojamiento_sesion;
   BEGIN
      IF v_mio IS NULL THEN
         RAISE_APPLICATION_ERROR(c_err_ambito,
            'El usuario ' || SYS_CONTEXT('USERENV', 'SESSION_USER') || ' no tiene un alojamiento asignado.');
      END IF;
      IF p_id_alojamiento IS NULL OR p_id_alojamiento <> v_mio THEN
         RAISE_APPLICATION_ERROR(c_err_ambito,
            'Operación fuera de su ámbito: el usuario ' || SYS_CONTEXT('USERENV', 'SESSION_USER')
            || ' solo puede operar sobre su propio alojamiento.');
      END IF;
   END sp_exigir_alojamiento;

END pkg_seguridad;
/
SHOW ERRORS PACKAGE BODY pkg_seguridad

/* =====================================================================
   Sección 2. Vistas de RECEPCIÓN (WITH READ ONLY)
   ---------------------------------------------------------------------
   Todas muestran solo el alojamiento del usuario conectado. El filtro
   va como subconsulta escalar (SELECT ... FROM dual) para que Oracle
   evalúe la función una vez por consulta y no una vez por fila.
   ===================================================================== */

-- En qué alojamiento estoy
CREATE OR REPLACE VIEW v_rec_mi_alojamiento AS
SELECT a.id_alojamiento, a.nombre_comercial, m.nombre AS municipio, ta.nombre AS tipo, a.telefono
FROM   alojamiento a
JOIN   municipio m         ON m.id_municipio = a.id_municipio
JOIN   tipo_alojamiento ta ON ta.id_tipo     = a.id_tipo
WHERE  a.id_alojamiento = (SELECT pkg_seguridad.fn_alojamiento_sesion FROM dual)
WITH READ ONLY;

CREATE OR REPLACE VIEW v_rec_habitaciones AS
SELECT h.id_habitacion, h.numero, h.tipo_habitacion, h.capacidad_max, h.descripcion, h.activa
FROM   habitacion h
WHERE  h.id_alojamiento = (SELECT pkg_seguridad.fn_alojamiento_sesion FROM dual)
WITH READ ONLY;

-- Tarifas vigentes o futuras de mis habitaciones
CREATE OR REPLACE VIEW v_rec_tarifas AS
SELECT h.id_habitacion, h.numero, t.id_temporada, t.nombre AS temporada, t.categoria,
       t.fecha_inicio, t.fecha_fin, tf.valor_noche
FROM   habitacion h
JOIN   tarifa tf   ON tf.id_habitacion = h.id_habitacion
JOIN   temporada t ON t.id_temporada   = tf.id_temporada
WHERE  h.id_alojamiento = (SELECT pkg_seguridad.fn_alojamiento_sesion FROM dual)
AND    t.fecha_fin     >= TRUNC(SYSDATE)
WITH READ ONLY;

CREATE OR REPLACE VIEW v_rec_servicios AS
SELECT s.id_servicio, s.nombre, s.descripcion, s.precio, s.unidad_cobro, s.activo
FROM   servicio s
WHERE  s.id_alojamiento = (SELECT pkg_seguridad.fn_alojamiento_sesion FROM dual)
WITH READ ONLY;

-- Clientes: recepción necesita encontrarlos para reservar. No son de un
-- alojamiento, así que se muestran todos, pero solo lo necesario.
CREATE OR REPLACE VIEW v_rec_clientes AS
SELECT c.id_cliente, c.tipo_documento, c.numero_documento, c.nombres, c.apellidos,
       c.correo, c.telefono, c.ciudad_origen, c.pais_origen
FROM   cliente c
WITH READ ONLY;

-- Reservas de mi alojamiento con su total, lo pagado y el saldo
CREATE OR REPLACE VIEW v_rec_reservas AS
SELECT r.id_reserva,
       r.id_cliente,
       c.nombres || ' ' || c.apellidos                 AS cliente,
       c.tipo_documento || ' ' || c.numero_documento   AS documento,
       r.fecha_reserva,
       r.fecha_checkin,
       r.fecha_checkout,
       r.estado,
       r.observaciones,
       pkg_turismouq.fn_total_reserva(r.id_reserva)    AS total,
       pkg_turismouq.fn_total_pagado(r.id_reserva)     AS pagado,
       pkg_turismouq.fn_total_reserva(r.id_reserva)
          - pkg_turismouq.fn_total_pagado(r.id_reserva) AS saldo
FROM   reserva r
JOIN   cliente c ON c.id_cliente = r.id_cliente
WHERE  r.id_alojamiento = (SELECT pkg_seguridad.fn_alojamiento_sesion FROM dual)
WITH READ ONLY;

-- Líneas (habitaciones) de esas reservas
CREATE OR REPLACE VIEW v_rec_reserva_habitaciones AS
SELECT rh.id_reserva, rh.id_habitacion, h.numero, rh.fecha_checkin, rh.fecha_checkout,
       rh.num_huespedes, rh.valor_estadia
FROM   reserva_habitacion rh
JOIN   habitacion h ON h.id_habitacion = rh.id_habitacion
WHERE  rh.id_alojamiento = (SELECT pkg_seguridad.fn_alojamiento_sesion FROM dual)
WITH READ ONLY;

CREATE OR REPLACE VIEW v_rec_pagos AS
SELECT p.id_pago, p.id_reserva, p.fecha_pago, p.monto, p.metodo, p.estado, p.concepto,
       p.monto_reembolsado, p.fecha_reembolso, p.referencia
FROM   pago p
JOIN   reserva r ON r.id_reserva = p.id_reserva
WHERE  r.id_alojamiento = (SELECT pkg_seguridad.fn_alojamiento_sesion FROM dual)
WITH READ ONLY;

/* =====================================================================
   Sección 3. Vistas del ENCARGADO y de GERENCIA
   ---------------------------------------------------------------------
   V_ADM_HABITACIONES y V_ADM_SERVICIOS son actualizables: una sola tabla
   y sin agregados. WITH CHECK OPTION impide que por la vista se inserte
   o se deje una fila que la propia vista no mostraría; es decir, el
   encargado no puede crear ni "mover" habitaciones o servicios a otro
   alojamiento (ORA-01402). Aquí el filtro llama a la función directamente
   (sin subconsulta) para que Oracle pueda hacer cumplir el CHECK OPTION.
   ===================================================================== */
CREATE OR REPLACE VIEW v_adm_habitaciones AS
SELECT id_habitacion, id_alojamiento, numero, tipo_habitacion, capacidad_max, descripcion, activa
FROM   habitacion
WHERE  id_alojamiento = pkg_seguridad.fn_alojamiento_sesion
WITH CHECK OPTION CONSTRAINT ck_v_adm_habitaciones;

CREATE OR REPLACE VIEW v_adm_servicios AS
SELECT id_servicio, id_alojamiento, nombre, descripcion, precio, unidad_cobro, activo
FROM   servicio
WHERE  id_alojamiento = pkg_seguridad.fn_alojamiento_sesion
WITH CHECK OPTION CONSTRAINT ck_v_adm_servicios;

-- Todas las tarifas (pasadas y futuras) de mis habitaciones; se cambian con PKG_ADMIN_ALOJAMIENTO
CREATE OR REPLACE VIEW v_adm_tarifas AS
SELECT tf.id_tarifa, h.id_habitacion, h.numero, t.id_temporada, t.nombre AS temporada, t.categoria,
       t.anio, t.fecha_inicio, t.fecha_fin, tf.valor_noche, tf.fecha_actualizacion
FROM   habitacion h
JOIN   tarifa tf   ON tf.id_habitacion = h.id_habitacion
JOIN   temporada t ON t.id_temporada   = tf.id_temporada
WHERE  h.id_alojamiento = (SELECT pkg_seguridad.fn_alojamiento_sesion FROM dual)
WITH READ ONLY;

CREATE OR REPLACE VIEW v_adm_liquidacion AS
SELECT l.anio, l.mes, l.reservas, l.noches_vendidas, l.ingreso_hospedaje, l.ingreso_servicios,
       l.ingreso_cancelaciones, l.total_bruto, l.comision_plataforma, l.neto_alojamiento, l.fecha_generacion
FROM   liquidacion_mensual l
WHERE  l.id_alojamiento = (SELECT pkg_seguridad.fn_alojamiento_sesion FROM dual)
WITH READ ONLY;

CREATE OR REPLACE VIEW v_adm_ocupacion AS
SELECT o.anio, o.mes, o.habitaciones, o.noches_disponibles, o.noches_ocupadas, o.pct_ocupacion,
       o.reservas, o.ingreso_hospedaje
FROM   mv_ocupacion_mensual o
WHERE  o.id_alojamiento = (SELECT pkg_seguridad.fn_alojamiento_sesion FROM dual)
WITH READ ONLY;

CREATE OR REPLACE VIEW v_adm_resenas AS
SELECT re.id_resena, re.id_reserva, r.fecha_checkout, re.calificacion, re.comentario, re.fecha_resena
FROM   resena re
JOIN   reserva r ON r.id_reserva = re.id_reserva
WHERE  r.id_alojamiento = (SELECT pkg_seguridad.fn_alojamiento_sesion FROM dual)
WITH READ ONLY;

-- Gerencia: clientes sin documento, nombre ni datos de contacto (solo para análisis de origen)
CREATE OR REPLACE VIEW v_ger_clientes AS
SELECT c.id_cliente, c.ciudad_origen, c.pais_origen, c.fecha_registro
FROM   cliente c
WITH READ ONLY;

/* =====================================================================
   Sección 4. Paquetes de acceso
   ---------------------------------------------------------------------
   Son de derechos del DUEÑO (AUTHID DEFINER, el valor por omisión): el
   recepcionista ejecuta el procedimiento sin tener permisos sobre las
   tablas que el procedimiento toca. Cada procedimiento comprueba primero
   que la habitación o la reserva sea del alojamiento de quien llama.
   Son puntos de entrada de la aplicación: confirman (COMMIT) su trabajo.
   ===================================================================== */
CREATE OR REPLACE PACKAGE pkg_recepcion AS

   PROCEDURE sp_registrar_cliente (
      p_tipo_documento    IN  VARCHAR2,
      p_numero_documento  IN  VARCHAR2,
      p_nombres           IN  VARCHAR2,
      p_apellidos         IN  VARCHAR2,
      p_correo            IN  VARCHAR2,
      p_telefono          IN  VARCHAR2,
      p_ciudad_origen     IN  VARCHAR2,
      p_id_cliente        OUT NUMBER,
      p_pais_origen       IN  VARCHAR2 DEFAULT 'Colombia'
   );

   -- Reserva + pago en una transacción (pkg_reservas_tx), solo en mi alojamiento
   PROCEDURE sp_reservar_con_pago (
      p_id_cliente     IN  NUMBER,
      p_id_habitacion  IN  NUMBER,
      p_fecha_in       IN  DATE,
      p_fecha_out      IN  DATE,
      p_num_huespedes  IN  NUMBER,
      p_monto_pago     IN  NUMBER,
      p_metodo         IN  VARCHAR2,
      p_referencia     IN  VARCHAR2,
      p_id_reserva     OUT NUMBER,
      p_id_pago        OUT NUMBER,
      p_observaciones  IN  VARCHAR2 DEFAULT NULL
   );

   PROCEDURE sp_registrar_pago (
      p_id_reserva  IN  NUMBER,
      p_monto       IN  NUMBER,
      p_metodo      IN  VARCHAR2,
      p_referencia  IN  VARCHAR2,
      p_id_pago     OUT NUMBER
   );

   PROCEDURE sp_cancelar_reserva (p_id_reserva IN NUMBER);

END pkg_recepcion;
/

CREATE OR REPLACE PACKAGE BODY pkg_recepcion AS

   -- alojamiento de una habitación / de una reserva (NULL si no existe)
   FUNCTION f_aloj_habitacion (p_id_habitacion NUMBER) RETURN NUMBER IS
      v NUMBER;
   BEGIN
      SELECT id_alojamiento INTO v FROM habitacion WHERE id_habitacion = p_id_habitacion;
      RETURN v;
   EXCEPTION
      WHEN NO_DATA_FOUND THEN RETURN NULL;
   END;

   FUNCTION f_aloj_reserva (p_id_reserva NUMBER) RETURN NUMBER IS
      v NUMBER;
   BEGIN
      SELECT id_alojamiento INTO v FROM reserva WHERE id_reserva = p_id_reserva;
      RETURN v;
   EXCEPTION
      WHEN NO_DATA_FOUND THEN RETURN NULL;
   END;

   PROCEDURE sp_registrar_cliente (
      p_tipo_documento    IN  VARCHAR2,
      p_numero_documento  IN  VARCHAR2,
      p_nombres           IN  VARCHAR2,
      p_apellidos         IN  VARCHAR2,
      p_correo            IN  VARCHAR2,
      p_telefono          IN  VARCHAR2,
      p_ciudad_origen     IN  VARCHAR2,
      p_id_cliente        OUT NUMBER,
      p_pais_origen       IN  VARCHAR2 DEFAULT 'Colombia'
   ) IS
   BEGIN
      IF pkg_seguridad.fn_alojamiento_sesion IS NULL THEN
         RAISE_APPLICATION_ERROR(pkg_seguridad.c_err_ambito,
            'Solo el personal de un alojamiento puede registrar clientes por este medio.');
      END IF;
      INSERT INTO cliente (tipo_documento, numero_documento, nombres, apellidos, correo,
                           telefono, ciudad_origen, pais_origen)
      VALUES (UPPER(TRIM(p_tipo_documento)), TRIM(p_numero_documento), TRIM(p_nombres), TRIM(p_apellidos),
              LOWER(TRIM(p_correo)), TRIM(p_telefono), TRIM(p_ciudad_origen), NVL(TRIM(p_pais_origen), 'Colombia'))
      RETURNING id_cliente INTO p_id_cliente;
      COMMIT;
   EXCEPTION
      WHEN DUP_VAL_ON_INDEX THEN
         RAISE_APPLICATION_ERROR(pkg_turismouq.c_err_parametro,
            'Ya existe un cliente con ese documento o con ese correo.');
   END sp_registrar_cliente;

   PROCEDURE sp_reservar_con_pago (
      p_id_cliente     IN  NUMBER,
      p_id_habitacion  IN  NUMBER,
      p_fecha_in       IN  DATE,
      p_fecha_out      IN  DATE,
      p_num_huespedes  IN  NUMBER,
      p_monto_pago     IN  NUMBER,
      p_metodo         IN  VARCHAR2,
      p_referencia     IN  VARCHAR2,
      p_id_reserva     OUT NUMBER,
      p_id_pago        OUT NUMBER,
      p_observaciones  IN  VARCHAR2 DEFAULT NULL
   ) IS
   BEGIN
      pkg_seguridad.sp_exigir_alojamiento(f_aloj_habitacion(p_id_habitacion));
      pkg_reservas_tx.sp_reservar_con_pago(
         p_id_cliente    => p_id_cliente,
         p_id_habitacion => p_id_habitacion,
         p_fecha_in      => p_fecha_in,
         p_fecha_out     => p_fecha_out,
         p_num_huespedes => p_num_huespedes,
         p_monto_pago    => p_monto_pago,
         p_metodo        => p_metodo,
         p_referencia    => p_referencia,
         p_id_reserva    => p_id_reserva,
         p_id_pago       => p_id_pago,
         p_si_falla_pago => 'DESHACER_TODO',
         p_confirmar     => 'S',
         p_observaciones => p_observaciones);
   END sp_reservar_con_pago;

   PROCEDURE sp_registrar_pago (
      p_id_reserva  IN  NUMBER,
      p_monto       IN  NUMBER,
      p_metodo      IN  VARCHAR2,
      p_referencia  IN  VARCHAR2,
      p_id_pago     OUT NUMBER
   ) IS
   BEGIN
      pkg_seguridad.sp_exigir_alojamiento(f_aloj_reserva(p_id_reserva));
      pkg_reservas_tx.sp_registrar_pago(p_id_reserva, p_monto, p_metodo, p_referencia, p_id_pago);
      COMMIT;
   END sp_registrar_pago;

   PROCEDURE sp_cancelar_reserva (p_id_reserva IN NUMBER) IS
   BEGIN
      pkg_seguridad.sp_exigir_alojamiento(f_aloj_reserva(p_id_reserva));
      pkg_turismouq.sp_cancelar_reserva(p_id_reserva);
      COMMIT;
   END sp_cancelar_reserva;

END pkg_recepcion;
/
SHOW ERRORS PACKAGE BODY pkg_recepcion

CREATE OR REPLACE PACKAGE pkg_admin_alojamiento AS

   -- Cambia la tarifa de una de MIS habitaciones en una temporada.
   -- El cambio queda en la auditoría de TARIFA con el usuario que lo hizo.
   PROCEDURE sp_cambiar_tarifa (
      p_id_habitacion IN NUMBER,
      p_id_temporada  IN NUMBER,
      p_valor_noche   IN NUMBER
   );

END pkg_admin_alojamiento;
/

CREATE OR REPLACE PACKAGE BODY pkg_admin_alojamiento AS

   PROCEDURE sp_cambiar_tarifa (
      p_id_habitacion IN NUMBER,
      p_id_temporada  IN NUMBER,
      p_valor_noche   IN NUMBER
   ) IS
      v_aloj NUMBER;
   BEGIN
      BEGIN
         SELECT id_alojamiento INTO v_aloj FROM habitacion WHERE id_habitacion = p_id_habitacion;
      EXCEPTION
         WHEN NO_DATA_FOUND THEN v_aloj := NULL;
      END;
      pkg_seguridad.sp_exigir_alojamiento(v_aloj);

      IF p_valor_noche IS NULL OR p_valor_noche <= 0 THEN
         RAISE_APPLICATION_ERROR(pkg_turismouq.c_err_parametro, 'El valor por noche debe ser mayor que cero.');
      END IF;

      UPDATE tarifa
      SET    valor_noche         = p_valor_noche,
             fecha_actualizacion = SYSDATE
      WHERE  id_habitacion = p_id_habitacion
      AND    id_temporada  = p_id_temporada;

      IF SQL%ROWCOUNT = 0 THEN
         RAISE_APPLICATION_ERROR(pkg_turismouq.c_err_no_existe,
            'No existe tarifa para la habitación ' || p_id_habitacion || ' en la temporada ' || p_id_temporada || '.');
      END IF;
      COMMIT;
   END sp_cambiar_tarifa;

END pkg_admin_alojamiento;
/
SHOW ERRORS PACKAGE BODY pkg_admin_alojamiento

/* =====================================================================
   Sección 5. Privilegios de objeto por rol
   ===================================================================== */

-- ---------- RECEPCIÓN: solo vistas y un paquete; ninguna tabla ----------
GRANT SELECT ON v_rec_mi_alojamiento       TO rol_recepcion;
GRANT SELECT ON v_rec_habitaciones         TO rol_recepcion;
GRANT SELECT ON v_rec_tarifas              TO rol_recepcion;
GRANT SELECT ON v_rec_servicios            TO rol_recepcion;
GRANT SELECT ON v_rec_clientes             TO rol_recepcion;
GRANT SELECT ON v_rec_reservas             TO rol_recepcion;
GRANT SELECT ON v_rec_reserva_habitaciones TO rol_recepcion;
GRANT SELECT ON v_rec_pagos                TO rol_recepcion;
GRANT EXECUTE ON pkg_recepcion             TO rol_recepcion;

-- ---------- ENCARGADO: hereda recepción (script 12) y mantiene lo suyo ----------
-- Sin DELETE: una habitación o un servicio con historia no se borra, se desactiva.
GRANT SELECT, INSERT, UPDATE ON v_adm_habitaciones TO rol_admin_alojamiento;
GRANT SELECT, INSERT, UPDATE ON v_adm_servicios    TO rol_admin_alojamiento;
GRANT SELECT ON v_adm_tarifas                      TO rol_admin_alojamiento;
GRANT SELECT ON v_adm_liquidacion                  TO rol_admin_alojamiento;
GRANT SELECT ON v_adm_ocupacion                    TO rol_admin_alojamiento;
GRANT SELECT ON v_adm_resenas                      TO rol_admin_alojamiento;
GRANT EXECUTE ON pkg_admin_alojamiento             TO rol_admin_alojamiento;

-- ---------- GERENTE: lectura de la operación e indicadores de TODOS los alojamientos ----------
GRANT SELECT ON municipio            TO rol_gerente;
GRANT SELECT ON tipo_alojamiento     TO rol_gerente;
GRANT SELECT ON alojamiento          TO rol_gerente;
GRANT SELECT ON habitacion           TO rol_gerente;
GRANT SELECT ON servicio             TO rol_gerente;
GRANT SELECT ON temporada            TO rol_gerente;
GRANT SELECT ON calendario           TO rol_gerente;
GRANT SELECT ON tarifa               TO rol_gerente;
GRANT SELECT ON reserva              TO rol_gerente;
GRANT SELECT ON reserva_habitacion   TO rol_gerente;
GRANT SELECT ON reserva_servicio     TO rol_gerente;
GRANT SELECT ON pago                 TO rol_gerente;
GRANT SELECT ON resena               TO rol_gerente;
GRANT SELECT ON liquidacion_mensual  TO rol_gerente;
GRANT SELECT ON mv_ocupacion_mensual TO rol_gerente;
GRANT SELECT ON reserva_historico    TO rol_gerente;
GRANT SELECT ON v_ger_clientes       TO rol_gerente;

-- ---------- AUDITOR: lectura de la auditoría y de lo que se audita ----------
GRANT SELECT ON auditoria_tarifa_operacion TO rol_auditor;
GRANT SELECT ON auditoria_tarifa_detalle   TO rol_auditor;
GRANT SELECT ON tarifa                     TO rol_auditor;
GRANT SELECT ON temporada                  TO rol_auditor;
GRANT SELECT ON habitacion                 TO rol_auditor;
GRANT SELECT ON alojamiento                TO rol_auditor;
GRANT SELECT ON reserva                    TO rol_auditor;
GRANT SELECT ON reserva_habitacion         TO rol_auditor;
GRANT SELECT ON pago                       TO rol_auditor;
GRANT SELECT ON liquidacion_mensual        TO rol_auditor;
GRANT SELECT ON reserva_historico          TO rol_auditor;
GRANT SELECT ON rol                        TO rol_auditor;
GRANT SELECT ON usuario_sistema            TO rol_auditor;

/* =====================================================================
   Sección 6. Evidencia
   ===================================================================== */
COLUMN rol_bd     FORMAT A24
COLUMN objeto     FORMAT A30
COLUMN tipo       FORMAT A18
COLUMN privilegios FORMAT A30

PROMPT Objetos de seguridad creados (deben estar VALID)
SELECT object_name, object_type, status
FROM   user_objects
WHERE  object_name IN ('PKG_SEGURIDAD', 'PKG_RECEPCION', 'PKG_ADMIN_ALOJAMIENTO')
   OR  object_name LIKE 'V\_REC\_%' ESCAPE '\'
   OR  object_name LIKE 'V\_ADM\_%' ESCAPE '\'
   OR  object_name LIKE 'V\_GER\_%' ESCAPE '\'
ORDER  BY object_type, object_name;

PROMPT Matriz de privilegios: qué recibió cada rol y sobre qué tipo de objeto
SELECT p.grantee                                                   AS rol_bd,
       p.table_name                                                AS objeto,
       p.type                                                      AS tipo,
       LISTAGG(p.privilege, ', ') WITHIN GROUP (ORDER BY p.privilege) AS privilegios
FROM   user_tab_privs_made p
WHERE  p.grantee LIKE 'ROL\_%' ESCAPE '\'
GROUP  BY p.grantee, p.table_name, p.type
ORDER  BY p.grantee, p.type, p.table_name;

PROMPT Comprobación: RECEPCIÓN no tiene privilegios sobre ninguna TABLA (debe decir 0)
SELECT COUNT(*) AS privilegios_de_recepcion_sobre_tablas
FROM   user_tab_privs_made
WHERE  grantee = 'ROL_RECEPCION'
AND    type    = 'TABLE';

PROMPT Resumen por rol y tipo de objeto
SELECT grantee AS rol_bd, type AS tipo, privilege, COUNT(*) AS objetos
FROM   user_tab_privs_made
WHERE  grantee LIKE 'ROL\_%' ESCAPE '\'
GROUP  BY grantee, type, privilege
ORDER  BY grantee, type, privilege;

PROMPT Seguridad lista. Ejecute 14_pruebas_seguridad.sql para probar cada rol.
