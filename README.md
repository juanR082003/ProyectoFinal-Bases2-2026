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
