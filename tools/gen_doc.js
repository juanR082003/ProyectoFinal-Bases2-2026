const fs = require('fs');
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType, Table, TableRow, TableCell,
  WidthType, ShadingType, BorderStyle, ImageRun, PageBreak, LevelFormat, Footer, PageNumber,
  TableOfContents,
} = require('docx');

const FONT = 'Arial';
const AZUL = '000000';
const W = 9360; // ancho útil (A4 con márgenes de 1")

const p = (text, opts = {}) => new Paragraph({
  spacing: { after: 120, line: 276 }, alignment: opts.align || AlignmentType.JUSTIFIED,
  children: (Array.isArray(text) ? text : [text]).map(t => typeof t === 'string' ? new TextRun({ text: t, font: FONT, size: 21 }) : t),
  ...opts.para,
});
const b = (t) => new TextRun({ text: t, bold: true, font: FONT, size: 21 });
const i = (t) => new TextRun({ text: t, italics: true, font: FONT, size: 21 });
const code = (t) => new TextRun({ text: t, font: 'Consolas', size: 19 });
const h1 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_1, spacing: { before: 360, after: 160 }, children: [new TextRun({ text: t, font: FONT })] });
const h2 = (t) => new Paragraph({ heading: HeadingLevel.HEADING_2, spacing: { before: 240, after: 120 }, children: [new TextRun({ text: t, font: FONT })] });
const bullet = (parts) => new Paragraph({ numbering: { reference: 'vinetas', level: 0 }, spacing: { after: 80 },
  children: (Array.isArray(parts) ? parts : [parts]).map(t => typeof t === 'string' ? new TextRun({ text: t, font: FONT, size: 21 }) : t) });
const codeBlock = (lines) => lines.map((l, k) => new Paragraph({
  shading: { type: ShadingType.CLEAR, fill: 'F2F2F2', color: 'auto' }, spacing: { after: k === lines.length - 1 ? 160 : 0 },
  indent: { left: 200 }, children: [code(l || ' ')] }));

const border = { style: BorderStyle.SINGLE, size: 4, color: 'BFBFBF' };
const borders = { top: border, bottom: border, left: border, right: border };
function table(headers, rows, widths) {
  return new Table({ width: { size: W, type: WidthType.DXA }, columnWidths: widths,
    rows: [new TableRow({ tableHeader: true, children: headers.map((h, k) => cell(h, true, widths[k])) }),
           ...rows.map(r => new TableRow({ children: r.map((c, k) => cell(c, false, widths[k])) }))] });
}
function cell(txt, head, w) {
  return new TableCell({
    borders, width: { size: w, type: WidthType.DXA },
    shading: head ? { type: ShadingType.CLEAR, fill: AZUL, color: 'auto' } : undefined,
    margins: { top: 60, bottom: 60, left: 90, right: 90 },
    children: String(txt).split('\n').map(line => new Paragraph({ children: [new TextRun({ text: line, font: FONT, size: 18, bold: head, color: head ? 'FFFFFF' : '000000' })] })),
  });
}
const caption = (t) => new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 80, after: 200 },
  children: [new TextRun({ text: t, italics: true, font: FONT, size: 18, color: '555555' })] });

// ------------------------------------------------------------------ contenido
const portada = [
  new Paragraph({ spacing: { before: 1800 }, alignment: AlignmentType.CENTER, children: [new TextRun({ text: 'UNIVERSIDAD DEL QUINDÍO', bold: true, font: FONT, size: 28 })] }),
  new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: 'Facultad de Ingeniería · Ingeniería de Sistemas y Computación', font: FONT, size: 22 })] }),
  new Paragraph({ spacing: { before: 1200 }, alignment: AlignmentType.CENTER, children: [new TextRun({ text: 'Proyecto integrador TurismoUQ', bold: true, font: FONT, size: 44, color: AZUL })] }),
  new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: 'Plataforma de reservas turísticas del Quindío', font: FONT, size: 26 })] }),
  new Paragraph({ spacing: { before: 400 }, alignment: AlignmentType.CENTER, children: [new TextRun({ text: 'Entrega 1 · Modelo de datos y consultas de análisis', bold: true, font: FONT, size: 28 })] }),
  new Paragraph({ spacing: { before: 1400 }, alignment: AlignmentType.CENTER, children: [new TextRun({ text: 'Integrantes', bold: true, font: FONT, size: 22 })] }),
  ...['Juan Camilo López', 'José Luis Rivadeneira', 'Juan Manuel Rincón'].map(t =>
    new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: t, font: FONT, size: 22 })] })),
  new Paragraph({ spacing: { before: 600 }, alignment: AlignmentType.CENTER, children: [new TextRun({ text: 'Bases de Datos II · código 12338 · grupo [01D / 01N]', font: FONT, size: 22 })] }),
  new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: 'Docente: Carolina Londoño Idárraga', font: FONT, size: 22 })] }),
  new Paragraph({ alignment: AlignmentType.CENTER, children: [new TextRun({ text: 'Armenia, periodo 2026-2', font: FONT, size: 22 })] }),
  new Paragraph({ children: [new PageBreak()] }),
];

const indice = [
  new Paragraph({ spacing: { after: 200 }, children: [new TextRun({ text: 'Contenido', bold: true, font: FONT, size: 28, color: AZUL })] }),
  new TableOfContents('Contenido', { hyperlink: true, headingStyleRange: '1-2' }),
  new Paragraph({ children: [new PageBreak()] }),
];

const intro = [
  h1('1. Alcance de la entrega'),
  p('Este documento acompaña los scripts de la Entrega 1 del proyecto integrador. TurismoUQ es la base de datos de una plataforma que reúne la oferta de alojamiento de los 12 municipios del Quindío y gestiona reservas, pagos, servicios complementarios y reseñas. Todo el trabajo vive dentro de Oracle Database XE 21c: no se construye interfaz.'),
  p('La entrega está compuesta por cuatro scripts numerados en orden de ejecución y por este documento, que contiene el modelo entidad-relación (MER), las reglas de negocio deducidas del enunciado y la explicación de las dos decisiones de diseño que el equipo debe sustentar.'),
  table(['Script', 'Se ejecuta como', 'Contenido'], [
    ['00_crear_usuario.sql', 'SYSTEM en XEPDB1', 'Crea el esquema TURISMOUQ con sus privilegios de sistema.'],
    ['01_ddl_turismouq.sql', 'TURISMOUQ', 'Borra y crea las 16 tablas con PK, FK, CHECK, NOT NULL, UNIQUE y comentarios.'],
    ['02_carga_datos.sql', 'TURISMOUQ', 'Carga catálogos y genera el volumen con PL/SQL y DBMS_RANDOM (semilla fija). Termina con un bloque de verificación de mínimos.'],
    ['03_consultas_analisis.sql', 'TURISMOUQ', 'Las 7 consultas de análisis, numeradas y comentadas.'],
  ], [2500, 1900, 4960]),
  p(''),
];

const mer = [
  h1('2. Modelo entidad-relación'),
  p('El modelo conserva las 14 entidades mínimas del enunciado y agrega dos: CALENDARIO, que resuelve la valoración noche por noche de una estadía, y ROL, que formaliza los perfiles de los usuarios internos. La figura 1 usa notación pata de gallo: el símbolo junto a cada entidad indica cuántas instancias de ella se relacionan con una instancia de la otra (raya = uno, pata de gallo = muchos) y el círculo indica participación opcional (mínimo cero).'),
  new Paragraph({ alignment: AlignmentType.CENTER, children: [new ImageRun({ type: 'png', data: fs.readFileSync('/home/claude/turismouq/docs/mer_turismouq.png'), transformation: { width: 600, height: 685 } })] }),
  caption('Figura 1. MER de TurismoUQ. La versión en alta resolución se entrega en docs/mer_turismouq.svg y .png.'),
  h2('2.1 Cardinalidad y participación de cada relación'),
  p('La tabla se lee así: «Un MUNICIPIO ubica 0..N ALOJAMIENTOS; cada ALOJAMIENTO está en exactamente 1 MUNICIPIO». La participación es total cuando el mínimo es 1 y parcial cuando el mínimo es 0.'),
  table(['Relación', 'Lado padre', 'Lado hijo', 'Participación', 'Implementación'], [
    ['MUNICIPIO ubica ALOJAMIENTO', '1..1', '0..N', 'Total del alojamiento; parcial del municipio', 'FK id_municipio NOT NULL'],
    ['TIPO_ALOJAMIENTO clasifica ALOJAMIENTO', '1..1', '0..N', 'Total del alojamiento', 'FK id_tipo NOT NULL'],
    ['ALOJAMIENTO ofrece HABITACION', '1..1', '1..N', 'Total en ambos lados (un alojamiento sin habitaciones no opera)', 'FK + UNIQUE(id_alojamiento, numero)'],
    ['ALOJAMIENTO ofrece SERVICIO', '1..1', '0..N', 'Total del servicio; parcial del alojamiento', 'FK + UNIQUE(id_alojamiento, nombre)'],
    ['HABITACION tiene precio en TARIFA', '1..1', '1..N', 'Total: toda habitación tiene tarifa en cada temporada', 'FK + UNIQUE(id_habitacion, id_temporada)'],
    ['TEMPORADA aplica a TARIFA', '1..1', '1..N', 'Total', 'FK id_temporada'],
    ['TEMPORADA agrupa días de CALENDARIO', '1..1', '1..N', 'Total: cada día tiene exactamente una temporada', 'PK fecha + FK id_temporada NOT NULL'],
    ['CLIENTE realiza RESERVA', '1..1', '0..N', 'Total de la reserva', 'FK id_cliente NOT NULL'],
    ['ALOJAMIENTO recibe RESERVA', '1..1', '0..N', 'Total de la reserva', 'FK id_alojamiento NOT NULL'],
    ['RESERVA incluye RESERVA_HABITACION', '1..1', '1..N', 'Total en ambos lados (toda reserva tiene al menos una habitación)', 'FK compuesta (id_reserva, id_alojamiento)'],
    ['HABITACION se reserva en RESERVA_HABITACION', '1..1', '0..N', 'Total de la línea', 'FK compuesta (id_habitacion, id_alojamiento)'],
    ['RESERVA contrata RESERVA_SERVICIO', '1..1', '0..N', 'Total de la línea', 'FK compuesta (id_reserva, id_alojamiento)'],
    ['SERVICIO se contrata en RESERVA_SERVICIO', '1..1', '0..N', 'Total de la línea', 'FK compuesta (id_servicio, id_alojamiento)'],
    ['RESERVA se paga con PAGO', '1..1', '0..N', 'Total del pago; parcial de la reserva (puede estar pendiente)', 'FK id_reserva NOT NULL'],
    ['RESERVA recibe RESENA', '1..1', '0..1', 'Total de la reseña; parcial de la reserva', 'FK compuesta (id_reserva, estado_reserva) + UNIQUE(id_reserva)'],
    ['ROL asigna USUARIO_SISTEMA', '1..1', '0..N', 'Total del usuario', 'FK compuesta (id_rol, ambito_rol)'],
    ['ALOJAMIENTO emplea USUARIO_SISTEMA', '0..1', '0..N', 'Parcial: solo encargados y recepción', 'FK opcional + CHECK de ámbito'],
    ['CALENDARIO – RESERVA_HABITACION (lógica)', 'noches', 'rango', 'Relación por rango de fechas, no por FK', 'checkin ≤ fecha < checkout'],
  ], [2500, 800, 800, 2660, 2600]),
  p(''),
  h2('2.2 Entidades agregadas'),
  bullet([b('CALENDARIO. '), 'Una fila por día del 01-01-2024 al 31-01-2027 (1.127 días), con la temporada vigente, si es festivo y las columnas virtuales año, mes y día de la semana. Su PK es la fecha, de modo que el motor impide que una noche pertenezca a dos temporadas, y la carga verifica que no queden huecos. Es la pieza central de la decisión de diseño 2 y la base de las consultas de ocupación mes a mes.']),
  bullet([b('ROL. '), 'Catálogo de los roles de la aplicación (administrador de plataforma, gerente, auditor, administrador de alojamiento y recepción) con su ámbito: PLATAFORMA o ALOJAMIENTO. El ámbito viaja en la FK compuesta de USUARIO_SISTEMA y un CHECK exige alojamiento solo a los roles de ámbito ALOJAMIENTO. Se alinea con los cuatro roles de base de datos de la Entrega 3.']),
  h2('2.3 Un patrón que se repite: FK compuesta hacia una clave candidata'),
  p('Varias reglas del negocio cruzan dos tablas, y normalmente exigirían un disparador. El modelo las resuelve de forma declarativa: el padre declara una clave única adicional (id, atributo) y el hijo la referencia con una FK de dos columnas. Por ejemplo, HABITACION declara UNIQUE(id_habitacion, id_alojamiento) y RESERVA declara UNIQUE(id_reserva, id_alojamiento); como RESERVA_HABITACION referencia ambas con el mismo id_alojamiento, es imposible registrar en una reserva del hotel X una habitación del hotel Y. El mismo patrón se usa en RESERVA_SERVICIO, RESENA y USUARIO_SISTEMA (tabla 2.1). Lo que el motor garantiza por sí solo no depende de que todos los programas recuerden validarlo.'),
];

const reglas = [
  h1('3. Reglas de negocio deducidas'),
  p('Las siguientes reglas no aparecen escritas de forma literal en el enunciado; se deducen de cómo opera el negocio. La columna final indica dónde queda garantizada cada una: con restricciones declarativas desde esta entrega o con la capa PL/SQL de la Entrega 2.'),
  table(['#', 'Regla', 'De dónde se deduce', 'Cómo se garantiza'], [
    ['R1', 'Si la reserva se cancela con MÁS de 5 días de anticipación al check-in se reembolsa el 80 % de lo pagado; con 5 días o menos no hay reembolso. Exactamente 5 días cae en "sin reembolso".', '1.4 Regla de cancelación', 'PAGO pasa a REEMBOLSADO con monto_reembolsado; CHECK: 0 ≤ reembolsado ≤ monto y solo un pago REEMBOLSADO tiene monto y fecha de reembolso. La carga aplica el 80 %; en la Entrega 2 lo hará el procedimiento de cancelación.'],
    ['R2', 'Solo se reseña una estadía COMPLETADA, una reseña por reserva, y una reserva reseñada ya no puede cambiar de estado.', '1.6 Reseñas', 'FK compuesta (id_reserva, estado_reserva) → RESERVA(id_reserva, estado) con CHECK estado_reserva = \'COMPLETADA\'; UNIQUE(id_reserva).'],
    ['R3', 'Todas las habitaciones de una reserva son del mismo alojamiento de la reserva.', '1.3 "3 habitaciones del mismo alojamiento"', 'FK compuestas de RESERVA_HABITACION hacia RESERVA y HABITACION con el mismo id_alojamiento.'],
    ['R4', 'Un servicio solo se contrata en reservas del alojamiento que lo ofrece.', '1.5 "el desayuno del Hotel X no es el del Hotel Y"', 'FK compuestas de RESERVA_SERVICIO hacia RESERVA y SERVICIO.'],
    ['R5', 'Una habitación no puede estar en dos reservas no canceladas cuyas noches se crucen.', '1.3 Regla de disponibilidad', 'La carga lo garantiza (mapa de noches ocupadas) y lo verifica al final; en la Entrega 2, disparador de fila.'],
    ['R6', 'Cada noche pertenece a una y solo una temporada, sin huecos; y cada habitación tiene exactamente una tarifa por temporada.', '1.2 Temporadas por año y tarifa por temporada', 'PK de CALENDARIO (fecha); UNIQUE(id_habitacion, id_temporada) en TARIFA; la carga verifica el cruce completo.'],
    ['R7', 'Las fechas de cada línea están dentro del rango general de la reserva; el check-in de la reserva es el mínimo de sus líneas y el check-out el máximo.', '1.3 "cada línea puede tener fechas ligeramente distintas dentro del rango general"', 'CHECK checkout > checkin en ambas tablas; la carga lo respeta; disparador en la Entrega 2.'],
    ['R8', 'Los huéspedes de una línea no superan la capacidad máxima de la habitación; una habitación sencilla aloja a lo sumo 2 personas.', '1.1 Capacidad máxima', 'CHECK de la sencilla en HABITACION; la capacidad por línea la valida sp_crear_reserva (Entrega 2).'],
    ['R9', 'Una reserva está pagada cuando la suma de sus pagos EXITOSOS cubre estadía + servicios. Los pagos FALLIDOS y PENDIENTES no cuentan.', '1.4 Pagos', 'Derivado (se consulta, no se almacena); los totales se calculan en consultas y en la Entrega 2.'],
    ['R10', 'La fecha de cancelación existe si y solo si la reserva está CANCELADA, y está entre la fecha de reserva y el check-in. Nadie reserva con check-in en el pasado.', '1.3 y 1.4', 'CHECK ck_reserva_cancelacion y ck_reserva_anticipada.'],
    ['R11', 'El precio pactado se congela: si la tarifa o el servicio cambian después, la reserva conserva el valor con el que se hizo.', '1.2 tarifas cambiantes y auditoría de TARIFA (Entrega 2)', 'Columnas valor_estadia y precio_unitario (instantánea al reservar); subtotal es columna virtual.'],
    ['R12', 'Los encargados y la recepción trabajan para un alojamiento; administradores, gerencia y auditoría no pertenecen a ninguno. El titular de una reserva es mayor de edad.', '1.7 Usuarios internos; 1.3 Clientes', 'FK compuesta (id_rol, ambito_rol) + CHECK de ámbito; CHECK de tipo de documento sin TI.'],
  ], [650, 3000, 2110, 3600]),
];

const decisiones = [
  h1('4. Decisiones de diseño'),
  h2('4.1 Una reserva con varias habitaciones'),
  p('La reserva se modela como encabezado y detalle. RESERVA guarda lo que es común a todo el grupo: el cliente que reserva y paga, el alojamiento, el rango general de fechas, el estado y la fecha de cancelación. RESERVA_HABITACION guarda una línea por habitación con sus propias fechas de check-in y check-out, el número de huéspedes y el valor de la estadía. Así, un grupo que toma tres habitaciones del mismo alojamiento es una sola reserva, con un solo estado y un solo conjunto de pagos, y la persona que llega un día después tiene una línea con check-in posterior.'),
  p('Tres detalles lo hacen robusto. Primero, la disponibilidad se valida por línea y no por reserva: la habitación de quien llega tarde queda libre esa primera noche para otra reserva. Segundo, el id_alojamiento del encabezado viaja en la FK compuesta de cada línea, de modo que el motor rechaza mezclar habitaciones de dos alojamientos (R3). Tercero, UNIQUE(id_reserva, id_habitacion) impide repetir la misma habitación en una reserva. Se descartó poner id_habitacion directamente en RESERVA, porque obligaría a partir un grupo en varias reservas con pagos, estados y cancelaciones independientes.'),
  h2('4.2 Una estadía que atraviesa dos temporadas'),
  p('Se usan tres piezas. TEMPORADA es una instancia por año con categoría ALTA, MEDIA o BAJA y rango de fechas inclusivo (Semana Santa 2025 y Semana Santa 2026 son filas distintas). TARIFA guarda un valor por noche para cada pareja habitación × temporada, fijado libremente por el alojamiento: no es un porcentaje sobre un precio base. CALENDARIO asigna cada noche a exactamente una temporada. Con esas piezas el valor de una línea de reserva es la suma, noche a noche, de la tarifa de la temporada a la que pertenece cada noche:'),
  p([i('valor = Σ tarifa(habitación, temporada(d))  para cada noche d con  checkin ≤ d < checkout')], { align: AlignmentType.CENTER }),
  p('Ejemplo con los datos cargados: la temporada media "inicio de diciembre 2025" termina el 14-dic y la alta "fin de año 2025-2026" empieza el 15-dic. Una estadía del 12 al 17 de diciembre tiene cinco noches: las del 12, 13 y 14 se cobran a tarifa media y las del 15 y 16 a tarifa alta. La noche del check-out no se cobra. En SQL es una sola consulta, que es la que implementará fn_valor_estadia en la Entrega 2:'),
  ...codeBlock([
    'SELECT SUM(t.valor_noche)',
    'FROM   calendario c',
    'JOIN   tarifa t ON t.id_temporada  = c.id_temporada',
    '              AND t.id_habitacion = :id_habitacion',
    'WHERE  c.fecha >= :fecha_in AND c.fecha < :fecha_out;',
  ]),
  p('Se prefirió CALENDARIO a comparar directamente rangos de temporadas porque convierte un problema de intervalos en un join por igualdad, garantiza con la PK que no existan solapamientos y deja visibles los huecos (si falta un día, la suma queda incompleta y la carga lo detecta). Además permite repartir ingresos y ocupación por mes y por temporada aunque la estadía cruce el corte. El valor calculado se guarda en RESERVA_HABITACION.valor_estadia como instantánea del precio pactado (R11): si mañana el alojamiento cambia su tarifa, la reserva ya hecha no cambia de valor.'),
];

const carga = [
  h1('5. Modelo físico y carga de datos'),
  p('El script 01 crea las 16 tablas con 16 claves primarias, 17 claves foráneas (6 de ellas compuestas), 25 restricciones UNIQUE y 46 CHECK, además de comentarios en todas las tablas y en las columnas clave. Usa columnas de identidad (GENERATED BY DEFAULT AS IDENTITY) y columnas virtuales (subtotal, año, mes y día de la semana). Empieza borrando las tablas si existen, de manera que corre de arriba abajo en una base limpia o en una ya usada.'),
  p('El script 02 inserta a mano los catálogos que conviene poder leer y genera el resto con PL/SQL y DBMS_RANDOM con semilla fija: cada ejecución produce exactamente los mismos datos, lo que permite repetir resultados en la sustentación. La fecha de corte de los datos es el 17-10-2026: lo anterior queda COMPLETADO o CANCELADO y lo posterior CONFIRMADO, PENDIENTE o CANCELADO.'),
  table(['Tabla', 'Mínimo', 'Generado', 'Cómo se logra la asimetría'], [
    ['MUNICIPIO', '12', '12', 'Los 12 municipios con código DANE.'],
    ['TIPO_ALOJAMIENTO', '4', '5', 'Se agrega Ecohotel.'],
    ['ALOJAMIENTO', '60', '60', 'Armenia 12, Salento 10, Filandia 7, Montenegro 7, Quimbaya 6, Calarcá 6, Circasia 4, La Tebaida 4 y 1 en Buenavista, Pijao, Génova y Córdoba.'],
    ['HABITACION', '400', '≈ 650', 'Hoteles de Armenia 30-40; otros hoteles 12-24; fincas 3-6; glampings 3-8; hostales 6-12; ecohoteles 8-14.'],
    ['TEMPORADA', '6', '75', 'Calendario real 2024 - ene 2027: Semana Santa, mitad de año, fin de año y puentes festivos (Ley Emiliani) son ALTA.'],
    ['TARIFA', 'cruce', 'habitaciones × 75', 'Cada alojamiento tiene su propio factor de alta (1,10 a 1,65), media y baja, más inflación anual.'],
    ['CLIENTE', '3.000', '3.000', 'Bogotá, Medellín y Cali dominan; 24 ciudades de Colombia y 14 del exterior (~11 % extranjeros).'],
    ['RESERVA', '25.000', '26.500', 'Peso por categoría de temporada, día de la semana, año (crecimiento) y un factor aleatorio por mes; popularidad distinta por alojamiento y municipio.'],
    ['RESERVA_HABITACION', '≥ 25.000', '≈ 32.000', '~16 % de las reservas con 2 a 6 habitaciones, algunas con llegada o salida desfasada.'],
    ['PAGO', '≥ 25.000', '≈ 37.000', 'Pago único, anticipo + saldo, intentos fallidos, pendientes y reembolsos del 80 %.'],
    ['SERVICIO', '30', '259', 'De 3 a 6 por alojamiento, con precio propio.'],
    ['RESERVA_SERVICIO', '40.000', '≥ 40.500', 'De 0 a 4 servicios por reserva; un ciclo final garantiza la meta.'],
    ['RESENA', '≥ 40 %', '≈ 47 %', 'Calificación según una "calidad real" de cada alojamiento que no siempre coincide con sus estrellas.'],
    ['USUARIO_SISTEMA', '10', '12', '2 administradores, gerente, auditor, un encargado por cada uno de los 5 tipos y 3 de recepción.'],
  ], [2000, 1000, 1500, 4860]),
  p(''),
  p('Las cifras marcadas con ≈ dependen del sorteo; el bloque final del script 02 imprime los conteos exactos, el porcentaje de reseñas, cuántas reservas tienen varias habitaciones y varios pagos, y comprueba que no exista ningún solapamiento entre reservas activas de una misma habitación.'),
];

const consultas = [
  h1('6. Consultas de análisis'),
  p('Las siete consultas responden las preguntas de la gerencia (sección 1.8 del enunciado). Todas valoran el hospedaje noche por noche con CALENDARIO y TARIFA, así que una estadía que cruza de un mes a otro o de una temporada a otra se reparte correctamente.'),
  table(['#', 'Pregunta de negocio', 'Técnica', 'Detalle'], [
    ['1', 'Ocupación de cada municipio mes a mes (2025)', 'PIVOT', 'Noches ocupadas / (habitaciones × días del mes). Los 12 meses pasan a columnas y se agrega la ocupación anual.'],
    ['2', 'Ingresos por municipio, tipo de alojamiento y temporada (2025)', 'ROLLUP + GROUPING', 'Hospedaje + servicios por categoría de temporada; GROUPING rotula subtotal de tipo, de municipio y total general; GROUPING_ID indica el nivel.'],
    ['3', 'Los 3 alojamientos de mayor ingreso en cada municipio', 'RANK() OVER (PARTITION BY)', 'Incluye participación en el municipio (RATIO_TO_REPORT) e ingreso por habitación.'],
    ['4', 'Variación del recaudo mes contra mes', 'LAG', 'Recaudo neto (pagos menos reembolsos en el mes en que salen); variación absoluta, porcentual y frente al mismo mes del año anterior (LAG 12).'],
    ['5', 'Desempeño de cada alojamiento en un rango de fechas', 'Variables de enlace', ':fecha_ini y :fecha_fin; ocupación, ADR y RevPAR contando solo las noches dentro del rango.'],
    ['6', 'De dónde sale y a dónde va el dinero, por tipo de alojamiento', 'UNPIVOT', 'Hospedaje, servicios, recaudado, retenido por cancelaciones y reembolsado pasan de columnas a filas.'],
    ['7', '¿Las estrellas autoasignadas coinciden con la opinión de los huéspedes?', 'Consulta libre (DENSE_RANK)', 'Brecha entre promedio de reseñas y estrellas; clasifica cada alojamiento como sobrevalorado, coherente o subvalorado.'],
  ], [500, 2700, 1900, 4260]),
  p(''),
  p([b('Por qué la consulta 7. '), 'Las estrellas las asigna el propio alojamiento, pero son lo primero que ve un turista al buscar. Si un alojamiento se presenta como cinco estrellas y sus huéspedes lo califican con tres, la plataforma pierde confianza. La consulta da a la gerencia una lista concreta de alojamientos para auditar y otra de alojamientos que podrían subir de categoría.']),
];

const ejecucion = [
  h1('7. Cómo ejecutar'),
  bullet(['Conectarse como SYSTEM a XEPDB1 y ejecutar ', code('@00_crear_usuario.sql'), '.']),
  bullet(['Conectarse como ', code('turismouq/TurismoUQ2026@localhost:1521/XEPDB1'), '.']),
  bullet(['Ejecutar ', code('@01_ddl_turismouq.sql'), ', luego ', code('@02_carga_datos.sql'), ' (de 2 a 5 minutos) y revisar que el bloque final diga "CARGA VERIFICADA".']),
  bullet(['Ejecutar ', code('@03_consultas_analisis.sql'), '. En SQL Developer, usar "Ejecutar script" (F5) para que funcionen VARIABLE y EXEC de la consulta 5.']),
  bullet(['Si se usa SQL*Plus en Windows, definir antes ', code('NLS_LANG=SPANISH_COLOMBIA.AL32UTF8'), ' para que las tildes y la ñ se guarden bien.']),
];

const doc = new Document({
  creator: 'Equipo TurismoUQ', title: 'TurismoUQ · Entrega 1',
  styles: {
    default: { document: { run: { font: FONT, size: 21 } } },
    paragraphStyles: [
      { id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true, run: { size: 30, bold: true, color: AZUL, font: FONT }, paragraph: { outlineLevel: 0 } },
      { id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true, run: { size: 25, bold: true, color: '000000', font: FONT }, paragraph: { outlineLevel: 1 } },
    ],
  },
  numbering: { config: [{ reference: 'vinetas', levels: [{ level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 540, hanging: 270 } } } }] }] },
  features: { updateFields: true },
  sections: [{
    properties: { page: { margin: { top: 1300, bottom: 1300, left: 1440, right: 1440 } } },
    footers: { default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.RIGHT, children: [
      new TextRun({ text: 'TurismoUQ · Entrega 1 · página ', font: FONT, size: 16, color: '777777' }),
      new TextRun({ children: [PageNumber.CURRENT], font: FONT, size: 16, color: '777777' })] })] }) },
    children: [...portada, ...intro, ...mer, ...reglas, ...decisiones, ...carga, ...consultas, ...ejecucion],
  }],
});
Packer.toBuffer(doc).then(buf => { fs.writeFileSync('/home/claude/turismouq/docs/Entrega1_TurismoUQ.docx', buf); console.log('ok'); });
