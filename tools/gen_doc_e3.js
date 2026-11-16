// Genera docs/Entrega3_TurismoUQ.docx  (uso: node tools/gen_doc_e3.js desde la raíz del repositorio)
const path = require('path');
const H = require('./doc_helpers.js');
const { fs, Document, Packer, Paragraph, TextRun, AlignmentType, PageBreak, LevelFormat, Footer, PageNumber,
        FONT, p, b, i, code, h1, h2, bullet, codeBlock, table } = H;
const { ImageRun } = require('docx');
const CAP = path.join(__dirname, '..', 'docs', 'capturas');

const centro = (t, opts = {}) => new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: opts.before || 0 },
  children: [new TextRun({ text: t, font: FONT, size: opts.size || 22, bold: !!opts.bold })] });
// Capturas reales de pantalla (SQL Developer y Terminal en macOS) tomadas al ejecutar los scripts.
const img = (archivo) => new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 80 },
  children: [new ImageRun({ type: 'jpg', data: fs.readFileSync(path.join(CAP, archivo)),
    transformation: { width: 600, height: 375 } })] });
const captura = (t, ...archivos) => [p([b(t)], { para: { keepNext: true } }), ...archivos.map(img), p('')];

const portada = [
  centro('UNIVERSIDAD DEL QUINDÍO', { before: 1800, size: 28, bold: true }),
  centro('Facultad de Ingeniería · Ingeniería de Sistemas y Computación'),
  centro('Proyecto integrador TurismoUQ', { before: 1200, size: 44, bold: true }),
  centro('Plataforma de reservas turísticas del Quindío', { size: 26 }),
  centro('Entrega 3 · Transacciones, índices y seguridad', { before: 400, size: 28, bold: true }),
  centro('Integrantes', { before: 1400, bold: true }),
  centro('Juan Camilo López'), centro('José Luis Rivadeneira'), centro('Juan Manuel Rincón'),
  centro('Bases de Datos II · código 12338 · grupo [01D / 01N]', { before: 600 }),
  centro('Docente: Carolina Londoño Idárraga'),
  centro('Armenia, periodo 2026-2'),
  new Paragraph({ children: [new PageBreak()] }),
];

const alcance = [
  h1('1. Alcance de la entrega'),
  p('La Entrega 3 cierra el proyecto. Sobre el modelo de la Entrega 1 y la capa PL/SQL de la Entrega 2 agrega cuatro cosas: una transacción que registra reserva y pago de forma atómica con SAVEPOINT, el control de la concurrencia cuando dos sesiones quieren la misma habitación, los índices que necesitan las consultas más repetidas y el esquema de seguridad con roles, vistas y un perfil.'),
  table(['Script', 'Conectado como', 'Contenido'], [
    ['09_transacciones.sql', 'TURISMOUQ', 'Paquete PKG_RESERVAS_TX (bloqueo de habitación, registro de pago y transacción reserva + pago con SAVEPOINT), disparador de reactivación y pruebas T9.'],
    ['10_concurrencia.sql', 'TURISMOUQ', 'Antes y después del bloqueo, reproducido en una sola sesión con transacciones autónomas (pruebas T10).'],
    ['concurrencia/sesion_A.sql, sesion_B.sql, monitor_system.sql', 'TURISMOUQ (dos ventanas) y SYSTEM', 'El mismo experimento con dos sesiones reales y la consulta del bloqueo en V$SESSION y V$LOCK.'],
    ['11_indices.sql', 'TURISMOUQ', 'Tres consultas lentas, plan y tiempo antes y después, tres índices (dos compuestos y uno basado en función) y el caso donde el índice no ayuda.'],
    ['12_seguridad_roles_usuarios.sql', 'SYSTEM @ XEPDB1', 'Perfil PERFIL_TURISMOUQ, los cuatro roles y cinco usuarios de ejemplo.'],
    ['13_seguridad_vistas_privilegios.sql', 'TURISMOUQ', 'PKG_SEGURIDAD, vistas por rol, paquetes de acceso y GRANT por rol.'],
    ['14_pruebas_seguridad.sql', 'cualquiera (se conecta por turnos)', 'Qué puede y qué no puede cada rol: cada prueba imprime OK o FALLA.'],
  ], [3100, 1900, 4360]),
  p(''),
  p('Ambiente de ejecución: Oracle Database 26ai Free en un contenedor Docker (gvenzl/oracle-free) en macOS, servicio FREEPDB1, con SQL Developer 26.2. La base se creó desde cero con los scripts 00 a 08 antes de ejecutar los de esta entrega. Los scripts también corren en Oracle XE 21c (servicio XEPDB1).'),
  p('Correspondencia con el enunciado: el entregable 1 (script de transacciones con SAVEPOINT y ROLLBACK) es el script 09; el 2 (documento del escenario de concurrencia con capturas) es la sección 3 de este documento, apoyada en el script 10 y la carpeta concurrencia; el 3 (script de índices y capturas de EXPLAIN PLAN) es el script 11 y la sección 4; el 4 (roles, usuarios, GRANT y vistas) son los scripts 12 y 13, con sus pruebas en el 14.'),
];

const transacciones = [
  h1('2. Transacción atómica: reserva + pago con SAVEPOINT'),
  p('En la Entrega 2 los procedimientos de reserva no hacían COMMIT a propósito, para poder componerlos. PKG_RESERVAS_TX.sp_reservar_con_pago los compone en una sola transacción con dos puntos de retorno:'),
  ...codeBlock([
    'SAVEPOINT sv_inicio            -- "nada pasó"',
    '   bloquear la habitación (SELECT ... FOR UPDATE)',
    '   crear la reserva PENDIENTE (pkg_turismouq.sp_crear_reserva)',
    'SAVEPOINT sv_reserva           -- "reserva sin pago"',
    '   registrar el pago (sp_registrar_pago)',
    '   si lo pagado llega al 30 % del total -> reserva CONFIRMADA',
    'COMMIT (opcional, p_confirmar)',
  ]),
  table(['Qué falla', 'Qué se hace', 'Qué queda'], [
    ['La reserva (habitación ocupada, fechas, capacidad, bloqueo)', 'ROLLBACK TO sv_inicio y se relanza el error', 'Nada. No se intenta el pago.'],
    ['El pago, con p_si_falla_pago = DESHACER_TODO', 'ROLLBACK TO sv_inicio y se relanza el error', 'Nada: sin pago no hay reserva (atomicidad).'],
    ['El pago, con p_si_falla_pago = CONSERVAR_RESERVA', 'ROLLBACK TO sv_reserva (rollback parcial)', 'La reserva PENDIENTE y sin pago, lista para reintentar el cobro.'],
  ], [3300, 3100, 2960]),
  p(''),
  p('Se usa ROLLBACK TO SAVEPOINT y no ROLLBACK porque un ROLLBACK completo también borraría lo que quien llama hubiera hecho antes dentro de su transacción. Con el savepoint, el procedimiento solo deshace su propio trabajo. La prueba T9.2 lo demuestra: registra un abono, llama a la transacción con un pago que falla y comprueba que la reserva nueva desapareció pero el abono anterior sigue ahí.'),
  h2('2.1 Reglas del pago'),
  p('sp_registrar_pago rechaza con el código propio -20009 un pago que no cumple las reglas: la reserva debe estar PENDIENTE o CONFIRMADA; el monto debe ser mayor que cero y no superar el saldo; el método debe ser válido; el efectivo no lleva referencia y los demás métodos sí; y una referencia electrónica no se repite, porque sería el mismo cobro enviado dos veces. El concepto se deduce (TOTAL, SALDO o ANTICIPO). El anticipo mínimo del 30 % para confirmar es un supuesto del equipo, definido como constante del paquete.'),
  h2('2.2 Demostración del rollback parcial'),
  p('Hay dos demostraciones. T9.3 usa el procedimiento: el pago supera el saldo, se hace ROLLBACK TO sv_reserva y la reserva queda PENDIENTE con cero pagos. T9.4 lo muestra paso a paso, sin el procedimiento, contando filas después de cada instrucción:'),
  table(['Paso', 'Reservas', 'Pagos'], [
    ['0. Estado inicial', '0', '0'],
    ['1. SAVEPOINT sv_a + reserva', '1', '0'],
    ['2. SAVEPOINT sv_b + pago', '1', '1'],
    ['3. ROLLBACK TO sv_b (parcial: se va el pago)', '1', '0'],
    ['4. ROLLBACK TO sv_a (se va la reserva)', '0', '0'],
  ], [5360, 2000, 2000]),
  p(''),
  h2('2.3 Límite de la Entrega 2 que se cierra'),
  p('El documento de la Entrega 2 dejó anotado que reactivar una reserva cancelada no volvía a validar el solape. TRG_RESERVA_REACTIVACION, un disparador compuesto sobre RESERVA.estado, lo resuelve: si una reserva pasa de CANCELADA a otro estado y alguna de sus habitaciones ya fue tomada por otra reserva activa en esas noches, lanza -20001 (prueba T9.6).'),
];

const concurrencia = [
  h1('3. Concurrencia: dos sesiones sobre la misma habitación'),
  h2('3.1 El problema'),
  p('Oracle trabaja por omisión en READ COMMITTED con lectura consistente: una sesión no ve lo que otra todavía no ha confirmado, y leer no bloquea. La validación de disponibilidad de sp_crear_reserva y el disparador TRG_RH_NO_SOLAPE son lecturas. Si dos recepcionistas reservan la misma habitación al mismo tiempo, ninguna ve la reserva de la otra, las dos validaciones pasan y la habitación queda vendida dos veces. Ni el procedimiento ni el disparador pueden evitarlo solos.'),
  h2('3.2 La solución: SELECT ... FOR UPDATE'),
  p('No se puede bloquear una fila que todavía no existe (la reserva nueva), así que se bloquea su dueño: la fila de HABITACION. sp_bloquear_habitacion ejecuta SELECT ... FOR UPDATE sobre ella antes de validar. La segunda sesión queda esperando ese bloqueo de fila; cuando la primera confirma, la segunda continúa, su validación ya ve la reserva nueva y recibe -20001 (no disponible). El bloqueo es por habitación: reservar otra habitación del mismo hotel no espera a nadie (prueba T10.3).'),
  table(['Variante', 'Comportamiento de la segunda sesión', 'Cuándo usarla'], [
    ['FOR UPDATE', 'Espera sin límite hasta que la primera termine.', 'Procesos por lotes.'],
    ['FOR UPDATE WAIT n', 'Espera hasta n segundos; si no, error -20010. Es el valor por omisión (10 s).', 'Recepción: da tiempo a que la otra termine sin colgar la pantalla.'],
    ['FOR UPDATE NOWAIT', 'No espera: error -20010 de inmediato.', 'Cuando se prefiere avisar y reintentar.'],
  ], [2200, 4200, 2960]),
  p(''),
  h2('3.3 Experimento con dos sesiones'),
  p('El experimento se hizo en SQL Developer con dos hojas de trabajo NO compartidas de la conexión TURISMOUQ (Ctrl+Shift+N; cada una abre su propia sesión: A con SID 213 y B con SID 18) y una hoja de la conexión SYSTEM para consultar el bloqueo. Cada paso es un archivo de la carpeta concurrencia/sqldeveloper (A1, B1, A2, B2, A3, B3, A6, B4, A7) que se ejecuta con @ y F5 en la hoja que corresponde. La misma secuencia está en concurrencia/sesion_A.sql y sesion_B.sql para SQL*Plus, con pausas. La habitación en disputa es la 3 (segunda del Hotel Mirador del Parque Sucre), noches del 22 al 24 de enero de 2027.'),
  table(['Paso', 'Ventana A', 'Ventana B', 'Resultado'], [
    ['Antes 1', 'sp_crear_reserva, sin COMMIT', '', 'A tiene la reserva sin confirmar.'],
    ['Antes 2', '', 'sp_crear_reserva de la misma habitación', 'B también reserva, sin esperar: no vio a A.'],
    ['Antes 3', 'COMMIT', 'COMMIT', 'Dos reservas CONFIRMADAS: sobreventa.'],
    ['Después 1', 'sp_reservar_con_pago (FOR UPDATE), sin COMMIT', '', 'A tiene bloqueada la fila de la habitación.'],
    ['Después 2', '', 'sp_reservar_con_pago', 'B se queda esperando: bloqueo real.'],
    ['Después 3', 'COMMIT', '', 'B despierta (esperó 86,6 s) y recibe -20001: una sola reserva.'],
    ['Variantes', 'sp_bloquear_habitacion', 'NOWAIT y WAIT 5', 'B recibe -20010 a los 0,00 s y a los 5,00 s.'],
  ], [1200, 2900, 2700, 2560]),
  p(''),
  ...captura('Captura 1 · Antes: la hoja A y la hoja B reservan la misma habitación sin esperar (SID 213 y SID 18)', 'c1_A_sin_bloqueo.jpg', 'c1_B_sin_bloqueo.jpg'),
  ...captura('Captura 2 · Antes: dos reservas CONFIRMADAS para la misma habitación y noches', 'c2_sobreventa.jpg'),
  ...captura('Captura 3 · Después: A reserva con FOR UPDATE sin confirmar; B queda ejecutándose (bloqueada)', 'c3_A_con_bloqueo.jpg', 'c3_B_bloqueada.jpg'),
  ...captura('Captura 4 · Hoja SYSTEM: V$SESSION (blocking_session) y V$LOCK muestran quién bloquea a quién', 'c4_monitor.jpg'),
  ...captura('Captura 5 · Después: tras el COMMIT de A, B despierta (86,6 s) y recibe ORA-20001', 'c5_B_despierta.jpg'),
  ...captura('Captura 6 · NOWAIT y WAIT 5: ORA-20010 a los 0,00 s y a los 5,00 s', 'c6_nowait_wait.jpg'),
  ...captura('Captura 7 · Resultado final con bloqueo: una sola reserva', 'c7_final_con_bloqueo.jpg'),
  h2('3.4 Lectura del bloqueo'),
  p('En la captura 4, la sesión B (SID 18) aparece ACTIVE, con el evento "enq: TX - row lock contention", 47 segundos esperando y blocking_session = 213, el SID de la sesión A. Su sentencia es el SELECT ... FROM habitacion ... FOR UPDATE. En V$LOCK, A tiene un bloqueo TX en modo 6 (exclusivo) con BLOCK = 1, y B pide (REQUEST) un TX en modo 6 sobre la misma transacción. Los bloqueos TM en modo 3 sobre HABITACION son el bloqueo de tabla compartido que acompaña a todo bloqueo de fila y no impiden a otras sesiones trabajar con otras filas.'),
  h2('3.5 Comparación'),
  table(['', 'Antes (sin bloqueo)', 'Después (FOR UPDATE)'], [
    ['Segunda sesión', 'Continúa de inmediato.', 'Espera, o es rechazada con -20010.'],
    ['Reservas activas para la misma habitación y noches', '2 (sobreventa)', '1'],
    ['Quién detecta el conflicto', 'Nadie', 'La validación de la segunda sesión, que ya ve la reserva confirmada.'],
    ['Costo', 'Ninguno', 'Una espera corta solo cuando dos sesiones coinciden en la misma habitación.'],
  ], [3100, 2900, 3360]),
  p(''),
  p('El script 10 reproduce lo mismo sin abrir dos ventanas: la segunda sesión se simula con una transacción autónoma, que es independiente de la principal, no ve sus cambios sin confirmar y compite por los mismos bloqueos. Sirve como evidencia repetible (imprime OK o FALLA); el experimento con dos ventanas es el que muestra la espera real.'),
];

const indices = [
  h1('4. Índices'),
  p('Antes de esta entrega, RESERVA, RESERVA_HABITACION y PAGO solo tenían los índices que Oracle crea para sus claves primarias y únicas. Se eligieron tres consultas por ser las que más se repiten en la operación.'),
  table(['Caso', 'Consulta', 'Quién la ejecuta', 'Índice'], [
    ['C1', 'Reservas de una habitación que se cruzan con un rango de noches', 'sp_crear_reserva, sp_agregar_habitacion y el disparador anti-solape, en cada reserva', 'COMPUESTO ix_rh_hab_fechas (id_habitacion, fecha_checkin, fecha_checkout)'],
    ['C2', 'Pagos exitosos de un día por método, filtrando por TRUNC(fecha_pago)', 'Cuadre de caja diario', 'BASADO EN FUNCIÓN ix_pago_dia (TRUNC(fecha_pago))'],
    ['C3', 'Total pagado de una reserva', 'fn_total_pagado, sp_registrar_pago y las vistas de recepción', 'COMPUESTO ix_pago_reserva (id_reserva, estado, monto), que cubre la consulta'],
  ], [800, 3000, 2800, 2760]),
  p(''),
  bullet([b('C1, orden de las columnas. '), 'Primero la columna de igualdad (id_habitacion) y después las de rango (fechas). Oracle baja por el árbol hasta la habitación y recorre solo sus reservas, ordenadas por fecha.']),
  bullet([b('C2, por qué basado en función. '), 'fecha_pago guarda la hora. Al envolver la columna en TRUNC, un índice normal sobre fecha_pago no se puede usar. El índice basado en función guarda TRUNC(fecha_pago) ya calculado y ordenado.']),
  bullet([b('C3, índice que cubre. '), 'Tiene todo lo que la consulta necesita: id_reserva para llegar, estado para filtrar y monto para sumar. Oracle responde solo con el índice, sin leer la tabla. Indexar esa clave foránea evita además el bloqueo de tabla completa sobre PAGO cuando se borra una reserva o se cambia su clave.']),
  h2('4.1 Cómo se midió'),
  p('El procedimiento sp_medir_indice hace dos cosas con cada consulta, antes y después de crear los índices: pide el plan con EXPLAIN PLAN y guarda el costo estimado y las operaciones de acceso, y mide el tiempo real de ejecutarla cientos de veces con valores distintos del parámetro (500 habitaciones, 300 días, 1.000 reservas). Todo queda en la tabla INDICE_MEDICION. El plan completo se imprime con DBMS_XPLAN.DISPLAY.'),
  h2('4.2 Resultados'),
  p('Valores de la sección "COMPARACIÓN ANTES / DESPUÉS" de la salida del script 11 (captura 11). Los tiempos dependen del equipo; el costo y el tipo de acceso son los del optimizador.'),
  table(['Caso', 'Acceso antes', 'Acceso después', 'Costo antes → después', 'Tiempo antes → después'], [
    ['C1', 'TABLE ACCESS FULL de RESERVA_HABITACION', 'INDEX RANGE SCAN de IX_RH_HAB_FECHAS', '68 → 10 (6,8 veces)', '244 ms → 9 ms en 500 ejecuciones (27 veces)'],
    ['C2', 'TABLE ACCESS FULL de PAGO', 'INDEX RANGE SCAN de IX_PAGO_DIA + acceso por ROWID', '104 → 32 (3,3 veces)', '2.487 ms → 13 ms en 300 ejecuciones (191 veces)'],
    ['C3', 'TABLE ACCESS FULL de PAGO', 'INDEX RANGE SCAN de IX_PAGO_RESERVA, sin acceso a la tabla', '102 → 2 (51 veces)', '382 ms → 14 ms en 1.000 ejecuciones (27 veces)'],
  ], [700, 2400, 2700, 1780, 1780]),
  p(''),
  ...captura('Captura 8 · C1: plan ANTES y plan DESPUÉS', 'i_c1_antes.jpg', 'i_c1_despues.jpg'),
  ...captura('Captura 9 · C2: plan ANTES y plan DESPUÉS', 'i_c2_antes.jpg', 'i_c2_despues.jpg'),
  ...captura('Captura 10 · C3: plan ANTES y plan DESPUÉS', 'i_c3_antes.jpg', 'i_c3_despues.jpg'),
  ...captura('Captura 11 · Tabla de comparación antes / después', 'i_comparacion.jpg'),
  h2('4.3 El caso donde el índice no ayuda'),
  p('RESERVA.estado tiene solo cuatro valores y COMPLETADA es la gran mayoría de las filas. Se creó un índice sobre estado (ix_reserva_estado) y se pidió el número de reservas COMPLETADAS y sus noches (caso C4). Con el índice disponible y las estadísticas al día, el optimizador lo ignora y sigue recorriendo la tabla completa (costo 68). Para confirmar que no es un error del optimizador, el caso C5 lo obliga a usar el índice con un hint: el costo sube a 660 (9,7 veces) y el tiempo de 69 ms a 187 ms. Las COMPLETADAS son el 79,2 % de las reservas.'),
  p([b('Por qué no ayuda:')]),
  bullet([b('Selectividad. '), 'Un índice sirve cuando descarta casi toda la tabla. Este filtro deja pasar la mayoría de las filas.']),
  bullet([b('Costo de ir a la tabla. '), 'Por cada entrada del índice Oracle visita el bloque de la tabla donde está la fila, de a un bloque por lectura. Las reservas COMPLETADAS están repartidas por todos los bloques (clustering factor alto), así que se terminan leyendo todos los bloques, muchos de ellos varias veces, además del índice.']),
  bullet([b('El recorrido completo es más barato. '), 'Lee cada bloque una sola vez y de a varios bloques por lectura.']),
  bullet([b('El índice no es gratis. '), 'Ocupa espacio y habría que mantenerlo en cada cambio de estado de una reserva.']),
  p('El índice no es malo en sí mismo: para un valor escaso como PENDIENTE (1,4 % de las filas, caso C6) el optimizador sí lo usa y el costo baja de 68 a 13. Lo que decide es cuántas filas devuelve el filtro, no la columna. Como la consulta frecuente es la de las completadas, el índice se elimina al final del script.'),
  ...captura('Captura 12 · C4: plan con el índice creado (lo ignora) y C5 con el hint (más costoso)', 'i_c4_con_indice.jpg', 'i_c5_hint.jpg'),
  ...captura('Captura 13 · Veredicto del caso donde el índice no ayuda', 'i_veredicto.jpg'),
];

const seguridad = [
  h1('5. Seguridad'),
  h2('5.1 Roles'),
  table(['Rol', 'Para quién', 'Qué puede hacer'], [
    ['ROL_RECEPCION', 'Mostrador de un alojamiento', 'Leer las vistas V_REC_* de su alojamiento y ejecutar PKG_RECEPCION (registrar cliente, reservar con pago, registrar pago, cancelar). Ningún privilegio sobre tablas.'],
    ['ROL_ADMIN_ALOJAMIENTO', 'Encargado de un alojamiento', 'Todo lo de recepción (rol heredado) y además mantener sus habitaciones y servicios por las vistas V_ADM_*, cambiar sus tarifas con PKG_ADMIN_ALOJAMIENTO y ver su liquidación, ocupación y reseñas.'],
    ['ROL_GERENTE', 'Gerencia de la plataforma', 'Solo lectura de la operación y de los indicadores de todos los alojamientos (incluida la vista materializada). Ve clientes sin datos personales (V_GER_CLIENTES).'],
    ['ROL_AUDITOR', 'Auditoría interna', 'Solo lectura de la auditoría de tarifas, pagos, reservas, liquidaciones y usuarios. No puede modificar ni borrar nada, tampoco la auditoría.'],
  ], [3000, 1900, 4460]),
  p(''),
  p('El único privilegio de sistema de los roles es CREATE SESSION. Los privilegios de objeto los otorga TURISMOUQ, dueño del esquema. Los usuarios de ejemplo son RECEP_HOTEL1 y ENC_HOTEL (Hotel Mirador del Parque Sucre), RECEP_SALENTO (Hostal Calle Real de Salento), GERENTE_GENERAL y AUDITOR_INTERNO. Cada uno corresponde a una fila de USUARIO_SISTEMA de la Entrega 1 (RECEP_HOTEL1 es el username recep.hotel1).'),
  h2('5.2 Recepción solo por vistas'),
  p('Un privilegio sobre una tabla es todo o nada: no distingue las filas de un hotel de las de otro. Por eso recepción no recibe ninguno. Las vistas V_REC_* filtran por el alojamiento del usuario conectado, que PKG_SEGURIDAD busca en USUARIO_SISTEMA con SYS_CONTEXT(\'USERENV\', \'SESSION_USER\'). Las vistas y los paquetes se ejecutan con los permisos de su dueño, pero SESSION_USER sigue siendo quien inició la sesión; así la misma vista le muestra a cada recepcionista solo su alojamiento. El script 13 termina con una comprobación que cuenta los privilegios de ROL_RECEPCION sobre tablas y debe dar 0.'),
  p('Para escribir, recepción usa PKG_RECEPCION. Cada procedimiento comprueba primero que la habitación o la reserva sea del alojamiento de quien llama y, si no, lanza -20011. La reserva pasa por la transacción de la sección 2, de modo que el camino de la aplicación siempre bloquea la habitación.'),
  h2('5.3 Encargado: vistas con WITH CHECK OPTION'),
  p('V_ADM_HABITACIONES y V_ADM_SERVICIOS son actualizables y llevan WITH CHECK OPTION: por la vista no se puede insertar ni dejar una fila que la propia vista no mostraría. El encargado no puede crear ni mover habitaciones a otro alojamiento (ORA-01402), y las de otros alojamientos ni siquiera le aparecen. No tiene DELETE: una habitación con historia se desactiva, no se borra. Las tarifas se cambian con PKG_ADMIN_ALOJAMIENTO.sp_cambiar_tarifa, y el cambio queda en la auditoría de la Entrega 2 con el usuario real que se conectó.'),
  h2('5.4 Perfil con límites de sesión'),
  table(['Límite', 'Valor', 'Para qué'], [
    ['SESSIONS_PER_USER', '2', 'Evita que una cuenta se comparta entre muchos equipos.'],
    ['IDLE_TIME', '15 minutos', 'Cierra la sesión de un computador de recepción desatendido.'],
    ['CONNECT_TIME', '480 minutos', 'Una sesión dura como máximo un turno de 8 horas.'],
    ['FAILED_LOGIN_ATTEMPTS', '3', 'Bloquea la cuenta al tercer intento fallido.'],
    ['PASSWORD_LOCK_TIME', '1/96 de día (15 minutos)', 'Tiempo que dura ese bloqueo.'],
    ['PASSWORD_LIFE_TIME / PASSWORD_GRACE_TIME', '90 días / 7 días', 'Vencimiento de la contraseña y plazo para cambiarla.'],
  ], [3300, 2300, 3760]),
  p(''),
  p('Los límites de recursos solo se aplican con el parámetro RESOURCE_LIMIT en TRUE; el script 12 lo fija y lo muestra. El perfil se asigna a los cinco usuarios; el dueño del esquema no lo lleva porque sus jobs programados y los experimentos de concurrencia necesitan varias sesiones.'),
  ...captura('Captura 14 · Script 12 (SYSTEM): límites del perfil, usuarios y roles', 's12.jpg'),
  ...captura('Captura 15 · Script 13: matriz de privilegios por rol y comprobación de recepción (0 tablas)', 's13.jpg'),
  ...captura('Captura 16 · Script 14 en SQL*Plus: RECEP_HOTEL1, RECEP_SALENTO y ENC_HOTEL', 's14a1.jpg', 's14a2.jpg'),
  ...captura('Captura 17 · Script 14 en SQL*Plus: GERENTE_GENERAL, AUDITOR_INTERNO y cierre (0 FALLA, 52 OK)', 's14b.jpg'),
];

const pruebas = [
  h1('6. Pruebas y resultados esperados'),
  p('Las reservas de prueba van en la segunda quincena de enero de 2027, en el Hotel Mirador del Parque Sucre (las de la Entrega 2 usan otro hotel), con observaciones que empiezan por "PRUEBA E3". Cada script borra las suyas al inicio, así que se puede repetir. Deben ejecutarse antes del 18 de enero de 2027, porque no se permite reservar con check-in en el pasado.'),
  table(['Prueba', 'Qué se prueba', 'Resultado esperado'], [
    ['T9.1', 'Reserva + anticipo del 50 %', 'Reserva CONFIRMADA con un pago exitoso.'],
    ['T9.2', 'Pago con referencia duplicada, DESHACER_TODO', 'Error -20009; no queda la reserva; el abono previo de la transacción se conserva.'],
    ['T9.3', 'Pago mayor que el saldo, CONSERVAR_RESERVA', 'Rollback parcial: reserva PENDIENTE con cero pagos.'],
    ['T9.4', 'SAVEPOINT y ROLLBACK TO paso a paso', 'Conteos 0/0, 1/0, 1/1, 1/0 y 0/0.'],
    ['T9.5', 'La reserva falla (habitación ocupada)', 'Error -20001; no se registra el pago.'],
    ['T9.6', 'Reactivar una reserva cancelada cuya habitación se volvió a vender', 'Error -20001.'],
    ['T10.1', 'Dos transacciones sin bloqueo', 'Anomalía reproducida: 2 reservas activas.'],
    ['T10.2', 'Dos transacciones con FOR UPDATE', 'B recibe -20010 mientras A está abierta y -20001 después del COMMIT de A; queda 1 reserva.'],
    ['T10.3', 'Bloqueo por habitación', 'Otra habitación del mismo hotel se bloquea sin esperar.'],
    ['Script 11', 'Tres consultas antes y después', 'De TABLE ACCESS FULL a INDEX RANGE SCAN, con menor costo y menor tiempo.'],
    ['Script 11, C4 a C6', 'Índice sobre estado', 'C4 lo ignora; C5 forzado cuesta más; se imprime el veredicto.'],
    ['T14.1 y T14.2', 'Recepción', 'Lee vistas; las tablas le devuelven ORA-00942; reserva en su hotel; -20011 en otro; no ve reservas de otro alojamiento.'],
    ['T14.3', 'Encargado', 'Hereda recepción; cambia su tarifa; ORA-01402 al crear una habitación en otro alojamiento; -20011 con tarifas ajenas.'],
    ['T14.4', 'Gerente', 'Lee todo el negocio; ORA-01031 al modificar (ORA-41900 en Oracle 23ai/26ai); no ve datos personales ni auditoría.'],
    ['T14.5', 'Auditor', 'Lee la auditoría; ORA-01031 / ORA-41900 al intentar modificarla o borrarla.'],
    ['T14.6', 'Auditoría de la tarifa cambiada en T14.3', 'El usuario registrado es ENC_HOTEL.'],
  ], [1500, 3500, 4360]),
  p(''),
  h1('7. Evidencia de ejecución'),
  p('Capturas de la "Salida de Script" de SQL Developer al ejecutar los scripts 09 y 10 con F5 (las de los scripts 11 a 14 están en las secciones 4 y 5). Todas las pruebas terminaron en OK.'),
  ...captura('Script 09 · Paquete, preparación y T9.1 a T9.2', '09a.jpg'),
  ...captura('Script 09 · T9.2 y T9.3 (rollback parcial)', '09b.jpg'),
  ...captura('Script 09 · T9.4 a T9.6', '09c.jpg'),
  ...captura('Script 10 · T10.1 y T10.2', '10a.jpg'),
  ...captura('Script 10 · T10.2 y T10.3', '10b.jpg'),
];

const ejecucion = [
  h1('8. Cómo ejecutar'),
  bullet(['Con la conexión TURISMOUQ, ejecutar con F5 y en orden ', code('09_transacciones.sql'), ', ', code('10_concurrencia.sql'), ' y ', code('11_indices.sql'), '.']),
  bullet(['Para el experimento de dos sesiones, abrir dos ventanas como TURISMOUQ y una como SYSTEM y seguir las instrucciones de ', code('concurrencia/sesion_A.sql'), '.']),
  bullet(['Con la conexión SYSTEM (servicio XEPDB1), ejecutar ', code('12_seguridad_roles_usuarios.sql'), '.']),
  bullet(['Con la conexión TURISMOUQ, ejecutar ', code('13_seguridad_vistas_privilegios.sql'), ' y después ', code('14_pruebas_seguridad.sql'), ', que se conecta por turnos como cada usuario.']),
  bullet(['Si se repite el script 12 hay que repetir el 13: al borrar un rol se pierden los privilegios otorgados. Si se repiten 01 y 02, hay que repetir 04 a 07 y 09 a 13.']),
  bullet(['En ninguna salida debe aparecer una línea que empiece por FALLA. En la ejecución documentada aquí no apareció ninguna.']),
  bullet(['El script 14 cambia de usuario con CONNECT. SQL Developer no muestra la salida después de un CONNECT dentro de un script, por eso ese script se ejecutó con SQL*Plus (captura 16 y 17).']),
];

const doc = new Document({
  creator: 'Equipo TurismoUQ', title: 'TurismoUQ · Entrega 3',
  styles: {
    default: { document: { run: { font: FONT, size: 21 } } },
    paragraphStyles: [
      { id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true, run: { size: 30, bold: true, color: '000000', font: FONT }, paragraph: { outlineLevel: 0 } },
      { id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true, run: { size: 25, bold: true, color: '000000', font: FONT }, paragraph: { outlineLevel: 1 } },
    ],
  },
  numbering: { config: [{ reference: 'vinetas', levels: [{ level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 540, hanging: 270 } } } }] }] },
  sections: [{
    properties: { page: { margin: { top: 1300, bottom: 1300, left: 1440, right: 1440 } } },
    footers: { default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.RIGHT, children: [
      new TextRun({ text: 'TurismoUQ · Entrega 3 · página ', font: FONT, size: 16, color: '777777' }),
      new TextRun({ children: [PageNumber.CURRENT], font: FONT, size: 16, color: '777777' })] })] }) },
    children: [...portada, ...alcance, ...transacciones, ...concurrencia, ...indices, ...seguridad, ...pruebas, ...ejecucion],
  }],
});
const salida = path.join(__dirname, '..', 'docs', 'Entrega3_TurismoUQ.docx');
Packer.toBuffer(doc).then(buf => { fs.writeFileSync(salida, buf); console.log('ok ' + salida); });
