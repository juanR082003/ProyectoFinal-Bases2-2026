# TurismoUQ · Proyecto integrador Bases de Datos II (2026-2)

Universidad del Quindío · Ingeniería de Sistemas y Computación · código 12338
Docente: Carolina Londoño Idárraga

**Integrantes:** Juan Camilo López · José Luis Rivadeneira · Juan Manuel Rincón

Base de datos de una plataforma de reservas turísticas del Quindío sobre **Oracle XE 21c**
(servicio `XEPDB1`). Los scripts están numerados en orden de ejecución y cada uno corre de
arriba abajo en una base limpia.

## Entrega 1 · Modelo y consultas de análisis

| Orden | Script | Conectado como | Qué hace |
|---|---|---|---|
| 0 | `00_crear_usuario.sql` | SYSTEM @ XEPDB1 | Crea el esquema `TURISMOUQ` (clave `TurismoUQ2026`) |
| 1 | `01_ddl_turismouq.sql` | TURISMOUQ | Borra y crea las 16 tablas con PK, FK, CHECK, NOT NULL, UNIQUE y comentarios |
| 2 | `02_carga_datos.sql` | TURISMOUQ | Carga catálogos y genera el volumen con PL/SQL + DBMS_RANDOM (semilla fija); termina con una verificación de mínimos |
| 3 | `03_consultas_analisis.sql` | TURISMOUQ | Las 7 consultas de análisis numeradas y comentadas |

```
sqlplus system/<clave>@localhost:1521/XEPDB1 @00_crear_usuario.sql
sqlplus turismouq/TurismoUQ2026@localhost:1521/XEPDB1
SQL> @01_ddl_turismouq.sql
SQL> @02_carga_datos.sql        -- 2 a 5 minutos; debe terminar en "CARGA VERIFICADA"
SQL> @03_consultas_analisis.sql
```

En SQL Developer: abrir cada archivo y usar **Ejecutar script (F5)**, no F9, para que funcionen
`VARIABLE` / `EXEC` de la consulta 5. En SQL*Plus sobre Windows, definir antes
`set NLS_LANG=SPANISH_COLOMBIA.AL32UTF8` para que las tildes se guarden bien.

## Carpetas

- `docs/` – documentos de las entregas (Word) y el MER en PNG/SVG.
- `tools/` – generadores usados para producir partes del script 02 (temporadas con festivos de
  Colombia, alojamientos, servicios, usuarios), el MER y el documento. **No** hacen falta para
  ejecutar la base de datos.

## Entrega 2 · Capa PL/SQL

| Orden | Script | Conectado como | Qué hace |
|---|---|---|---|
| 4 | `04_tablespace_historico.sql` | **SYSTEM** @ XEPDB1 | Tablespace `TS_TURISMOUQ_HIST`, cuota y `CREATE JOB` |
| 5 | `05_paquete_turismouq.sql` | TURISMOUQ | `PKG_TURISMOUQ`: `fn_valor_estadia`, `sp_crear_reserva`, cursores con parámetros (liquidación mensual), cancelación |
| 6 | `06_disparadores.sql` | TURISMOUQ | Auditoría de TARIFA (sentencia) y anti-solape de reservas (fila) |
| 7 | `07_historico_vista_materializada.sql` | TURISMOUQ | `RESERVA_HISTORICO` en el tablespace, `MV_OCUPACION_MENSUAL` y jobs |
| 8 | `08_pruebas_entrega2.sql` | TURISMOUQ | Evidencia: cada prueba imprime OK o FALLA |

Si se vuelven a ejecutar 01 y 02, hay que repetir 04 a 07 (borrar las tablas borra sus disparadores
y deja inválida la vista materializada).

## Entrega 3 · Transacciones, índices y seguridad

| Orden | Script | Conectado como | Qué hace |
|---|---|---|---|
| 9 | `09_transacciones.sql` | TURISMOUQ | `PKG_RESERVAS_TX`: reserva + pago atómicos con `SAVEPOINT`, rollback parcial, bloqueo de habitación; disparador de reactivación; pruebas T9 |
| 10 | `10_concurrencia.sql` | TURISMOUQ | Antes y después de `SELECT ... FOR UPDATE`, reproducido con transacciones autónomas (pruebas T10) |
| 11 | `11_indices.sql` | TURISMOUQ | 3 consultas lentas, plan y tiempo antes/después, índices compuestos y basado en función, y el caso donde el índice no ayuda |
| 12 | `12_seguridad_roles_usuarios.sql` | **SYSTEM** @ XEPDB1 | Perfil `PERFIL_TURISMOUQ`, 4 roles y 5 usuarios de ejemplo |
| 13 | `13_seguridad_vistas_privilegios.sql` | TURISMOUQ | `PKG_SEGURIDAD`, vistas `V_REC_*` / `V_ADM_*` / `V_GER_*`, paquetes de acceso y `GRANT` por rol |
| 14 | `14_pruebas_seguridad.sql` | cualquiera | Se conecta por turnos como cada usuario y prueba qué puede y qué no (OK / FALLA) |

**Experimento de concurrencia con dos sesiones reales** (de aquí salen las capturas del documento):
abrir dos ventanas como TURISMOUQ y una como SYSTEM y seguir las pausas de
`concurrencia/sesion_A.sql` (ventana A), `concurrencia/sesion_B.sql` (ventana B) y
`concurrencia/monitor_system.sql` (ventana SYSTEM, muestra el bloqueo en `V$SESSION` y `V$LOCK`).

Usuarios de ejemplo (clave entre paréntesis): `RECEP_HOTEL1` y `RECEP_SALENTO` (`Recepcion_2026`),
`ENC_HOTEL` (`Encargado_2026`), `GERENTE_GENERAL` (`Gerencia_2026`), `AUDITOR_INTERNO` (`Auditoria_2026`).

En SQL Developer el mismo experimento se hace con dos hojas **no compartidas** de TURISMOUQ
(Ctrl+Shift+N) y una de SYSTEM, ejecutando con `@` y F5 los pasos de `concurrencia/sqldeveloper/`
en este orden: A0, A1, B1, A2, B2, A4 · A3, B3 (queda esperando), `monitor_system.sql` en SYSTEM, A2 ·
A6, B4, A7.

El documento `docs/Entrega3_TurismoUQ.docx` incluye las capturas reales de la ejecución
(carpeta `docs/capturas/`), hechas en Oracle Database 26ai Free (Docker, servicio `FREEPDB1`)
con SQL Developer 26.2 en macOS.

Notas:

- Si se repite el script 12 hay que repetir el 13 (al borrar un rol se pierden sus privilegios).
- Si se vuelven a ejecutar 01 y 02, hay que repetir 04 a 07 y 09 a 13.
- Las pruebas reservan en enero de 2027: deben ejecutarse antes del 18-01-2027.
- `14_pruebas_seguridad.sql` asume `localhost:1521/FREEPDB1` (Oracle Free 23ai/26ai); en Oracle XE 21c cambiar su línea `DEFINE conexion` a `XEPDB1`. Como cambia de usuario con `CONNECT`, conviene ejecutarlo en SQL*Plus o SQLcl: SQL Developer no muestra la salida después de un `CONNECT` dentro de un script.

## Orden completo desde una base limpia

```
SYSTEM     00
TURISMOUQ  01  02  03
SYSTEM     04
TURISMOUQ  05  06  07  08
TURISMOUQ  09  10  11
SYSTEM     12
TURISMOUQ  13  14
```
