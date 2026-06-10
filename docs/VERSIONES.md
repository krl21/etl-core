# Historial de Versiones - ETL-Core

Este documento describe las versiones de `etl-core`, sus características principales y los cambios introducidos en cada versión.

---

## Tabla de Contenidos

1. [Versión 2.5.1 (Actual)](#versión-251-actual)
2. [Versión 2.5](#versión-25)
3. [Versión 2.4](#versión-24)
4. [Versión 2.3](#versión-23)
5. [Versión 2.2](#versión-22)
6. [Versión 2.1](#versión-21)
7. [Versión 1.2.0](#versión-120)
8. [Versiones Anteriores](#versiones-anteriores)

---

## Versión 2.5.1 (Actual)

### Características Principales

- **Carga masiva a BigQuery**: Límite configurable de expedientes pendientes por ciclo para evitar saturar memoria y conexiones cuando hay grandes volúmenes en PostgreSQL
- **Marcado por `id_nodo`**: Tras una subida exitosa, se marcan todas las versiones pendientes del mismo expediente, evitando reenvíos de filas obsoletas
- **Operaciones PostgreSQL ampliadas**: Consultas pendientes centralizadas y función para vaciar tablas vía pool

### Nuevo en esta Versión

#### Consultas de registros pendientes con límite

- **`Connection.PostgresHelpers.pending_bq_query/4`**: Construye la consulta SELECT de registros con `estado_analisis = "sin_analizar"`, con soporte opcional de `:limit` sobre `id_nodo` distintos (ordenados por `MAX(fecha_creado) DESC`)
- **`Connection.Postgres.get_pending_bq/4`** y **`Connection.PostgresPool.get_pending_bq/4`**: Nuevo cuarto argumento `opts` (p. ej. `[limit: 500]`). La firma anterior con 3 argumentos sigue siendo válida

#### Marcado masivo por expediente

- **`Connection.Postgres.mark_as_sent_to_bq_by_id_nodos/4`**
- **`Connection.PostgresPool.mark_as_sent_to_bq_by_id_nodos/4`**

Actualizan a `analizado_en_bq` todas las filas pendientes (`sin_analizar`) de los `id_nodo` indicados, opcionalmente filtradas por `tipo`. Sustituyen el marcado fila a fila por `id` en el flujo de subida a BigQuery.

#### Eliminación total de tabla (pool)

- **`Connection.PostgresPool.delete_all/2`**: Ejecuta `DELETE FROM tabla` usando el pool de PostgreSQL

#### BigQuery Uploader y Handler

- **`Genserver.BigqueryUploader`**: Nueva clave opcional `:pending_limit` (pool y legacy). Limita cuántos `id_nodo` distintos se procesan por tabla en cada ciclo
- **`Genserver.Handlers.Bigquery.run/10`** y **`run_with_pool/10`**: Nuevo parámetro opcional `pending_limit` (default `nil`, sin límite)
- **Modo pool**: Cada tabla en `:info` se procesa en su propio bloque `try/rescue`; un fallo en una tabla no aborta el ciclo completo
- Tras insertar con éxito, el handler usa `mark_as_sent_to_bq_by_id_nodos/4` en lugar de `mark_as_sent_to_bq/3`

#### Protocolo post-proceso

- **`Genserver.Protocols.PBigqueryPostProcess`**: En el mapa `context` de `after_upload/3`, la clave `:successful_ids` pasa a ser `:successful_id_nodos` (lista de `id_nodo`, no de `id` de fila)

### Módulos Afectados

- `Connection.PostgresHelpers`: `pending_bq_query/4`
- `Connection.Postgres`: `get_pending_bq/4`, `mark_as_sent_to_bq_by_id_nodos/4`
- `Connection.PostgresPool`: `get_pending_bq/4`, `mark_as_sent_to_bq_by_id_nodos/4`, `delete_all/2`
- `Genserver.Handlers.Bigquery`: `run/10`, `run_with_pool/10`, lógica de agrupación por `id_nodo`
- `Genserver.BigqueryUploader`: `:pending_limit`, manejo de errores por tabla en modo pool
- `Genserver.Protocols.PBigqueryPostProcess`: documentación y contrato del contexto

### Migración desde v2.5

- **Sin cambios obligatorios** si no se personaliza el uploader ni el protocolo post-proceso
- **Opcional — limitar carga por ciclo** (recomendado con tablas grandes):

```elixir
{Genserver.BigqueryUploader, %{
  business: :my_business,
  pg_pool_name: :postgres_pool,
  bq_pool_name: :bigquery_pool,
  pending_limit: 500,
  # ... resto de config
}}
```

- **Si implementas `PBigqueryPostProcess`**: reemplazar `context.successful_ids` por `context.successful_id_nodos`

---

## Versión 2.5

### Características Principales

- **Documentación BigQuery**: Guía de referencia centralizada para ODBC, imagen Docker del driver, ejemplos de conexión y consultas, y tablas/atributos por negocio

### Nuevo en esta Versión

#### `docs/BIGQUERY_GUIA_REFERENCIA.md`

- Imagen Docker recomendada (`googlebigqueryodbc:3.0.0-prod`) y registros asociados
- Pasos de conexión ODBC desde Elixir (`:odbc`, DSN, warehouse)
- Ejemplos de consultas `SELECT`
- Sección de tablas y atributos por proyecto ETL (New Vehicles, Transfer Vehicles, Leasing)

### Módulos Afectados

- Ningún cambio en firmas públicas de código obligatorio para esta versión documentada; el foco es documentación operativa de BigQuery

### Migración desde v2.4

- **Sin cambios de API**: las aplicaciones que ya usan `Pool.BigQuery` y `Connection.Odbc` siguen igual
- Opcional: usar la guía para homogeneizar configuración DSN/warehouse y consultas de diagnóstico

---

## Versión 2.4

### Características Principales

- **Resiliencia RabbitMQ**: El consumidor AMQP se reinicia de forma coordinada cuando cae la conexión (p. ej. `socket_closed_unexpectedly`), evitando que el supervisor interno del cliente AMQP agote reinicios

### Nuevo en esta Versión

#### `Genserver.RabbitConsumer`

- **`Process.monitor/1`** sobre el PID del proceso de conexión AMQP (`connection.pid`)
- Al recibir **`{:DOWN, ref, :process, _pid, reason}`** (conexión cerrada o proceso muerto):
  - Se registra error y opcionalmente se notifica a Slack (`webhook_url`)
  - El GenServer termina con **`{:stop, {:amqp_connection_down, reason}, state}`** para que el **supervisor de la aplicación** vuelva a levantar el consumidor con `AMQP.Connection.open/1` nuevo
- Los mensajes **sin ack** vuelven a la cola en RabbitMQ
- **`terminate/2`**: cierre seguro de la conexión AMQP (`close_amqp_safely/1`) incluso si el proceso de conexión ya murió

### Módulos Afectados

- `Genserver.RabbitConsumer`: monitor de conexión, `handle_info` para `{:DOWN, ...}`, `terminate/2`, `close_amqp_safely/1`

### Migración desde v2.3

- **RabbitConsumer**: misma tupla de arranque; no hay nuevas claves en `info` obligatorias

---

## Versión 2.3

### Características Principales

- **Refactorización de Limpieza BigQuery**: Optimización de la eliminación de duplicados usando una sola consulta SQL
- **Mejora de Rendimiento**: Reducción significativa en el tiempo de ejecución de limpieza
- **Simplificación del Código**: Eliminación de lógica compleja de procesamiento por lotes

### Nuevo en esta Versión

#### Limpieza de BigQuery Optimizada

- **Refactorización de `Cleaning.Cleaner.run_bigquery_cleanup/4`**:
  - **Antes**: Múltiples consultas SQL con procesamiento por lotes
    - Obtención de IDs duplicados
    - Procesamiento en chunks de 500 registros
    - Múltiples consultas SELECT y DELETE
  - **Ahora**: Una sola consulta SQL atómica
    - Uso de `CREATE OR REPLACE TABLE` con `QUALIFY` y `ROW_NUMBER()`
    - Operación atómica y más eficiente
    - Eliminación directa de duplicados manteniendo el registro más reciente

- **Nueva función `build_cleanup_query/1`**:
  - Construye la consulta SQL optimizada
  - Usa `PARTITION BY` con los campos de ID únicos
  - Ordena por timestamp descendente para mantener el registro más reciente

#### Mejoras de Rendimiento

- **Reducción de consultas**: De múltiples consultas por lote a una sola consulta
- **Operación atómica**: La limpieza se realiza en una sola transacción
- **Menor uso de memoria**: No requiere cargar todos los IDs duplicados en memoria

### Módulos Afectados

- `Cleaning.Cleaner`: Refactorización completa de `run_bigquery_cleanup/4`
  - Eliminadas funciones: `get_duplicate_ids/2`, `get_rows_to_keep/3`, `delete_duplicates/3`, `build_where_clause/2`, `mconvert_for_bigquery/2`
  - Nueva función: `build_cleanup_query/1`

### Migración desde v2.2

No se requieren cambios en el código existente. La API pública se mantiene igual:
- `Cleaning.Cleaner.run/3` mantiene la misma interfaz
- `Cleaning.Cleaner.run_all/2` mantiene la misma interfaz
- `Cleaning.Cleaner.run_for_module/3` mantiene la misma interfaz

**Nota**: El cambio es interno y transparente para los usuarios del módulo.

### Ejemplo de Consulta Generada

```sql
CREATE OR REPLACE TABLE dataset.table_name AS
SELECT *
FROM dataset.table_name
QUALIFY
  ROW_NUMBER() OVER (
    PARTITION BY unique_id
    ORDER BY timestamp DESC
  ) = 1;
```

---

## Versión 2.2

### Características Principales

- **Sistema de Constantes en JSON**: Constantes externas cargadas en tiempo de compilación
- **Pools de Conexiones Mejorados**: Gestión optimizada de conexiones a PostgreSQL y BigQuery
- **Normalización de Caracteres Extendida**: Soporte completo para caracteres especiales y Unicode

### Nuevo en esta Versión

#### Constantes Externas

- **`lib/time/holidays.json`**: Días feriados por año para Chile
  - Cargado automáticamente por `Time.Timem` en tiempo de compilación
  - Actualización sin modificar código fuente
  - Recompilación automática cuando cambia el archivo

- **`lib/type/char_mappings.json`**: Mapeos de caracteres especiales
  - Sección `spanish_chars`: Caracteres españoles (ñ, á, é, í, ó, ú)
  - Sección `unicode_chars`: Más de 200 conversiones Unicode a ASCII
  - Sección `denormalize`: Mapeos inversos para restaurar caracteres
  - Cargado automáticamente por `Type.Normalize` en tiempo de compilación

#### Funciones de Utilidad

- **`Stuff.find_project_file/1`**: Búsqueda de archivos en el sistema de archivos
  - Busca archivos desde múltiples ubicaciones
  - Soporte para entornos de desarrollo y producción (Okteto)

#### Mejoras en Documentación

- Documentación completa de constantes en `MODULOS_REFERENCIA.md`
- Sección de gestión de constantes en `ARQUITECTURA.md`
- Ejemplos de uso y actualización de constantes

### Módulos Afectados

- `Time.Timem`: Carga feriados desde JSON
- `Type.Normalize`: Carga mapeos de caracteres desde JSON
- `Stuff`: Nueva función `find_project_file/1`

### Migración desde v2.1

No se requieren cambios en el código existente. Los archivos JSON se cargan automáticamente si están presentes en `constants/`.

---

## Versión 2.1

### Características Principales

- **Pools de Conexiones**: Sistema de pools para PostgreSQL y BigQuery
- **Modo Legacy Compatible**: Soporte para código existente sin pools
- **Mejoras de Rendimiento**: Reutilización de conexiones

### Nuevo en esta Versión

#### Pools de Conexiones

- **`Pool.Postgres`**: Pool de conexiones para PostgreSQL
  - Gestión automática de conexiones
  - Reconexión automática ante fallos
  - Supervisión OTP con reinicio automático
  - Health checks periódicos

- **`Pool.BigQuery`**: Pool de conexiones para BigQuery via ODBC
  - Gestión eficiente de conexiones ODBC
  - Reutilización de conexiones
  - Manejo de recursos optimizado

#### Nuevas Funciones en DataModel

- **`execute_insert_pooled/3`**: Inserción usando pool de conexiones
- **`execute_insert_with_retry_pooled/3`**: Inserción con retry usando pool

#### Modos de Operación

| Característica | Pool Mode (v2.1+) | Legacy Mode |
|----------------|-------------------|-------------|
| **Gestión de conexiones** | Pool automático | Conexión temporal por operación |
| **Parámetro** | `pg_pool_name` / `bq_pool_name` | `pg_config` / `data_source` |
| **Reconexión** | Automática | Manual |
| **Rendimiento** | Alto (reutiliza conexiones) | Moderado |
| **Uso recomendado** | Producción | Desarrollo, compatibilidad |

### Módulos Afectados

- `DataModel.RecordPg.Base`: Nuevas funciones con soporte de pools
- `DataModel.TaskPg.Base`: Nuevas funciones con soporte de pools
- `Connection.PostgresPool`: Nuevo módulo para operaciones con pool
- `Pool.Postgres`: Nuevo módulo de pool
- `Pool.BigQuery`: Nuevo módulo de pool

### Migración desde v1.2.0

**Opción 1: Migrar a Pool Mode (Recomendado)**
```elixir
# Antes (Legacy)
def execute_insert(records, pg_config, batch_id) do
  # ... código legacy
end

# Después (Pool)
def execute_insert_pooled(records, pg_pool_name, batch_id) do
  Connection.PostgresPool.insert_many(pg_pool_name, table_name(), records)
end
```

**Opción 2: Mantener Legacy Mode**
- El código existente sigue funcionando sin cambios
- No se requiere migración inmediata

---

## Versión 1.2.0

### Características Principales

- **Sistema ETL Base**: Funcionalidad core del sistema ETL
- **Modelos de Datos**: Macros para definir entidades y subentidades
- **GenServers**: Workers para procesamiento de mensajes
- **Conexiones Legacy**: Conexiones temporales por operación

### Componentes Principales

#### Modelos de Datos

- `DataModel.Record.Base`: Base para expedientes/records
- `DataModel.RecordPg.Base`: Base para PostgreSQL
- `DataModel.Task.Base`: Base para tareas
- `DataModel.TaskPg.Base`: Base para tareas en PostgreSQL

#### GenServers

- `Genserver.RabbitConsumer`: Consumo de mensajes desde RabbitMQ
- `Genserver.ForcedLoad`: Carga histórica desde ElasticSearch
- `Genserver.BigqueryUploader`: Subida de datos a BigQuery
- `Genserver.Cleaning`: Limpieza de datos procesados

#### Utilidades

- `Type.Type`: Conversiones de tipos
- `Type.Normalize`: Normalización de caracteres (versión inicial)
- `Time.WorkingTime`: Cálculo de tiempo laboral
- `Time.Timem`: Utilidades de tiempo y fechas (versión inicial)
- `Common.Payload`: Extracción de datos de payloads
- `Statement.Sql`: Generación de statements SQL

#### Conexiones

- `Connection.Postgres`: Conexiones temporales a PostgreSQL
- `Connection.Odbc`: Conexiones a BigQuery via ODBC
- Modo legacy: Cada operación crea su propia conexión

### Funcionalidades

- Procesamiento de mensajes desde RabbitMQ
- Carga forzada desde ElasticSearch
- Persistencia en PostgreSQL (staging)
- Subida a BigQuery (destino final)
- Limpieza automática de datos procesados
- Notificaciones a Slack
- Manejo de errores con retry

---

## Versiones Anteriores

### Versión 1.0.0 - 1.1.x

Versiones iniciales del sistema ETL con funcionalidad básica:

- Estructura base del sistema
- Modelos de datos iniciales
- Conexiones básicas
- Procesamiento de mensajes

---

## Guía de Actualización

### De v1.2.0 a v2.1

1. **Actualizar dependencias en `mix.exs`**:
```elixir
{:etl_core, git: "https://github.com/krl21/etl-core.git", branch: "v2.1"}
```

2. **Configurar pools en el supervisor** (opcional, para usar Pool Mode):
```elixir
# En lib/mi_app/application.ex
children = [
  # ... otros children
  Pool.Postgres.child_spec(:postgres_pool, pool_config),
  Pool.BigQuery.child_spec(:bigquery_pool, bq_pool_config)
]
```

3. **Migrar funciones de inserción** (opcional):
   - Cambiar `execute_insert/3` por `execute_insert_pooled/3`
   - Actualizar llamadas para usar nombres de pools

### De v2.1 a v2.2

1. **Actualizar dependencias en `mix.exs`**:
```elixir
{:etl_core, git: "https://github.com/krl21/etl-core.git", branch: "v2.2"}
```

2. **Crear carpeta `constants/`** (opcional):
   - Los archivos JSON se cargan automáticamente si existen
   - Puedes personalizar feriados y mapeos de caracteres

3. **No se requieren cambios en el código existente**

### De v2.2 a v2.3

1. **Actualizar dependencias en `mix.exs`**:
```elixir
{:etl_core, git: "https://github.com/krl21/etl-core.git", branch: "v2.3"}
```

2. **No se requieren cambios en el código existente**
   - La refactorización es interna y transparente
   - La API pública se mantiene igual
   - Mejoras de rendimiento automáticas

### De v2.3 a v2.4

1. **Actualizar dependencias en `mix.exs`**:
```elixir
{:etl_core, git: "https://github.com/krl21/etl-core.git", branch: "v2.4"}
```

2. **No se requieren cambios de firma en el código existente**
   - `Genserver.RabbitConsumer` se comporta igual ante arranque; mejora la recuperación cuando RabbitMQ o la red cortan el socket
   - Si se interpretaba el entero de `{:ok, n}` en limpieza BigQuery como “filas borradas”, tener en cuenta que en éxito puede ser **0** (reemplazo de tabla)

### De v2.4 a v2.5

1. **Actualizar dependencias en `mix.exs`**:
```elixir
{:etl_core, git: "https://github.com/krl21/etl-core.git", branch: "v2.5"}
```

2. **Sin cambios obligatorios de código**
   - Revisar opcionalmente `docs/BIGQUERY_GUIA_REFERENCIA.md` para operación y troubleshooting de BigQuery por ODBC

### De v2.5 a v2.5.1

1. **Actualizar dependencias en `mix.exs`**:
```elixir
{:etl_core, git: "https://github.com/krl21/etl-core.git", branch: "v2.5.1"}
```

2. **Sin cambios obligatorios** para el flujo estándar de subida a BigQuery
   - Opcional: configurar `:pending_limit` en `Genserver.BigqueryUploader` si hay muchos registros pendientes en PostgreSQL
   - Si existe implementación custom de `PBigqueryPostProcess`, actualizar `:successful_ids` → `:successful_id_nodos`

---

## Notas de Versión

### Compatibilidad

- **Elixir**: Requiere Elixir ~> 1.14.0-rc.0
- **OTP**: Compatible con versiones modernas de OTP
- **PostgreSQL**: Compatible con versiones 10+
- **BigQuery**: Compatible con todas las versiones actuales

### Dependencias Principales

- `timex` - Manejo de fechas
- `jason` / `poison` - Procesamiento JSON
- `postgrex` - Cliente PostgreSQL
- `nimble_pool` - Pools de conexiones
- `poolboy` - Pool para BigQuery/ODBC
- `amqp` - Cliente RabbitMQ
- `ecto_sql` - SQL para Ecto

### Breaking Changes

**v2.5 → v2.5.1**: Cambio menor en protocolo post-proceso
- `Genserver.Protocols.PBigqueryPostProcess`: el contexto usa `:successful_id_nodos` en lugar de `:successful_ids`. Solo afecta implementaciones custom de `after_upload/3`
- Firmas existentes de `get_pending_bq/3`, `run/9` y `run_with_pool/9` siguen siendo compatibles (nuevos argumentos opcionales con default)

**v2.4 → v2.5**: Ninguno
- Incorporación de documentación (`BIGQUERY_GUIA_REFERENCIA.md`); sin cambios en contratos de módulos del core descritos en esta versión

**v2.3 → v2.4**: Ninguno en firmas públicas
- Comportamiento mejorado ante caída AMQP (reinicio del consumidor por el supervisor de la app)
- Limpieza BigQuery: retorno `{:ok, 0}` en el camino de éxito (sin conteo de filas); si algún código dependía del número devuelto, revisar

**v2.2 → v2.3**: Ninguno
- Refactorización interna transparente
- API pública sin cambios
- Mejoras de rendimiento automáticas

**v2.1 → v2.2**: Ninguno
- Cambios son aditivos
- Compatibilidad total con código existente

**v1.2.0 → v2.1**: Ninguno (modo legacy compatible)
- El código existente sigue funcionando
- Migración a pools es opcional

---

## Roadmap Futuro

### Próximas mejoras (post v2.5.1)

- Mejoras en el sistema de constantes
- Soporte para múltiples zonas horarias
- Optimizaciones de rendimiento adicionales

### Versión 3.0 (En Consideración)

- Refactorización mayor de la API
- Nuevo sistema de configuración
- Soporte para más bases de datos

---

## Soporte

Para preguntas sobre versiones específicas o migración, consultar:
- `docs/ARQUITECTURA.md` - Arquitectura del sistema
- `docs/BIGQUERY_GUIA_REFERENCIA.md` - Referencia BigQuery (ODBC, Docker, tablas por negocio)
- `docs/MODULOS_REFERENCIA.md` - Referencia de módulos
- `docs/GUIA_CREAR_ETL.md` - Guía para crear nuevos ETLs

