# Historial de Versiones - ETL-Core

Este documento describe las versiones de `etl-core`, sus características principales y los cambios introducidos en cada versión.

---

## Tabla de Contenidos

1. [Versión 2.8 (Actual)](#versión-28-actual)
2. [Versión 2.7](#versión-27)
3. [Versión 2.6.1](#versión-261)
4. [Versión 2.6.0](#versión-260)
5. [Versión 2.5.1](#versión-251)
6. [Versión 2.5](#versión-25)
7. [Versión 2.4](#versión-24)
8. [Versión 2.3](#versión-23)
9. [Versión 2.2](#versión-22)
10. [Versión 2.1](#versión-21)
11. [Versión 1.2.0](#versión-120)
12. [Versiones Anteriores](#versiones-anteriores)

---

## Versión 2.8 (Actual)

### Características Principales

- **Google Cloud Storage**: nuevo módulo `Connection.Gcs` para trabajar con buckets (subir, descargar, listar y eliminar archivos y carpetas), autenticado con una cuenta de servicio
- **Subidas grandes y en paralelo**: los archivos de más de 8 MiB se suben de forma resumable (por bloques de 8 MiB) y varios archivos se pueden subir en paralelo
- **Carga de GCS a BigQuery**: nuevo módulo `Connection.GcsToBigQuery`, que carga archivos de GCS en tablas de BigQuery con `LOAD DATA` a través de ODBC, usando el esquema de la tabla destino
- **Carga directa a BigQuery en la carga forzada**: al terminar la carga a RabbitMQ, la carga forzada puede exportar los registros pendientes de la tabla temporal de Postgres a archivos JSONL, subirlos a GCS y cargarlos en BigQuery
- **`ForcedLoad.Handler` dividido en submódulos**: el handler conserva solo la API pública (`run/3` y `run_record_load/2`)

### Nuevo en esta Versión

#### `Connection.Gcs` (nuevo)

- `configure/1`: recibe una vez las credenciales de la cuenta de servicio (ruta al JSON, contenido o mapa). El token se obtiene con Goth y se guarda en caché hasta 5 minutos antes de vencer
- Subida: `upload_file/4`, `upload_binary/4`, `upload_to_folder/4`, `upload_files/4` (en paralelo, 4 por defecto) y `upload_directory/4`. Devuelven la URI `gs://bucket/objeto`
- Descarga y lectura: `read_object/2`, `download_file/3` (si la ruta termina en `/`, usa el nombre del objeto) y `download_folder/3`
- Consulta: `list_objects/2`, `exists?/2`, `folder_exists?/2`, `gcs_uri/2`
- Carpetas y borrado: `create_folder/2`, `delete_object/2`, `delete_folder/2`
- Reintentos con backoff exponencial y jitter ante errores 408, 429, 5xx y de red
- `Connection.Gcs.Helpers`: funciones de apoyo (petición HTTP con Tesla y hackney, subida media y resumable, token, reintentos)
- `Connection.Gcs.ContentType`: tipo MIME según la extensión del archivo (82 extensiones; por defecto `application/octet-stream`)

#### `Connection.GcsToBigQuery` (nuevo)

- `configure/2`: guarda la configuración ODBC para que el driver Simba se autentique con la cuenta de servicio de las credenciales (la misma de `Connection.Gcs`). La valida abriendo y cerrando una conexión
- `load/3` y `load/4`: ejecutan `LOAD DATA` dentro de `BEGIN ... END;` (como sentencia suelta, el driver le asigna una tabla de destino y BigQuery la rechaza). `load/4` acepta un pid, un pool o una configuración ODBC
- Antes de cargar, leen las columnas de la tabla en `INFORMATION_SCHEMA.COLUMNS` y las indican en `LOAD DATA`, para que BigQuery no detecte el esquema desde los archivos (p. ej. un `STRING` con fechas cargado como `DATE`). La tabla debe existir
- Devuelven `:ok` o `{:error, mensaje}`; el mensaje de un error de carga incluye las URIs
- `export_records/5` y `export_records/6`: convierten registros a NDJSON, los suben a GCS, los cargan y borran el archivo
- Formatos: CSV, NDJSON, Parquet, Avro y ORC. Modos: `:append` (por defecto) y `:overwrite`

#### `Connection.Odbc`

- `execute/2` (nuevo): ejecuta cualquier sentencia (p. ej. `LOAD DATA` o un script `BEGIN ... END;`) sin reintentos. Si falla, lanza una excepción con el mensaje del driver como texto
- Logs: se distingue la aplicación ODBC (`start/0`, `stop/0`) de las conexiones (`connect/1`, `disconnect/1`), y se incluye el pid en la apertura y el cierre

#### Carga forzada (`ForcedLoad`)

- `ForcedLoad.Config`: nuevos callbacks opcionales para la carga directa a BigQuery:

| Campo | Por defecto | Descripción |
|---|---|---|
| `bigquery_direct_load` | `false` | Activa la carga directa |
| `bigquery_tables_by_type` | `[]` | Lista de `{tipo, tabla}` |
| `postgres_pool` | `:postgres_pool` | Pool de `Pool.Postgres` |
| `postgres_temp_table` | `nil` | Tabla temporal con los registros (obligatoria) |
| `postgres_export_batch_size` | `10_000` | Registros por lote al exportar y marcar |
| `files_path` | `"./tmp"` | Directorio local de los archivos |
| `gcs_bucket` | `nil` | Bucket (obligatorio) |
| `gcs_folder` | `nil` | Carpeta del bucket; con `nil` o `""`, la raíz |
| `gcs_credentials` | `nil` | JSON de credenciales de la cuenta de servicio, como mapa o string (obligatorio) |

- `ForcedLoad.Config.default/1`: valores por defecto de `postgres_pool`, `postgres_export_batch_size` y `files_path`
- `ForcedLoad.Helpers.validate_direct_load!/1`: valida los campos, que el pool esté iniciado y que exista la tabla temporal; crea el directorio y configura `Connection.Gcs` y `Connection.GcsToBigQuery`
- `ForcedLoad.Handler.DirectLoad.run/4` (nuevo), al terminar la carga a RabbitMQ:
  1. Espera a que se vacíen las colas usadas (cada 10 s, hasta 5 minutos; 5 s más al vaciarse). Si no se vacían, continúa; si falla la consulta, notifica y termina
  2. Por cada tipo, exporta los registros `sin_analizar` a `<business_name>_<tipo>-<yyyyMMddHHmmssSSS>.jsonl` (una línea por columna `informacion`) y los marca como `analizado_en_bq` en Postgres, por lotes y en una transacción por tipo. Si falla, se revierte
  3. Sube los archivos a GCS con hasta 3 reintentos cada 5 s, y borra del directorio local los subidos
  4. Carga cada archivo en su tabla y borra de GCS los cargados
  5. Notifica un resumen de éxitos y fallos. Los archivos no subidos quedan en `files_path` y los no cargados, en GCS
- `ForcedLoad.Handler`: la conexión ODBC a BigQuery se cierra al terminar los intervalos, antes de la carga directa. El código interno pasa a `ForcedLoad.Handler.Loader` (intervalos, expedientes y tareas) y `ForcedLoad.Handler.Ids` (obtención de IDs)
- `Genserver.ForcedLoad.init/1`: valida la configuración de la carga directa. Si es inválida, notifica el error y devuelve `:ignore` (la carga forzada no se ejecuta, pero la aplicación sigue en pie)

#### Dependencias (`mix.exs`)

- Nuevas: `goth ~> 1.4` (token OAuth de Google) y `tesla ~> 1.22` (cliente HTTP de GCS, con adaptador hackney)
- Fijadas por compatibilidad con Elixir 1.14: `finch ~> 0.21.0`, `mint 1.9.1` y `hpax 1.0.3` (las versiones posteriores requieren Elixir 1.15)
- `compile.sh` (nuevo): desbloquea y limpia `hpax` y `mint` y las dependencias sin uso, y recompila

### Módulos Afectados

- Nuevos: `Connection.Gcs`, `Connection.Gcs.Helpers`, `Connection.Gcs.ContentType`, `Connection.GcsToBigQuery`, `ForcedLoad.Handler.DirectLoad`, `ForcedLoad.Handler.Loader`, `ForcedLoad.Handler.Ids`
- `Connection.Odbc`: `execute/2` (nuevo), logs de `start/0`, `stop/0`, `connect/1`, `disconnect/1`
- `ForcedLoad.Config`, `ForcedLoad.Helpers`, `ForcedLoad.Handler`, `Genserver.ForcedLoad`

### Migración desde v2.7

1. **Actualizar dependencias en `mix.exs`**:
```elixir
{:etl_core, git: "https://github.com/krl21/etl-core.git", branch: "v2.8"}
```
Si el proyecto fija `finch`, `mint` o `hpax` en versiones que requieren Elixir 1.15, debe alinearlas con las de `etl-core`.

2. **Sin cambios obligatorios de código**: la carga directa está desactivada por defecto y la API pública de `ForcedLoad.Handler` no cambia.

3. **Para activar la carga directa** (opcional):
   - Definir en la configuración `bigquery_direct_load`, `bigquery_tables_by_type`, `postgres_temp_table`, `gcs_bucket` y `gcs_credentials` (y, si aplica, `gcs_folder`, `postgres_pool`, `postgres_export_batch_size` y `files_path`)
   - La cuenta de servicio debe tener acceso al bucket y a BigQuery: el driver ODBC se autentica con ella, no con la cuenta del DSN
   - El pool de Postgres debe iniciarse antes que `Genserver.ForcedLoad` en el árbol de supervisión
   - Las tablas de BigQuery deben existir

4. **Uso directo de funciones privadas de `ForcedLoad.Handler`**: si algún ETL dependía de ellas (no deberían), ahora están en `ForcedLoad.Handler.Loader` e `Ids`.

---

## Versión 2.7

### Características Principales

- **Texto UTF-8 real en BigQuery**: los valores de texto se envían y se guardan tal cual (con `ñ`, tildes, comillas, emojis, etc.), sin reemplazarlos por la plantilla de caracteres especiales (`ñ` → `%nn%`, `'` → `%r_%`, …)
- **Queries codificadas como bytes UTF-8**: las sentencias se envían al driver ODBC con `:binary.bin_to_list/1` en lugar de `Kernel.to_charlist/1`. Esto evita que los caracteres fuera de ASCII lleguen como bytes inválidos y queden guardados como `�` (U+FFFD)
- **Resultados como binarios**: la conexión ODBC se abre con `binary_strings: :on`, por lo que el driver devuelve los textos como binarios de Elixir en vez de charlists
- **Escape correcto de literales**: al no existir la plantilla, los strings se escapan como literales de BigQuery para no romper el SQL ni abrir inyección (p. ej. `O'Higgins` → `'O\'Higgins'`)

### Nuevo en esta Versión

#### `Connection.Odbc`

- `connect/1`: abre la conexión con `:odbc.connect(conn_str, binary_strings: :on)` (antes `[]`)
- `insert/2`, `update/2`, `delete/2`, `select/2` y `get_uuid/1`: convierten la sentencia con `:binary.bin_to_list/1` (antes `Kernel.to_charlist/1`)
- `get_uuid/1`: usa `to_string/1` en lugar de `List.to_string/1` para soportar el UUID devuelto como binario

#### `Type.Type`

- `convert_for_bigquery/1` (strings): ya no llama a `Type.Normalize.normalize_special_chars/1`
- `convert_for_bigquery/1` (mapas → `JSON`): ya no normaliza el JSON generado por `Poison.encode!/1`; ahora se escapa con `escape_bigquery_string/1`
- `escape_bigquery_string/1` (privada): escapa `\`, `'`, `\n`, `\r` y `\t` como literal de BigQuery. El backslash se escapa primero
- `convert_from_bigquery/1`: devuelve el valor sin desnormalizar (se comenta `unescape_bigquery_string/1`)
- Se comenta el `alias Type.Normalize`, que queda sin uso

`Type.Normalize` y `lib/type/char_mappings.json` se mantienen en el código, pero ya no se invocan al subir ni al leer.

### Módulos Afectados

- `Connection.Odbc`: `connect/1`, `insert/2`, `update/2`, `delete/2`, `select/2`, `get_uuid/1`
- `Type.Type`: `convert_for_bigquery/1`, `convert_from_bigquery/1`, `escape_bigquery_string/1`

### Migración desde v2.6.1

1. **Actualizar dependencias en `mix.exs`**:
```elixir
{:etl_core, git: "https://github.com/krl21/etl-core.git", branch: "v2.7"}
```

2. **Registros históricos**: los datos que ya están en BigQuery con plantilla (`%nn%`, `%aa%`, `%r_%`, …) **ya no se desnormalizan al leer** y se verán literal. Si un proceso necesita mostrarlos correctamente, debe aplicar `Type.Normalize.denormalize_special_chars/1` de forma explícita o migrar esos datos.

3. **Uso directo de `:odbc`**: quien use el `pid` de `Connection.Odbc.connect/1` con `:odbc.sql_query/2` directamente recibirá los textos como **binarios** en lugar de charlists, y debe enviar sus queries con `:binary.bin_to_list/1`. Quienes usan `Connection.Odbc.select/2` no se ven afectados.

4. **Caracteres fuera de ASCII**: los caracteres que antes se descartaban (emojis, símbolos no mapeados, etc.) ahora se guardan. Revisar si algún consumidor aguas abajo asumía texto solo ASCII.

---

## Versión 2.6.1

### Características Principales

- **Resiliencia ante caídas masivas de conexión AMQP**: mitiga el escenario observado en producción donde varios consumers caían casi simultáneamente por `:socket_closed_unexpectedly`, agotaban la intensidad de reinicio por defecto de OTP y escalaban el crash hasta dejar colas sin consumidor
- **Jitter en la reconexión**: `Genserver.RabbitConsumer` espera un intervalo aleatorio antes de dejar que el supervisor lo reinicie, evitando que todos los consumers reconecten en el mismo instante
- **Mayor tolerancia a ráfagas de reinicio**: `Genserver.ConsumerSupervisor` soporta más reinicios en una ventana más amplia antes de escalar el crash a su supervisor padre
- **Recuperación automática del registro de consumers**: nuevo `Genserver.ConsumerBootstrap`, pensado para vivir junto a `ConsumerSupervisor` dentro de un supervisor `:rest_for_one`, de modo que si `ConsumerSupervisor` llega a caer y reiniciarse, los consumers se vuelven a registrar automáticamente

### Nuevo en esta Versión

#### `Genserver.RabbitConsumer`

- Al recibir `{:DOWN, ref, :process, _pid, reason}` (conexión AMQP caída), ahora se espera un jitter de **1 a 5 segundos** (`Process.sleep/1` con un delay aleatorio) antes de retornar `{:stop, {:amqp_connection_down, reason}, state}`
- Objetivo: cuando RabbitMQ o la red cortan el socket de varias colas a la vez, evita que todos los consumers golpeen la reconexión en el mismo instante ("tormenta de reconexión")

#### `Genserver.ConsumerSupervisor`

- `init/1` ahora inicializa el `DynamicSupervisor` con `max_restarts: 10, max_seconds: 30`, en lugar del default de OTP (`max_restarts: 3, max_seconds: 5`)
- Objetivo: tolerar que varios consumers caigan casi simultáneamente (p. ej. un corte de red o un reinicio del broker) sin agotar la intensidad de reinicio y escalar el crash al supervisor de la aplicación

#### `Genserver.ConsumerBootstrap` (módulo nuevo)

`GenServer` cuyo único propósito es, en su `init/1`, invocar `Genserver.ConsumerSupervisor.start_consumers/1` con la lista de consumers configurados.

Pensado para ejecutarse como el hijo inmediatamente después de `Genserver.ConsumerSupervisor` dentro de un supervisor con estrategia `:rest_for_one`:

```elixir
%{
    id: MyApp.ConsumersTree,
    type: :supervisor,
    start: {Supervisor, :start_link, [
        [
            Genserver.ConsumerSupervisor,
            {Genserver.ConsumerBootstrap, consumers}
        ],
        [strategy: :rest_for_one, name: MyApp.ConsumersTree]
    ]}
}
```

Con `:rest_for_one`, si `ConsumerSupervisor` cae (p. ej. agotó su intensidad de reinicio), se reinicia junto con `ConsumerBootstrap`, que en su nuevo `init/1` vuelve a registrar todos los consumers. Sin este mecanismo, `ConsumerSupervisor` solo recrea su tabla ETS interna al reiniciarse — no sabe qué consumers debía tener corriendo — y las colas quedarían sin consumidor hasta un reinicio manual o de la aplicación completa.

`start_consumer/2` es idempotente ante colas ya `:running`, por lo que volver a llamar `start_consumers/1` en cada `init/1` es seguro incluso si algunos consumers seguían vivos.

### Módulos Afectados

- `Genserver.RabbitConsumer`: jitter antes de `{:stop, {:amqp_connection_down, reason}, state}`
- `Genserver.ConsumerSupervisor`: intensidad de reinicio del `DynamicSupervisor`
- `Genserver.ConsumerBootstrap`: módulo nuevo

### Migración desde v2.6.0

1. **Actualizar dependencias en `mix.exs`**:
```elixir
{:etl_core, git: "https://github.com/krl21/etl-core.git", branch: "v2.6.1"}
```

2. **Sin cambios obligatorios**: `Genserver.RabbitConsumer` y `Genserver.ConsumerSupervisor` mantienen la misma API pública; el jitter y la intensidad de reinicio son transparentes para el llamador.

3. **Recomendado — cerrar el gap de re-registro**: envolver `Genserver.ConsumerSupervisor` junto con `Genserver.ConsumerBootstrap` en un supervisor `:rest_for_one` (ver ejemplo arriba), en lugar de montar `Genserver.ConsumerSupervisor` como hijo directo del supervisor raíz y llamar `start_consumers/1` una sola vez tras `Supervisor.start_link/2`. Si se mantiene el patrón anterior, el comportamiento es el mismo que en v2.6.0 (sin el fix del gap de re-registro).

---

## Versión 2.6.0

### Características Principales

- **Control manual de consumers RabbitMQ en runtime**: Nuevo `Genserver.ConsumerSupervisor` que permite detener, iniciar y reiniciar consumers por nombre de cola sin reiniciar la aplicación
- **Ciclo de vida del canal AMQP garantizado**: `Genserver.RabbitConsumer` linkea el canal a su propio proceso, asegurando que el canal se cierre siempre que el GenServer muera

### Nuevo en esta Versión

#### `Genserver.ConsumerSupervisor`

`DynamicSupervisor` que gestiona el ciclo de vida de `Genserver.RabbitConsumer` y `Genserver.RabbitConsumerByBatch`. Mantiene un registro ETS interno con el módulo y los args originales de cada consumer, de modo que pueden reiniciarse sin que el caller conserve la configuración. El `init/1` es seguro ante reinicios del supervisor (no falla si la tabla ETS ya existe).

**API pública:**

- **`start_consumer/2`**: Inicia un consumer hijo bajo el supervisor. Comportamiento según el estado actual de la cola:
  - `:not_found` → arranca el consumer con los args proporcionados.
  - `:running` → devuelve el pid existente sin reiniciar.
  - `:stopped` → limpia la entrada y reinicia con los nuevos args.
  - Retorna `{:ok, pid}` o `{:error, reason}`.

- **`start_consumers/1`**: Inicia múltiples consumers de una vez a partir de una lista de tuplas `{module, args}`. Usado desde `Application.start/2` tras levantar el árbol de supervisión.

- **`stop_consumer/1`**: Detiene el consumer de la cola indicada de forma limpia (ejecuta `terminate/2`, cierra la conexión AMQP, mensajes sin ack vuelven a la cola). El consumer no se reinicia automáticamente.

- **`restart_consumer/1`**: Reinicia el consumer usando los args originales retenidos en el registro ETS. Útil para recuperar un consumer en estado `:stopped`.

- **`restart_consumer/3`**: Reinicia el consumer con un nuevo `module` y `args`. Actualiza el registro ETS con los nuevos valores.

- **`remove_consumer/1`**: Detiene el consumer y lo elimina permanentemente del registro. A diferencia de `stop_consumer/1`, tras esta llamada `restart_consumer/1` retornará `{:error, :not_found}`.

- **`list_consumers/0`**: Devuelve todos los consumers registrados con sus campos `:queue`, `:module`, `:pid` y `:status`.

- **`consumer_status/1`**: Devuelve `:running`, `:stopped` o `:not_found` para una cola dada.

**Comportamiento ante crashes:** Los consumers usan estrategia `:transient`, por lo que un crash inesperado (p. ej. caída de la conexión AMQP) es reiniciado automáticamente por el `ConsumerSupervisor`. Las salidas `:normal` y `:shutdown` no provocan reinicio automático.

#### `Genserver.RabbitConsumer`

- **`Process.link(channel.pid)`** en `init/1`: el proceso de canal AMQP queda vinculado al GenServer. Si el GenServer muere (incluyendo `:kill`), el canal muere con él y RabbitMQ desregistra el consumer de inmediato.
- **`Process.flag(:trap_exit, true)`** en `init/1`: las señales de exit de procesos linkeados llegan como mensajes, permitiendo que `terminate/2` se ejecute siempre en un shutdown limpio.
- **`terminate/2`**: cierra la conexión AMQP, lo que por protocolo cierra en cascada todos sus canales.

### Módulos Afectados

- `Genserver.ConsumerSupervisor`: módulo nuevo
- `Genserver.RabbitConsumer`: ciclo de vida del canal AMQP

### Migración desde v2.5.1

1. **Actualizar dependencias en `mix.exs`**:
```elixir
{:etl_core, git: "https://github.com/krl21/etl-core.git", branch: "v2.6.0"}
```

2. **Agregar `Genserver.ConsumerSupervisor` al árbol de supervisión** (después de los pools):
```elixir
children = [
  child_postgres_pool(),
  child_bigquery_pool(),
  Genserver.ConsumerSupervisor
]
{:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)
```

3. **Inicializar los consumers tras levantar el supervisor**:
```elixir
Genserver.ConsumerSupervisor.start_consumers(rabbit_consumer_configs())
```

4. **Adaptar la función que construye los consumers** — en lugar de devolver child specs para el supervisor raíz, debe devolver tuplas `{module, args}`:
```elixir
# Antes
defp rabbit_consumer_children do
  Enum.map(queues, fn {_key, queue_info} ->
    %{id: :"RabbitConsumer.#{queue_info.config.queue}",
      start: {Genserver.RabbitConsumer, :start_link, [{queue_info, amqp, info}]}}
  end)
end

# Después
defp rabbit_consumer_configs do
  Enum.map(queues, fn {_key, queue_info} ->
    {Genserver.RabbitConsumer, {queue_info, amqp, info}}
  end)
end
```

---

## Versión 2.5.1

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

### De v2.5.1 a v2.6.0

1. **Actualizar dependencias en `mix.exs`**:
```elixir
{:etl_core, git: "https://github.com/krl21/etl-core.git", branch: "v2.6.0"}
```

2. **Agregar `Genserver.ConsumerSupervisor` al árbol de supervisión** y mover la inicialización de consumers fuera del `build_children/0`. Ver sección [Migración desde v2.5.1](#migración-desde-v251) en la descripción de v2.6.0.

3. **Sin cambios obligatorios** si se prefiere mantener los consumers como hijos directos del supervisor raíz

### De v2.6.0 a v2.6.1

1. **Actualizar dependencias en `mix.exs`**:
```elixir
{:etl_core, git: "https://github.com/krl21/etl-core.git", branch: "v2.6.1"}
```

2. **Sin cambios obligatorios de código** para conservar el comportamiento anterior (con las mejoras de jitter e intensidad de reinicio ya activas)
3. **Opcional — recomendado**: adoptar `Genserver.ConsumerBootstrap` en un supervisor `:rest_for_one` junto a `Genserver.ConsumerSupervisor` para cerrar el gap de re-registro de consumers. Ver sección [Migración desde v2.6.0](#migración-desde-v260) en la descripción de v2.6.1

---

## Notas de Versión

### Compatibilidad

- **Elixir**: Requiere Elixir ~> 1.14.0-rc.0
- **OTP**: Compatible con versiones modernas de OTP
- **PostgreSQL**: Compatible con versiones 10+
- **BigQuery**: Compatible con todas las versiones actuales

### Dependencias Principales

- `goth` - Token OAuth de Google (GCS)
- `tesla` - Cliente HTTP para la API de GCS
- `timex` - Manejo de fechas
- `jason` / `poison` - Procesamiento JSON
- `postgrex` - Cliente PostgreSQL
- `nimble_pool` - Pools de conexiones
- `poolboy` - Pool para BigQuery/ODBC
- `amqp` - Cliente RabbitMQ
- `ecto_sql` - SQL para Ecto

### Breaking Changes

**v2.6.0 → v2.6.1**: Ninguno
- `Genserver.ConsumerBootstrap` es un módulo nuevo y aditivo; adoptarlo (envolviendo `ConsumerSupervisor` en un supervisor `:rest_for_one`) es opcional pero recomendado
- El jitter de 1-5s antes de reiniciar un consumer y la mayor intensidad de reinicio de `ConsumerSupervisor` son cambios de comportamiento interno, sin impacto en la API pública

**v2.5.1 → v2.6.0**:
- `Genserver.ConsumerSupervisor` es un módulo nuevo y aditivo; la migración es opcional
- `start_consumer/2` ya no retorna `{:error, :already_running}`; si la cola está `:running` devuelve `{:ok, pid}` del proceso existente
- Los consumers usan `restart: :transient` en lugar de `:permanent`; las salidas `:normal` y `:shutdown` ya no provocan reinicio automático
- Los consumers existentes siguen funcionando sin cambios si no se adopta el nuevo supervisor

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

### Próximas mejoras (post v2.6.1)

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

