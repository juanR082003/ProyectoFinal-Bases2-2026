const H = require('./doc_helpers.js');
const { fs, Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType, PageBreak, LevelFormat, Footer, PageNumber,
        FONT, AZUL, p, b, i, code, h1, h2, bullet, codeBlock, table } = H;

const centro = (t, opts = {}) => new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: opts.before || 0 },
  children: [new TextRun({ text: t, font: FONT, size: opts.size || 22, bold: !!opts.bold })] });

const portada = [
  centro('UNIVERSIDAD DEL QUINDÍO', { before: 1800, size: 28, bold: true }),
  centro('Facultad de Ingeniería · Ingeniería de Sistemas y Computación'),
  centro('Proyecto integrador TurismoUQ', { before: 1200, size: 44, bold: true }),
  centro('Plataforma de reservas turísticas del Quindío', { size: 26 }),
  centro('Entrega 2 · Capa PL/SQL', { before: 400, size: 28, bold: true }),
  centro('Integrantes', { before: 1400, bold: true }),
  centro('Juan Camilo López'), centro('José Luis Rivadeneira'), centro('Juan Manuel Rincón'),
  centro('Bases de Datos II · código 12338 · grupo [01D / 01N]', { before: 600 }),
  centro('Docente: Carolina Londoño Idárraga'),
  centro('Armenia, periodo 2026-2'),
  new Paragraph({ children: [new PageBreak()] }),
];

const alcance = [
  h1('1. Alcance de la entrega'),
  p('La Entrega 2 lleva al motor la lógica del negocio de TurismoUQ: el cálculo del valor de una estadía que cruza temporadas, la creación validada de reservas, la liquidación mensual por alojamiento, la auditoría de tarifas, el bloqueo de reservas solapadas, un tablespace propio para el histórico y una vista materializada de ocupación mensual. Se ejecuta sobre el esquema y los datos de la Entrega 1.'),
  table(['Script', 'Conectado como', 'Contenido'], [
    ['04_tablespace_historico.sql', 'SYSTEM @ XEPDB1', 'Tablespace TS_TURISMOUQ_HIST con su datafile, cuota para TURISMOUQ y privilegio CREATE JOB.'],
    ['05_paquete_turismouq.sql', 'TURISMOUQ', 'Tabla LIQUIDACION_MENSUAL y paquete PKG_TURISMOUQ: función, procedimientos, cursores con parámetros y excepciones propias.'],
    ['06_disparadores.sql', 'TURISMOUQ', 'Auditoría de TARIFA (disparador de sentencia) y anti-solape de reservas (disparador de fila).'],
    ['07_historico_vista_materializada.sql', 'TURISMOUQ', 'RESERVA_HISTORICO en el tablespace propio, archivado, vista materializada MV_OCUPACION_MENSUAL y jobs programados.'],
    ['08_pruebas_entrega2.sql', 'TURISMOUQ', 'Evidencia: 32 pruebas, que imprimen OK o FALLA, sobre cada componente.'],
  ], [3000, 1800, 4560]),
  p(''),
  p('Correspondencia con lo que pide el enunciado: el entregable 1 (función, procedimiento, cursor y paquete) es el script 05; el 2 (los dos disparadores) es el 06; el 3 (tablespace y vista materializada) son el 04 y el 07; el 4 (evidencia de prueba) es el 08 junto con este documento.'),
];

const paquete = [
  h1('2. Paquete PKG_TURISMOUQ'),
  p('Todo lo que pide la entrega queda agrupado en un solo paquete. La especificación publica la interfaz, los parámetros del negocio (máximo de noches, días y porcentaje de reembolso, comisiones) y las excepciones; el cuerpo guarda la implementación y lo que es privado, como el cursor de tramos de temporada y las validaciones comunes.'),
  table(['Elemento', 'Tipo', 'Qué hace'], [
    ['fn_valor_estadia', 'Función', 'Valor de una estadía aplicando la tarifa de cada temporada que atraviesa.'],
    ['sp_desglose_estadia', 'Procedimiento', 'Imprime el mismo cálculo tramo por tramo (útil para sustentar).'],
    ['fn_habitacion_disponible', 'Función', 'S/N según si la habitación está libre en un rango de noches.'],
    ['sp_crear_reserva', 'Procedimiento', 'Crea encabezado y primera línea con todas las validaciones y excepciones propias.'],
    ['sp_agregar_habitacion', 'Procedimiento', 'Agrega otra habitación del mismo alojamiento (reservas de grupo) y amplía el rango general.'],
    ['fn_total_reserva / fn_total_pagado / fn_esta_pagada', 'Funciones', 'Estadía + servicios, pagos exitosos y regla de reserva pagada.'],
    ['sp_cancelar_reserva', 'Procedimiento', 'Cancela y aplica la regla de reembolso del 80 % con más de 5 días.'],
    ['sp_liquidacion_mensual', 'Procedimiento', 'Proceso masivo con cuatro cursores explícitos con parámetros.'],
    ['c_tramos', 'Cursor privado con parámetros', 'Temporadas que se cruzan con la estadía y la tarifa de la habitación en cada una.'],
  ], [3100, 1900, 4360]),
  p(''),
  h2('2.1 Excepciones propias'),
  p('Cada condición de error tiene un código fijo que se lanza con RAISE_APPLICATION_ERROR y, además, una excepción con nombre en la especificación (PRAGMA EXCEPTION_INIT), de modo que quien llama puede escribir WHEN pkg_turismouq.ex_no_disponible en lugar de comparar números.'),
  table(['Código', 'Excepción', 'Cuándo se lanza'], [
    ['-20001', 'ex_no_disponible', 'La habitación ya está ocupada por otra reserva no cancelada en esas noches.'],
    ['-20002', 'ex_fechas', 'Check-out anterior o igual al check-in, más de 30 noches o cancelación fuera de rango.'],
    ['-20003', 'ex_capacidad', 'Huéspedes por encima de la capacidad máxima de la habitación (o menos de 1).'],
    ['-20004', 'ex_no_existe', 'Cliente, habitación o reserva inexistente, o habitación inactiva.'],
    ['-20005', 'ex_sin_tarifa', 'Noches sin temporada definida o temporada sin tarifa para la habitación.'],
    ['-20006', 'ex_estado', 'El estado de la reserva no permite la operación (por ejemplo, cancelar dos veces).'],
    ['-20007', 'ex_fecha_pasada', 'Check-in en el pasado.'],
    ['-20008', 'ex_parametro', 'Parámetro obligatorio nulo o inválido.'],
  ], [1100, 2000, 6260]),
  p(''),
  h2('2.2 fn_valor_estadia: la estadía que cruza temporadas'),
  p('La función recorre, con el cursor c_tramos, las temporadas que se cruzan con la estadía (las que empiezan antes del check-out y terminan en o después del check-in). Para cada tramo cuenta cuántas noches de la estadía caen dentro y las multiplica por la tarifa de la habitación en esa temporada:'),
  p([i('noches del tramo = LEAST(check-out, fin del tramo + 1) − GREATEST(check-in, inicio del tramo)')], { align: AlignmentType.CENTER }),
  p('Ejemplo con los datos cargados: la temporada media "inicio de diciembre 2026" va hasta el 14-dic y la alta "fin de año 2026-2027" empieza el 15-dic. Para una estadía del 12 al 17 de diciembre, el tramo medio aporta LEAST(17, 15) − GREATEST(12, 1) = 3 noches (12, 13 y 14) y el tramo alto aporta LEAST(17, 11-ene) − GREATEST(12, 15) = 2 noches (15 y 16). La noche del check-out no se cobra.'),
  p('Dos controles evitan cobrar mal: si una temporada no tiene tarifa para la habitación se lanza -20005, y si la suma de noches de los tramos no da el total de noches de la estadía (hay días sin temporada) también se rechaza, en lugar de devolver un valor incompleto. La prueba T1 compara el resultado con un cálculo independiente noche por noche sobre CALENDARIO, y además muestra cuánto se habría cobrado mal usando una sola tarifa, la del día de llegada.'),
  h2('2.3 sp_crear_reserva'),
  p('Valida en este orden: estado inicial permitido (PENDIENTE o CONFIRMADA), existencia del cliente, fechas (check-out posterior al check-in, máximo 30 noches, check-in no pasado), existencia y estado activo de la habitación, capacidad y, por último, disponibilidad. Solo si todo pasa calcula el valor con fn_valor_estadia, inserta el encabezado y la línea, y devuelve el id de la reserva por un parámetro OUT. Para reservas de grupo, sp_agregar_habitacion bloquea el encabezado (SELECT … FOR UPDATE), valida la nueva línea con las mismas reglas, exige que la habitación sea del mismo alojamiento y amplía el rango general de la reserva.'),
  p('Los procedimientos de reserva no hacen COMMIT: confirmar o deshacer lo decide quien los llama. Esto permite que en la Entrega 3 reserva y pago queden en una sola transacción con SAVEPOINT.'),
  h2('2.4 Cursor explícito con parámetros: liquidación mensual'),
  p('sp_liquidacion_mensual(p_anio, p_mes, p_id_alojamiento) recorre los alojamientos con OPEN, FETCH y CLOSE explícitos y, para cada uno, abre tres cursores más con parámetros (alojamiento, primer y último día del mes):'),
  bullet([b('c_alojamientos(cp_id): '), 'todos los alojamientos o solo el indicado.']),
  bullet([b('c_hospedaje(cp_aloj, cp_ini, cp_fin): '), 'noches del mes de reservas confirmadas o completadas, valoradas con la tarifa de su temporada; las estadías que cruzan de un mes a otro se reparten.']),
  bullet([b('c_servicios(cp_aloj, cp_ini, cp_fin): '), 'servicios prestados en el mes.']),
  bullet([b('c_cancelaciones(cp_aloj, cp_ini, cp_fin): '), 'dinero retenido por cancelaciones del mes (100 % con 5 días o menos, 20 % con más de 5).']),
  p('Con eso calcula el total bruto, la comisión de TurismoUQ (12 % del hospedaje y de lo retenido, 8 % de los servicios; es un supuesto del equipo, definido como constante del paquete) y el neto a girar al alojamiento. El resultado se guarda en LIQUIDACION_MENSUAL, se imprime un resumen y se confirma al final. El proceso es repetible: si el mes ya estaba liquidado, se reemplaza. Un job de DBMS_SCHEDULER lo ejecuta el día 1 de cada mes para el mes anterior.'),
  h2('2.5 Cancelación y reserva pagada'),
  p('sp_cancelar_reserva implementa la regla R1 de la Entrega 1. Si los días entre la fecha de cancelación y el check-in son más de 5, los pagos exitosos pasan a REEMBOLSADO con el 80 % devuelto; con 5 días o menos no hay reembolso y los pagos quedan exitosos. Los pagos pendientes se anulan. Recibe la fecha de cancelación como parámetro opcional (por defecto SYSDATE) para poder probar ambos casos. fn_esta_pagada implementa la regla R9: una reserva está pagada cuando sus pagos exitosos cubren estadía más servicios.'),
];

const disparadores = [
  h1('3. Disparadores'),
  h2('3.1 Auditoría de TARIFA (nivel de sentencia)'),
  p('El objetivo es registrar quién cambió una tarifa, cuándo, el valor anterior y el nuevo. La dificultad es que un disparador de sentencia se ejecuta una sola vez por instrucción y no tiene acceso a :OLD ni a :NEW. Se usa la solución clásica de tres piezas, coordinadas por el paquete PKG_AUDITORIA_TARIFA:'),
  table(['Disparador', 'Nivel y momento', 'Función'], [
    ['TRG_TARIFA_AUD_INICIO', 'Sentencia, BEFORE', 'Deja vacío el buffer en memoria.'],
    ['TRG_TARIFA_AUD_FILA', 'Fila, AFTER', 'Solo anota en memoria id, valor anterior y valor nuevo de cada fila (no hace DML). Un UPDATE que deja el mismo valor no se anota.'],
    ['TRG_TARIFA_AUDITORIA', 'Sentencia, AFTER', 'Es el que audita: inserta un encabezado por instrucción (operación, filas afectadas, usuario de la base, usuario del sistema operativo, equipo, programa, fecha y hora) y vuelca todo el detalle con FORALL.'],
  ], [2700, 1900, 4760]),
  p(''),
  p('Las dos tablas de auditoría son AUDITORIA_TARIFA_OPERACION (una fila por instrucción) y AUDITORIA_TARIFA_DETALLE (una por tarifa, con la diferencia como columna virtual). El detalle no tiene FK hacia TARIFA a propósito: la auditoría debe sobrevivir aunque la tarifa se borre. Al auditar por sentencia, todas las filas de una instrucción comparten una marca de tiempo y un id de operación, y queda registro incluso de un UPDATE que no afectó filas.'),
  h2('3.2 Anti-solape de reservas (nivel de fila)'),
  p('TRG_RH_NO_SOLAPE impide registrar o modificar una línea de RESERVA_HABITACION cuyas noches se crucen con otra línea no cancelada de la misma habitación. Dos rangos [a1, a2) y [b1, b2) se solapan si a1 < b2 y b1 < a2; así una reserva que entra el mismo día en que otra sale no choca.'),
  p('Un disparador FOR EACH ROW que consulta la misma tabla que se está modificando provoca ORA-04091 (tabla mutante) en un UPDATE o en un INSERT … SELECT. Por eso se implementa como COMPOUND TRIGGER, la forma que Oracle recomienda desde la versión 11g. En BEFORE EACH ROW valida las fechas de la fila, en AFTER EACH ROW anota su id y en AFTER STATEMENT revisa cada fila anotada contra las demás. Si encuentra un solape lanza -20001, y Oracle deshace la instrucción completa. La prueba T3 lo demuestra con un INSERT directo que choca, con el caso borde (entrar el día de salida de otra reserva) y con un UPDATE.'),
  p('Se bloquea contra reservas PENDIENTES, CONFIRMADAS y COMPLETADAS, no solo contra las confirmadas, porque las tres tienen la habitación asignada; una CANCELADA la libera (prueba T6.4). Hay dos límites conocidos que se atacan en la Entrega 3. Primero, dos sesiones concurrentes no ven las filas aún sin confirmar de la otra; eso se resuelve con SELECT … FOR UPDATE. Segundo, reactivar una reserva cancelada no vuelve a validar el solape.'),
];

const tablespace = [
  h1('4. Tablespace para el histórico de reservas'),
  p('El script 04, ejecutado como SYSTEM, crea TS_TURISMOUQ_HIST con un datafile propio ubicado en la misma carpeta que el datafile de USERS (se calcula en tiempo de ejecución, así funciona en Windows y en Linux). Tamaño inicial 50 MB, AUTOEXTEND de 10 MB hasta 1 GB, gestión local de extensiones y de espacio de segmentos. En él vive RESERVA_HISTORICO con sus índices: una fila desnormalizada por línea de reserva cerrada (COMPLETADA o CANCELADA) de un año terminado, con cliente, alojamiento, municipio, habitación, valores, pagos y calificación congelados al momento de archivar. sp_archivar_reservas(p_anio) archiva un año completo y no duplica si se vuelve a ejecutar; el script 07 archiva 2024.'),
  p([b('¿Por qué separarlo? ')]),
  bullet([b('Ciclo de vida distinto. '), 'Las reservas cerradas de años anteriores ya no cambian. En su propio tablespace se puede poner READ ONLY al cerrar cada año y respaldar una sola vez, en lugar de copiarlo en cada backup diario.']),
  bullet([b('Crecimiento controlado. '), 'El histórico crece cada año sin límite. Con su propio datafile y MAXSIZE, ese crecimiento no consume ni puede llenar el espacio de las tablas operativas.']),
  bullet([b('Rendimiento de E/S. '), 'Las consultas analíticas sobre años viejos leen otro archivo, que en un servidor real puede ir en un disco más barato sin afectar las reservas en línea.']),
  bullet([b('Administración. '), 'El histórico se puede mover, desconectar o restaurar sin tocar la operación diaria.']),
  p('En producción, después de archivar y verificar un año, se purgarían esas reservas de las tablas operativas. En el proyecto se conservan para que las consultas de la Entrega 1 sigan mostrando 2024-2026 completos.'),
];

const vista = [
  h1('5. Vista materializada de ocupación mensual'),
  p('MV_OCUPACION_MENSUAL precalcula, por alojamiento y mes, el número de habitaciones, las noches disponibles, las noches ocupadas, el porcentaje de ocupación, las reservas y el ingreso de hospedaje (noches valoradas con la tarifa de su temporada). La consulta base cruza unas 650 habitaciones con unos 1.100 días del calendario; la vista reduce eso a unas 2.200 filas listas para leer, con un índice por año y mes.'),
  table(['Opción', 'Valor elegido', 'Justificación'], [
    ['Construcción', 'BUILD IMMEDIATE', 'La vista queda poblada al crearla; los reportes sirven desde el primer momento.'],
    ['Método', 'REFRESH COMPLETE', 'El refresco rápido (FAST) exige logs y una consulta simple. Esta usa un join por rango de fechas, subconsultas agregadas, COUNT(DISTINCT) y un CROSS JOIN, que Oracle no admite para FAST. Un refresco completo tarda segundos.'],
    ['Momento', 'ON DEMAND', 'ON COMMIT obligaría a recalcular la vista dentro de cada transacción de reserva, pago o cambio de tarifa, y volvería lenta la operación en línea, que es lo prioritario.'],
    ['Programación', 'Diaria, 2:00 a. m. (DBMS_SCHEDULER)', 'Es un indicador de gestión mensual: a la gerencia le basta el dato del cierre de ayer, y a esa hora el refresco no compite con las reservas. Si se necesita al instante, se refresca a mano con DBMS_MVIEW.REFRESH.'],
  ], [1700, 2400, 5260]),
  p(''),
  p('La prueba T8 muestra el comportamiento de la política. Las reservas de prueba de enero de 2027 todavía no aparecen en la vista, que está desactualizada (staleness). Después de un refresco manual coinciden con las tablas base. La prueba T4.2 usa la vista para verificar la liquidación.'),
];

const pruebas = [
  h1('6. Pruebas y resultados esperados'),
  p('El script 08 deja los datos de prueba en la segunda quincena de enero de 2027, donde el calendario tiene temporadas y la carga no generó reservas, así que los resultados no dependen del azar. Borra al inicio cualquier prueba anterior (observaciones "PRUEBA E2"), por lo que se puede ejecutar varias veces. Cada prueba imprime OK o FALLA.'),
  table(['Prueba', 'Qué se prueba', 'Resultado esperado'], [
    ['T1.1', 'Estadía 12-17 dic 2026 (MEDIA → ALTA)', 'Desglose 3 noches media + 2 alta; igual al cálculo independiente por CALENDARIO.'],
    ['T1.2 / T1.3', 'Una temporada / tres tramos (baja, puente alto, baja)', 'OK: función = cálculo independiente.'],
    ['T1.4', 'Función usada dentro de un SELECT', 'Devuelve el mismo valor que T1.1.'],
    ['T1.5 / T1.6', 'Check-out = check-in / noches fuera del calendario', 'Errores -20002 y -20005.'],
    ['T2.1', 'Reserva válida 18-21 ene 2027', 'Reserva creada con su valor.'],
    ['T2.2 a T2.5', 'Solape, fechas invertidas, capacidad, check-in pasado', 'Errores -20001, -20002, -20003 y -20007.'],
    ['T2.6', 'Segunda habitación del grupo que llega un día después', 'Dos líneas; el rango general pasa a 18-22 ene.'],
    ['T3.1', 'INSERT directo que choca (sin pasar por el paquete)', 'Bloqueado por el disparador con -20001.'],
    ['T3.2', 'Entrar el día en que sale otra reserva', 'Se permite.'],
    ['T3.3', 'UPDATE que crea un solape', 'Bloqueado con -20001, sin ORA-04091.'],
    ['T4.1 a T4.4', 'Liquidación de diciembre de 2025', '60 alojamientos; hospedaje igual al de la vista materializada; reliquidar no duplica.'],
    ['T5.1 a T5.3', 'Subir tarifas, UPDATE sin cambios, restaurar desde la auditoría', 'Encabezados con usuario, equipo y hora; detalle con valor anterior y nuevo; operación con 0 filas registrada.'],
    ['T6.1', 'Cancelación con más de 5 días', 'Pago REEMBOLSADO con el 80 %.'],
    ['T6.2', 'Cancelación 2 días antes', 'Pago EXITOSO, sin reembolso.'],
    ['T6.3 / T6.4', 'Cancelar dos veces / reservar una habitación liberada', 'Error -20006; nueva reserva creada y marcada como pagada.'],
    ['T7.1 a T7.3', 'Tablespace e histórico', 'Tabla en TS_TURISMOUQ_HIST; re-archivar da 0; conteo igual a las líneas cerradas de 2024; error -20008 para el año en curso.'],
    ['T8.1 a T8.3', 'Vista materializada', 'Antes del refresco no cuenta las reservas nuevas; después coincide con las tablas base.'],
  ], [1300, 3700, 4360]),
  p(''),
  h1('7. Evidencia de ejecución'),
  p('Pegar a continuación las capturas de la "Salida de script" de SQL Developer al ejecutar 08_pruebas_entrega2.sql, una por bloque de pruebas.'),
  ...['T1 · fn_valor_estadia', 'T2 · sp_crear_reserva', 'T3 · disparador anti-solape', 'T4 · liquidación mensual', 'T5 · auditoría de TARIFA', 'T6 · cancelación', 'T7 · tablespace e histórico', 'T8 · vista materializada']
    .flatMap(t => [p([b(t)]), p([i('[captura]')]), p('')]),
];

const ejecucion = [
  h1('8. Cómo ejecutar'),
  bullet(['Con la conexión SYSTEM (servicio XEPDB1), ejecutar ', code('04_tablespace_historico.sql'), ' con F5.']),
  bullet(['Con la conexión TURISMOUQ, ejecutar en orden ', code('05_paquete_turismouq.sql'), ', ', code('06_disparadores.sql'), ' y ', code('07_historico_vista_materializada.sql'), '. Cada uno termina mostrando sus objetos como VALID o ENABLED.']),
  bullet(['Ejecutar ', code('08_pruebas_entrega2.sql'), ' con F5 y revisar que no aparezca ninguna línea FALLA.']),
  bullet(['Si se vuelven a correr 01 y 02 (base desde cero), después hay que repetir 04 a 07: borrar las tablas también borra sus disparadores y deja inválida la vista materializada.']),
];

const doc = new Document({
  creator: 'Equipo TurismoUQ', title: 'TurismoUQ · Entrega 2',
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
      new TextRun({ text: 'TurismoUQ · Entrega 2 · página ', font: FONT, size: 16, color: '777777' }),
      new TextRun({ children: [PageNumber.CURRENT], font: FONT, size: 16, color: '777777' })] })] }) },
    children: [...portada, ...alcance, ...paquete, ...disparadores, ...tablespace, ...vista, ...pruebas, ...ejecucion],
  }],
});
Packer.toBuffer(doc).then(buf => { fs.writeFileSync('/home/claude/turismouq/docs/Entrega2_TurismoUQ.docx', buf); console.log('ok'); });
