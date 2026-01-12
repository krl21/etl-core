# Referencia de Módulos ETL-Core v2.0

Este documento describe los módulos disponibles en `etl-core` v2.0, sus funciones principales y aspectos importantes a considerar.

---

## Tabla de Contenidos

1. [Estructura de Datos](#estructura-de-datos)
2. [Modelos de Datos](#modelos-de-datos)
3. [GenServers](#genservers)
4. [Conexiones](#conexiones)
5. [Utilidades](#utilidades)
6. [Limpieza de Datos](#limpieza-de-datos)
7. [Carga Forzada](#carga-forzada)

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
| `execute_insert/3` | Ejecuta inserción en base de datos |
| `execute_insert_with_retry/3` | Inserción con estrategia de reintento divide-and-conquer |
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
  
  def insert_by_lote(batch, batch_id, pg_conn) do
    {grouped, keys} = batch |> filter_batch() |> group_by_unique_id()
    
    records = 
      keys
      |> Enum.map(&prepare_record(&1, Map.get(grouped, &1), [], []))
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, r} -> r end)
    
    execute_insert_with_retry(records, pg_conn, batch_id)
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

Consumidor continuo de colas RabbitMQ.

**Inicialización:**
```elixir
{Genserver.RabbitConsumer, {queue_info, amqp_connection, info}}
```

Donde:
- `queue_info`: Mapa con `:business` y `:config`
- `amqp_connection`: Configuración de conexión AMQP
- `info`: Mapa con `:pg_conn`, `:webhook_url`, etc.

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

Sube datos de PostgreSQL a BigQuery periódicamente.

**Configuración:**
```elixir
{Genserver.BigqueryUploader, %{
  business: :mi_negocio,
  data_source: bq_config,
  pg_config: pg_connection_config,
  info: [
    %{bq_table: "tabla_bq", tipo: "expediente", pg_table: "tabla_pg"}
  ],
  periodicity: periodicidad,
  batch_size: 70,
  webhook_url: webhook_url
}}
```

---

### `Genserver.Cleaning`

Limpia registros ya procesados de PostgreSQL periódicamente.

---

### `Genserver.Monitor`

Monitorea el estado de los GenServers y envía heartbeats.

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
    |> MiApp.Record.insert_by_lote(batch_id, info.pg_conn)
  end
  
  def perform(batch, batch_id, :task, info) do
    batch
    |> MiApp.Task.insert_by_lote(batch_id, info.pg_conn)
  end
end
```

---

## Consideraciones Importantes

### 1. Configuración en Runtime vs Compilación

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
- `postgrex` - PostgreSQL
- `amqp` - RabbitMQ

