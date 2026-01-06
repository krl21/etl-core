# Guía para Crear un ETL desde Cero

Esta guía describe paso a paso cómo crear un nuevo proyecto ETL utilizando `etl-core`.

---

## Tabla de Contenidos

1. [Estructura del Proyecto](#estructura-del-proyecto)
2. [Paso 1: Crear el Proyecto](#paso-1-crear-el-proyecto)
3. [Paso 2: Configuración de Dependencias](#paso-2-configuración-de-dependencias)
4. [Paso 3: Configuración de la Aplicación](#paso-3-configuración-de-la-aplicación)
5. [Paso 4: Definir Entidades](#paso-4-definir-entidades)
6. [Paso 5: Implementar el Worker](#paso-5-implementar-el-worker)
7. [Paso 6: Configurar ForcedLoad](#paso-6-configurar-forcedload)
8. [Paso 7: Configurar Subida a BigQuery](#paso-7-configurar-subida-a-bigquery)
9. [Paso 8: Configurar Limpieza de Datos](#paso-8-configurar-limpieza-de-datos)
10. [Paso 9: Implementar Application](#paso-9-implementar-application)
11. [Paso 10: Configurar el Tipo Documental](#paso-10-configurar-el-tipo-documental)
12. [Paso 11: Archivos Adicionales](#paso-11-archivos-adicionales)
13. [Checklist Final](#checklist-final)

---

## Estructura del Proyecto

```
mi_etl/
├── config/
│   ├── config.exs          # Configuración del logger
│   ├── dev.exs             # Configuración de desarrollo
│   ├── prod.exs            # Configuración de producción
│   ├── runtime.exs         # Configuración en runtime (variables de entorno)
│   └── test.exs            # Configuración de tests
├── lib/
│   ├── mi_etl.ex           # Módulo principal
│   ├── mi_etl/
│   │   └── application.ex  # Application (supervisor tree)
│   ├── entity/
│   │   ├── record/
│   │   │   ├── record.ex           # Entidad principal Record
│   │   │   └── subentities/
│   │   │       ├── record_base.ex  # Atributos base del record
│   │   │       ├── buyer.ex        # Sub-entidad Comprador
│   │   │       └── vehicle.ex      # Sub-entidad Vehículo
│   │   └── task/
│   │       └── task.ex             # Entidad Task
│   ├── impl/
│   │   ├── genserver/
│   │   │   ├── worker.ex           # Implementación del Worker
│   │   │   └── forced_load_config.ex
│   │   ├── time/
│   │   │   └── my_time.ex          # Configuración de tiempo laboral
│   │   └── type/
│   │       └── documentary_type_of.ex
│   └── tools/
│       └── stuff.ex                # Funciones auxiliares
└── mix.exs
```

---

## Paso 1: Crear el Proyecto

```bash
mix new mi_etl --sup
cd mi_etl
```

---

## Paso 2: Configuración de Dependencias

### `mix.exs`

```elixir
defmodule MiEtl.MixProject do
  use Mix.Project

  def project do
    [
      app: :mi_etl,
      version: "0.1.0",
      elixir: "~> 1.14.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MiEtl.Application, []}
    ]
  end

  defp releases do
    [
      mi_etl: [
        start_distribution_during_config: true,
        include_executables_for: [:unix],
        cookie: "node",
        version: "0.1.0",
        applications: [mi_etl: :permanent]
      ]
    ]
  end

  defp deps do
    [
      # ETL Core - Cambiar URL por el repositorio real
      {:etl_core, git: "https://github.com/krl21/etl-core.git", branch: "vx.x"},
      
      # Logger flexible (opcional)
      {:flex_logger, "~> 0.2.1"},
      
      # Flow para procesamiento paralelo (opcional)
      {:flow, "~> 1.0"}
    ]
  end
end
```

### Instalar dependencias

```bash
mix deps.get
```

---

## Paso 3: Configuración de la Aplicación

### `config/config.exs`

```elixir
import Config

# Configuración del Logger
config :logger, :console,
  format: "$date $time $metadata[$level] $message\n",
  metadata: [:request_id]

config :logger,
  backends: [{FlexLogger, :logger_name}]

config :logger, :logger_name,
  logger: :console,
  format: "$date $time $metadata[$level] $levelpad$message\n",
  metadata: [:request_id]

config :logger,
  handle_otp_reports: false,
  handle_sasl_reports: false

import_config "#{Mix.env()}.exs"
```

### `config/dev.exs`

```elixir
import Config

config :logger, :logger_name,
  level_config: [application: :mi_etl, level: :debug]
```

### `config/runtime.exs`

Este archivo contiene TODA la configuración que depende de variables de entorno:

```elixir
import Config

################
### Nivel de log
################
config :logger, :logger_name,
  level_config: [application: :mi_etl, level: :debug]

################
### Zona horaria
################
config :mi_etl,
  timezone: "America/Santiago"

################
### BigQuery
################
config :mi_etl,
  bigquery: %{
    configuration: [
      dsn: System.get_env("DNS"),
      warehouse: System.get_env("DATAMART_MI_ETL")
    ],
    table: %{
      record: "#{System.get_env("DATAMART_MI_ETL")}.#{System.get_env("MI_ETL_RECORDS_TABLE")}",
      task: "#{System.get_env("DATAMART_MI_ETL")}.#{System.get_env("MI_ETL_TASK_TABLE")}",
      ...
    }
  }

################
### Notificaciones Slack
################
config :mi_etl,
  notification: %{
    slack_webhook: %{
      url: %{
        bug: System.get_env("SLACK_WEBHOOK_FOR_BUGS"),
        notification: System.get_env("SLACK_WEBHOOK_FOR_NOTIFICATIONS")
      },
      headers: [{"Content-type", "application/json"}]
    }
  }

################
### Credenciales de usuario
################
config :mi_etl,
  user: %{
    totalcheck: %{
      username: System.get_env("TOTALCHECK_USERNAME"),
      password: System.get_env("TOTALCHECK_PASSWORD")
    }
  }

################
### Servicios externos
################
config :mi_etl,
  # Ticket de autenticación
  ticket: %{
    url: System.get_env("TICKET_ACCESS_URL"),
    keys: ["<username>", "<password>"],
    headers: [{"Accept", "application/json"}]
  },
  # ElasticSearch
  elasticsearch: %{
    url: "http://#{System.get_env("ELASTICSEARCH_HOST")}:9200/<type_documentary>/<mode>",
    keys: ["<type_documentary>", "<mode>"],
    mode: ["_search"],
    type_documentary: ["mi_tipo_documental"],
    headers: [{"Content-type", "application/json"}]
  },
  # NodeService
  nodeservice: %{
    url: System.get_env("NODE_SERVICE_URL"),
    keys: ["<unique_id>", "<ticket>"],
    headers: [{"Content-type", "application/json"}]
  },
  # WorkflowService
  workflowservice: %{
    url: System.get_env("WORKFLOW_SERVICE_URL"),
    keys: ["<type_documentary>", "<contentref>", "<ticket>"],
    headers: [{"Content-type", "application/json"}]
  }

################
### RabbitMQ
################
config :mi_etl,
  my_amqp_client: %{
    connection: [
      host: System.get_env("AMQP_HOST"),
      port: System.get_env("AMQP_PORT"),
      username: System.get_env("AMQP_USERNAME"),
      password: System.get_env("AMQP_PASSWORD")
    ],
    queue: %{
      mi_negocio: %{
        record: %{
          business: :record,
          config: %{
            queue: System.get_env("AMQP_RECORD_QUEUE"),
            exchange: System.get_env("AMQP_RECORD_QUEUE"),
            queue_error: "#{System.get_env("AMQP_RECORD_QUEUE")}_error",
            queue_arguments: [
              {"x-dead-letter-exchange", :longstr, ""},
              {"x-dead-letter-routing-key", :longstr, "#{System.get_env("AMQP_RECORD_QUEUE")}_error"}
            ],
            listen: [
              # Exchanges a los que escuchar, si aplica
              "on_created_mi_documento",
              "on_updated_mi_documento"
            ]
          }
        },
        task: %{
          business: :task,
          config: %{
            queue: System.get_env("AMQP_TASK_QUEUE"),
            exchange: System.get_env("AMQP_TASK_QUEUE"),
            queue_error: "#{System.get_env("AMQP_TASK_QUEUE")}_error",
            queue_arguments: [
              {"x-dead-letter-exchange", :longstr, ""},
              {"x-dead-letter-routing-key", :longstr, "#{System.get_env("AMQP_TASK_QUEUE")}_error"}
            ],
            listen: [
              "on_create_tarea_1",
              "on_completed_tarea_1",
              "on_create_tarea_2",
              "on_completed_tarea_2", 
              ...
            ]
          }
        }
      }
    }
  }

################
### Tamaños de batch
################
config :mi_etl,
  batch_size: 200,
  batch_size_process: 70

################
### Periodicidad de GenServers
################
config :mi_etl,
  activation_time: %{
    rabbit_consumer_by_batch: %{
      periodicity: %{day: 0, hour: 0, minute: 2, second: 0}
    },
    cleanup_in_bigquery: %{
      periodicity: %{day: 0, hour: 1, minute: 30, second: 0}
    },
    bigquery_uploader: %{
      periodicity: %{day: 0, hour: 0, minute: 1, second: 0}
    }
  }

################
### PostgreSQL
################
config :mi_etl,
  postgres: %{
    connection: %{
      hostname: System.get_env("PG_HOST"),
      port: (System.get_env("PG_PORT") || "5432") |> String.to_integer(),
      database: System.get_env("PG_DATABASE"),
      username: System.get_env("PG_USERNAME"),
      password: System.get_env("PG_PASSWORD")
    },
    tables: [
      System.get_env("PG_TABLE")
    ],
    register_type: %{
      record: "expediente",
      task: "tarea"
    }
  }
```

---

## Paso 4: Definir Entidades

### 4.1 Sub-entidades (Proveedores de Atributos)

Las sub-entidades definen los atributos que se extraen del payload. 

**Importante**: Debe existir al menos un fichero `record_base.ex` que defina los atributos fundamentales:
- `unique_id` - Identificador único del registro
- `last_update` - Fecha de última actualización
- `timestamp` - Marca de tiempo para ordenamiento

Luego se pueden crear sub-entidades adicionales según la estructura del payload.

```elixir
defmodule Entity.Record.MiSubentidad do
  @moduledoc """
  Sub-entidad con atributos específicos.
  """
  
  use DataModel.Attribute.Provider

  # Definir atributos usando %Struct.InfoAttr{}
  @campo1 %Struct.InfoAttr{
    id: :nombre_en_bd,           # Nombre de la columna en BD propia
    id_payload: "nombrePayload", # Nombre del campo en el JSON
    type: :string,               # Tipo: :string, :integer, :float, :boolean, :timestamp
    keys_to_search: ["data"]     # Ruta en el payload (opcional)
  }

  @campo2 %Struct.InfoAttr{
    id: :otro_campo,
    id_payload: "otherField",
    type: :integer,
    default_value: 0             # Valor por defecto (opcional)
  }

  # Registrar atributos
  attr_list [
    @campo1,
    @campo2
  ]

  # Post-procesamiento opcional
  def special_post_processing(values, payload) do
    # Modificar values según lógica de negocio
    values
  end
end
```

### 4.2 Entidad Record Principal

`lib/entity/record/record.ex`

```elixir
defmodule Entity.Record.Record do
  @moduledoc """
  Entidad principal Record.
  """

  use DataModel.RecordPg.Base
  use Cleaning.CleanableTable

  require Logger
  import Stuff, only: [list_subtraction: 2]
  alias Entity.Record.RecordBase

  ################
  ### Configuración
  ################

  entity_config(
    app: :mi_etl,
    table_name_path: [:postgres, :tables],
    batch_size_key: :batch_size_process,
    unique_id: RecordBase.unique_id(),
    timestamp: RecordBase.timestamp(),
    value_type_path: [:postgres, :register_type, :record],
    slack_webhook_url_path: [:notification, :slack_webhook, :url, :bug],
    slack_env_var: "ENVIRONMENT"
  )

  ################
  ### CleanableTable
  ################

  @impl Cleaning.CleanableTable
  def business_key, do: :record

  @impl Cleaning.CleanableTable
  def bigquery_config do
    %{
      table: Application.get_env(:mi_etl, :bigquery)[:table][:record],
      id_fields: [RecordBase.unique_id()],
      timestamp_field: RecordBase.timestamp()
    }
  end

  @impl Cleaning.CleanableTable
  def postgres_config do
    %{
      table: Application.get_env(:mi_etl, :postgres)[:tables] |> List.first(),
      register_type: Application.get_env(:mi_etl, :postgres)[:register_type][:record]
    }
  end

  ################
  ### Subentidades
  ################

  subentities [
    Entity.Record.RecordBase,
    Entity.Record.Buyer
    # Agregar más sub-entidades según sea necesario
  ]

  special_post_processing [
    Entity.Record.Buyer
    # Agregar el resto que implementa la función special_post_processing
  ]

  ################
  ### Generar funciones helper
  ################

  generate_helper_functions()

  ################
  ### Funciones públicas (opcional)
  ################

  def unique_id(), do: RecordBase.unique_id()
  def last_update(), do: RecordBase.last_update()
  def timestamp(), do: RecordBase.timestamp()

  ################
  ### insert_by_lote
  ################

  def insert_by_lote([], _batch_id, _pg_conn), do: {:ok, 0}

  def insert_by_lote(batch, batch_id, pg_conn)
      when is_list(batch) and is_binary(batch_id) do

    {grouped, keys} =
      batch
      |> filter_batch()
      |> group_by_unique_id()

    records =
      keys
      |> Enum.map(fn key ->
        try do
          prepare_record(key, Map.get(grouped, key), [], [])
        rescue
          error ->
            handle_processing_error(batch_id, key, error, %{
              function: :insert_by_lote,
              module: __MODULE__
            })
            {:error, nil}
        end
      end)
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, record} -> record end)

    execute_insert_with_retry(records, pg_conn, batch_id)
  end

  ################
  ### Overrides
  ################

  def filter_batch(batch) do
    Enum.filter(batch, fn
      %{"type" => type_} -> type_ == @documental_type
      _ -> false
    end)
  end

  def build_data(payloads, _stored_data, _additional_info) do
    update_fields = fn map, fields ->
      Enum.reduce(fields, map, fn {key, _value} = tuple, acc ->
        List.keystore(acc, key, 0, tuple)
      end)
    end

    payloads
    |> Enum.reduce([], fn payload, acc ->
      differences =
        payload
        |> Payload.extract_with_format(attr_list(), false)
        |> apply_post_processing([], payload)
        |> list_subtraction(acc)

      update_fields.(acc, differences)
    end)
  end
end
```

### 4.3 Entidad Task

`lib/entity/task/task.ex`

```elixir
defmodule Entity.Task.Task do
  @moduledoc """
  Entidad Task.
  """

  use DataModel.TaskPg.Base
  use Cleaning.CleanableTable
  alias Struct.InfoAttr

  ################
  ### Atributos
  ################

  @contentref %InfoAttr{
    id: :expediente_asociado,
    id_payload: "contentref",
    type: :string
  }

  @executed_by %InfoAttr{
    id: :ejecutado_por,
    id_payload: "executedby",
    type: :string
  }

  @start_date %InfoAttr{
    id: :fecha_inicio,
    id_payload: "ini",
    type: :timestamp
  }

  @end_date %InfoAttr{
    id: :fecha_fin,
    id_payload: "fin",
    type: :timestamp
  }

  @name %InfoAttr{
    id: :nombre,
    id_payload: "name",
    type: :string
  }

  @status %InfoAttr{
    id: :estado,
    id_payload: "status",
    type: :string
  }

  @elapsed_working_time %InfoAttr{
    id: :tiempo_laborable_transcurrido,
    type: :integer,
    default_value: -1
  }

  @timestamp %InfoAttr{
    id: :timestamp,
    type: :integer
  }

  ################
  ### Listas de atributos
  ################

  own_attributes [
    @contentref,
    @executed_by,
    @start_date,
    @end_date,
    @name,
    @status
  ]

  computed_attributes [
    @elapsed_working_time,
    @timestamp
  ]

  ################
  ### Configuración
  ################

  task_config(
    app: :mi_etl,
    table_name_path: [:postgres, :tables],
    group_by_keys: [@contentref, @name],
    timestamp: @timestamp,
    value_type_path: [:postgres, :register_type, :task],
    elapsed_time_config: %{
      start_date_attr: @start_date,
      end_date_attr: @end_date,
      target_attr: @elapsed_working_time,
      business: :mi_negocio
    },
    slack_webhook_url_path: [:notification, :slack_webhook, :url, :bug],
    slack_env_var: "ENVIRONMENT"
  )

  ################
  ### CleanableTable
  ################

  @impl Cleaning.CleanableTable
  def business_key, do: :task

  @impl Cleaning.CleanableTable
  def bigquery_config do
    %{
      table: Application.get_env(:mi_etl, :bigquery)[:table][:task],
      id_fields: [@contentref, @name],
      timestamp_field: @timestamp
    }
  end

  @impl Cleaning.CleanableTable
  def postgres_config do
    %{
      table: Application.get_env(:mi_etl, :postgres)[:tables] |> List.last(),
      register_type: Application.get_env(:mi_etl, :postgres)[:register_type][:task]
    }
  end

  ################
  ### Generar funciones
  ################

  generate_task_helper_functions()
end
```

---

## Paso 5: Implementar el Worker

El Worker implementa el protocolo `Genserver.Protocols.PWorker` y define cómo procesar cada tipo de negocio.

**Se pueden definir tantas implementaciones de `perform/4` como tipos de negocio existan** (`:record`, `:task`, `:otro`, etc.). Cada una recibe el batch y lo procesa según su lógica.

`lib/impl/genserver/worker.ex`

```elixir
defimpl Genserver.Protocols.PWorker, for: List do
  @moduledoc """
  Implementación del protocolo Worker para procesar lotes de mensajes.
  """

  require Logger
  alias Entity.Record.Record
  alias Entity.Task.Task
  import Notification.Notify, only: [notify_slack: 4]

  # Implementación para :record
  def perform(batch, batch_id, :record = business, %{pg_conn: pg_conn} = _info) do
    batch_id = batch_id || "any"
    Logger.debug("Nuevo batch. Negocio: #{inspect(business)}. Mensajes: #{length(batch)}")

    try do
      batch
      |> Enum.map(fn %{"current" => payload} -> payload end)
      |> Record.insert_by_lote(batch_id, pg_conn)
    rescue
      error ->
        Logger.error("Error procesando batch: #{inspect(error)}")
        notify_slack(...)
    end
  end

  # Implementación para :task
  def perform(batch, batch_id, :task, %{pg_conn: pg_conn} = _info) do
    Task.insert_by_lote(batch, batch_id, pg_conn)
  end

  # Agregar más implementaciones según sea necesario:
  # def perform(batch, batch_id, :otro_tipo, info) do ... end
end
```

**Nota**: Cada nuevo tipo de negocio requiere:
1. Una función `perform/4` con el átomo correspondiente
2. Una cola RabbitMQ configurada con ese `business`
3. La entidad correspondiente que procese los datos

---

## Paso 6: Configurar ForcedLoad

`lib/impl/genserver/forced_load_config.ex`

```elixir
defmodule Impl.Genserver.ForcedLoadConfig do
  @moduledoc """
  Configuración para carga forzada.
  """

  use ForcedLoad.Config
  import Type.PDocumentaryTypeOf
  alias Entity.Record.RecordBase

  @allowed_task_names [
    "tarea_1",
    "tarea_2",
    "tarea_3"
    # Agregar nombres de tareas permitidas
  ]

  @impl true
  def app_name, do: :mi_etl

  @impl true
  def business_name, do: "MI NEGOCIO"

  @impl true
  def documentary_type, do: documentary_type_of(:record)

  @impl true
  def record_queue_path, do: [:my_amqp_client, :queue, :mi_negocio, :record, :config, :queue]

  @impl true
  def task_queue_path, do: [:my_amqp_client, :queue, :mi_negocio, :task, :config, :queue]

  @impl true
  def bigquery_table_path, do: [:bigquery, :table, :record]

  @impl true
  def unique_id_field, do: RecordBase.unique_id().id

  @impl true
  def unique_id_payload_field, do: RecordBase.unique_id().id_payload

  @impl true
  def last_update_field, do: RecordBase.last_update().id

  @impl true
  def last_update_payload_field, do: RecordBase.last_update().id_payload

  @impl true
  def time_step, do: 30

  @impl true
  def batch_size, do: 400

  @impl true
  def batch_delay, do: 0

  @impl true
  def webhook_url_path, do: [:notification, :slack_webhook, :url, :notification]

  @impl true
  def task_name_filter, do: @allowed_task_names

  ################
  ### Funciones auxiliares
  ################

  def allowed_task_names, do: @allowed_task_names

  def build_config_with_default_tasks do
    build_config(%{task_name_filter: @allowed_task_names})
  end
end
```

---

## Paso 7: Configurar Subida a BigQuery

El `Genserver.BigqueryUploader` es responsable de tomar los registros almacenados en PostgreSQL (estado `sin_analizar`) y subirlos periódicamente a BigQuery.

### Flujo de Subida

```
PostgreSQL (sin_analizar) → BigqueryUploader → BigQuery
                                    ↓
                          PostgreSQL (analizado_en_bq)
```

### Configuración en Application

El BigqueryUploader se configura como un child del supervisor:

```elixir
defp child_bigquery_uploader do
  bq_config = Application.get_env(:mi_etl, :bigquery)
  pg_config = Application.get_env(:mi_etl, :postgres)

  {Genserver.BigqueryUploader, %{
    # Identificador del negocio
    business: :mi_negocio,
    
    # Configuración ODBC para BigQuery
    data_source: bq_config[:configuration],
    
    # Configuración de conexión PostgreSQL
    pg_config: pg_config[:connection],
    
    # Información de tablas a sincronizar
    info: [
      %{
        bq_table: bq_config[:table][:record],      # Tabla destino en BigQuery
        tipo: pg_config[:register_type][:record],  # Tipo de registro a filtrar
        pg_table: List.first(pg_config[:tables])   # Tabla origen en PostgreSQL
      },
      %{
        bq_table: bq_config[:table][:task],
        tipo: pg_config[:register_type][:task],
        pg_table: List.last(pg_config[:tables])
      }
    ],
    
    # Periodicidad de ejecución (cada 1 minuto en este ejemplo)
    periodicity: Application.get_env(:mi_etl, :activation_time)[:bigquery_uploader][:periodicity],
    
    # Cantidad de registros por batch
    batch_size: Application.get_env(:mi_etl, :batch_size_process),
    
    # Webhook para notificaciones de error
    webhook_url: slack_webhook_url()
  }}
end
```

### Parámetros de Configuración

| Parámetro | Descripción | Ejemplo |
|-----------|-------------|---------|
| `business` | Identificador único del negocio | `:mi_negocio` |
| `data_source` | Configuración ODBC para BigQuery | `[dsn: "...", warehouse: "..."]` |
| `pg_config` | Configuración de conexión PostgreSQL | `%{hostname: "...", ...}` |
| `info` | Lista de mapas con configuración de tablas | Ver arriba |
| `periodicity` | Frecuencia de ejecución | `%{day: 0, hour: 0, minute: 1, second: 0}` |
| `batch_size` | Registros por batch | `70` |
| `webhook_url` | URL de Slack para errores | `"https://..."` |

### Configuración de Periodicidad en `runtime.exs`

```elixir
config :mi_etl,
  activation_time: %{
    bigquery_uploader: %{
      periodicity: %{
        day: 0,
        hour: 0,
        minute: 1,    # Ejecutar cada 1 minuto
        second: 0
      }
    }
  }
```

### Proceso de Subida

1. **Lectura**: Obtiene registros de PostgreSQL con `estado_analisis = 'sin_analizar'`
2. **Agrupación**: Agrupa por `id_nodo` y mantiene el más reciente
3. **Transformación**: Convierte el campo `informacion` (JSONB) a columnas SQL
4. **Inserción**: Ejecuta INSERT en BigQuery via ODBC
5. **Actualización**: Marca registros como `analizado_en_bq` en PostgreSQL

### Consideraciones

- **Conexiones persistentes**: El GenServer mantiene conexiones abiertas a PostgreSQL y BigQuery
- **Retry automático**: Si falla un batch, se divide a la mitad y reintenta
- **Notificaciones**: Envía alertas a Slack en caso de errores

---

## Paso 8: Configurar Limpieza de Datos

El `Genserver.Cleaning` elimina registros duplicados en BigQuery y limpia registros ya procesados en PostgreSQL.

### Flujo de Limpieza

```
BigQuery                          PostgreSQL
   ↓                                  ↓
Eliminar duplicados            Eliminar registros con
(mantener más reciente)        estado = 'analizado_en_bq'
```

### Implementar CleanableTable en las Entidades

Cada entidad que se desee limpiar debe implementar el behaviour `Cleaning.CleanableTable`:

```elixir
defmodule Entity.Record.Record do
  use DataModel.RecordPg.Base
  use Cleaning.CleanableTable  # ← Agregar este use

  # ... configuración existente ...

  ################
  ### CleanableTable Implementation
  ################

  @impl Cleaning.CleanableTable
  def business_key, do: :record

  @impl Cleaning.CleanableTable
  def bigquery_config do
    %{
      # Tabla de BigQuery a limpiar
      table: Application.get_env(:mi_etl, :bigquery)[:table][:record],
      
      # Campos que identifican un registro único
      id_fields: [RecordBase.unique_id()],
      
      # Campo de timestamp para determinar cuál es más reciente
      timestamp_field: RecordBase.timestamp()
    }
  end

  @impl Cleaning.CleanableTable
  def postgres_config do
    %{
      # Tabla de PostgreSQL a limpiar
      table: Application.get_env(:mi_etl, :postgres)[:tables] |> List.first(),
      
      # Tipo de registro para filtrar
      register_type: Application.get_env(:mi_etl, :postgres)[:register_type][:record]
    }
  end
end
```

### Configurar CleaningSupervisor

El supervisor registra los módulos limpiables:

```elixir
defp child_cleaning_supervisor do
  {Cleaning.CleaningSupervisor, cleanable_modules: [
    Entity.Record.Record,
    Entity.Task.Task
    # Agregar más entidades limpiables
  ]}
end
```

### Configurar Cleaning GenServer

```elixir
defp child_cleaning do
  {Genserver.Cleaning, %{
    # :all para limpiar todas las tablas registradas
    # o un business_key específico (:record, :task)
    business: :all,
    
    # Configuración ODBC para BigQuery
    bq_config: Application.get_env(:mi_etl, :bigquery)[:configuration],
    
    # Configuración PostgreSQL (opcional, nil para omitir limpieza PG)
    pg_config: Application.get_env(:mi_etl, :postgres)[:connection],
    
    # Periodicidad de limpieza
    periodicity: Application.get_env(:mi_etl, :activation_time)[:cleanup_in_bigquery][:periodicity] 
                 |> notification_frequency(),
    
    # Webhook para notificaciones
    webhook_url: slack_webhook_url()
  }}
end
```

### Configuración de Periodicidad en `runtime.exs`

```elixir
config :mi_etl,
  activation_time: %{
    cleanup_in_bigquery: %{
      periodicity: %{
        day: 0,
        hour: 1,      # Ejecutar cada 1 hora 30 minutos
        minute: 30,
        second: 0
      }
    }
  }
```

### Proceso de Limpieza en BigQuery

La limpieza en BigQuery elimina duplicados manteniendo el registro más reciente:

```sql
-- Query generado internamente
DELETE FROM tabla
WHERE unique_id IN (
  SELECT unique_id 
  FROM tabla t1
  WHERE EXISTS (
    SELECT 1 FROM tabla t2 
    WHERE t2.unique_id = t1.unique_id 
    AND t2.timestamp > t1.timestamp
  )
)
```

### Proceso de Limpieza en PostgreSQL

Elimina registros que ya fueron enviados a BigQuery:

```sql
DELETE FROM tabla
WHERE estado_analisis IN ('analizado_en_bq', 'con_problemas')
  AND tipo = 'expediente'
```

### Modos de Operación

| Modo | Descripción |
|------|-------------|
| `business: :all` | Limpia todas las tablas registradas en CleaningSupervisor |
| `business: :record` | Limpia solo la tabla de records |
| `business: :task` | Limpia solo la tabla de tasks |

### Consideraciones

- **Frecuencia**: La limpieza es costosa, no ejecutar muy frecuentemente (recomendado: cada 30-90 minutos)
- **Conexiones**: Mantiene conexiones persistentes a BigQuery y PostgreSQL
- **Orden**: Primero limpia BigQuery (duplicados), luego PostgreSQL (ya procesados)

---

## Paso 9: Implementar Application

`lib/mi_etl/application.ex`

```elixir
defmodule MiEtl.Application do
  @moduledoc false

  use Application
  require Logger
  import Time.Timem, only: [notification_frequency: 1]
  import Notification.Notify, only: [notify_slack: 4]
  alias Connection.Postgres
  alias Impl.Genserver.ForcedLoadConfig

  @impl true
  def start(_type, _args) do
    Logger.info("Cargando variables globales de la aplicación")
    Application.load(:mi_etl)

    Logger.info("Iniciando conexión ODBC")
    Connection.Odbc.start()

    setup_postgres()

    children = build_children()

    opts = [strategy: :one_for_one, name: MiEtl.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    send_startup_notification()

    {:ok, pid}
  end

  defp build_children do
    [
      child_task_supervisor(),
      child_monitor(),
      child_bigquery_uploader(),
      child_cleaning_supervisor(),
      child_cleaning()
      # child_forced_load()  # Descomentar si se necesita carga forzada al inicio
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Kernel.++(rabbit_consumer_children())
  end

  defp child_task_supervisor do
    {Task.Supervisor, name: SupervisorTareas}
  end

  defp child_monitor do
    {Genserver.Monitor, {slack_webhook_url(), System.get_env("ENVIRONMENT")}}
  end

  defp child_bigquery_uploader do
    bq_config = Application.get_env(:mi_etl, :bigquery)
    pg_config = Application.get_env(:mi_etl, :postgres)

    {Genserver.BigqueryUploader, %{
      business: :mi_negocio,
      data_source: bq_config[:configuration],
      pg_config: pg_config[:connection],
      info: bigquery_upload_info(bq_config, pg_config),
      periodicity: Application.get_env(:mi_etl, :activation_time)[:bigquery_uploader][:periodicity],
      batch_size: Application.get_env(:mi_etl, :batch_size_process),
      webhook_url: slack_webhook_url()
    }}
  end

  defp bigquery_upload_info(bq_config, pg_config) do
    [
      {:record, List.first(pg_config[:tables])},
      {:task, List.last(pg_config[:tables])}
    ]
    |> Enum.map(fn {type, pg_table} ->
      %{
        bq_table: bq_config[:table][type],
        tipo: pg_config[:register_type][type],
        pg_table: pg_table
      }
    end)
  end

  defp child_cleaning_supervisor do
    {Cleaning.CleaningSupervisor, cleanable_modules: [
      Entity.Record.Record,
      Entity.Task.Task
    ]}
  end

  defp child_cleaning do
    {Genserver.Cleaning, %{
      business: :all,
      bq_config: Application.get_env(:mi_etl, :bigquery)[:configuration],
      pg_config: Application.get_env(:mi_etl, :postgres)[:connection],
      periodicity: Application.get_env(:mi_etl, :activation_time)[:cleanup_in_bigquery][:periodicity] |> notification_frequency(),
      webhook_url: slack_webhook_url()
    }}
  end

  defp child_forced_load do
    {Genserver.ForcedLoad, {
      :record,
      [
        {{2024, 1, 1}, {0, 0, 0}},
        Timex.now() |> Timex.to_erl()
      ],
      ForcedLoadConfig.build_config()
    }}
  end

  defp rabbit_consumer_children do
    info = %{
      pg_conn: get_postgres_connection(),
      webhook_url: slack_webhook_url()
    }

    amqp_connection = Application.get_env(:mi_etl, :my_amqp_client)[:connection]

    Application.get_env(:mi_etl, :my_amqp_client)[:queue][:mi_negocio]
    |> Enum.map(fn {_key, data_map} ->
      %{
        id: :"RabbitConsumer.#{data_map.config.queue}",
        start: {Genserver.RabbitConsumer, :start_link, [{data_map, amqp_connection, info}]}
      }
    end)
  end

  defp get_postgres_connection do
    connection_config = Application.get_env(:mi_etl, :postgres)[:connection]

    case Postgres.connect(connection_config) do
      {:ok, conn} ->
        Logger.info("Conexión PostgreSQL establecida para consumidores RabbitMQ")
        conn

      {:error, reason} ->
        Logger.error("Error conectando a PostgreSQL: #{inspect(reason)}")
        nil
    end
  end

  defp slack_webhook_url do
    Application.get_env(:mi_etl, :notification)[:slack_webhook][:url][:bug]
  end

  defp send_startup_notification do
    message = "🚀 STARTING APPLICATION..."

    notify_slack(
      slack_webhook_url(),
      Application.get_env(:mi_etl, :notification)[:slack_webhook][:headers],
      System.get_env("ENVIRONMENT"),
      message
    )
  end

  defp setup_postgres do
    Logger.info("Configurando PostgreSQL")

    postgres_config = Application.get_env(:mi_etl, :postgres)
    connection_config = postgres_config[:connection]
    tables = postgres_config[:tables]

    case Postgres.connect(connection_config) do
      {:ok, conn} ->
        Logger.info("Conexión PostgreSQL establecida")

        Enum.each(tables, fn table_name ->
          case Postgres.create_table_if_not_exists(conn, table_name) do
            {:error, reason} ->
              Logger.error("Error creando tabla '#{table_name}': #{inspect(reason)}")
            _ ->
              :ok
          end
        end)

        Postgres.disconnect(conn)

      {:error, reason} ->
        Logger.error("Error conectando a PostgreSQL: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
```

---

## Paso 10: Configurar el Tipo Documental

`lib/impl/type/documentary_type_of.ex`

```elixir
defimpl Type.PDocumentaryTypeOf, for: Atom do
  @moduledoc """
  Implementación del tipo documental para el negocio.
  """

  def documentary_type_of(:record), do: "mi_tipo_documental"
  def documentary_type_of(:task), do: "mi_tipo_documental"
  def documentary_type_of(_), do: nil
end
```

---

## Paso 11: Archivos Adicionales

### `lib/impl/time/my_time.ex`

```elixir
defimpl Time.PWorkingTimeForBusiness, for: Atom do
  @moduledoc """
  Configuración de tiempo laboral para el negocio.
  """

  # Horario laboral: 9:00 - 18:00, Lunes a Viernes
  def working_time(:mi_negocio) do
    %{
      start_hour: 9,
      end_hour: 18,
      working_days: [1, 2, 3, 4, 5]  # Lunes a Viernes
    }
  end

  def working_time(_), do: nil
end
```

### `lib/tools/stuff.ex`

```elixir
defmodule Tools.Stuff do
  @moduledoc """
  Funciones auxiliares específicas del proyecto.
  """

  require Logger
  import Notification.Notify, only: [notify_slack: 4]

  def handle_error(batch_id, unique_id, error, module, function) do
    msg = """
    [#{module} Error]
    Function: #{function}
    Record Id: #{inspect(unique_id)}
    Batch Id: #{inspect(batch_id)}
    Error: #{inspect(error)}
    """

    Logger.error(msg)

    notify_slack(
      Application.get_env(:mi_etl, :notification)[:slack_webhook][:url][:bug],
      Application.get_env(:mi_etl, :notification)[:slack_webhook][:headers],
      System.get_env("ENVIRONMENT"),
      msg
    )
  end
end
```

### `Dockerfile`

```dockerfile
FROM elixir:1.14-alpine AS build

RUN apk add --no-cache build-base git

WORKDIR /app

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only prod && \
    mix deps.compile

COPY config config
COPY lib lib
COPY rel rel

RUN mix release

# Runtime
FROM alpine:3.18 AS app

RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app

COPY --from=build /app/_build/prod/rel/mi_etl ./

ENV HOME=/app

CMD ["bin/mi_etl", "start"]
```

### `rel/env.sh.eex`

```bash
#!/bin/sh

export RELEASE_DISTRIBUTION=name
export RELEASE_NODE=mi_etl@127.0.0.1
```

---

## Checklist Final

### Estructura de Archivos
- [ ] `mix.exs` con dependencias correctas
- [ ] `config/config.exs` - Logger básico
- [ ] `config/runtime.exs` - Todas las variables de entorno
- [ ] `lib/mi_etl/application.ex` - Supervisor tree

### Entidades
- [ ] `entity/record/subentities/record_base.ex` - Atributos base con `unique_id`, `last_update`, `timestamp`
- [ ] `entity/record/record.ex` - Entidad Record principal
- [ ] `entity/task/task.ex` - Entidad Task
- [ ] Sub-entidades adicionales según necesidad

### Implementaciones
- [ ] `impl/genserver/worker.ex` - Protocolo PWorker
- [ ] `impl/genserver/forced_load_config.ex` - Configuración ForcedLoad
- [ ] `impl/type/documentary_type_of.ex` - Tipo documental
- [ ] `impl/time/my_time.ex` - Tiempo laboral (si se usa)

### Configuración
- [ ] Variables de entorno documentadas
- [ ] Colas RabbitMQ definidas
- [ ] Tablas BigQuery especificadas
- [ ] Conexión PostgreSQL configurada

### Deployment
- [ ] Dockerfile funcional
- [ ] Configuración de Kubernetes/Okteto
- [ ] Scripts de inicio (startup.sh)

---

## Variables de Entorno Requeridas

```bash
# BigQuery
DNS=
DATAMART_MI_ETL=
MI_ETL_RECORDS_TABLE=
MI_ETL_TASK_TABLE=

# Slack
SLACK_WEBHOOK_FOR_BUGS=
SLACK_WEBHOOK_FOR_NOTIFICATIONS=

# Credenciales
TOTALCHECK_USERNAME=
TOTALCHECK_PASSWORD=

# Servicios
TICKET_ACCESS_URL=
ELASTICSEARCH_HOST=
NODE_SERVICE_URL=
WORKFLOW_SERVICE_URL=

# RabbitMQ
AMQP_HOST=
AMQP_PORT=
AMQP_USERNAME=
AMQP_PASSWORD=
AMQP_RECORD_QUEUE=
AMQP_TASK_QUEUE=

# PostgreSQL
PG_HOST=
PG_PORT=
PG_DATABASE=
PG_USERNAME=
PG_PASSWORD=
PG_TABLE_RECORDS=
PG_TABLE_TASKS=

# Ambiente
ENVIRONMENT=
```
