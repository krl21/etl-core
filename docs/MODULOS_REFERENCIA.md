# Referencia de Módulos ETL-Core v2.1

Este documento describe los módulos disponibles en `etl-core` v2.1, sus funciones principales y aspectos importantes a considerar.

---

## Tabla de Contenidos

1. [Estructura de Datos](#estructura-de-datos)
2. [Modelos de Datos](#modelos-de-datos)
3. [GenServers](#genservers)
4. [Pools de Conexiones](#pools-de-conexiones) *(nuevo en v2.1)*
5. [Conexiones](#conexiones)
6. [Utilidades](#utilidades)
7. [Limpieza de Datos](#limpieza-de-datos)
8. [Carga Forzada](#carga-forzada)

---

## Estructura de Datos

### `Struct.InfoAttr`

Define los atributos que relacionan campos del payload con columnas en la base de datos.

```elixir
%Struct.InfoAttr{
  id: :nombre_columna,           # Atom. Nombre en la base de datos
  id_payload: "nombrePayload",   # String. Nombre en el payload JSON
  type: :string,                 # Atom. Tipo de dato (:string, :integer, :float, :boolean, :timestamp)
  keys_to_search: ["data"],      # List. Ruta para buscar en el payload anidado
  default_value: nil             # Valor por defecto si no se encuentra
}
```

**Tipos soportados:**
- `:string` - Texto
- `:integer` - Número entero
- `:float` - Número decimal
- `:boolean` - Verdadero/Falso
- `:timestamp` - Fecha/hora (se convierte desde varios formatos)
- `:map` - Objeto JSON
- `:list` - Lista/Array

---

## Modelos de Datos

### `DataModel.Record.Base` / `DataModel.RecordPg.Base`

Base para entidades que procesan y almacenan **expedientes/records** en BigQuery o PostgreSQL respectivamente.

#### Macros de Configuración

| Macro | Descripción |
|-------|-------------|
| `entity_config/1` | Configuración principal de la entidad |
| `own_attributes/1` | Lista de atributos propios |
| `subentities/1` | Lista de sub-entidades |
| `special_post_processing/1` | Entidades que requieren procesamiento especial |
| `generate_helper_functions/0` | Genera funciones auxiliares |

#### Opciones de `entity_config/1`

```elixir
entity_config(
  app: :mi_app,                                    # Requerido. Nombre de la aplicación
  table_key: :record,                              # Clave para tabla en BigQuery (estático)
  table_key_path: [:bigquery, :table, :record],    # O ruta dinámica desde config
  table_name_path: [:postgres, :tables],           # Para PostgreSQL: ruta a nombre de tabla
  batch_size_key: :batch_size_process,             # Clave para tamaño de batch
  unique_id: @unique_id,                           # InfoAttr identificador único
  timestamp: @timestamp,                           # InfoAttr para timestamp (opcional)
  value_type_path: [:postgres, :register_type, :record],  # Tipo de registro (PostgreSQL)
  slack_webhook_url_path: [:notification, :slack_webhook, :url, :bug],  # Notificaciones
  slack_env_var: "ENVIRONMENT"                     # Variable de entorno para ambiente
)
```

#### Funciones Generadas (Building Blocks)

| Función | Descripción |
|---------|-------------|
| `attr_list/0` | Retorna lista completa de atributos (propios + subentidades) |
| `filter_batch/1` | Filtra el batch antes de procesar (sobreescribible) |
| `group_by_unique_id/1` | Agrupa payloads por ID único |
| `build_data/3` | Construye datos del record desde payloads |
| `apply_post_processing/3` | Aplica post-procesamiento especial |
| `prepare_record/4` | Prepara un registro para inserción |
| `execute_insert/3` | Ejecuta inserción (modo legacy - crea conexión temporal) |
| `execute_insert_with_retry/3` | Inserción con retry divide-and-conquer (modo legacy) |
| `execute_insert_pooled/3` | Ejecuta inserción usando pool *(nuevo v2.1)* |
| `execute_insert_with_retry_pooled/3` | Inserción con retry usando pool *(nuevo v2.1)* |
| `handle_processing_error/4` | Maneja errores y envía notificaciones |

#### Ejemplo de Uso

```elixir
defmodule MiApp.Record do
  use DataModel.RecordPg.Base
  
  entity_config(
    app: :mi_app,
    table_name_path: [:postgres, :tables],
    batch_size_key: :batch_size_process,
    unique_id: MiApp.RecordBase.unique_id()
  )
  
  subentities [
    MiApp.RecordBase,
    MiApp.Vehicle,
    MiApp.Buyer
  ]
  
  generate_helper_functions()
  
  def insert_by_lote(batch, batch_id, pg_config) do
    {grouped, keys} = batch |> filter_batch() |> group_by_unique_id()
    
    records = 
      keys
      |> Enum.map(&prepare_record(&1, Map.get(grouped, &1), [], []))
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, r} -> r end)
    
    execute_insert_with_retry(records, pg_config, batch_id)
  end
end
```

---

### `DataModel.Task.Base` / `DataModel.TaskPg.Base`

Base para entidades que procesan y almacenan **tareas**.

#### Macros de Configuración

| Macro | Descripción |
|-------|-------------|
| `task_config/1` | Configuración principal de la tarea |
| `own_attributes/1` | Lista de atributos propios |
| `computed_attributes/1` | Atributos calculados (ej: tiempo transcurrido) |
| `generate_task_helper_functions/0` | Genera funciones auxiliares |

#### Opciones de `task_config/1`

```elixir
task_config(
  app: :mi_app,
  table_name_path: [:postgres, :tables],
  group_by_keys: [@contentref, @name],  # Clave compuesta para agrupar
  timestamp: @timestamp,
  value_type_path: [:postgres, :register_type, :task],
  elapsed_time_config: %{               # Configuración de tiempo transcurrido
    start_date_attr: @start_date,
    end_date_attr: @end_date,
    target_attr: @elapsed_working_time,
    business: :mi_negocio               # Para calcular tiempo laboral
  },
  slack_webhook_url_path: [:notification, :slack_webhook, :url, :bug],
  slack_env_var: "ENVIRONMENT"
)
```

#### Funciones Generadas

| Función | Descripción |
|---------|-------------|
| `attr_list/0` | Retorna lista completa (own + computed) |
| `group_by_composite_key/1` | Agrupa por clave compuesta |
| `build_data/1` | Construye datos de la tarea |
| `calculate_elapsed_time/1` | Calcula tiempo laboral transcurrido |
| `prepare_record/3` | Prepara registro para inserción |
| `execute_insert/3` | Ejecuta inserción |
| `after_insert/3` | Hook post-inserción (sobreescribible) |

---

### `DataModel.Attribute.Provider`

Para definir sub-entidades que solo proveen atributos (sin lógica de inserción).

```elixir
defmodule MiApp.Buyer do
  use DataModel.Attribute.Provider
  
  @name %Struct.InfoAttr{id: :nombre, id_payload: "name", type: :string}
  @rut %Struct.InfoAttr{id: :rut, id_payload: "rut", type: :string}
  
  attr_list [@name, @rut]
  
  # Función opcional para post-procesamiento
  def special_post_processing(values, payload) do
    # Modificar values según lógica de negocio
    values
  end
end
```

---

## GenServers

### `Genserver.RabbitConsumer`

Consumidor continuo de colas RabbitMQ. Soporta modo pool y modo legacy.

**Inicialización (modo pool - recomendado):**
```elixir
{Genserver.RabbitConsumer, {queue_info, amqp_connection, %{
  pg_pool_name: :postgres_pool,  # Nombre del pool de PostgreSQL
  webhook_url: "https://hooks.slack.com/..."
}}}
```

**Inicialización (modo legacy):**
```elixir
{Genserver.RabbitConsumer, {queue_info, amqp_connection, %{
  pg_config: %{hostname: "...", ...},  # Configuración directa
  webhook_url: "https://hooks.slack.com/..."
}}}
```

Donde:
- `queue_info`: Mapa con `:business` y `:config`
- `amqp_connection`: Configuración de conexión AMQP
- `info`: Mapa con `:pg_pool_name` O `:pg_config`, más `:webhook_url`

**Configuración de cola:**
```elixir
%{
  queue: "nombre_cola",
  exchange: "nombre_exchange",
  queue_error: "nombre_cola_error",
  queue_arguments: [
    {"x-dead-letter-exchange", :longstr, ""},
    {"x-dead-letter-routing-key", :longstr, "nombre_cola_error"}
  ],
  listen: ["exchange_1", "exchange_2"]  # Exchanges a escuchar
}
```

---

### `Genserver.ForcedLoad`

GenServer para carga forzada de datos históricos.

**Inicialización:**
```elixir
{Genserver.ForcedLoad, {:record, [start_date, end_date], config}}
```

Donde `config` se construye con `ForcedLoad.Config`.

---

### `Genserver.BigqueryUploader`

Sube datos de PostgreSQL a BigQuery periódicamente. Soporta modo pool y modo legacy.

**Configuración (modo pool - recomendado):**
```elixir
{Genserver.BigqueryUploader, %{
  business: :mi_negocio,
  pg_pool_name: :postgres_pool,     # Nombre del pool de PostgreSQL
  bq_pool_name: :bigquery_pool,     # Nombre del pool de BigQuery
  info: [
    %{bq_table: "tabla_bq", tipo: "expediente", pg_table: "tabla_pg"}
  ],
  periodicity: periodicidad,
  batch_size: 70,
  webhook_url: webhook_url
}}
```

**Configuración (modo legacy):**
```elixir
{Genserver.BigqueryUploader, %{
  business: :mi_negocio,
  data_source: bq_config,           # Configuración ODBC para BigQuery
  pg_config: pg_connection_config,  # Configuración de conexión PostgreSQL
  info: [
    %{bq_table: "tabla_bq", tipo: "expediente", pg_table: "tabla_pg"}
  ],
  periodicity: periodicidad,
  batch_size: 70,
  webhook_url: webhook_url
}}
```

**Ciclo de ejecución (modo pool):**
1. Se obtienen conexiones de los pools
2. Se procesan las tablas configuradas en `info`
3. Las conexiones se devuelven automáticamente al pool

**Ciclo de ejecución (modo legacy):**
1. Se crean las conexiones a PostgreSQL y BigQuery
2. Se procesan las tablas configuradas en `info`
3. Se cierran ambas conexiones (incluso si hay errores, usando `try/after`)

---

### `Genserver.Cleaning`

Limpia registros ya procesados de PostgreSQL periódicamente.

---

### `Genserver.Monitor`

Monitorea el estado de los GenServers y envía heartbeats.

---

## Pools de Conexiones

> **Nuevo en v2.1**: Los pools de conexiones permiten reutilizar conexiones a PostgreSQL y BigQuery,
> evitando la sobrecarga de abrir/cerrar conexiones para cada operación.

### `Pool.Postgres`

Supervisor que gestiona un pool de conexiones PostgreSQL usando Postgrex.

**Características:**
- Pool gestionado por DBConnection (reconexión automática)
- Soporte para modo simple y modo dual (read/write)
- Supervisado por OTP (reinicio automático)

**Inicialización (modo simple):**
```elixir
{Pool.Postgres, %{
  name: :postgres_pool,
  config: %{
    hostname: "localhost",
    port: 5432,
    database: "mi_db",
    username: "user",
    password: "pass"
  },
  pool_size: 10
}}
```

**Inicialización (modo dual):**
```elixir
{Pool.Postgres, %{
  name: :postgres_pool,
  config: %{
    write_hostname: "primary.db",
    read_hostname: "replica.db",
    port: 5432,
    database: "mi_db",
    username: "user",
    password: "pass"
  },
  pool_size: 10
}}
```

**Funciones principales:**

| Función | Descripción |
|---------|-------------|
| `query/3` | Ejecuta query en pool de escritura |
| `query_read/3` | Ejecuta query en pool de lectura (o escritura si no hay dual) |
| `transaction/2` | Ejecuta función dentro de transacción |

---

### `Pool.BigQuery`

Pool de conexiones ODBC para BigQuery usando **poolboy**.

**Características:**
- Workers GenServer con conexión ODBC persistente
- Soporte para `max_overflow` (workers adicionales bajo carga)
- Reconexión automática en caso de fallo
- Estadísticas del pool disponibles

**Inicialización:**
```elixir
{Pool.BigQuery, [
  name: :bigquery_pool,
  data_source: [dsn: "bigquery64", warehouse: "mi_warehouse"],
  pool_size: 5,
  max_overflow: 2  # Workers adicionales bajo carga (opcional, default: 2)
]}
```

**Uso principal:**
```elixir
# Versión que lanza excepción en caso de error
Pool.BigQuery.with_connection(:bigquery_pool, fn conn ->
  Connection.Odbc.insert(conn, statement)
end)

# Versión "safe" que retorna {:ok, result} o {:error, reason}
Pool.BigQuery.with_connection_safe(:bigquery_pool, fn conn ->
  Connection.Odbc.insert(conn, statement)
end)
```

**Funciones principales:**

| Función | Descripción |
|---------|-------------|
| `with_connection/3` | Ejecuta función con conexión del pool (lanza excepción en error) |
| `with_connection_safe/3` | Ejecuta función retornando `{:ok, result}` o `{:error, reason}` |
| `status/1` | Retorna estado del pool (`:running` o `:pool_not_found`) |
| `pool_stats/1` | Retorna estadísticas: workers disponibles, overflow, checked out |

---

### `Pool.BigQuery.Worker`

Worker GenServer que gestiona una conexión ODBC individual.

**Características:**
- Mantiene conexión ODBC persistente
- Reconecta automáticamente si la conexión falla en `init/1`
- Desconecta limpiamente en `terminate/2`

**Funciones:**

| Función | Descripción |
|---------|-------------|
| `execute/3` | Ejecuta función con la conexión ODBC del worker |

---

### `Connection.PostgresPool`

API de alto nivel para operaciones PostgreSQL usando un pool nombrado.

**Funciones principales:**

| Función | Descripción |
|---------|-------------|
| `insert_many/3` | Inserta múltiples registros |
| `get_pending_bq/3` | Obtiene registros pendientes de BigQuery |
| `mark_as_sent_to_bq/3` | Marca registros como enviados |
| `delete_analyzed_records/3` | Elimina registros analizados |
| `create_table_if_not_exists/2` | Crea tabla si no existe |

**Ejemplo:**
```elixir
# Insertar registros usando pool
Connection.PostgresPool.insert_many(:postgres_pool, "mi_tabla", [
  %{id_nodo: "uuid-1", tipo: "expediente", informacion: %{...}},
  %{id_nodo: "uuid-2", tipo: "expediente", informacion: %{...}}
])

# Obtener pendientes
Connection.PostgresPool.get_pending_bq(:postgres_pool, "mi_tabla", "expediente")
```

---

## Conexiones

### `Connection.Odbc`

Conexión a BigQuery via ODBC.

```elixir
# Iniciar ODBC
Connection.Odbc.start()

# Conectar
pid = Connection.Odbc.connect([dsn: "mi_dsn", warehouse: "mi_warehouse"])

# Operaciones
Connection.Odbc.insert(pid, statement)
Connection.Odbc.select(pid, statement)
Connection.Odbc.update(pid, statement)
Connection.Odbc.delete(pid, statement)

# Cerrar
Connection.Odbc.disconnect(pid)
```

---

### `Connection.Postgres`

Conexión y operaciones con PostgreSQL.

**Modos de conexión:**
- **Simple**: Un solo servidor
- **Dual**: Read replica (separar lectura/escritura)

```elixir
# Conexión simple
{:ok, conn} = Connection.Postgres.connect(%{
  hostname: "localhost",
  port: 5432,
  database: "mi_db",
  username: "user",
  password: "pass"
})

# Conexión dual
{:ok, conn} = Connection.Postgres.connect(%{
  write_hostname: "primary.db",
  read_hostname: "replica.db",
  # ... resto de configuración
})
```

**Operaciones principales:**
```elixir
# Insertar registros
Connection.Postgres.insert_many(conn, "tabla", [%{id_nodo: "uuid", tipo: "tipo", informacion: %{...}}])

# Obtener pendientes de BQ
Connection.Postgres.get_pending_bq(conn, "tabla", "tipo_registro")

# Marcar como enviados
Connection.Postgres.mark_as_sent_to_bq(conn, "tabla", [id1, id2])

# Eliminar analizados
Connection.Postgres.delete_analyzed_records(conn, "tabla", register_type: "expediente")
```

**Estructura de tabla:**
| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | SERIAL | PK autoincremental |
| `id_nodo` | VARCHAR(100) | UUID del nodo |
| `tipo` | VARCHAR(100) | Tipo de registro |
| `informacion` | JSONB | Datos del registro |
| `fecha_creado` | TIMESTAMP | Fecha de creación |
| `estado_analisis` | VARCHAR(20) | Estado: sin_analizar, analizado_en_bq, con_problemas |

---

## Utilidades

### `Common.Payload`

Funciones para trabajar con payloads JSON.

```elixir
# Extraer dato del payload
Common.Payload.extract_data(payload, "campo", ["ruta", "anidada"], valor_default)

# Extraer y formatear según lista de atributos
Common.Payload.extract_with_format(payload, attr_list, eliminar_nulos?)

# Agrupar por campos
{mapa_agrupado, lista_claves} = Common.Payload.reduce_by(lista, [campo1_attr, campo2_attr])
```

---

### `Type.Type`

Conversiones de tipos.

```elixir
# Convertir valor a tipo específico
Type.Type.convert("123", :integer)  # => 123
Type.Type.convert(123, :string)     # => "123"
Type.Type.convert(1668036600542, :string_datetime)  # => "2022-11-09T23:30:00.542Z"

# Convertir para BigQuery
Type.Type.convert_for_bigquery("texto")  # => "'texto'"
Type.Type.convert_for_bigquery(nil)      # => "NULL"
```

---

### `Statement.Sql`

Generación de statements SQL para BigQuery.

```elixir
# INSERT
Statement.Sql.insert("tabla", [campo1: valor1, campo2: valor2])

# Combinar múltiples inserts
Statement.Sql.merge_inserts([query1, query2])

# SELECT con WHERE
Statement.Sql.select("tabla", [:campo1, :campo2], where: [campo: valor])
```

---

### `Time.WorkingTime`

Cálculo de tiempo laboral.

```elixir
# Calcular tiempo transcurrido en horario laboral
Time.WorkingTime.elapsed_time(fecha_inicio, fecha_fin, :mi_negocio, opts)
# => {:ok, minutos} | {:error, mensaje}
```

---

### `Notification.Notify`

Envío de notificaciones.

```elixir
Notification.Notify.notify_slack(
  webhook_url,
  [{"Content-type", "application/json"}],
  "Ambiente",
  "Mensaje"
)
```

---

## Limpieza de Datos

### `Cleaning.CleanableTable`

Behaviour para entidades que pueden limpiarse automáticamente.

```elixir
defmodule MiApp.Record do
  use Cleaning.CleanableTable
  
  @impl Cleaning.CleanableTable
  def business_key, do: :record
  
  @impl Cleaning.CleanableTable
  def bigquery_config do
    %{
      table: "tabla_bq",
      id_fields: [unique_id_attr()],
      timestamp_field: timestamp_attr()
    }
  end
  
  @impl Cleaning.CleanableTable
  def postgres_config do
    %{
      table: "tabla_pg",
      register_type: "expediente"
    }
  end
end
```

---

## Carga Forzada

### `ForcedLoad.Config`

Behaviour para configurar cargas forzadas.

**Callbacks requeridos:**
- `app_name/0` - Nombre de la aplicación
- `business_name/0` - Nombre legible del negocio
- `documentary_type/0` - Tipo documental para ElasticSearch
- `record_queue_path/0` - Ruta a cola de records
- `task_queue_path/0` - Ruta a cola de tareas
- `bigquery_table_path/0` - Ruta a tabla BigQuery
- `unique_id_field/0` - Campo de ID único en BigQuery
- `unique_id_payload_field/0` - Campo de ID único en payload
- `last_update_field/0` - Campo de última actualización en BigQuery
- `last_update_payload_field/0` - Campo de última actualización en payload

**Callbacks opcionales:**
- `time_step/0` - Días por intervalo (default: 7)
- `batch_size/0` - Tamaño de batch (default: 200)
- `batch_delay/0` - Delay entre batches (default: 0)
- `includes_record/0` - Cargar records (default: true)
- `includes_task/0` - Cargar tareas (default: true)
- `task_name_filter/0` - Lista de tareas a filtrar
- `skip_elasticsearch/0` - Omitir consultas ES (default: false)
- `skip_bigquery/0` - Omitir consultas BQ (default: false)

```elixir
defmodule MiApp.ForcedLoadConfig do
  use ForcedLoad.Config
  
  @impl true
  def app_name, do: :mi_app
  
  @impl true
  def business_name, do: "MI NEGOCIO"
  
  @impl true
  def documentary_type, do: "mi_tipo_documental"
  
  # ... resto de callbacks
  
  # Construir configuración
  def build_config do
    build_config()  # Heredado de ForcedLoad.Config
  end
end
```

---

## Protocolos

### `Genserver.Protocols.PWorker`

Define cómo procesar lotes de mensajes según el tipo de negocio.

```elixir
defimpl Genserver.Protocols.PWorker, for: List do
  def perform(batch, batch_id, :record, info) do
    batch
    |> Enum.map(fn %{"current" => payload} -> payload end)
    |> MiApp.Record.insert_by_lote(batch_id, info.pg_config)
  end
  
  def perform(batch, batch_id, :task, info) do
    batch
    |> MiApp.Task.insert_by_lote(batch_id, info.pg_config)
  end
end
```

---

## Consideraciones Importantes

### 1. Modos de Conexión: Pool vs Legacy

A partir de la versión 1.2.0, el sistema soporta **dos modos de conexión**:

| Característica | Pool Mode (v2.1+) | Legacy Mode |
|----------------|---------------------|-------------|
| **Gestión de conexiones** | Pool automático | Conexión temporal por operación |
| **Parámetro** | `pg_pool_name` / `bq_pool_name` | `pg_config` / `data_source` |
| **Reconexión** | Automática por DBConnection/NimblePool | Manual |
| **Rendimiento** | Alto (reutiliza conexiones) | Moderado (overhead de conexión) |
| **Uso recomendado** | Producción | Desarrollo, compatibilidad |

**Patrón de conexión con pool (recomendado):**
```elixir
def execute_insert_pooled(records, pg_pool_name, batch_id) do
  # El pool gestiona las conexiones automáticamente
  case Connection.PostgresPool.insert_many(pg_pool_name, table_name(), records) do
    {:ok, count} -> {:ok, count}
    {:error, reason} ->
      Logger.error("Error en inserción: #{inspect(reason)}")
      {:error, reason}
  end
end

# BigQuery con pool
Pool.BigQuery.with_connection(:bigquery_pool, fn bq_conn ->
  Connection.Odbc.insert(bq_conn, statement)
end)
```

**Patrón de conexión temporal (legacy):**
```elixir
def execute_insert(records, pg_config, batch_id) do
  try do
    case Connection.Postgres.connect(pg_config) do
      {:ok, pg_conn} ->
        try do
          Connection.Postgres.insert_many(pg_conn, table_name(), records)
        after
          Connection.Postgres.disconnect(pg_conn)
        end
      {:error, reason} ->
        Logger.error("Error conectando: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Error inesperado: #{inspect(error)}")
      {:error, error}
  end
end
```

**Beneficios del modo pool:**
- Mayor rendimiento al reutilizar conexiones
- Reconexión automática ante fallos
- Supervisión OTP con reinicio automático
- Health checks periódicos
- Mejor manejo de recursos

**Beneficios del modo legacy:**
- Simplicidad para desarrollo local
- Compatibilidad con código existente
- No requiere configurar pools en el supervisor

### 2. Configuración en Runtime vs Compilación

Usar `*_path` para valores que se resuelven desde variables de entorno en runtime:
- `table_key_path` en lugar de `table_key`
- `slack_webhook_url_path` en lugar de `slack_webhook_url`
- `slack_env_var` en lugar de `slack_env`

### 2. Manejo de Errores

- Todas las entidades tienen `handle_processing_error/4` que envía notificaciones a Slack
- La estrategia `execute_insert_with_retry` divide el batch a la mitad en caso de error

### 3. Estados de Análisis en PostgreSQL

| Estado | Descripción |
|--------|-------------|
| `sin_analizar` | Pendiente de subir a BigQuery |
| `analizado_en_bq` | Subido exitosamente |
| `con_problemas` | Error al procesar |

### 4. Orden de Procesamiento

1. Filtrar batch (`filter_batch/1`)
2. Agrupar por ID (`group_by_unique_id/1` o `group_by_composite_key/1`)
3. Construir datos (`build_data/1` o `build_data/3`)
4. Aplicar post-procesamiento
5. Preparar registros
6. Ejecutar inserción

### 5. Dependencias Mínimas

El proyecto ETL depende de:
- `etl_core` - Funcionalidad base
- `timex` - Manejo de fechas
- `poison` / `jason` - JSON
- `postgrex` - PostgreSQL (y pools)
- `poolboy` - Pool de conexiones para BigQuery/ODBC *(actualizado v2.1)*
- `amqp` - RabbitMQ

