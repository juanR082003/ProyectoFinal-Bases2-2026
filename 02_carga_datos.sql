/* =====================================================================
   TurismoUQ · Proyecto integrador Bases de Datos II · 2026-2
   Script 02 · Carga de datos (volumen mínimo y asimétrico)
   ---------------------------------------------------------------------
   Requisito previo: haber ejecutado 01_ddl_turismouq.sql (tablas vacías).
   Tiempo estimado en Oracle XE 21c: 2 a 5 minutos.

   Estrategia
     · Catálogos pequeños (municipios, tipos, roles, temporadas,
       alojamientos, servicios, usuarios) se insertan con INSERT
       explícitos: son datos "de negocio" que conviene poder leer.
     · Las tablas grandes (habitaciones, tarifas, clientes, reservas,
       líneas, servicios contratados, pagos, reseñas) se generan con
       PL/SQL y DBMS_RANDOM con SEMILLA FIJA: cada ejecución produce
       exactamente los mismos datos (reproducible para la sustentación).
     · La asimetría es deliberada: municipios con distinto peso
       turístico, alojamientos con distinta popularidad, días con peso
       según temporada y día de la semana, crecimiento año a año y un
       factor aleatorio por mes.
     · La fecha de corte de los datos es el 17-10-2026: lo anterior está
       COMPLETADO o CANCELADO; lo posterior está CONFIRMADO, PENDIENTE o
       CANCELADO.

   Secciones
     1. Catálogos: MUNICIPIO, TIPO_ALOJAMIENTO, ROL
     2. TEMPORADA (2024 - ene 2027) y CALENDARIO (un día por fila)
     3. ALOJAMIENTO (60) y SERVICIO
     4. HABITACION (PL/SQL, asimétrico por tipo de alojamiento)
     5. TARIFA (cruce habitación x temporada)
     6. CLIENTE (3.000)
     7. RESERVA, RESERVA_HABITACION, RESERVA_SERVICIO, PAGO, RESENA
     8. USUARIO_SISTEMA
     9. Verificación de volúmenes y reglas + estadísticas
   ===================================================================== */

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
SET SQLBLANKLINES ON
SET FEEDBACK OFF
ALTER SESSION SET NLS_DATE_FORMAT = 'YYYY-MM-DD';

/* =====================================================================
   1. Catálogos
   ===================================================================== */
PROMPT 1. Catálogos...

-- Los 12 municipios del Quindío con su código DANE
INSERT INTO municipio VALUES ( 1, '63001', 'Armenia');
INSERT INTO municipio VALUES ( 2, '63111', 'Buenavista');
INSERT INTO municipio VALUES ( 3, '63130', 'Calarcá');
INSERT INTO municipio VALUES ( 4, '63190', 'Circasia');
INSERT INTO municipio VALUES ( 5, '63212', 'Córdoba');
INSERT INTO municipio VALUES ( 6, '63272', 'Filandia');
INSERT INTO municipio VALUES ( 7, '63302', 'Génova');
INSERT INTO municipio VALUES ( 8, '63401', 'La Tebaida');
INSERT INTO municipio VALUES ( 9, '63470', 'Montenegro');
INSERT INTO municipio VALUES (10, '63548', 'Pijao');
INSERT INTO municipio VALUES (11, '63594', 'Quimbaya');
INSERT INTO municipio VALUES (12, '63690', 'Salento');

INSERT INTO tipo_alojamiento VALUES (1, 'Finca cafetera', 'Casa campesina dentro de una finca productora de café, pocas habitaciones');
INSERT INTO tipo_alojamiento VALUES (2, 'Hotel', 'Establecimiento urbano o campestre con recepción 24 h y muchas habitaciones');
INSERT INTO tipo_alojamiento VALUES (3, 'Glamping', 'Domos o cabañas de lujo en entorno natural, pocas unidades');
INSERT INTO tipo_alojamiento VALUES (4, 'Hostal', 'Alojamiento económico con habitaciones sencillas o compartidas');
INSERT INTO tipo_alojamiento VALUES (5, 'Ecohotel', 'Hotel de bajo impacto ambiental dentro de reservas naturales');

INSERT INTO rol VALUES (1, 'ADMIN_PLATAFORMA',  'PLATAFORMA',  'Administra catálogos, usuarios y parámetros de toda la plataforma');
INSERT INTO rol VALUES (2, 'GERENTE',           'PLATAFORMA',  'Consulta indicadores y reportes de todos los alojamientos');
INSERT INTO rol VALUES (3, 'AUDITOR',           'PLATAFORMA',  'Solo lectura de movimientos y auditoría (tarifas, pagos)');
INSERT INTO rol VALUES (4, 'ADMIN_ALOJAMIENTO', 'ALOJAMIENTO', 'Encargado: gestiona habitaciones, tarifas y reservas de su alojamiento');
INSERT INTO rol VALUES (5, 'RECEPCION',         'ALOJAMIENTO', 'Registra check-in, check-out y pagos en su alojamiento');
COMMIT;

/* =====================================================================
   2. Temporadas y calendario
   Temporadas reales de Colombia: Semana Santa, mitad de año,
   diciembre-enero y puentes festivos (Ley Emiliani) son ALTA; el resto
   del año se reparte entre MEDIA y BAJA. Cubre del 01-01-2024 al
   31-01-2027 sin huecos ni solapamientos.
   ===================================================================== */
PROMPT 2. Temporadas y calendario...

-- 75 temporadas (generadas a partir del calendario de festivos de Colombia)
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta fin de año 2023-2024', 'ALTA', 2024, DATE '2024-01-01', DATE '2024-01-07');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Baja inicio de año 2024', 'BAJA', 2024, DATE '2024-01-08', DATE '2024-03-21');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta Semana Santa 2024', 'ALTA', 2024, DATE '2024-03-22', DATE '2024-03-30');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media abril-junio 2024 (tramo 1)', 'MEDIA', 2024, DATE '2024-03-31', DATE '2024-05-09');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Ascensión del Señor 2024', 'ALTA', 2024, DATE '2024-05-10', DATE '2024-05-12');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media abril-junio 2024 (tramo 2)', 'MEDIA', 2024, DATE '2024-05-13', DATE '2024-05-30');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Corpus Christi 2024', 'ALTA', 2024, DATE '2024-05-31', DATE '2024-06-02');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media abril-junio 2024 (tramo 3)', 'MEDIA', 2024, DATE '2024-06-03', DATE '2024-06-06');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Sagrado Corazón 2024', 'ALTA', 2024, DATE '2024-06-07', DATE '2024-06-09');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media abril-junio 2024 (tramo 4)', 'MEDIA', 2024, DATE '2024-06-10', DATE '2024-06-13');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta vacaciones mitad de año 2024', 'ALTA', 2024, DATE '2024-06-14', DATE '2024-07-20');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media agosto-septiembre 2024 (tramo 1)', 'MEDIA', 2024, DATE '2024-07-21', DATE '2024-08-15');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Asunción de la Virgen 2024', 'ALTA', 2024, DATE '2024-08-16', DATE '2024-08-18');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media agosto-septiembre 2024 (tramo 2)', 'MEDIA', 2024, DATE '2024-08-19', DATE '2024-09-30');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Baja octubre-noviembre 2024 (tramo 1)', 'BAJA', 2024, DATE '2024-10-01', DATE '2024-10-10');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Día de la Raza 2024', 'ALTA', 2024, DATE '2024-10-11', DATE '2024-10-13');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media receso escolar octubre 2024', 'MEDIA', 2024, DATE '2024-10-14', DATE '2024-10-20');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Baja octubre-noviembre 2024 (tramo 2)', 'BAJA', 2024, DATE '2024-10-21', DATE '2024-10-31');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Todos los Santos 2024', 'ALTA', 2024, DATE '2024-11-01', DATE '2024-11-03');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Baja octubre-noviembre 2024 (tramo 3)', 'BAJA', 2024, DATE '2024-11-04', DATE '2024-11-07');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Independencia de Cartagena 2024', 'ALTA', 2024, DATE '2024-11-08', DATE '2024-11-10');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Baja octubre-noviembre 2024 (tramo 4)', 'BAJA', 2024, DATE '2024-11-11', DATE '2024-11-30');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media inicio de diciembre 2024', 'MEDIA', 2024, DATE '2024-12-01', DATE '2024-12-14');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta fin de año 2024-2025', 'ALTA', 2024, DATE '2024-12-15', DATE '2025-01-05');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Baja inicio de año 2025 (tramo 1)', 'BAJA', 2025, DATE '2025-01-06', DATE '2025-03-20');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente San José 2025', 'ALTA', 2025, DATE '2025-03-21', DATE '2025-03-23');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Baja inicio de año 2025 (tramo 2)', 'BAJA', 2025, DATE '2025-03-24', DATE '2025-04-10');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta Semana Santa 2025', 'ALTA', 2025, DATE '2025-04-11', DATE '2025-04-19');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media abril-junio 2025 (tramo 1)', 'MEDIA', 2025, DATE '2025-04-20', DATE '2025-05-29');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Ascensión del Señor 2025', 'ALTA', 2025, DATE '2025-05-30', DATE '2025-06-01');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media abril-junio 2025 (tramo 2)', 'MEDIA', 2025, DATE '2025-06-02', DATE '2025-06-13');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta vacaciones mitad de año 2025', 'ALTA', 2025, DATE '2025-06-14', DATE '2025-07-20');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media agosto-septiembre 2025 (tramo 1)', 'MEDIA', 2025, DATE '2025-07-21', DATE '2025-08-14');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Asunción de la Virgen 2025', 'ALTA', 2025, DATE '2025-08-15', DATE '2025-08-17');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media agosto-septiembre 2025 (tramo 2)', 'MEDIA', 2025, DATE '2025-08-18', DATE '2025-09-30');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Baja octubre-noviembre 2025 (tramo 1)', 'BAJA', 2025, DATE '2025-10-01', DATE '2025-10-09');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Día de la Raza 2025', 'ALTA', 2025, DATE '2025-10-10', DATE '2025-10-12');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media receso escolar octubre 2025', 'MEDIA', 2025, DATE '2025-10-13', DATE '2025-10-19');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Baja octubre-noviembre 2025 (tramo 2)', 'BAJA', 2025, DATE '2025-10-20', DATE '2025-10-30');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Todos los Santos 2025', 'ALTA', 2025, DATE '2025-10-31', DATE '2025-11-02');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Baja octubre-noviembre 2025 (tramo 3)', 'BAJA', 2025, DATE '2025-11-03', DATE '2025-11-13');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Independencia de Cartagena 2025', 'ALTA', 2025, DATE '2025-11-14', DATE '2025-11-16');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Baja octubre-noviembre 2025 (tramo 4)', 'BAJA', 2025, DATE '2025-11-17', DATE '2025-11-30');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media inicio de diciembre 2025 (tramo 1)', 'MEDIA', 2025, DATE '2025-12-01', DATE '2025-12-04');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Inmaculada Concepción 2025', 'ALTA', 2025, DATE '2025-12-05', DATE '2025-12-07');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media inicio de diciembre 2025 (tramo 2)', 'MEDIA', 2025, DATE '2025-12-08', DATE '2025-12-14');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta fin de año 2025-2026', 'ALTA', 2025, DATE '2025-12-15', DATE '2026-01-11');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Baja inicio de año 2026 (tramo 1)', 'BAJA', 2026, DATE '2026-01-12', DATE '2026-03-19');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente San José 2026', 'ALTA', 2026, DATE '2026-03-20', DATE '2026-03-22');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Baja inicio de año 2026 (tramo 2)', 'BAJA', 2026, DATE '2026-03-23', DATE '2026-03-26');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta Semana Santa 2026', 'ALTA', 2026, DATE '2026-03-27', DATE '2026-04-04');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media abril-junio 2026 (tramo 1)', 'MEDIA', 2026, DATE '2026-04-05', DATE '2026-04-29');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Día del Trabajo 2026', 'ALTA', 2026, DATE '2026-04-30', DATE '2026-05-02');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media abril-junio 2026 (tramo 2)', 'MEDIA', 2026, DATE '2026-05-03', DATE '2026-05-14');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Ascensión del Señor 2026', 'ALTA', 2026, DATE '2026-05-15', DATE '2026-05-17');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media abril-junio 2026 (tramo 3)', 'MEDIA', 2026, DATE '2026-05-18', DATE '2026-06-04');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Corpus Christi 2026', 'ALTA', 2026, DATE '2026-06-05', DATE '2026-06-07');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media abril-junio 2026 (tramo 4)', 'MEDIA', 2026, DATE '2026-06-08', DATE '2026-06-13');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta vacaciones mitad de año 2026', 'ALTA', 2026, DATE '2026-06-14', DATE '2026-07-20');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media agosto-septiembre 2026 (tramo 1)', 'MEDIA', 2026, DATE '2026-07-21', DATE '2026-08-05');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Batalla de Boyacá 2026', 'ALTA', 2026, DATE '2026-08-06', DATE '2026-08-08');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media agosto-septiembre 2026 (tramo 2)', 'MEDIA', 2026, DATE '2026-08-09', DATE '2026-08-13');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Asunción de la Virgen 2026', 'ALTA', 2026, DATE '2026-08-14', DATE '2026-08-16');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media agosto-septiembre 2026 (tramo 3)', 'MEDIA', 2026, DATE '2026-08-17', DATE '2026-09-30');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Baja octubre-noviembre 2026 (tramo 1)', 'BAJA', 2026, DATE '2026-10-01', DATE '2026-10-08');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Día de la Raza 2026', 'ALTA', 2026, DATE '2026-10-09', DATE '2026-10-11');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media receso escolar octubre 2026', 'MEDIA', 2026, DATE '2026-10-12', DATE '2026-10-18');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Baja octubre-noviembre 2026 (tramo 2)', 'BAJA', 2026, DATE '2026-10-19', DATE '2026-10-29');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Todos los Santos 2026', 'ALTA', 2026, DATE '2026-10-30', DATE '2026-11-01');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Baja octubre-noviembre 2026 (tramo 3)', 'BAJA', 2026, DATE '2026-11-02', DATE '2026-11-12');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta puente Independencia de Cartagena 2026', 'ALTA', 2026, DATE '2026-11-13', DATE '2026-11-15');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Baja octubre-noviembre 2026 (tramo 4)', 'BAJA', 2026, DATE '2026-11-16', DATE '2026-11-30');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Media inicio de diciembre 2026', 'MEDIA', 2026, DATE '2026-12-01', DATE '2026-12-14');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Alta fin de año 2026-2027', 'ALTA', 2026, DATE '2026-12-15', DATE '2027-01-10');
INSERT INTO temporada (nombre, categoria, anio, fecha_inicio, fecha_fin) VALUES ('Baja inicio de año 2027', 'BAJA', 2027, DATE '2027-01-11', DATE '2027-01-31');
COMMIT;

-- CALENDARIO: un día por fila, unido a la temporada que lo contiene.
-- Si dos temporadas se solaparan, la PK (fecha) fallaría aquí.
INSERT INTO calendario (fecha, id_temporada)
SELECT d.fecha, t.id_temporada
FROM  (SELECT DATE '2024-01-01' + LEVEL - 1 AS fecha
       FROM   dual
       CONNECT BY LEVEL <= DATE '2027-01-31' - DATE '2024-01-01' + 1) d
JOIN   temporada t
  ON   d.fecha BETWEEN t.fecha_inicio AND t.fecha_fin;

-- Festivos nacionales de Colombia en el rango
UPDATE calendario SET es_festivo = 'S' WHERE fecha IN (
   DATE '2024-01-01', DATE '2024-01-08', DATE '2024-03-25', DATE '2024-03-28', DATE '2024-03-29', DATE '2024-05-01',
   DATE '2024-05-13', DATE '2024-06-03', DATE '2024-06-10', DATE '2024-07-01', DATE '2024-07-20', DATE '2024-08-07',
   DATE '2024-08-19', DATE '2024-10-14', DATE '2024-11-04', DATE '2024-11-11', DATE '2024-12-08', DATE '2024-12-25',
   DATE '2025-01-01', DATE '2025-01-06', DATE '2025-03-24', DATE '2025-04-17', DATE '2025-04-18', DATE '2025-05-01',
   DATE '2025-06-02', DATE '2025-06-23', DATE '2025-06-30', DATE '2025-07-20', DATE '2025-08-07', DATE '2025-08-18',
   DATE '2025-10-13', DATE '2025-11-03', DATE '2025-11-17', DATE '2025-12-08', DATE '2025-12-25', DATE '2026-01-01',
   DATE '2026-01-12', DATE '2026-03-23', DATE '2026-04-02', DATE '2026-04-03', DATE '2026-05-01', DATE '2026-05-18',
   DATE '2026-06-08', DATE '2026-06-15', DATE '2026-06-29', DATE '2026-07-20', DATE '2026-08-07', DATE '2026-08-17',
   DATE '2026-10-12', DATE '2026-11-02', DATE '2026-11-16', DATE '2026-12-08', DATE '2026-12-25', DATE '2027-01-01',
   DATE '2027-01-11');
COMMIT;

-- Control: el calendario no debe tener huecos
DECLARE
   v_dias NUMBER;
BEGIN
   SELECT COUNT(*) INTO v_dias FROM calendario;
   IF v_dias <> DATE '2027-01-31' - DATE '2024-01-01' + 1 THEN
      RAISE_APPLICATION_ERROR(-20010, 'El calendario tiene huecos: ' || v_dias || ' días');
   END IF;
   DBMS_OUTPUT.PUT_LINE('   Calendario completo: ' || v_dias || ' días');
END;
/

/* =====================================================================
   3. Alojamientos (60, repartidos de forma desigual) y servicios
   Armenia 12, Salento 10, Filandia 7, Montenegro 7, Quimbaya 6,
   Calarcá 6, Circasia 4, La Tebaida 4 y 1 en cada uno de Buenavista,
   Pijao, Génova y Córdoba. Nombres, NIT y contactos son ficticios.
   ===================================================================== */
PROMPT 3. Alojamientos y servicios...

INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (1, 2, 'Hotel Mirador del Parque Sucre', '937190825-0', 'Cra 17 # 23-03, Armenia', 4, '318 068 6238', 'reservas@hotelmiradordelparquesucre.com.co', 'https://www.hotelmiradordelparquesucre.com.co', DATE '2023-07-06');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (1, 2, 'Hotel Torre Cafetera', '977347919-7', 'Cra 14 # 38-04, Armenia', 5, '606 736 5051', 'reservas@hoteltorrecafetera.com.co', 'https://www.hoteltorrecafetera.com.co', DATE '2023-08-23');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (1, 2, 'Hotel Avenida Bolívar', '911809980-6', 'Cra 17 # 27-96, Armenia', 3, '606 752 7809', 'reservas@hotelavenidabolivar.com.co', NULL, DATE '2023-08-04');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (1, 2, 'Hotel Ejecutivo La Castellana', '954276994-2', 'Cra 15 # 36-44, Armenia', 4, '606 739 0233', 'reservas@hotelejecutivolacastellana.com.co', NULL, DATE '2023-09-15');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (1, 2, 'Hotel Plaza Quimbaya Centro', '971785983-3', 'Cra 17 # 22-91, Armenia', 3, '606 750 3653', 'reservas@hotelplazaquimbayacentro.com.co', 'https://www.hotelplazaquimbayacentro.com.co', DATE '2023-01-10');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (1, 2, 'Gran Hotel Guadua Real', '936063991-5', 'Cra 19 # 43-08, Armenia', 5, '606 748 0238', 'reservas@granhotelguaduareal.com.co', 'https://www.granhotelguaduareal.com.co', DATE '2023-03-02');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (1, 2, 'Hotel Los Fundadores Suites', '935127741-9', 'Cra 15 # 34-62, Armenia', 4, '606 749 0127', 'reservas@hotellosfundadoressuites.com.co', 'https://www.hotellosfundadoressuites.com.co', DATE '2023-08-09');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (1, 4, 'Hostal La Calle Catorce', '971886706-2', 'Cra 18 # 27-93, Armenia', 2, '606 745 6642', 'reservas@hostallacallecatorce.com.co', 'https://www.hostallacallecatorce.com.co', DATE '2023-07-19');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (1, 4, 'Hostal Ruta del Café Armenia', '984132827-0', 'Cra 10 # 48-41, Armenia', 2, '317 713 2463', 'reservas@hostalrutadelcafearmenia.com.co', 'https://www.hostalrutadelcafearmenia.com.co', DATE '2023-07-29');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (1, 4, 'Hostal Barrio Laureles', '947337589-4', 'Cra 12 # 42-89, Armenia', 1, '606 749 6889', 'reservas@hostalbarriolaureles.com.co', NULL, DATE '2023-09-17');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (1, 1, 'Finca Cafetera El Edén Urbano', '986617069-9', 'Vereda La Granja, km 8 vía Armenia', 3, '606 738 1642', 'reservas@fincacafeteraeledenurbano.com.co', NULL, DATE '2023-02-09');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (1, 5, 'Ecohotel Bosque de Yarumos', '966788440-5', 'Vereda San Juan, km 8 vía Armenia', 4, '606 746 2537', 'reservas@ecohotelbosquedeyarumos.com.co', 'https://www.ecohotelbosquedeyarumos.com.co', DATE '2023-04-25');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (12, 4, 'Hostal Calle Real de Salento', '910437587-6', 'Calle 7 # 9-57, Salento', 2, '606 733 2687', 'reservas@hostalcallerealdesalento.com.co', 'https://www.hostalcallerealdesalento.com.co', DATE '2023-01-01');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (12, 4, 'Hostal Mochileros del Cocora', '964068547-7', 'Calle 8 # 9-41, Salento', 1, '606 734 3470', 'reservas@hostalmochilerosdelcocora.com.co', NULL, DATE '2023-02-17');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (12, 4, 'Hostal Balcones de Colores', '960035747-9', 'Calle 7 # 5-13, Salento', 2, '314 039 1797', 'reservas@hostalbalconesdecolores.com.co', NULL, DATE '2023-04-30');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (12, 3, 'Glamping Domos del Valle de Cocora', '942285679-4', 'Vereda La Esperanza, km 4 vía Salento', 4, '606 735 7461', 'reservas@glampingdomosdelvalledecocor.com.co', NULL, DATE '2023-09-08');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (12, 3, 'Glamping Palma de Cera', '947090240-4', 'Vereda El Agrado, km 6 vía Salento', 5, '319 936 8101', 'reservas@glampingpalmadecera.com.co', 'https://www.glampingpalmadecera.com.co', DATE '2023-04-05');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (12, 1, 'Finca Cafetera La Aldea del Alto', '969681138-0', 'Vereda El Agrado, km 9 vía Salento', 3, '318 289 1874', 'reservas@fincacafeteralaaldeadelalto.com.co', 'https://www.fincacafeteralaaldeadelalto.com.co', DATE '2023-02-20');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (12, 1, 'Finca El Recreo de Boquía', '918578595-1', 'Vereda La Granja, km 3 vía Salento', 4, '310 715 1364', 'reservas@fincaelrecreodeboquia.com.co', 'https://www.fincaelrecreodeboquia.com.co', DATE '2023-01-23');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (12, 2, 'Hotel Mirador Alto de la Cruz', '942532766-4', 'Calle 4 # 9-08, Salento', 4, '606 730 8624', 'reservas@hotelmiradoraltodelacruz.com.co', NULL, DATE '2023-03-22');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (12, 2, 'Hotel Colonial Plaza Bolívar', '988729665-8', 'Calle 9 # 12-39, Salento', 3, '606 759 0063', 'reservas@hotelcolonialplazabolivar.com.co', 'https://www.hotelcolonialplazabolivar.com.co', DATE '2023-07-03');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (12, 5, 'Ecohotel Reserva Río Quindío', '973730826-1', 'Vereda La Bella, km 5 vía Salento', 4, '312 933 5823', 'reservas@ecohotelreservarioquindio.com.co', 'https://www.ecohotelreservarioquindio.com.co', DATE '2023-05-10');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (6, 3, 'Glamping Colina Iluminada', '975304968-9', 'Vereda La Bella, km 4 vía Filandia', 5, '606 747 1237', 'reservas@glampingcolinailuminada.com.co', NULL, DATE '2023-08-26');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (6, 3, 'Glamping Bosque de Bambú', '911813040-9', 'Vereda La Esperanza, km 7 vía Filandia', 4, '606 734 0186', 'reservas@glampingbosquedebambu.com.co', NULL, DATE '2023-07-30');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (6, 1, 'Finca Cafetera Los Cerezos', '986639361-6', 'Vereda La Esperanza, km 9 vía Filandia', 4, '310 332 7880', 'reservas@fincacafeteraloscerezos.com.co', NULL, DATE '2023-08-10');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (6, 1, 'Finca La Herencia Filandeña', '980056210-0', 'Vereda La Esperanza, km 6 vía Filandia', 3, '317 492 8403', 'reservas@fincalaherenciafilandena.com.co', 'https://www.fincalaherenciafilandena.com.co', DATE '2023-09-14');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (6, 4, 'Hostal El Mirador Filandia', '949433707-6', 'Calle 8 # 8-51, Filandia', 2, '316 752 6039', 'reservas@hostalelmiradorfilandia.com.co', 'https://www.hostalelmiradorfilandia.com.co', DATE '2023-07-29');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (6, 4, 'Hostal Bahareque', '997306602-1', 'Calle 7 # 6-18, Filandia', 2, '606 750 7022', 'reservas@hostalbahareque.com.co', 'https://www.hostalbahareque.com.co', DATE '2023-06-17');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (6, 2, 'Hotel Casona del Parque Filandia', '923180755-3', 'Calle 4 # 6-17, Filandia', 3, '606 745 2373', 'reservas@hotelcasonadelparquefilandia.com.co', 'https://www.hotelcasonadelparquefilandia.com.co', DATE '2023-09-14');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (9, 1, 'Finca Hotel Puerto Espejo', '945153864-8', 'Vereda El Roble, km 3 vía Montenegro', 4, '318 074 6311', 'reservas@fincahotelpuertoespejo.com.co', 'https://www.fincahotelpuertoespejo.com.co', DATE '2023-01-19');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (9, 1, 'Finca Cafetera Villa Laura', '936297116-3', 'Vereda La Bella, km 2 vía Montenegro', 3, '606 740 8859', 'reservas@fincacafeteravillalaura.com.co', 'https://www.fincacafeteravillalaura.com.co', DATE '2023-07-06');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (9, 1, 'Finca El Ocaso Cafetero', '916484975-1', 'Vereda El Roble, km 7 vía Montenegro', 3, '606 747 4845', 'reservas@fincaelocasocafetero.com.co', 'https://www.fincaelocasocafetero.com.co', DATE '2023-09-14');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (9, 1, 'Finca Bambusa', '916421212-6', 'Vereda Pantanillo, km 8 vía Montenegro', 4, '311 608 8214', 'reservas@fincabambusa.com.co', 'https://www.fincabambusa.com.co', DATE '2023-09-27');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (9, 2, 'Hotel Entrada al Parque', '934377520-5', 'Calle 3 # 9-54, Montenegro', 4, '312 940 4574', 'reservas@hotelentradaalparque.com.co', NULL, DATE '2023-03-20');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (9, 2, 'Hotel Pueblo Tapao Plaza', '980367686-0', 'Calle 7 # 6-07, Montenegro', 3, '606 735 5520', 'reservas@hotelpueblotapaoplaza.com.co', NULL, DATE '2023-05-05');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (9, 3, 'Glamping Mirador de Pisamal', '993768908-5', 'Vereda La Esperanza, km 9 vía Montenegro', 4, '606 753 3948', 'reservas@glampingmiradordepisamal.com.co', 'https://www.glampingmiradordepisamal.com.co', DATE '2023-01-23');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (11, 1, 'Finca Cafetera Las Acacias', '935200951-5', 'Vereda La Palmera, km 12 vía Quimbaya', 3, '317 895 1081', 'reservas@fincacafeteralasacacias.com.co', 'https://www.fincacafeteralasacacias.com.co', DATE '2023-06-27');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (11, 1, 'Finca Los Guaduales de Panaca', '918843960-0', 'Vereda Palestina, km 10 vía Quimbaya', 4, '313 472 7987', 'reservas@fincalosguadualesdepanaca.com.co', 'https://www.fincalosguadualesdepanaca.com.co', DATE '2023-05-06');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (11, 1, 'Finca La Montaña Luminosa', '931973513-1', 'Vereda La Granja, km 5 vía Quimbaya', 3, '317 387 1936', 'reservas@fincalamontanaluminosa.com.co', 'https://www.fincalamontanaluminosa.com.co', DATE '2023-09-24');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (11, 2, 'Hotel Alumbrado de Velas', '989062869-7', 'Calle 4 # 4-28, Quimbaya', 4, '313 997 0355', 'reservas@hotelalumbradodevelas.com.co', 'https://www.hotelalumbradodevelas.com.co', DATE '2023-09-07');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (11, 2, 'Hotel Campestre El Arriero', '921392263-5', 'Calle 3 # 8-34, Quimbaya', 3, '606 759 5520', 'reservas@hotelcampestreelarriero.com.co', 'https://www.hotelcampestreelarriero.com.co', DATE '2023-07-22');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (11, 3, 'Glamping Estrellas de Quimbaya', '964645180-5', 'Vereda Pantanillo, km 2 vía Quimbaya', 4, '606 753 7418', 'reservas@glampingestrellasdequimbaya.com.co', 'https://www.glampingestrellasdequimbaya.com.co', DATE '2023-02-06');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (3, 2, 'Hotel Jardín Botánico', '913679004-5', 'Calle 9 # 10-36, Calarcá', 4, '606 739 8450', 'reservas@hoteljardinbotanico.com.co', 'https://www.hoteljardinbotanico.com.co', DATE '2023-07-27');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (3, 1, 'Finca Cafetera La Rochela', '974211722-3', 'Vereda El Roble, km 9 vía Calarcá', 3, '606 745 2405', 'reservas@fincacafeteralarochela.com.co', 'https://www.fincacafeteralarochela.com.co', DATE '2023-08-03');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (3, 1, 'Finca El Mariposario', '969744685-2', 'Vereda El Agrado, km 2 vía Calarcá', 4, '606 743 7484', 'reservas@fincaelmariposario.com.co', 'https://www.fincaelmariposario.com.co', DATE '2023-07-03');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (3, 4, 'Hostal Alto del Río', '936563004-9', 'Calle 9 # 5-37, Calarcá', 2, '606 740 4725', 'reservas@hostalaltodelrio.com.co', 'https://www.hostalaltodelrio.com.co', DATE '2023-07-24');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (3, 5, 'Ecohotel Cañón del Quindío', '922260674-7', 'Vereda La Esperanza, km 10 vía Calarcá', 4, '316 285 6846', 'reservas@ecohotelcanondelquindio.com.co', 'https://www.ecohotelcanondelquindio.com.co', DATE '2023-07-22');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (3, 1, 'Finca Santa Ana de Calarcá', '928447588-5', 'Vereda Boquía, km 12 vía Calarcá', 3, '310 164 5462', 'reservas@fincasantaanadecalarca.com.co', 'https://www.fincasantaanadecalarca.com.co', DATE '2023-08-15');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (4, 1, 'Finca Cafetera La Pradera de Circasia', '938920654-6', 'Vereda San Juan, km 4 vía Circasia', 3, '606 743 9620', 'reservas@fincacafeteralapraderadecirc.com.co', NULL, DATE '2023-05-25');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (4, 1, 'Finca La Cabaña de Barcelona', '986593116-2', 'Vereda La Granja, km 10 vía Circasia', 3, '606 746 9251', 'reservas@fincalacabanadebarcelona.com.co', 'https://www.fincalacabanadebarcelona.com.co', DATE '2023-06-08');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (4, 4, 'Hostal Mirador de Circasia', '986675936-6', 'Vereda La Palmera, km 1 vía Circasia', 2, '606 741 1626', 'reservas@hostalmiradordecircasia.com.co', 'https://www.hostalmiradordecircasia.com.co', DATE '2023-05-21');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (4, 3, 'Glamping Alto de la Cruz Circasia', '930895884-2', 'Vereda El Caimo, km 4 vía Circasia', 4, '606 750 5534', 'reservas@glampingaltodelacruzcircasia.com.co', 'https://www.glampingaltodelacruzcircasia.com.co', DATE '2023-02-07');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (8, 2, 'Hotel Aeropuerto El Edén', '954362143-2', 'Calle 8 # 12-42, La Tebaida', 3, '310 255 0952', 'reservas@hotelaeropuertoeleden.com.co', 'https://www.hotelaeropuertoeleden.com.co', DATE '2023-09-06');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (8, 1, 'Finca Cafetera Mangos Viejos', '977018875-4', 'Vereda El Agrado, km 5 vía La Tebaida', 3, '319 693 7700', 'reservas@fincacafeteramangosviejos.com.co', 'https://www.fincacafeteramangosviejos.com.co', DATE '2023-02-26');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (8, 1, 'Finca Los Samanes', '952084701-1', 'Vereda La Esperanza, km 7 vía La Tebaida', 4, '606 750 8370', 'reservas@fincalossamanes.com.co', 'https://www.fincalossamanes.com.co', DATE '2023-04-22');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (8, 4, 'Hostal Estación Tebaida', '972593659-1', 'Vereda El Caimo, km 4 vía La Tebaida', 1, '606 747 4693', 'reservas@hostalestaciontebaida.com.co', 'https://www.hostalestaciontebaida.com.co', DATE '2023-01-28');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (2, 1, 'Finca Mirador del Valle Buenavista', '913992982-7', 'Vereda El Agrado, km 6 vía Buenavista', 4, '606 740 4722', 'reservas@fincamiradordelvallebuenavis.com.co', 'https://www.fincamiradordelvallebuenavis.com.co', DATE '2023-08-20');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (10, 1, 'Finca Cafetera Pueblo Sin Prisa', '917898099-2', 'Vereda El Agrado, km 4 vía Pijao', 3, '606 747 6116', 'reservas@fincacafeterapueblosinprisa.com.co', 'https://www.fincacafeterapueblosinprisa.com.co', DATE '2023-05-13');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (7, 1, 'Finca El Páramo de Génova', '969861185-2', 'Vereda Llanitos, km 4 vía Génova', 3, '318 649 3861', 'reservas@fincaelparamodegenova.com.co', 'https://www.fincaelparamodegenova.com.co', DATE '2023-07-21');
INSERT INTO alojamiento (id_municipio, id_tipo, nombre_comercial, nit, direccion, estrellas, telefono, correo, sitio_web, fecha_registro) VALUES (5, 4, 'Hostal Quebrada Córdoba', '971267749-0', 'Vereda El Agrado, km 7 vía Córdoba', 2, '311 454 9593', 'reservas@hostalquebradacordoba.com.co', 'https://www.hostalquebradacordoba.com.co', DATE '2023-07-20');
COMMIT;

-- 259 servicios repartidos entre los 60 alojamientos
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Mirador del Parque Sucre'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 34000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Mirador del Parque Sucre'), 'Spa y masajes', 'Masaje relajante de 60 minutos con aceites de café', 124000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Mirador del Parque Sucre'), 'Lavandería', 'Lavado y planchado por bolsa', 28000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Torre Cafetera'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 25000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Torre Cafetera'), 'Parqueadero', 'Parqueadero cubierto por noche', 20000, 'POR_DIA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Torre Cafetera'), 'Entradas PANACA', 'Ingreso a PANACA con transporte', 136000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Avenida Bolívar'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 32000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Avenida Bolívar'), 'Lavandería', 'Lavado y planchado por bolsa', 26000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Avenida Bolívar'), 'Entradas Parque del Café', 'Pasaporte de ingreso al Parque Nacional del Café', 97000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Ejecutivo La Castellana'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 31000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Ejecutivo La Castellana'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 125000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Ejecutivo La Castellana'), 'Lavandería', 'Lavado y planchado por bolsa', 22000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Ejecutivo La Castellana'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 67000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Plaza Quimbaya Centro'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 32000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Plaza Quimbaya Centro'), 'Entradas Parque del Café', 'Pasaporte de ingreso al Parque Nacional del Café', 108000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Plaza Quimbaya Centro'), 'Lavandería', 'Lavado y planchado por bolsa', 24000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Plaza Quimbaya Centro'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 85000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Plaza Quimbaya Centro'), 'Entradas PANACA', 'Ingreso a PANACA con transporte', 119000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Plaza Quimbaya Centro'), 'Spa y masajes', 'Masaje relajante de 60 minutos con aceites de café', 153000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Gran Hotel Guadua Real'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 36000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Gran Hotel Guadua Real'), 'Entradas PANACA', 'Ingreso a PANACA con transporte', 132000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Gran Hotel Guadua Real'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 87000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Gran Hotel Guadua Real'), 'Entradas Parque del Café', 'Pasaporte de ingreso al Parque Nacional del Café', 94000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Gran Hotel Guadua Real'), 'Spa y masajes', 'Masaje relajante de 60 minutos con aceites de café', 132000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Gran Hotel Guadua Real'), 'Lavandería', 'Lavado y planchado por bolsa', 39000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Los Fundadores Suites'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 31000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Los Fundadores Suites'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 70000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Los Fundadores Suites'), 'Entradas PANACA', 'Ingreso a PANACA con transporte', 109000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal La Calle Catorce'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 20000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal La Calle Catorce'), 'Lavandería', 'Lavado y planchado por bolsa', 31000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal La Calle Catorce'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 85000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal La Calle Catorce'), 'Alquiler de bicicletas', 'Bicicleta de montaña con casco por día', 40000, 'POR_DIA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal La Calle Catorce'), 'Tour Valle de Cocora', 'Excursión guiada al Valle de Cocora y palmas de cera', 80000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Ruta del Café Armenia'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 22000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Ruta del Café Armenia'), 'Tour Valle de Cocora', 'Excursión guiada al Valle de Cocora y palmas de cera', 72000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Ruta del Café Armenia'), 'Alquiler de bicicletas', 'Bicicleta de montaña con casco por día', 55000, 'POR_DIA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Ruta del Café Armenia'), 'Lavandería', 'Lavado y planchado por bolsa', 27000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Ruta del Café Armenia'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 76000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Barrio Laureles'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 29000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Barrio Laureles'), 'Lavandería', 'Lavado y planchado por bolsa', 23000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Barrio Laureles'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 61000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera El Edén Urbano'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 28000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera El Edén Urbano'), 'Cabalgata', 'Cabalgata guiada de 2 horas por senderos rurales', 58000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera El Edén Urbano'), 'Entradas Parque del Café', 'Pasaporte de ingreso al Parque Nacional del Café', 113000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera El Edén Urbano'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 87000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Ecohotel Bosque de Yarumos'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 34000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Ecohotel Bosque de Yarumos'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 78000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Ecohotel Bosque de Yarumos'), 'Cabalgata', 'Cabalgata guiada de 2 horas por senderos rurales', 83000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Ecohotel Bosque de Yarumos'), 'Avistamiento de aves', 'Salida de madrugada con guía ornitólogo', 109000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Ecohotel Bosque de Yarumos'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 55000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Calle Real de Salento'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 23000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Calle Real de Salento'), 'Alquiler de bicicletas', 'Bicicleta de montaña con casco por día', 40000, 'POR_DIA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Calle Real de Salento'), 'Lavandería', 'Lavado y planchado por bolsa', 24000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Mochileros del Cocora'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 18000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Mochileros del Cocora'), 'Lavandería', 'Lavado y planchado por bolsa', 27000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Mochileros del Cocora'), 'Tour Valle de Cocora', 'Excursión guiada al Valle de Cocora y palmas de cera', 80000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Balcones de Colores'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 23000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Balcones de Colores'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 80000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Balcones de Colores'), 'Lavandería', 'Lavado y planchado por bolsa', 30000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Balcones de Colores'), 'Alquiler de bicicletas', 'Bicicleta de montaña con casco por día', 46000, 'POR_DIA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Balcones de Colores'), 'Tour Valle de Cocora', 'Excursión guiada al Valle de Cocora y palmas de cera', 84000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Domos del Valle de Cocora'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 21000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Domos del Valle de Cocora'), 'Avistamiento de aves', 'Salida de madrugada con guía ornitólogo', 79000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Domos del Valle de Cocora'), 'Jacuzzi privado', 'Jacuzzi al aire libre por 2 horas', 75000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Domos del Valle de Cocora'), 'Fogata y asado', 'Kit de fogata con asado para el grupo', 105000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Domos del Valle de Cocora'), 'Cena romántica', 'Cena para dos con decoración especial', 188000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Domos del Valle de Cocora'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 79000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Palma de Cera'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 36000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Palma de Cera'), 'Tour Valle de Cocora', 'Excursión guiada al Valle de Cocora y palmas de cera', 88000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Palma de Cera'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 153000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Palma de Cera'), 'Avistamiento de aves', 'Salida de madrugada con guía ornitólogo', 113000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Palma de Cera'), 'Jacuzzi privado', 'Jacuzzi al aire libre por 2 horas', 70000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera La Aldea del Alto'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 25000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera La Aldea del Alto'), 'Fogata y asado', 'Kit de fogata con asado para el grupo', 128000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera La Aldea del Alto'), 'Entradas Parque del Café', 'Pasaporte de ingreso al Parque Nacional del Café', 107000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca El Recreo de Boquía'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 33000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca El Recreo de Boquía'), 'Avistamiento de aves', 'Salida de madrugada con guía ornitólogo', 95000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca El Recreo de Boquía'), 'Tour Valle de Cocora', 'Excursión guiada al Valle de Cocora y palmas de cera', 102000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Mirador Alto de la Cruz'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 33000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Mirador Alto de la Cruz'), 'Parqueadero', 'Parqueadero cubierto por noche', 11000, 'POR_DIA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Mirador Alto de la Cruz'), 'Spa y masajes', 'Masaje relajante de 60 minutos con aceites de café', 148000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Mirador Alto de la Cruz'), 'Entradas Parque del Café', 'Pasaporte de ingreso al Parque Nacional del Café', 111000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Mirador Alto de la Cruz'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 52000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Mirador Alto de la Cruz'), 'Lavandería', 'Lavado y planchado por bolsa', 31000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Colonial Plaza Bolívar'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 22000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Colonial Plaza Bolívar'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 58000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Colonial Plaza Bolívar'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 72000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Ecohotel Reserva Río Quindío'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 23000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Ecohotel Reserva Río Quindío'), 'Avistamiento de aves', 'Salida de madrugada con guía ornitólogo', 89000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Ecohotel Reserva Río Quindío'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 83000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Ecohotel Reserva Río Quindío'), 'Tour Valle de Cocora', 'Excursión guiada al Valle de Cocora y palmas de cera', 120000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Ecohotel Reserva Río Quindío'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 59000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Ecohotel Reserva Río Quindío'), 'Cabalgata', 'Cabalgata guiada de 2 horas por senderos rurales', 85000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Colina Iluminada'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 23000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Colina Iluminada'), 'Fogata y asado', 'Kit de fogata con asado para el grupo', 136000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Colina Iluminada'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 73000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Colina Iluminada'), 'Jacuzzi privado', 'Jacuzzi al aire libre por 2 horas', 100000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Colina Iluminada'), 'Cena romántica', 'Cena para dos con decoración especial', 169000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Colina Iluminada'), 'Avistamiento de aves', 'Salida de madrugada con guía ornitólogo', 79000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Bosque de Bambú'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 20000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Bosque de Bambú'), 'Cena romántica', 'Cena para dos con decoración especial', 208000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Bosque de Bambú'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 138000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Los Cerezos'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 35000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Los Cerezos'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 99000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Los Cerezos'), 'Clase de barismo', 'Taller de métodos de preparación de café', 69000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Los Cerezos'), 'Avistamiento de aves', 'Salida de madrugada con guía ornitólogo', 86000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Los Cerezos'), 'Cabalgata', 'Cabalgata guiada de 2 horas por senderos rurales', 87000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Los Cerezos'), 'Entradas Parque del Café', 'Pasaporte de ingreso al Parque Nacional del Café', 105000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca La Herencia Filandeña'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 26000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca La Herencia Filandeña'), 'Clase de barismo', 'Taller de métodos de preparación de café', 77000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca La Herencia Filandeña'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 135000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal El Mirador Filandia'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 21000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal El Mirador Filandia'), 'Alquiler de bicicletas', 'Bicicleta de montaña con casco por día', 51000, 'POR_DIA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal El Mirador Filandia'), 'Lavandería', 'Lavado y planchado por bolsa', 34000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal El Mirador Filandia'), 'Tour Valle de Cocora', 'Excursión guiada al Valle de Cocora y palmas de cera', 113000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal El Mirador Filandia'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 74000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Bahareque'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 30000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Bahareque'), 'Tour Valle de Cocora', 'Excursión guiada al Valle de Cocora y palmas de cera', 87000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Bahareque'), 'Alquiler de bicicletas', 'Bicicleta de montaña con casco por día', 36000, 'POR_DIA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Casona del Parque Filandia'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 31000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Casona del Parque Filandia'), 'Entradas Parque del Café', 'Pasaporte de ingreso al Parque Nacional del Café', 84000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Casona del Parque Filandia'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 131000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Casona del Parque Filandia'), 'Spa y masajes', 'Masaje relajante de 60 minutos con aceites de café', 107000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Casona del Parque Filandia'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 63000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Casona del Parque Filandia'), 'Lavandería', 'Lavado y planchado por bolsa', 29000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Hotel Puerto Espejo'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 25000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Hotel Puerto Espejo'), 'Avistamiento de aves', 'Salida de madrugada con guía ornitólogo', 105000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Hotel Puerto Espejo'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 60000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Hotel Puerto Espejo'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 152000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Hotel Puerto Espejo'), 'Fogata y asado', 'Kit de fogata con asado para el grupo', 162000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Hotel Puerto Espejo'), 'Clase de barismo', 'Taller de métodos de preparación de café', 77000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Villa Laura'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 19000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Villa Laura'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 65000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Villa Laura'), 'Cabalgata', 'Cabalgata guiada de 2 horas por senderos rurales', 86000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Villa Laura'), 'Avistamiento de aves', 'Salida de madrugada con guía ornitólogo', 103000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Villa Laura'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 55000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca El Ocaso Cafetero'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 26000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca El Ocaso Cafetero'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 75000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca El Ocaso Cafetero'), 'Cabalgata', 'Cabalgata guiada de 2 horas por senderos rurales', 67000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Bambusa'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 27000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Bambusa'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 62000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Bambusa'), 'Cabalgata', 'Cabalgata guiada de 2 horas por senderos rurales', 65000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Entrada al Parque'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 24000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Entrada al Parque'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 89000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Entrada al Parque'), 'Entradas PANACA', 'Ingreso a PANACA con transporte', 93000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Entrada al Parque'), 'Spa y masajes', 'Masaje relajante de 60 minutos con aceites de café', 151000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Entrada al Parque'), 'Lavandería', 'Lavado y planchado por bolsa', 27000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Pueblo Tapao Plaza'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 31000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Pueblo Tapao Plaza'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 52000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Pueblo Tapao Plaza'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 131000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Mirador de Pisamal'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 27000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Mirador de Pisamal'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 129000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Mirador de Pisamal'), 'Jacuzzi privado', 'Jacuzzi al aire libre por 2 horas', 125000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Las Acacias'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 21000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Las Acacias'), 'Clase de barismo', 'Taller de métodos de preparación de café', 70000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Las Acacias'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 79000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Los Guaduales de Panaca'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 30000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Los Guaduales de Panaca'), 'Entradas Parque del Café', 'Pasaporte de ingreso al Parque Nacional del Café', 86000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Los Guaduales de Panaca'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 73000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Los Guaduales de Panaca'), 'Avistamiento de aves', 'Salida de madrugada con guía ornitólogo', 95000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca La Montaña Luminosa'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 29000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca La Montaña Luminosa'), 'Clase de barismo', 'Taller de métodos de preparación de café', 65000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca La Montaña Luminosa'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 88000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca La Montaña Luminosa'), 'Avistamiento de aves', 'Salida de madrugada con guía ornitólogo', 102000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Alumbrado de Velas'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 24000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Alumbrado de Velas'), 'Entradas PANACA', 'Ingreso a PANACA con transporte', 92000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Alumbrado de Velas'), 'Spa y masajes', 'Masaje relajante de 60 minutos con aceites de café', 106000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Campestre El Arriero'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 31000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Campestre El Arriero'), 'Parqueadero', 'Parqueadero cubierto por noche', 19000, 'POR_DIA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Campestre El Arriero'), 'Spa y masajes', 'Masaje relajante de 60 minutos con aceites de café', 98000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Estrellas de Quimbaya'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 22000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Estrellas de Quimbaya'), 'Avistamiento de aves', 'Salida de madrugada con guía ornitólogo', 108000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Estrellas de Quimbaya'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 74000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Estrellas de Quimbaya'), 'Fogata y asado', 'Kit de fogata con asado para el grupo', 106000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Jardín Botánico'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 28000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Jardín Botánico'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 98000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Jardín Botánico'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 69000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Jardín Botánico'), 'Lavandería', 'Lavado y planchado por bolsa', 23000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Jardín Botánico'), 'Parqueadero', 'Parqueadero cubierto por noche', 20000, 'POR_DIA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera La Rochela'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 23000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera La Rochela'), 'Entradas Parque del Café', 'Pasaporte de ingreso al Parque Nacional del Café', 109000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera La Rochela'), 'Cabalgata', 'Cabalgata guiada de 2 horas por senderos rurales', 63000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera La Rochela'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 85000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera La Rochela'), 'Fogata y asado', 'Kit de fogata con asado para el grupo', 146000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera La Rochela'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 91000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca El Mariposario'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 24000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca El Mariposario'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 90000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca El Mariposario'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 53000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca El Mariposario'), 'Fogata y asado', 'Kit de fogata con asado para el grupo', 147000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca El Mariposario'), 'Clase de barismo', 'Taller de métodos de preparación de café', 67000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca El Mariposario'), 'Cabalgata', 'Cabalgata guiada de 2 horas por senderos rurales', 78000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Alto del Río'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 23000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Alto del Río'), 'Tour Valle de Cocora', 'Excursión guiada al Valle de Cocora y palmas de cera', 111000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Alto del Río'), 'Alquiler de bicicletas', 'Bicicleta de montaña con casco por día', 44000, 'POR_DIA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Ecohotel Cañón del Quindío'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 23000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Ecohotel Cañón del Quindío'), 'Spa y masajes', 'Masaje relajante de 60 minutos con aceites de café', 153000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Ecohotel Cañón del Quindío'), 'Cabalgata', 'Cabalgata guiada de 2 horas por senderos rurales', 68000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Ecohotel Cañón del Quindío'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 120000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Ecohotel Cañón del Quindío'), 'Avistamiento de aves', 'Salida de madrugada con guía ornitólogo', 79000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Santa Ana de Calarcá'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 22000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Santa Ana de Calarcá'), 'Cabalgata', 'Cabalgata guiada de 2 horas por senderos rurales', 66000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Santa Ana de Calarcá'), 'Clase de barismo', 'Taller de métodos de preparación de café', 81000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Santa Ana de Calarcá'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 128000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Santa Ana de Calarcá'), 'Fogata y asado', 'Kit de fogata con asado para el grupo', 105000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera La Pradera de Circasia'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 26000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera La Pradera de Circasia'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 65000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera La Pradera de Circasia'), 'Fogata y asado', 'Kit de fogata con asado para el grupo', 77000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera La Pradera de Circasia'), 'Clase de barismo', 'Taller de métodos de preparación de café', 64000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera La Pradera de Circasia'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 72000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera La Pradera de Circasia'), 'Entradas Parque del Café', 'Pasaporte de ingreso al Parque Nacional del Café', 112000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca La Cabaña de Barcelona'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 31000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca La Cabaña de Barcelona'), 'Clase de barismo', 'Taller de métodos de preparación de café', 63000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca La Cabaña de Barcelona'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 64000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca La Cabaña de Barcelona'), 'Avistamiento de aves', 'Salida de madrugada con guía ornitólogo', 106000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca La Cabaña de Barcelona'), 'Cabalgata', 'Cabalgata guiada de 2 horas por senderos rurales', 66000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Mirador de Circasia'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 23000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Mirador de Circasia'), 'Alquiler de bicicletas', 'Bicicleta de montaña con casco por día', 36000, 'POR_DIA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Mirador de Circasia'), 'Tour Valle de Cocora', 'Excursión guiada al Valle de Cocora y palmas de cera', 70000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Mirador de Circasia'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 59000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Alto de la Cruz Circasia'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 25000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Alto de la Cruz Circasia'), 'Avistamiento de aves', 'Salida de madrugada con guía ornitólogo', 71000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Alto de la Cruz Circasia'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 134000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Alto de la Cruz Circasia'), 'Fogata y asado', 'Kit de fogata con asado para el grupo', 130000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Aeropuerto El Edén'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 28000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Aeropuerto El Edén'), 'Lavandería', 'Lavado y planchado por bolsa', 35000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Aeropuerto El Edén'), 'Entradas PANACA', 'Ingreso a PANACA con transporte', 106000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Aeropuerto El Edén'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 85000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Mangos Viejos'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 27000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Mangos Viejos'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 80000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Mangos Viejos'), 'Fogata y asado', 'Kit de fogata con asado para el grupo', 131000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Mangos Viejos'), 'Cabalgata', 'Cabalgata guiada de 2 horas por senderos rurales', 68000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Mangos Viejos'), 'Avistamiento de aves', 'Salida de madrugada con guía ornitólogo', 102000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Mangos Viejos'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 73000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Los Samanes'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 30000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Los Samanes'), 'Fogata y asado', 'Kit de fogata con asado para el grupo', 98000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Los Samanes'), 'Clase de barismo', 'Taller de métodos de preparación de café', 77000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Los Samanes'), 'Avistamiento de aves', 'Salida de madrugada con guía ornitólogo', 103000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Los Samanes'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 83000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Los Samanes'), 'Entradas Parque del Café', 'Pasaporte de ingreso al Parque Nacional del Café', 100000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Estación Tebaida'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 23000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Estación Tebaida'), 'Tour Valle de Cocora', 'Excursión guiada al Valle de Cocora y palmas de cera', 104000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Estación Tebaida'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 70000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Estación Tebaida'), 'Lavandería', 'Lavado y planchado por bolsa', 22000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Mirador del Valle Buenavista'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 25000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Mirador del Valle Buenavista'), 'Fogata y asado', 'Kit de fogata con asado para el grupo', 127000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Mirador del Valle Buenavista'), 'Cabalgata', 'Cabalgata guiada de 2 horas por senderos rurales', 88000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Mirador del Valle Buenavista'), 'Avistamiento de aves', 'Salida de madrugada con guía ornitólogo', 112000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Mirador del Valle Buenavista'), 'Entradas Parque del Café', 'Pasaporte de ingreso al Parque Nacional del Café', 89000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Mirador del Valle Buenavista'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 74000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Pueblo Sin Prisa'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 25000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Pueblo Sin Prisa'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 87000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera Pueblo Sin Prisa'), 'Entradas Parque del Café', 'Pasaporte de ingreso al Parque Nacional del Café', 95000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca El Páramo de Génova'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 19000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca El Páramo de Génova'), 'Transporte aeropuerto El Edén', 'Traslado privado desde o hacia el aeropuerto El Edén', 135000, 'POR_SERVICIO');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca El Páramo de Génova'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 60000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Quebrada Córdoba'), 'Desayuno típico', 'Calentado paisa o desayuno continental con café de origen', 20000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Quebrada Córdoba'), 'Alquiler de bicicletas', 'Bicicleta de montaña con casco por día', 54000, 'POR_DIA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Quebrada Córdoba'), 'Tour Valle de Cocora', 'Excursión guiada al Valle de Cocora y palmas de cera', 114000, 'POR_PERSONA');
INSERT INTO servicio (id_alojamiento, nombre, descripcion, precio, unidad_cobro) VALUES ((SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Quebrada Córdoba'), 'Tour del café', 'Recorrido por el cafetal, beneficio y catación guiada', 80000, 'POR_PERSONA');
COMMIT;

/* =====================================================================
   4. Habitaciones (asimétrico)
   Hoteles de Armenia: 30-40; hoteles de otros municipios: 12-24;
   fincas cafeteras: 3-6; glampings: 3-8; hostales: 6-12; ecohoteles: 8-14.
   Los hoteles numeran por piso (101, 102...); los demás con prefijo.
   ===================================================================== */
PROMPT 4. Habitaciones...

DECLARE
   v_n     PLS_INTEGER;
   v_tipo  VARCHAR2(10);
   v_cap   PLS_INTEGER;
   v_num   VARCHAR2(10);
   v_desc  VARCHAR2(250);
   v_u     NUMBER;
   v_total PLS_INTEGER := 0;
BEGIN
   DBMS_RANDOM.SEED(2026201);
   FOR a IN (SELECT id_alojamiento, id_tipo, id_municipio
             FROM   alojamiento
             ORDER  BY id_alojamiento) LOOP

      -- 4.1 Cantidad de habitaciones según tipo (y municipio para hoteles)
      v_n := CASE a.id_tipo
                WHEN 2 THEN CASE WHEN a.id_municipio = 1
                                 THEN TRUNC(DBMS_RANDOM.VALUE(30, 41))
                                 ELSE TRUNC(DBMS_RANDOM.VALUE(12, 25)) END
                WHEN 1 THEN TRUNC(DBMS_RANDOM.VALUE(3, 7))
                WHEN 3 THEN TRUNC(DBMS_RANDOM.VALUE(3, 9))
                WHEN 4 THEN TRUNC(DBMS_RANDOM.VALUE(6, 13))
                ELSE        TRUNC(DBMS_RANDOM.VALUE(8, 15))
             END;

      FOR k IN 1 .. v_n LOOP
         -- 4.2 Tipo y capacidad de la habitación según el tipo de alojamiento
         v_u := DBMS_RANDOM.VALUE;
         IF a.id_tipo = 2 THEN                                   -- hotel
            IF    v_u < 0.30 THEN v_tipo := 'SENCILLA'; v_cap := TRUNC(DBMS_RANDOM.VALUE(1, 3));
            ELSIF v_u < 0.82 THEN v_tipo := 'DOBLE';    v_cap := TRUNC(DBMS_RANDOM.VALUE(2, 4));
            ELSE                  v_tipo := 'SUITE';    v_cap := TRUNC(DBMS_RANDOM.VALUE(2, 5));
            END IF;
            v_num := TO_CHAR((TRUNC((k - 1) / 10) + 1) * 100 + MOD(k - 1, 10) + 1);
         ELSIF a.id_tipo = 1 THEN                                -- finca cafetera
            IF    v_u < 0.50 THEN v_tipo := 'DOBLE';  v_cap := TRUNC(DBMS_RANDOM.VALUE(2, 5));
            ELSIF v_u < 0.80 THEN v_tipo := 'CABANA'; v_cap := TRUNC(DBMS_RANDOM.VALUE(4, 9));
            ELSE                  v_tipo := 'SUITE';  v_cap := TRUNC(DBMS_RANDOM.VALUE(2, 4));
            END IF;
            v_num := 'F' || LPAD(k, 2, '0');
         ELSIF a.id_tipo = 3 THEN                                -- glamping
            IF v_u < 0.70 THEN v_tipo := 'CABANA'; v_cap := TRUNC(DBMS_RANDOM.VALUE(2, 4));
            ELSE               v_tipo := 'SUITE';  v_cap := TRUNC(DBMS_RANDOM.VALUE(2, 5));
            END IF;
            v_num := 'D' || LPAD(k, 2, '0');
         ELSIF a.id_tipo = 4 THEN                                -- hostal
            IF v_u < 0.45 THEN v_tipo := 'SENCILLA'; v_cap := TRUNC(DBMS_RANDOM.VALUE(1, 3));
            ELSE               v_tipo := 'DOBLE';    v_cap := TRUNC(DBMS_RANDOM.VALUE(2, 5));
            END IF;
            v_num := 'H' || LPAD(k, 2, '0');
         ELSE                                                    -- ecohotel
            IF    v_u < 0.40 THEN v_tipo := 'DOBLE';  v_cap := TRUNC(DBMS_RANDOM.VALUE(2, 4));
            ELSIF v_u < 0.80 THEN v_tipo := 'CABANA'; v_cap := TRUNC(DBMS_RANDOM.VALUE(3, 7));
            ELSE                  v_tipo := 'SUITE';  v_cap := TRUNC(DBMS_RANDOM.VALUE(2, 5));
            END IF;
            v_num := 'E' || LPAD(k, 2, '0');
         END IF;

         v_desc := CASE v_tipo
                      WHEN 'SENCILLA' THEN 'Habitación sencilla con cama semidoble y baño privado'
                      WHEN 'DOBLE'    THEN 'Habitación doble con cama queen o dos camas'
                      WHEN 'SUITE'    THEN 'Suite con sala, balcón y vista a la cordillera'
                      ELSE                 'Cabaña independiente rodeada de guaduales y cafetales'
                   END || ' (capacidad ' || v_cap || ')';

         INSERT INTO habitacion (id_alojamiento, numero, tipo_habitacion, capacidad_max, descripcion)
         VALUES (a.id_alojamiento, v_num, v_tipo, v_cap, v_desc);
         v_total := v_total + 1;
      END LOOP;
   END LOOP;
   COMMIT;
   DBMS_OUTPUT.PUT_LINE('   Habitaciones creadas: ' || v_total);
END;
/

/* =====================================================================
   5. Tarifas: una por cada habitación x temporada (se deriva del cruce)
   Precio = base(tipo alojamiento, tipo habitación)
            x estrellas x capacidad x ruido por habitación
            x factor de la categoría PROPIO DE CADA ALOJAMIENTO
            x subfactor de la temporada x inflación anual.
   El factor de ALTA va de 1,10 a 1,65: hay alojamientos que casi no
   suben en temporada alta para competir por volumen.
   ===================================================================== */
PROMPT 5. Tarifas (cruce habitación x temporada)...

DECLARE
   TYPE t_num  IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
   TYPE t_temp IS TABLE OF temporada%ROWTYPE;
   f_alta  t_num;
   f_media t_num;
   f_baja  t_num;
   v_temps t_temp;
   v_base  NUMBER;
   v_f     NUMBER;
   v_infl  NUMBER;
   v_total PLS_INTEGER := 0;
BEGIN
   DBMS_RANDOM.SEED(2026202);

   -- 5.1 Política de precios de cada alojamiento
   FOR a IN (SELECT id_alojamiento FROM alojamiento ORDER BY id_alojamiento) LOOP
      f_alta(a.id_alojamiento)  := DBMS_RANDOM.VALUE(1.10, 1.65);
      f_media(a.id_alojamiento) := DBMS_RANDOM.VALUE(0.95, 1.12);
      f_baja(a.id_alojamiento)  := DBMS_RANDOM.VALUE(0.72, 0.92);
   END LOOP;

   SELECT * BULK COLLECT INTO v_temps FROM temporada ORDER BY fecha_inicio;

   -- 5.2 Recorrer habitaciones y generar su tarifa en cada temporada
   FOR h IN (SELECT h.id_habitacion, h.id_alojamiento, h.tipo_habitacion,
                    h.capacidad_max, a.id_tipo, a.estrellas
             FROM   habitacion h
             JOIN   alojamiento a ON a.id_alojamiento = h.id_alojamiento
             ORDER  BY h.id_habitacion) LOOP

      v_base := CASE h.id_tipo
                   WHEN 2 THEN CASE h.tipo_habitacion WHEN 'SENCILLA' THEN 120000 WHEN 'DOBLE' THEN 180000 ELSE 320000 END
                   WHEN 1 THEN CASE h.tipo_habitacion WHEN 'DOBLE' THEN 220000 WHEN 'CABANA' THEN 380000 WHEN 'SUITE' THEN 300000 ELSE 150000 END
                   WHEN 3 THEN CASE h.tipo_habitacion WHEN 'SUITE' THEN 460000 ELSE 340000 END
                   WHEN 4 THEN CASE h.tipo_habitacion WHEN 'SENCILLA' THEN 55000 ELSE 85000 END
                   ELSE        CASE h.tipo_habitacion WHEN 'CABANA' THEN 330000 WHEN 'SUITE' THEN 390000 WHEN 'SENCILLA' THEN 150000 ELSE 210000 END
                END;
      v_base := v_base * (0.70 + 0.12 * h.estrellas)
                       * (1 + 0.08 * GREATEST(h.capacidad_max - 2, 0))
                       * DBMS_RANDOM.VALUE(0.92, 1.08);

      FOR i IN 1 .. v_temps.COUNT LOOP
         -- factor de la categoría según la política del alojamiento
         v_f := CASE v_temps(i).categoria
                   WHEN 'ALTA'  THEN f_alta(h.id_alojamiento)
                   WHEN 'MEDIA' THEN f_media(h.id_alojamiento)
                   ELSE              f_baja(h.id_alojamiento)
                END;
         -- subfactor: no todas las temporadas altas valen lo mismo
         IF v_temps(i).nombre LIKE 'Alta puente%' THEN
            v_f := 1 + (v_f - 1) * 0.75;
         ELSIF v_temps(i).nombre LIKE 'Alta fin de a%' THEN
            v_f := v_f * 1.06;
         ELSIF v_temps(i).nombre LIKE 'Alta vacaciones%' THEN
            v_f := v_f * 0.97;
         END IF;
         v_infl := CASE v_temps(i).anio WHEN 2024 THEN 1.00 WHEN 2025 THEN 1.06
                                        WHEN 2026 THEN 1.11 ELSE 1.16 END;

         INSERT INTO tarifa (id_habitacion, id_temporada, valor_noche, fecha_actualizacion)
         VALUES (h.id_habitacion, v_temps(i).id_temporada,
                 GREATEST(ROUND(v_base * v_f * v_infl, -3), 30000),
                 v_temps(i).fecha_inicio - 60);
         v_total := v_total + 1;
      END LOOP;
   END LOOP;
   COMMIT;
   DBMS_OUTPUT.PUT_LINE('   Tarifas creadas: ' || v_total);
END;
/

/* =====================================================================
   6. Clientes (3.000) con ciudades de origen ponderadas:
   Bogotá, Medellín y Cali dominan; ~11 % son extranjeros.
   ===================================================================== */
PROMPT 6. Clientes...

DECLARE
   TYPE t_txt IS TABLE OF VARCHAR2(60);
   TYPE t_num IS TABLE OF NUMBER;
   v_nom  t_txt := t_txt('Juan','María','Carlos','Ana','Luis','Laura','Andrés','Valentina','Santiago','Camila',
                         'Jorge','Daniela','Felipe','Natalia','Diego','Paula','Sebastián','Sofía','Alejandro','Isabella',
                         'Mateo','Mariana','David','Juliana','Nicolás','Catalina','Esteban','Manuela','Julián','Carolina',
                         'Ricardo','Gabriela','Óscar','Lucía','Mauricio','Diana','Hernán','Paola','Tomás','Sara');
   v_ape  t_txt := t_txt('García','Rodríguez','Martínez','López','González','Hernández','Pérez','Sánchez','Ramírez','Torres',
                         'Flórez','Rivera','Gómez','Díaz','Cardona','Morales','Ortiz','Castaño','Giraldo','Ospina',
                         'Restrepo','Valencia','Arango','Henao','Mejía','Londoño','Montoya','Quintero','Salazar','Zuluaga',
                         'Velásquez','Duque','Muñoz','Rojas','Vargas','Jiménez','Moreno','Correa','Álvarez','Toro');
   v_ciu  t_txt := t_txt('Bogotá','Medellín','Cali','Pereira','Armenia','Manizales','Ibagué','Barranquilla','Bucaramanga',
                         'Cartagena','Villavicencio','Neiva','Cúcuta','Santa Marta','Pasto','Tunja','Popayán','Calarcá',
                         'Tuluá','Palmira','Cartago','Montería','Chía','Envigado',
                         'Madrid','Ciudad de México','Miami','Nueva York','Buenos Aires','Santiago de Chile','Quito',
                         'Lima','Caracas','Toronto','Berlín','París','Ámsterdam','Londres');
   v_pais t_txt := t_txt('Colombia','Colombia','Colombia','Colombia','Colombia','Colombia','Colombia','Colombia','Colombia',
                         'Colombia','Colombia','Colombia','Colombia','Colombia','Colombia','Colombia','Colombia','Colombia',
                         'Colombia','Colombia','Colombia','Colombia','Colombia','Colombia',
                         'España','México','Estados Unidos','Estados Unidos','Argentina','Chile','Ecuador',
                         'Perú','Venezuela','Canadá','Alemania','Francia','Países Bajos','Reino Unido');
   v_ind  t_txt := t_txt('34','52','1','1','54','56','593','51','58','1','49','33','31','44');  -- indicativos extranjeros
   v_peso t_num := t_num(24,14,11,6,4,4,3,3,3,2,2,2,1.5,1.2,1,1,1,0.8,1,1,1,0.8,0.8,1,
                         1.5,1.2,1.2,0.8,0.8,0.7,0.8,0.7,0.8,0.5,0.5,0.5,0.4,0.4);
   v_dom  t_txt := t_txt('gmail.com','gmail.com','gmail.com','hotmail.com','hotmail.com','outlook.com','yahoo.com','correo.com.co');
   v_suma   NUMBER := 0;
   v_x      NUMBER;
   v_c      PLS_INTEGER;
   v_n1     VARCHAR2(60);
   v_n2     VARCHAR2(60);
   v_a1     VARCHAR2(60);
   v_a2     VARCHAR2(60);
   v_tdoc   VARCHAR2(3);
   v_ndoc   VARCHAR2(20);
   v_tel    VARCHAR2(20);
   v_correo VARCHAR2(120);

   FUNCTION f_item(p_lista t_txt) RETURN VARCHAR2 IS
   BEGIN
      RETURN p_lista(TRUNC(DBMS_RANDOM.VALUE(1, p_lista.COUNT + 1)));
   END;
BEGIN
   DBMS_RANDOM.SEED(2026203);
   FOR i IN 1 .. v_peso.COUNT LOOP v_suma := v_suma + v_peso(i); END LOOP;

   FOR i IN 1 .. 3000 LOOP
      -- 6.1 Ciudad de origen por ruleta ponderada
      v_x := DBMS_RANDOM.VALUE(0, v_suma);
      v_c := 1;
      WHILE v_x > v_peso(v_c) AND v_c < v_peso.COUNT LOOP
         v_x := v_x - v_peso(v_c);
         v_c := v_c + 1;
      END LOOP;

      -- 6.2 Nombre y apellidos
      v_n1 := f_item(v_nom);
      v_n2 := CASE WHEN DBMS_RANDOM.VALUE < 0.4 THEN ' ' || f_item(v_nom) END;
      v_a1 := f_item(v_ape);
      v_a2 := f_item(v_ape);

      -- 6.3 Documento según nacionalidad (el número se construye con i para ser único)
      IF v_pais(v_c) = 'Colombia' THEN
         v_tdoc := 'CC';
         IF DBMS_RANDOM.VALUE < 0.3 THEN
            v_ndoc := TO_CHAR(10000000 + i * 29000 + TRUNC(DBMS_RANDOM.VALUE(0, 29000)));     -- cédula antigua (8 dígitos)
         ELSE
            v_ndoc := TO_CHAR(1000000000 + i * 2731 + TRUNC(DBMS_RANDOM.VALUE(0, 2731)));     -- 10 dígitos
         END IF;
         v_tel := '3' || LPAD(TRUNC(DBMS_RANDOM.VALUE(0, 25)), 2, '0') || ' '
                      || LPAD(TRUNC(DBMS_RANDOM.VALUE(0, 10000000)), 7, '0');
      ELSE
         IF v_pais(v_c) = 'Venezuela' THEN
            v_tdoc := 'PPT';
            v_ndoc := TO_CHAR(5000000 + i * 311 + TRUNC(DBMS_RANDOM.VALUE(0, 311)));
         ELSIF DBMS_RANDOM.VALUE < 0.15 THEN
            v_tdoc := 'CE';
            v_ndoc := LPAD(i * 37, 7, '0');
         ELSE
            v_tdoc := 'PA';
            v_ndoc := CHR(65 + TRUNC(DBMS_RANDOM.VALUE(0, 26))) || CHR(65 + TRUNC(DBMS_RANDOM.VALUE(0, 26)))
                      || LPAD(i, 7, '0');
         END IF;
         v_tel := '+' || v_ind(v_c - 24) || ' ' || LPAD(TRUNC(DBMS_RANDOM.VALUE(0, 1000000000)), 9, '0');
      END IF;

      -- 6.4 Correo único (sin tildes ni espacios) + consecutivo
      v_correo := TRANSLATE(LOWER(v_n1 || '.' || v_a1), 'áéíóúñü ', 'aeiounu') || i || '@' || f_item(v_dom);

      INSERT INTO cliente (tipo_documento, numero_documento, nombres, apellidos, correo,
                           telefono, ciudad_origen, pais_origen, fecha_registro)
      VALUES (v_tdoc, v_ndoc, v_n1 || v_n2, v_a1 || ' ' || v_a2, v_correo,
              v_tel, v_ciu(v_c), v_pais(v_c), DATE '2023-07-01' + TRUNC(DBMS_RANDOM.VALUE(0, 1150)));
   END LOOP;
   COMMIT;
   DBMS_OUTPUT.PUT_LINE('   Clientes creados: 3000');
END;
/

/* =====================================================================
   7. Reservas y todo lo que cuelga de ellas
   Para cada reserva:
     a) se sortea la fecha de check-in con peso por temporada
        (ALTA 3,2 / MEDIA 1,6 / BAJA 0,8), día de la semana, año y mes;
     b) se sortea el alojamiento con peso por popularidad;
     c) se sortean noches (1 a 14) y número de habitaciones (1 a 6);
     d) se buscan habitaciones LIBRES (mapa en memoria de noches
        ocupadas): nunca se generan solapamientos entre reservas no
        canceladas de la misma habitación;
     e) el valor de cada línea se calcula NOCHE POR NOCHE con la tarifa
        de la temporada de esa noche (misma lógica de fn_valor_estadia);
     f) servicios, pagos (único / anticipo + saldo / fallidos /
        reembolsos del 80 %) y reseñas (solo COMPLETADAS, ~47 %).
   ===================================================================== */
PROMPT 7. Reservas, líneas, servicios, pagos y reseñas (tarda unos minutos)...

DECLARE
   c_hoy            CONSTANT DATE := DATE '2026-10-17';   -- fecha de corte de los datos
   c_cal_ini        CONSTANT DATE := DATE '2024-01-01';   -- primer día del calendario (offset 0)
   c_in_fin         CONSTANT DATE := DATE '2026-12-31';   -- último check-in posible
   c_meta_reservas  CONSTANT PLS_INTEGER := 26500;
   c_meta_servicios CONSTANT PLS_INTEGER := 40500;

   TYPE t_num  IS TABLE OF NUMBER       INDEX BY PLS_INTEGER;
   TYPE t_txt  IS TABLE OF VARCHAR2(20) INDEX BY PLS_INTEGER;
   TYPE t_mapa IS TABLE OF NUMBER       INDEX BY VARCHAR2(24);

   -- alojamientos (índice 1..v_na)
   a_id      t_num;  a_acum  t_num;  a_calidad t_num;
   a_hab_ini t_num;  a_hab_n t_num;  a_srv_ini t_num;  a_srv_n t_num;
   v_na      PLS_INTEGER := 0;
   -- habitaciones y servicios (arreglos planos, agrupados por alojamiento)
   h_id   t_num;  h_cap    t_num;  v_nh PLS_INTEGER := 0;
   s_id   t_num;  s_precio t_num;  s_unidad t_txt;  v_ns PLS_INTEGER := 0;
   -- clientes
   cli_id t_num;  v_nc PLS_INTEGER := 0;
   -- calendario por offset (0 = 01-01-2024) y pesos de check-in
   d_temp t_num;  d_cat t_txt;  d_acum t_num;  v_nd PLS_INTEGER := 0;
   m_mes  t_num;                                   -- factor aleatorio por año-mes
   -- tarifas ('idHab-idTemp') y noches ocupadas ('idHab-offset')
   m_tarifa  t_mapa;
   m_ocupada t_mapa;
   -- reservas no canceladas (para la recarga de servicios)
   r_id t_num; r_ai t_num; r_in t_num; r_noches t_num; r_hues t_num; r_estado t_txt;
   v_nr PLS_INTEGER := 0;
   -- líneas de la reserva en construcción
   l_hab t_num; l_in t_num; l_out t_num; l_hues t_num; l_valor t_num;

   -- variables de trabajo
   v_off      PLS_INTEGER;   v_in      DATE;          v_out     DATE;
   v_noches   PLS_INTEGER;   v_ai      PLS_INTEGER;   v_nlin    PLS_INTEGER;
   v_estado   VARCHAR2(10);  v_fres    DATE;          v_fcan    DATE;
   v_lead     PLS_INTEGER;   v_ok      BOOLEAN;       v_libre   BOOLEAN;
   v_intentos PLS_INTEGER;   v_hi      PLS_INTEGER;   v_rid     NUMBER;
   v_total    NUMBER;        v_serv    NUMBER;        v_hues    PLS_INTEGER;
   v_u        NUMBER;        v_peso    NUMBER;        v_k       PLS_INTEGER;
   v_nsrv     PLS_INTEGER;   v_ini_s   PLS_INTEGER;   v_si      PLS_INTEGER;
   v_fser     DATE;          v_cant    PLS_INTEGER;   v_anti    NUMBER;
   v_calif    PLS_INTEGER;   v_ci      PLS_INTEGER;
   v_coment   VARCHAR2(500);
   v_creadas  PLS_INTEGER := 0;
   v_fallos   PLS_INTEGER := 0;
   v_lin_srv  PLS_INTEGER := 0;
   v_ref      PLS_INTEGER := 0;

   -- Ruleta: devuelve el índice cuyo acumulado cubre un número aleatorio (búsqueda binaria)
   FUNCTION f_pick(p_acum IN t_num, p_n IN PLS_INTEGER) RETURN PLS_INTEGER IS
      v_x  NUMBER := DBMS_RANDOM.VALUE(0, p_acum(p_n));
      v_lo PLS_INTEGER := 1;
      v_hi PLS_INTEGER := p_n;
      v_md PLS_INTEGER;
   BEGIN
      WHILE v_lo < v_hi LOOP
         v_md := TRUNC((v_lo + v_hi) / 2);
         IF p_acum(v_md) < v_x THEN v_lo := v_md + 1; ELSE v_hi := v_md; END IF;
      END LOOP;
      RETURN v_lo;
   END;

   -- Entero aleatorio uniforme entre p_a y p_b (ambos incluidos)
   FUNCTION f_ent(p_a IN NUMBER, p_b IN NUMBER) RETURN PLS_INTEGER IS
   BEGIN
      RETURN TRUNC(DBMS_RANDOM.VALUE(p_a, p_b + 1));
   END;

   -- Método de pago; el efectivo solo aparece en pagos presenciales (saldo al llegar)
   FUNCTION f_metodo(p_presencial IN BOOLEAN) RETURN VARCHAR2 IS
      v NUMBER := DBMS_RANDOM.VALUE;
   BEGIN
      IF p_presencial AND v < 0.35 THEN RETURN 'EFECTIVO'; END IF;
      v := DBMS_RANDOM.VALUE;
      RETURN CASE WHEN v < 0.38 THEN 'TARJETA_CREDITO'
                  WHEN v < 0.66 THEN 'PSE'
                  WHEN v < 0.86 THEN 'TARJETA_DEBITO'
                  ELSE               'TRANSFERENCIA' END;
   END;

   -- Comentario de la reseña acorde con la calificación (25 % sin comentario)
   FUNCTION f_comentario(p_calif IN PLS_INTEGER) RETURN VARCHAR2 IS
      TYPE t_l IS TABLE OF VARCHAR2(200);
      v_buenos t_l := t_l('Excelente atención y una vista espectacular de los cafetales.',
                          'Volveríamos sin dudarlo, el desayuno y el café son de otro nivel.',
                          'Todo muy limpio y el personal súper amable.',
                          'Perfecto para descansar en familia, muy tranquilo.',
                          'La mejor experiencia del viaje por el Quindío.');
      v_medios t_l := t_l('Buena ubicación, aunque las habitaciones necesitan mantenimiento.',
                          'Cumple, pero el precio es alto para lo que ofrece.',
                          'El lugar es bonito, el servicio fue lento.',
                          'Agradable, pero hubo ruido en la noche.');
      v_malos  t_l := t_l('No coincidía con las fotos publicadas.',
                          'Problemas con el agua caliente y nadie dio solución.',
                          'Mala atención en recepción y la habitación olía a humedad.',
                          'No lo recomiendo, cobraron servicios que no pedimos.');
   BEGIN
      IF DBMS_RANDOM.VALUE < 0.25 THEN RETURN NULL; END IF;
      IF p_calif >= 4 THEN
         RETURN v_buenos(TRUNC(DBMS_RANDOM.VALUE(1, v_buenos.COUNT + 1)));
      ELSIF p_calif = 3 THEN
         RETURN v_medios(TRUNC(DBMS_RANDOM.VALUE(1, v_medios.COUNT + 1)));
      ELSE
         RETURN v_malos(TRUNC(DBMS_RANDOM.VALUE(1, v_malos.COUNT + 1)));
      END IF;
   END;

   -- Inserta un pago; los métodos electrónicos reciben una referencia única
   PROCEDURE p_pago(p_reserva  IN NUMBER,   p_fecha   IN DATE,     p_monto IN NUMBER,
                    p_metodo   IN VARCHAR2, p_estado  IN VARCHAR2, p_concepto IN VARCHAR2,
                    p_reemb    IN NUMBER := 0, p_freemb IN DATE := NULL) IS
      v_r VARCHAR2(30);
   BEGIN
      IF p_metodo <> 'EFECTIVO' THEN
         v_ref := v_ref + 1;
         v_r   := 'TX' || LPAD(v_ref, 10, '0');
      END IF;
      INSERT INTO pago (id_reserva, fecha_pago, monto, metodo, estado, concepto,
                        monto_reembolsado, fecha_reembolso, referencia)
      VALUES (p_reserva, p_fecha, ROUND(p_monto, 2), p_metodo, p_estado, p_concepto,
              p_reemb, p_freemb, v_r);
   END;

BEGIN
   DBMS_RANDOM.SEED(2026205);

   -- 7.1 Alojamientos: popularidad = tamaño^0,75 x peso del municipio x azar
   FOR a IN (SELECT al.id_alojamiento, al.id_municipio, al.estrellas,
                    (SELECT COUNT(*) FROM habitacion h WHERE h.id_alojamiento = al.id_alojamiento) AS n_hab
             FROM   alojamiento al
             ORDER  BY al.id_alojamiento) LOOP
      v_na := v_na + 1;
      a_id(v_na) := a.id_alojamiento;
      v_peso := POWER(a.n_hab, 0.75)
              * CASE a.id_municipio
                   WHEN 12 THEN 2.2  WHEN 6 THEN 1.8  WHEN 1 THEN 1.5  WHEN 9 THEN 1.5
                   WHEN 11 THEN 1.3  WHEN 3 THEN 0.9  WHEN 4 THEN 0.9  WHEN 8 THEN 0.8
                   WHEN 2  THEN 0.8  WHEN 10 THEN 0.6 ELSE 0.5
                END
              * DBMS_RANDOM.VALUE(0.45, 1.8);
      IF v_na = 1 THEN a_acum(v_na) := v_peso; ELSE a_acum(v_na) := a_acum(v_na - 1) + v_peso; END IF;
      -- "calidad real" percibida por los huéspedes (no siempre coincide con las estrellas)
      a_calidad(v_na) := 0.6 * DBMS_RANDOM.VALUE(2.6, 4.9) + 0.4 * (2.5 + 0.45 * a.estrellas);

      a_hab_ini(v_na) := v_nh + 1;
      FOR h IN (SELECT id_habitacion, capacidad_max FROM habitacion
                WHERE id_alojamiento = a.id_alojamiento ORDER BY id_habitacion) LOOP
         v_nh := v_nh + 1;
         h_id(v_nh)  := h.id_habitacion;
         h_cap(v_nh) := h.capacidad_max;
      END LOOP;
      a_hab_n(v_na) := v_nh - a_hab_ini(v_na) + 1;

      a_srv_ini(v_na) := v_ns + 1;
      FOR s IN (SELECT id_servicio, precio, unidad_cobro FROM servicio
                WHERE id_alojamiento = a.id_alojamiento ORDER BY id_servicio) LOOP
         v_ns := v_ns + 1;
         s_id(v_ns)     := s.id_servicio;
         s_precio(v_ns) := s.precio;
         s_unidad(v_ns) := s.unidad_cobro;
      END LOOP;
      a_srv_n(v_na) := v_ns - a_srv_ini(v_na) + 1;
   END LOOP;

   -- 7.2 Clientes
   FOR c IN (SELECT id_cliente FROM cliente ORDER BY id_cliente) LOOP
      v_nc := v_nc + 1;
      cli_id(v_nc) := c.id_cliente;
   END LOOP;

   -- 7.3 Calendario en memoria y peso de cada día como fecha de check-in
   FOR d IN (SELECT c.fecha, c.id_temporada, c.dia_semana, c.anio, c.mes, t.categoria
             FROM   calendario c
             JOIN   temporada t ON t.id_temporada = c.id_temporada
             ORDER  BY c.fecha) LOOP
      v_off := d.fecha - c_cal_ini;
      d_temp(v_off) := d.id_temporada;
      d_cat(v_off)  := d.categoria;
      IF d.fecha <= c_in_fin THEN
         IF NOT m_mes.EXISTS(d.anio * 100 + d.mes) THEN
            m_mes(d.anio * 100 + d.mes) := DBMS_RANDOM.VALUE(0.80, 1.25);
         END IF;
         v_peso := CASE d.categoria WHEN 'ALTA' THEN 3.2 WHEN 'MEDIA' THEN 1.6 ELSE 0.8 END
                 * CASE d.dia_semana WHEN 5 THEN 1.7 WHEN 6 THEN 1.4 WHEN 4 THEN 1.0
                                     WHEN 7 THEN 0.8 ELSE 0.7 END
                 * CASE d.anio WHEN 2024 THEN 0.85 WHEN 2025 THEN 1.00 ELSE 1.12 END
                 * m_mes(d.anio * 100 + d.mes);
         v_nd := v_nd + 1;                      -- índice v_nd  <=>  offset v_nd - 1
         IF v_nd = 1 THEN d_acum(v_nd) := v_peso; ELSE d_acum(v_nd) := d_acum(v_nd - 1) + v_peso; END IF;
      END IF;
   END LOOP;

   -- 7.4 Tarifas en memoria
   FOR t IN (SELECT id_habitacion, id_temporada, valor_noche FROM tarifa) LOOP
      m_tarifa(t.id_habitacion || '-' || t.id_temporada) := t.valor_noche;
   END LOOP;

   -- 7.5 Ciclo principal
   WHILE v_creadas < c_meta_reservas LOOP
      IF v_fallos > 500000 THEN
         RAISE_APPLICATION_ERROR(-20020, 'Demasiados intentos fallidos generando reservas');
      END IF;

      -- a) fecha de check-in, noches y alojamiento
      v_off := f_pick(d_acum, v_nd) - 1;
      v_in  := c_cal_ini + v_off;
      v_u   := DBMS_RANDOM.VALUE;
      v_noches := CASE WHEN v_u < 0.18 THEN 1 WHEN v_u < 0.48 THEN 2 WHEN v_u < 0.70 THEN 3
                       WHEN v_u < 0.83 THEN 4 WHEN v_u < 0.90 THEN 5 WHEN v_u < 0.94 THEN 6
                       WHEN v_u < 0.98 THEN 7 ELSE f_ent(8, 14) END;
      IF d_cat(v_off) = 'ALTA' AND DBMS_RANDOM.VALUE < 0.30 THEN
         v_noches := v_noches + 1;               -- en temporada alta las estadías son más largas
      END IF;
      v_out := v_in + v_noches;
      v_ai  := f_pick(a_acum, v_na);

      -- b) número de habitaciones (la mayoría 1; grupos hasta 6)
      v_u    := DBMS_RANDOM.VALUE;
      v_nlin := CASE WHEN v_u < 0.84 THEN 1 WHEN v_u < 0.95 THEN 2
                     WHEN v_u < 0.985 THEN 3 ELSE f_ent(4, 6) END;
      v_nlin := LEAST(v_nlin, a_hab_n(v_ai));

      -- c) estado según la fecha de corte
      IF v_out <= c_hoy THEN
         v_estado := CASE WHEN DBMS_RANDOM.VALUE < 0.14 THEN 'CANCELADA' ELSE 'COMPLETADA' END;
      ELSIF v_in <= c_hoy THEN
         v_estado := CASE WHEN DBMS_RANDOM.VALUE < 0.08 THEN 'CANCELADA' ELSE 'CONFIRMADA' END;
      ELSE
         v_u := DBMS_RANDOM.VALUE;
         v_estado := CASE WHEN v_u < 0.12 THEN 'CANCELADA'
                          WHEN v_u < 0.32 THEN 'PENDIENTE' ELSE 'CONFIRMADA' END;
      END IF;

      -- d) buscar habitaciones libres para cada línea
      v_ok := TRUE;
      FOR k IN 1 .. v_nlin LOOP
         l_in(k)  := v_off;
         l_out(k) := v_off + v_noches;
         IF k > 1 AND v_noches >= 2 THEN         -- alguien del grupo llega después o se va antes
            v_u := DBMS_RANDOM.VALUE;
            IF    v_u < 0.12 THEN l_in(k)  := v_off + 1;
            ELSIF v_u < 0.20 THEN l_out(k) := v_off + v_noches - 1;
            END IF;
         END IF;

         v_libre := FALSE;
         v_intentos := 0;
         WHILE NOT v_libre AND v_intentos < 15 LOOP
            v_intentos := v_intentos + 1;
            v_hi := a_hab_ini(v_ai) + f_ent(0, a_hab_n(v_ai) - 1);
            v_libre := TRUE;
            FOR j IN 1 .. k - 1 LOOP              -- no repetir habitación en la misma reserva
               IF l_hab(j) = v_hi THEN v_libre := FALSE; END IF;
            END LOOP;
            IF v_libre THEN
               FOR n IN l_in(k) .. l_out(k) - 1 LOOP
                  IF m_ocupada.EXISTS(h_id(v_hi) || '-' || n) THEN
                     v_libre := FALSE;
                     EXIT;
                  END IF;
               END LOOP;
            END IF;
         END LOOP;

         IF NOT v_libre THEN
            v_ok := FALSE;
            EXIT;
         END IF;
         l_hab(k) := v_hi;
      END LOOP;

      IF NOT v_ok THEN
         v_fallos := v_fallos + 1;               -- sin cupo: se descarta y se sortea otra
      ELSE
         -- e) huéspedes y valor de cada línea, NOCHE POR NOCHE
         v_total := 0;
         v_hues  := 0;
         FOR k IN 1 .. v_nlin LOOP
            l_hues(k)  := f_ent(CEIL(h_cap(l_hab(k)) / 2), h_cap(l_hab(k)));
            l_valor(k) := 0;
            FOR n IN l_in(k) .. l_out(k) - 1 LOOP
               l_valor(k) := l_valor(k) + m_tarifa(h_id(l_hab(k)) || '-' || d_temp(n));
            END LOOP;
            v_total := v_total + l_valor(k);
            v_hues  := v_hues + l_hues(k);
         END LOOP;

         -- fecha en que se hizo la reserva (más anticipación en temporada alta)
         v_lead := TRUNC(POWER(DBMS_RANDOM.VALUE, 1.6)
                   * CASE d_cat(v_off) WHEN 'ALTA' THEN 100 WHEN 'MEDIA' THEN 50 ELSE 30 END);
         v_fres := v_in - v_lead + DBMS_RANDOM.VALUE(7 / 24, 22 / 24);
         IF v_fres > c_hoy THEN
            v_fres := c_hoy - DBMS_RANDOM.VALUE(0, 20);
         END IF;

         -- fecha de cancelación: entre la reserva y el día del check-in, nunca después del corte
         v_fcan := NULL;
         IF v_estado = 'CANCELADA' THEN
            v_fcan := v_fres + DBMS_RANDOM.VALUE * ((v_in + 0.95) - v_fres);
            IF v_fcan > c_hoy THEN
               v_fcan := GREATEST(v_fres, c_hoy - DBMS_RANDOM.VALUE(0, 5));
            END IF;
         END IF;

         -- cliente: 80 % uniforme, 20 % sesgado (clientes frecuentes)
         IF DBMS_RANDOM.VALUE < 0.8 THEN
            v_ci := f_ent(1, v_nc);
         ELSE
            v_ci := LEAST(v_nc, 1 + TRUNC(v_nc * POWER(DBMS_RANDOM.VALUE, 1.5)));
         END IF;

         INSERT INTO reserva (id_cliente, id_alojamiento, fecha_reserva, fecha_checkin,
                              fecha_checkout, estado, fecha_cancelacion)
         VALUES (cli_id(v_ci), a_id(v_ai), v_fres, v_in, v_out, v_estado, v_fcan)
         RETURNING id_reserva INTO v_rid;

         FOR k IN 1 .. v_nlin LOOP
            INSERT INTO reserva_habitacion (id_reserva, id_alojamiento, id_habitacion, fecha_checkin,
                                            fecha_checkout, num_huespedes, valor_estadia)
            VALUES (v_rid, a_id(v_ai), h_id(l_hab(k)), c_cal_ini + l_in(k),
                    c_cal_ini + l_out(k), l_hues(k), l_valor(k));
            IF v_estado <> 'CANCELADA' THEN      -- solo las no canceladas ocupan la habitación
               FOR n IN l_in(k) .. l_out(k) - 1 LOOP
                  m_ocupada(h_id(l_hab(k)) || '-' || n) := 1;
               END LOOP;
            END IF;
         END LOOP;

         -- f1) servicios complementarios (servicios distintos dentro de la reserva)
         v_serv := 0;
         IF v_estado <> 'CANCELADA' THEN
            v_u    := DBMS_RANDOM.VALUE;
            v_nsrv := CASE WHEN v_u < 0.15 THEN 0 WHEN v_u < 0.40 THEN 1 WHEN v_u < 0.65 THEN 2
                           WHEN v_u < 0.85 THEN 3 ELSE 4 END;
            v_nsrv  := LEAST(v_nsrv, a_srv_n(v_ai));
            v_ini_s := f_ent(0, a_srv_n(v_ai) - 1);
            FOR k IN 1 .. v_nsrv LOOP
               v_si   := a_srv_ini(v_ai) + MOD(v_ini_s + k - 1, a_srv_n(v_ai));
               v_fser := v_in + f_ent(0, v_noches - 1);
               v_cant := CASE s_unidad(v_si)
                            WHEN 'POR_PERSONA' THEN f_ent(1, v_hues)
                            WHEN 'POR_DIA'     THEN f_ent(1, v_noches)
                            ELSE                    f_ent(1, 2) END;
               v_cant := LEAST(v_cant, 50);
               INSERT INTO reserva_servicio (id_reserva, id_alojamiento, id_servicio,
                                             fecha_servicio, cantidad, precio_unitario)
               VALUES (v_rid, a_id(v_ai), s_id(v_si), v_fser, v_cant, s_precio(v_si));
               v_serv    := v_serv + v_cant * s_precio(v_si);
               v_lin_srv := v_lin_srv + 1;
            END LOOP;
            v_nr := v_nr + 1;
            r_id(v_nr) := v_rid;  r_ai(v_nr) := v_ai;  r_in(v_nr) := v_off;
            r_noches(v_nr) := v_noches;  r_hues(v_nr) := v_hues;  r_estado(v_nr) := v_estado;
         END IF;
         v_total := v_total + v_serv;            -- total = estadía + servicios

         -- f2) pagos según el estado
         CASE v_estado
            WHEN 'COMPLETADA' THEN
               IF DBMS_RANDOM.VALUE < 0.06 THEN   -- intento fallido previo
                  p_pago(v_rid, v_fres, v_total, f_metodo(FALSE), 'FALLIDO', 'TOTAL');
               END IF;
               IF DBMS_RANDOM.VALUE < 0.50 THEN   -- pago único
                  p_pago(v_rid, v_fres + 5 / 1440, v_total, f_metodo(FALSE), 'EXITOSO', 'TOTAL');
               ELSE                                -- anticipo + saldo al llegar
                  v_anti := ROUND(v_total * DBMS_RANDOM.VALUE(0.30, 0.50), -3);
                  p_pago(v_rid, v_fres + 5 / 1440, v_anti, f_metodo(FALSE), 'EXITOSO', 'ANTICIPO');
                  p_pago(v_rid, v_in + DBMS_RANDOM.VALUE(14 / 24, 20 / 24), v_total - v_anti,
                         f_metodo(TRUE), 'EXITOSO', 'SALDO');
               END IF;
            WHEN 'CONFIRMADA' THEN
               IF DBMS_RANDOM.VALUE < 0.35 THEN
                  p_pago(v_rid, v_fres, v_total, f_metodo(FALSE), 'EXITOSO', 'TOTAL');
               ELSE
                  v_anti := ROUND(v_total * DBMS_RANDOM.VALUE(0.30, 0.50), -3);
                  p_pago(v_rid, v_fres, v_anti, f_metodo(FALSE), 'EXITOSO', 'ANTICIPO');
                  IF v_in <= c_hoy THEN            -- estadía en curso: ya pagó el saldo
                     p_pago(v_rid, v_in + 0.6, v_total - v_anti, f_metodo(TRUE), 'EXITOSO', 'SALDO');
                  END IF;
               END IF;
            WHEN 'PENDIENTE' THEN
               v_u := DBMS_RANDOM.VALUE;
               IF v_u >= 0.45 THEN
                  v_anti := ROUND(v_total * DBMS_RANDOM.VALUE(0.30, 0.50), -3);
                  p_pago(v_rid, v_fres,
                         v_anti, CASE WHEN DBMS_RANDOM.VALUE < 0.6 THEN 'PSE' ELSE 'TRANSFERENCIA' END,
                         CASE WHEN v_u < 0.75 THEN 'PENDIENTE' ELSE 'FALLIDO' END, 'ANTICIPO');
               END IF;
            WHEN 'CANCELADA' THEN
               IF DBMS_RANDOM.VALUE < 0.70 THEN   -- 70 % alcanzó a pagar algo
                  IF DBMS_RANDOM.VALUE < 0.30 THEN
                     v_anti := v_total;
                  ELSE
                     v_anti := ROUND(v_total * DBMS_RANDOM.VALUE(0.30, 0.50), -3);
                  END IF;
                  IF (v_in - TRUNC(v_fcan)) > 5 THEN   -- regla: > 5 días => reembolso del 80 %
                     p_pago(v_rid, v_fres, v_anti, f_metodo(FALSE), 'REEMBOLSADO',
                            CASE WHEN v_anti = v_total THEN 'TOTAL' ELSE 'ANTICIPO' END,
                            ROUND(v_anti * 0.8, 2), v_fcan + DBMS_RANDOM.VALUE(0.5, 4));
                  ELSE                                 -- <= 5 días: no hay reembolso
                     p_pago(v_rid, v_fres, v_anti, f_metodo(FALSE), 'EXITOSO',
                            CASE WHEN v_anti = v_total THEN 'TOTAL' ELSE 'ANTICIPO' END);
                  END IF;
               END IF;
         END CASE;

         -- f3) reseña: solo estadías COMPLETADAS (~47 %)
         IF v_estado = 'COMPLETADA' AND DBMS_RANDOM.VALUE < 0.47 THEN
            v_calif := ROUND(a_calidad(v_ai) + DBMS_RANDOM.NORMAL * 0.85);
            v_calif := GREATEST(1, LEAST(5, v_calif));
            -- una función local no se puede llamar dentro de SQL: se evalúa antes
            v_coment := f_comentario(v_calif);
            INSERT INTO resena (id_reserva, calificacion, comentario, fecha_resena)
            VALUES (v_rid, v_calif, v_coment,
                    LEAST(v_out + DBMS_RANDOM.VALUE(0.2, 15), c_hoy));
         END IF;

         v_creadas := v_creadas + 1;
         IF MOD(v_creadas, 5000) = 0 THEN
            COMMIT;
            DBMS_OUTPUT.PUT_LINE('   ... ' || v_creadas || ' reservas');
         END IF;
      END IF;
   END LOOP;

   -- 7.6 Recarga de servicios hasta la meta (solo sobre estadías COMPLETADAS,
   --     y con su pago de saldo, para que la reserva siga quedando pagada)
   WHILE v_lin_srv < c_meta_servicios LOOP
      v_k := f_ent(1, v_nr);
      IF r_estado(v_k) = 'COMPLETADA' THEN
         v_ai   := r_ai(v_k);
         v_si   := a_srv_ini(v_ai) + f_ent(0, a_srv_n(v_ai) - 1);
         v_fser := c_cal_ini + r_in(v_k) + f_ent(0, r_noches(v_k) - 1);
         v_cant := CASE s_unidad(v_si)
                      WHEN 'POR_PERSONA' THEN f_ent(1, r_hues(v_k))
                      WHEN 'POR_DIA'     THEN f_ent(1, r_noches(v_k))
                      ELSE                    1 END;
         v_cant := LEAST(v_cant, 50);
         BEGIN
            INSERT INTO reserva_servicio (id_reserva, id_alojamiento, id_servicio,
                                          fecha_servicio, cantidad, precio_unitario)
            VALUES (r_id(v_k), a_id(v_ai), s_id(v_si), v_fser, v_cant, s_precio(v_si));
            p_pago(r_id(v_k), v_fser + 0.8, v_cant * s_precio(v_si), f_metodo(TRUE), 'EXITOSO', 'SALDO');
            v_lin_srv := v_lin_srv + 1;
         EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN NULL;     -- ese servicio ya estaba ese día: se intenta otro
         END;
      END IF;
   END LOOP;

   COMMIT;
   DBMS_OUTPUT.PUT_LINE('   Reservas creadas: ' || v_creadas || '  (sorteos descartados por falta de cupo: ' || v_fallos || ')');
   DBMS_OUTPUT.PUT_LINE('   Líneas de servicio: ' || v_lin_srv);
END;
/

-- La fecha de registro del cliente no puede ser posterior a su primera reserva
UPDATE cliente c
SET    fecha_registro = LEAST(fecha_registro,
                              NVL((SELECT MIN(TRUNC(r.fecha_reserva)) - 1
                                   FROM   reserva r
                                   WHERE  r.id_cliente = c.id_cliente), fecha_registro));
COMMIT;

/* =====================================================================
   8. Usuarios internos (al menos un administrador y un encargado por
   cada tipo de alojamiento)
   ===================================================================== */
PROMPT 8. Usuarios del sistema...

INSERT INTO usuario_sistema (username, nombre_completo, correo, id_rol, ambito_rol, id_alojamiento) VALUES ('admin.plataforma', 'Laura Marcela Ospina Gil', 'admin.plataforma@turismouq.com.co', 1, 'PLATAFORMA', NULL);
INSERT INTO usuario_sistema (username, nombre_completo, correo, id_rol, ambito_rol, id_alojamiento) VALUES ('admin.soporte', 'Andrés Felipe Cardona Ruiz', 'admin.soporte@turismouq.com.co', 1, 'PLATAFORMA', NULL);
INSERT INTO usuario_sistema (username, nombre_completo, correo, id_rol, ambito_rol, id_alojamiento) VALUES ('gerente.general', 'Patricia Elena Henao Arango', 'gerente.general@turismouq.com.co', 2, 'PLATAFORMA', NULL);
INSERT INTO usuario_sistema (username, nombre_completo, correo, id_rol, ambito_rol, id_alojamiento) VALUES ('auditor.interno', 'Jorge Iván Valencia Mejía', 'auditor.interno@turismouq.com.co', 3, 'PLATAFORMA', NULL);
INSERT INTO usuario_sistema (username, nombre_completo, correo, id_rol, ambito_rol, id_alojamiento) VALUES ('enc.finca', 'Carlos Mario Londoño Castaño', 'enc.finca@turismouq.com.co', 4, 'ALOJAMIENTO', (SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Finca Cafetera El Edén Urbano'));
INSERT INTO usuario_sistema (username, nombre_completo, correo, id_rol, ambito_rol, id_alojamiento) VALUES ('enc.hotel', 'Diana Carolina Restrepo Giraldo', 'enc.hotel@turismouq.com.co', 4, 'ALOJAMIENTO', (SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Mirador del Parque Sucre'));
INSERT INTO usuario_sistema (username, nombre_completo, correo, id_rol, ambito_rol, id_alojamiento) VALUES ('enc.glamping', 'Santiago Arias Montoya', 'enc.glamping@turismouq.com.co', 4, 'ALOJAMIENTO', (SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Glamping Domos del Valle de Cocora'));
INSERT INTO usuario_sistema (username, nombre_completo, correo, id_rol, ambito_rol, id_alojamiento) VALUES ('enc.hostal', 'Valentina Quintero López', 'enc.hostal@turismouq.com.co', 4, 'ALOJAMIENTO', (SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal La Calle Catorce'));
INSERT INTO usuario_sistema (username, nombre_completo, correo, id_rol, ambito_rol, id_alojamiento) VALUES ('enc.ecohotel', 'Julián David Ramírez Toro', 'enc.ecohotel@turismouq.com.co', 4, 'ALOJAMIENTO', (SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Ecohotel Bosque de Yarumos'));
INSERT INTO usuario_sistema (username, nombre_completo, correo, id_rol, ambito_rol, id_alojamiento) VALUES ('recep.hotel1', 'María José Salazar Bedoya', 'recep.hotel1@turismouq.com.co', 5, 'ALOJAMIENTO', (SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Mirador del Parque Sucre'));
INSERT INTO usuario_sistema (username, nombre_completo, correo, id_rol, ambito_rol, id_alojamiento) VALUES ('recep.hotel2', 'Juan Sebastián Correa Duque', 'recep.hotel2@turismouq.com.co', 5, 'ALOJAMIENTO', (SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hotel Torre Cafetera'));
INSERT INTO usuario_sistema (username, nombre_completo, correo, id_rol, ambito_rol, id_alojamiento) VALUES ('recep.salento', 'Natalia Gómez Rincón', 'recep.salento@turismouq.com.co', 5, 'ALOJAMIENTO', (SELECT id_alojamiento FROM alojamiento WHERE nombre_comercial = 'Hostal Calle Real de Salento'));
COMMIT;

/* =====================================================================
   9. Verificación: volúmenes mínimos del enunciado y reglas clave
   ===================================================================== */
PROMPT 9. Verificación...

DECLARE
   v_n     NUMBER;
   v_comp  NUMBER;
   v_err   PLS_INTEGER := 0;

   PROCEDURE p_check(p_tabla VARCHAR2, p_min NUMBER) IS
      v_c NUMBER;
   BEGIN
      EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || p_tabla INTO v_c;
      DBMS_OUTPUT.PUT_LINE(RPAD(p_tabla, 20) || LPAD(TO_CHAR(v_c, 'FM999G999'), 9)
                           || '   (mínimo ' || p_min || ') '
                           || CASE WHEN v_c >= p_min THEN 'OK' ELSE '<<< FALTA' END);
      IF v_c < p_min THEN v_err := v_err + 1; END IF;
   END;
BEGIN
   DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------');
   p_check('MUNICIPIO', 12);           p_check('TIPO_ALOJAMIENTO', 4);
   p_check('ALOJAMIENTO', 60);         p_check('HABITACION', 400);
   p_check('TEMPORADA', 6);            p_check('CALENDARIO', 1);
   p_check('TARIFA', 1);               p_check('CLIENTE', 3000);
   p_check('RESERVA', 25000);          p_check('RESERVA_HABITACION', 25000);
   p_check('PAGO', 25000);             p_check('SERVICIO', 30);
   p_check('RESERVA_SERVICIO', 40000); p_check('ROL', 1);
   p_check('USUARIO_SISTEMA', 10);

   -- TARIFA debe ser exactamente el cruce habitación x temporada
   SELECT (SELECT COUNT(*) FROM habitacion) * (SELECT COUNT(*) FROM temporada)
        - (SELECT COUNT(*) FROM tarifa)
   INTO   v_n FROM dual;
   DBMS_OUTPUT.PUT_LINE('Tarifas faltantes en el cruce habitación x temporada: ' || v_n);
   IF v_n <> 0 THEN v_err := v_err + 1; END IF;

   -- Reseñas >= 40 % de las reservas completadas
   SELECT COUNT(*) INTO v_comp FROM reserva WHERE estado = 'COMPLETADA';
   SELECT COUNT(*) INTO v_n    FROM resena;
   DBMS_OUTPUT.PUT_LINE('Reseñas: ' || v_n || ' de ' || v_comp || ' completadas = '
                        || ROUND(100 * v_n / NULLIF(v_comp, 0), 1) || ' %');
   IF v_n < 0.40 * v_comp THEN v_err := v_err + 1; END IF;

   -- Reservas con más de una habitación y con más de un pago
   SELECT COUNT(*) INTO v_n FROM (SELECT id_reserva FROM reserva_habitacion GROUP BY id_reserva HAVING COUNT(*) > 1);
   DBMS_OUTPUT.PUT_LINE('Reservas con más de una habitación: ' || v_n);
   SELECT COUNT(*) INTO v_n FROM (SELECT id_reserva FROM pago GROUP BY id_reserva HAVING COUNT(*) > 1);
   DBMS_OUTPUT.PUT_LINE('Reservas con más de un pago: ' || v_n);

   -- Ninguna habitación ocupada dos veces por reservas no canceladas
   SELECT COUNT(*) INTO v_n
   FROM   reserva_habitacion a
   JOIN   reserva ra ON ra.id_reserva = a.id_reserva
   JOIN   reserva_habitacion b ON b.id_habitacion = a.id_habitacion
                              AND b.id_reserva_habitacion > a.id_reserva_habitacion
   JOIN   reserva rb ON rb.id_reserva = b.id_reserva
   WHERE  ra.estado <> 'CANCELADA' AND rb.estado <> 'CANCELADA'
   AND    a.fecha_checkin < b.fecha_checkout
   AND    b.fecha_checkin < a.fecha_checkout;
   DBMS_OUTPUT.PUT_LINE('Solapamientos entre reservas activas: ' || v_n);
   IF v_n <> 0 THEN v_err := v_err + 1; END IF;

   DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------');
   DBMS_OUTPUT.PUT_LINE(CASE WHEN v_err = 0 THEN 'CARGA VERIFICADA: todos los mínimos se cumplen.'
                             ELSE 'ATENCIÓN: ' || v_err || ' verificaciones fallaron.' END);
END;
/

-- Estadísticas del optimizador (necesarias para los planes de ejecución de la Entrega 3)
BEGIN
   DBMS_STATS.GATHER_SCHEMA_STATS(ownname => USER, cascade => TRUE);
END;
/

SET FEEDBACK ON
PROMPT Carga terminada.
