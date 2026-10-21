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

@@TEMP@@
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
@@FEST@@
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

@@ALOJ@@
COMMIT;

@@SRV@@
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

@@US@@
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
