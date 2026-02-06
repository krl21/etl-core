# Guía para Crear un ETL desde Cero

Esta guía describe paso a paso cómo crear un nuevo proyecto ETL utilizando `etl-core`.

---

## Tabla de Contenidos

- [Guía para Crear un ETL desde Cero](#guía-para-crear-un-etl-desde-cero)
  - [Tabla de Contenidos](#tabla-de-contenidos)
  - [Visión General](#visión-general)
    - [Componentes Principales](#componentes-principales)
  - [Estructura del Proyecto](#estructura-del-proyecto)
  - [Paso 1: Crear el Proyecto](#paso-1-crear-el-proyecto)
  - [Paso 2: Configuración de Dependencias](#paso-2-configuración-de-dependencias)
    - [`mix.exs`](#mixexs)
    - [Instalar dependencias](#instalar-dependencias)
  - [Paso 3: Archivos de Configuración](#paso-3-archivos-de-configuración)
    - [3.1 `config/config.exs`](#31-configconfigexs)
    - [3.2 `config/dev.exs`](#32-configdevexs)
    - [3.3 `config/prod.exs` y `config/test.exs`](#33-configprodexs-y-configtestexs)
    - [3.4 `config/runtime.exs` (CRÍTICO)](#34-configruntimeexs-crítico)
  - [Paso 4: Definir Sub-entidades (Atributos)](#paso-4-definir-sub-entidades-atributos)
    - [4.1 Atributos Base (OBLIGATORIO)](#41-atributos-base-obligatorio)
    - [4.2 Sub-entidades Adicionales](#42-sub-entidades-adicionales)
    - [4.3 Sub-entidad con Post-procesamiento](#43-sub-entidad-con-post-procesamiento)
  - [Paso 5: Crear la Entidad Record Principal](#paso-5-crear-la-entidad-record-principal)
  - [Paso 6: Crear la Entidad Task](#paso-6-crear-la-entidad-task)
  - [Paso 7: Implementar el Worker](#paso-7-implementar-el-worker)
  - [Paso 8: Configurar ForcedLoad](#paso-8-configurar-forcedload)
  - [Paso 9: Configurar el Tipo Documental](#paso-9-configurar-el-tipo-documental)
    - [Configuración de Tiempo Laboral (Opcional)](#configuración-de-tiempo-laboral-opcional)
  - [Paso 10: Implementar Application](#paso-10-implementar-application)
  - [Paso 11: Archivos de Deployment](#paso-11-archivos-de-deployment)
    - [11.1 `k8s/canary/deployment.yml`](#111-k8scanarydeploymentyml)
    - [11.2 `startup-prod.sh`](#112-startup-prodsh)
    - [11.3 `Dockerfile`](#113-dockerfile)
    - [11.4 `rel/env.sh.eex`](#114-relenvsheex)
  - [Checklist Final](#checklist-final)
    - [Estructura de Archivos](#estructura-de-archivos)
    - [Pools de Conexiones (v2.1+)](#pools-de-conexiones-v21)
    - [Entidades](#entidades)
    - [Implementaciones](#implementaciones)
    - [Configuración](#configuración)
    - [Deployment](#deployment)
  - [Variables de Entorno Requeridas](#variables-de-entorno-requeridas)
  - [Consejos y Mejores Prácticas](#consejos-y-mejores-prácticas)
    - [1. Nombrado de Atributos](#1-nombrado-de-atributos)
    - [2. Manejo de Errores](#2-manejo-de-errores)
    - [3. Post-procesamiento](#3-post-procesamiento)
    - [4. Testing](#4-testing)
    - [5. Carga Masiva](#5-carga-masiva)
    - [6. Pools de Conexiones (v2.1+)](#6-pools-de-conexiones-v21)

---

## Visión General

El sistema ETL sigue un flujo de datos bien definido:

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  RabbitMQ   │───►│   Worker    │───►│ PostgreSQL  │───►│  BigQuery   │
│  (Eventos)  │    │ (Procesa)   │    │  (Buffer)   │    │ (Destino)   │
└─────────────┘    └─────────────┘    └──────┬──────┘    └──────┬──────┘
                                             │                  │
                                     ┌───────┴──────┐   ┌───────┴──────┐
                                     │ Pool.Postgres│   │Pool.BigQuery │
                                     │  (v2.1+)   │   │  (v2.1+)   │
                                     └───────┬──────┘   └───────┬──────┘
                                             │                  │
                   ┌─────────────────────────┼──────────────────┘
                   │                         │
            ┌──────┴──────┐           ┌──────┴──────┐
            │ BigQuery    │           │  Cleaning   │
            │  Uploader   │           │ (Limpieza)  │
            └─────────────┘           └─────────────┘
```

> **Nota v2.1+**: Los pools gestionan las conexiones automáticamente, evitando
> abrir/cerrar conexiones para cada operación.

### Componentes Principales

| Componente | Descripción |
|------------|-------------|
| **Pool.Postgres** | Pool de conexiones PostgreSQL (v2.1+) |
| **Pool.BigQuery** | Pool de conexiones BigQuery via ODBC (v2.1+) |
| **RabbitConsumer** | Consume mensajes de colas RabbitMQ en tiempo real |
| **Worker** | Procesa los mensajes según el tipo de negocio (`:record`, `:task`) |
| **PostgreSQL** | Buffer intermedio para almacenamiento temporal |
| **BigqueryUploader** | Sube datos de PostgreSQL a BigQuery periódicamente |
| **Cleaning** | Elimina duplicados y registros ya procesados |
| **ForcedLoad** | Carga histórica de datos desde ElasticSearch |

---

## Estructura del Proyecto

```
mi_etl/
├── config/
│   ├── config.exs              # Configuración del logger
│   ├── dev.exs                 # Configuración de desarrollo (PostgreSQL local)
│   ├── prod.exs                # Configuración de producción
│   ├── runtime.exs             # Configuración en runtime (IMPORTANTE: variables de entorno)
│   └── test.exs                # Configuración de tests
├── k8s/
│   ├── canary/
│   │   └── deployment.yml      # Deployment para ambiente Canary/QA
│   └── production/
│       └── deployment.yml      # Deployment para Producción
├── lib/
│   ├── mi_etl.ex               # Módulo principal (puede estar vacío)
│   ├── mi_etl/
│   │   └── application.ex      # Application (supervisor tree) - MUY IMPORTANTE
│   ├── entity/
│   │   ├── record/
│   │   │   ├── record.ex               # Entidad principal Record
│   │   │   └── subentities/
│   │   │       ├── record_base.ex      # Atributos base (unique_id, timestamp, etc.)
│   │   │       ├── buyer.ex            # Sub-entidad Comprador
│   │   │       ├── vehicle.ex          # Sub-entidad Vehículo
│   │   │       └── ...                 # Más sub-entidades según el negocio
│   │   └── task/
│   │       └── task.ex                 # Entidad Task
│   ├── impl/
│   │   ├── genserver/
│   │   │   ├── worker.ex               # Implementación del protocolo PWorker
│   │   │   └── forced_load_config.ex   # Configuración para carga forzada
│   │   ├── time/
│   │   │   └── my_time.ex              # Configuración de tiempo laboral
│   │   └── type/
│   │       └── documentary_type_of.ex  # Mapeo de tipos documentales
│   └── tools/
│       └── stuff.ex                    # Funciones auxiliares específicas
├── rel/
│   ├── env.bat.eex             # Variables para Windows
│   └── env.sh.eex              # Variables para Unix
├── Dockerfile                  # Imagen Docker
├── mix.exs                     # Dependencias y configuración del proyecto
├── startup-prod.sh             # Script para ejecutar en producción (Okteto)
└── startup-qa.sh               # Script para ejecutar en QA
```

---

## Paso 1: Crear el Proyecto

```bash
# Crear proyecto con supervisor
mix new mi_etl --sup
cd mi_etl

# Crear estructura de directorios
mkdir -p lib/entity/record/subentities
mkdir -p lib/entity/task
mkdir -p lib/impl/genserver
mkdir -p lib/impl/time
mkdir -p lib/impl/type
mkdir -p lib/tools
mkdir -p config
mkdir -p k8s/canary
mkdir -p k8s/production
mkdir -p rel
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
      elixir: "~> 1.14.0-rc.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      extras: ["README.md"]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :odbc],  # :odbc es necesario para BigQuery
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
      # ETL Core v2.1 - Librería base (incluye pools de conexiones)
      {:etl_core, git: "https://github.com/krl21/etl-core.git", branch: "v2.2"},
      
      # Logger flexible
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
mix compile
```

---

## Paso 3: Archivos de Configuración

### 3.1 `config/config.exs`

Configuración base del logger:

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

# Importar configuración específica del ambiente
import_config "#{Mix.env()}.exs"
```

### 3.2 `config/dev.exs`

Configuración para desarrollo local:

```elixir
import Config

config :logger, :logger_name,
  level_config: [application: :mi_etl, level: :debug]

# PostgreSQL local para desarrollo (opcional)
config :mi_etl,
  postgres: %{
    connection: %{
      hostname: "localhost",
      port: 5432,
      database: "mi_etl_dev",
      username: "postgres",
      password: "postgres"
    },
    tables: ["mi_etl_records"],
    register_type: %{
      record: "expediente",
      task: "tarea"
    }
  }
```

### 3.3 `config/prod.exs` y `config/test.exs`

```elixir
# config/prod.exs
import Config

config :logger, :logger_name,
  level_config: [application: :mi_etl, level: :info]

# config/test.exs
import Config

config :logger, :logger_name,
  level_config: [application: :mi_etl, level: :warning]
```

### 3.4 `config/runtime.exs` (CRÍTICO)

Este archivo contiene **TODA** la configuración que depende de variables de entorno. Es el archivo más importante de configuración.

```elixir
import Config

################
### Nivel de log
################
config :logger, :logger_name,
  level_config: [application: :mi_etl, level: :debug]

################
### Zona horaria para conversiones de fecha
################
config :mi_etl,
  timezone: "America/Santiago"

################
### Configuración de BigQuery
################
config :mi_etl,
  bigquery: %{
    configuration: [
      dsn: System.get_env("DNS"),
      warehouse: System.get_env("DATAMART_MI_ETL")
    ],
    table: %{
      record: "#{System.get_env("DATAMART_MI_ETL")}.#{System.get_env("MI_ETL_SERVICE_TABLE")}",
      task: "#{System.get_env("DATAMART_MI_ETL")}.#{System.get_env("MI_ETL_TASK_TABLE")}"
    }
  }

################
### Configuración de notificaciones Slack
################
config :mi_etl,
  notification: %{
    slack_webhook: %{
      url: %{
        bug: System.get_env("SLACK_WEBNOOK_FOR_BUGS"),
        notification: System.get_env("SLACK_WEBNOOK_FOR_NOTIFICATIONS")
      },
      headers: [{"Content-type", "application/json"}]
    }
  }

################
### Credenciales de usuario del sistema
################
config :mi_etl,
  user: %{
    totalcheck: %{
      username: System.get_env("TOTALCHECK_USERNAME"),
      password: System.get_env("TOTALCHECK_PASSWORD")
    }
  }

################
### Servicios externos DOX
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
    type_documentary: ["mi_tipo_documental"],  # Cambiar según el negocio
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
### Configuración de RabbitMQ
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
              # Exchanges a escuchar (dejar vacío si no aplica)
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
              # Lista de eventos de tareas a escuchar
              "on_create_tarea_1",
              "on_completed_tarea_1"
              # ... agregar más según el negocio
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
  batch_size: 200,            # Tamaño de batch para consultas
  batch_size_process: 70      # Tamaño de batch para procesamiento

################
### Periodicidad de GenServers
################
config :mi_etl,
  activation_time: %{
    rabbit_consumer_by_batch: %{
      periodicity: %{day: 0, hour: 0, minute: 2, second: 0}
    },
    cleanup_in_bigquery: %{
      periodicity: %{day: 0, hour: 1, minute: 30, second: 0}  # Cada 90 minutos
    },
    bigquery_uploader: %{
      periodicity: %{day: 0, hour: 0, minute: 1, second: 0}   # Cada 1 minuto
    }
  }

################
### Configuración de PostgreSQL (Buffer)
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

## Paso 4: Definir Sub-entidades (Atributos)

Las sub-entidades definen los atributos que se extraen del payload JSON.

### 4.1 Atributos Base (OBLIGATORIO)

Este archivo **debe existir** y contener al menos: `unique_id`, `last_update` y `timestamp`.

`lib/entity/record/subentities/record_base.ex`

```elixir
defmodule Entity.Record.Subentities.RecordBase do
  @moduledoc """
  Atributos base del expediente. Define unique_id, timestamp y otros campos fundamentales.
  """
  
  use DataModel.Attribute.Provider
  alias Struct.InfoAttr

  ################
  ### Atributos Fundamentales
  ################

  @unique_id %InfoAttr{
    id: :unique_id,
    id_payload: "unique_id",
    type: :string
  }

  @last_update %InfoAttr{
    id: :ultima_actualizacion,
    id_payload: "updated_at",
    type: :string
  }

  @inserted_at %InfoAttr{
    id: :fecha_solicitud,
    id_payload: "inserted_at",
    type: :string
  }

  @inserted_at_timestamp %InfoAttr{
    id: :fecha_solicitud_,
    id_payload: "inserted_at",
    type: :timestamp
  }

  @is_deleted %InfoAttr{
    id: :esta_eliminado,
    id_payload: "deleted",
    type: :boolean,
    keys_to_search: ["data"],
    default_value: false
  }

  @timestamp %InfoAttr{
    id: :timestamp,
    type: :integer
  }

  @tenant %InfoAttr{
    id: :tenant,
    id_payload: "tenant",
    type: :string
  }

  ################
  ### Registrar atributos
  ################

  attr_list [
    @unique_id,
    @last_update,
    @inserted_at,
    @inserted_at_timestamp,
    @is_deleted,
    @timestamp,
    @tenant
  ]

  ################
  ### Funciones Públicas (Getters)
  ################

  @doc "Retorna el atributo unique_id"
  def unique_id, do: @unique_id

  @doc "Retorna el atributo last_update"
  def last_update, do: @last_update

  @doc "Retorna el atributo timestamp"
  def timestamp, do: @timestamp

  ################
  ### Post-procesamiento (Opcional)
  ################

  @doc """
  Procesamiento especial después de extraer los datos.
  Aquí se calcula el timestamp automáticamente.
  """
  def special_post_processing(values, _payload) do
    Keyword.put(values, @timestamp.id, Timex.now() |> Timex.to_unix())
  end
end
```

### 4.2 Sub-entidades Adicionales

Crear una sub-entidad por cada grupo lógico de atributos.

`lib/entity/record/subentities/vehicle.ex`

```elixir
defmodule Entity.Record.Subentities.Vehicle do
  @moduledoc """
  Atributos relacionados con el vehículo.
  """

  use DataModel.Attribute.Provider
  alias Struct.InfoAttr

  ################
  ### Atributos del Vehículo
  ################

  @brand %InfoAttr{
    id: :marca_vehiculo,
    id_payload: "marca",
    type: :string,
    keys_to_search: ["data", "parser", "vehiculo"]
  }

  @model %InfoAttr{
    id: :modelo_vehiculo,
    id_payload: "modelo",
    type: :string,
    keys_to_search: ["data", "parser", "vehiculo"]
  }

  @year %InfoAttr{
    id: :anno_vehiculo,
    id_payload: "anual",
    type: :integer,
    keys_to_search: ["data", "parser", "vehiculo"]
  }

  @license_plate %InfoAttr{
    id: :patente_vehiculo,
    id_payload: "placa_patente",
    type: :string,
    keys_to_search: ["data"]
  }

  @color %InfoAttr{
    id: :color_vehiculo,
    id_payload: "color",
    type: :string,
    keys_to_search: ["data", "parser", "vehiculo"]
  }

  @vehicle_type %InfoAttr{
    id: :tipo_vehiculo,
    id_payload: "tipo_vehiculo",
    type: :string,
    keys_to_search: ["data", "parser", "vehiculo"]
  }

  @vin %InfoAttr{
    id: :vin_vehiculo,
    id_payload: "vin",
    type: :string,
    keys_to_search: ["data", "parser", "vehiculo"]
  }

  @chassis %InfoAttr{
    id: :chassis_vehiculo,
    id_payload: "chassis",
    type: :string,
    keys_to_search: ["data", "parser", "vehiculo"]
  }

  ################
  ### Registrar atributos
  ################

  attr_list [
    @brand,
    @model,
    @year,
    @license_plate,
    @color,
    @vehicle_type,
    @vin,
    @chassis
  ]

  # No necesita special_post_processing si no hay lógica especial
end
```

### 4.3 Sub-entidad con Post-procesamiento

`lib/entity/record/subentities/buyer.ex`

```elixir
defmodule Entity.Record.Subentities.Buyer do
  @moduledoc """
  Atributos del comprador con lógica de post-procesamiento.
  """

  use DataModel.Attribute.Provider
  alias Struct.InfoAttr

  @buyer_name %InfoAttr{
    id: :nombre_comprador,
    id_payload: "comprador_nombre",
    type: :string,
    keys_to_search: ["data"]
  }

  @buyer_rut %InfoAttr{
    id: :rut_comprador,
    id_payload: "comprador_rut",
    type: :string,
    keys_to_search: ["data"]
  }

  @buyer_type %InfoAttr{
    id: :tipo_comprador,
    id_payload: "comprador_tipo",
    type: :string,
    keys_to_search: ["data"]
  }

  # Campo calculado (no viene del payload directamente)
  @buyer_full_name %InfoAttr{
    id: :nombre_completo_comprador,
    type: :string
  }

  attr_list [
    @buyer_name,
    @buyer_rut,
    @buyer_type,
    @buyer_full_name
  ]

  @doc """
  Post-procesamiento: combinar razón social con nombre si está disponible.
  """
  def special_post_processing(values, payload) do
    razon_social = get_in(payload, ["data", "comprador_razon_social"])
    nombre = Keyword.get(values, @buyer_name.id)
    
    nombre_completo = 
      case {razon_social, nombre} do
        {nil, n} -> n
        {rs, nil} -> rs
        {rs, n} -> "#{rs} - #{n}"
      end
    
    Keyword.put(values, @buyer_full_name.id, nombre_completo)
  end
end
```

---

## Paso 5: Crear la Entidad Record Principal

`lib/entity/record/record.ex`

```elixir
defmodule Entity.Record.Record do
  @moduledoc """
  Entidad principal Record. Combina todas las sub-entidades y define la lógica de inserción.
  """

  use DataModel.RecordPg.Base
  use Cleaning.CleanableTable
  require Logger
  import Stuff, only: [list_subtraction: 2]

  ################
  ### Aliases de Sub-entidades
  ################

  @record_base    Entity.Record.Subentities.RecordBase
  @vehicle        Entity.Record.Subentities.Vehicle
  @buyer          Entity.Record.Subentities.Buyer
  # Agregar más sub-entidades según necesidad

  ################
  ### Configuración de la Entidad
  ################

  entity_config(
    app: :mi_etl,
    table_name_path: [:postgres, :tables],
    batch_size_key: :batch_size_process,
    unique_id: @record_base.unique_id(),
    timestamp: @record_base.timestamp(),
    value_type_path: [:postgres, :register_type, :record],
    slack_webhook_url_path: [:notification, :slack_webhook, :url, :bug],
    slack_env_var: "ENVIRONMENT"
  )

  ################
  ### CleanableTable Implementation
  ################

  @impl Cleaning.CleanableTable
  def business_key, do: :record

  @impl Cleaning.CleanableTable
  def bigquery_config do
    %{
      table: Application.get_env(:mi_etl, :bigquery)[:table][:record],
      id_fields: [@record_base.unique_id()],
      timestamp_field: @record_base.timestamp()
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
  ### Sub-entidades
  ################

  subentities [
    @record_base,
    @vehicle,
    @buyer
    # Agregar más sub-entidades
  ]

  ################
  ### Entidades con post-procesamiento especial
  ################

  special_post_processing [
    @record_base,  # Para calcular timestamp
    @buyer         # Para calcular nombre completo
  ]

  ################
  ### Generar funciones auxiliares
  ################

  generate_helper_functions()

  ################
  ### Funciones Públicas (Getters)
  ################

  def unique_id, do: @record_base.unique_id()
  def last_update, do: @record_base.last_update()
  def timestamp, do: @record_base.timestamp()

  ################
  ### Función Principal: insert_by_lote (Modo Legacy)
  ################

  @doc """
  Inserta registros desde un batch (modo legacy - crea conexión temporal).

  ## Parámetros
    - `batch`: Lista de payloads
    - `batch_id`: Identificador del batch
    - `pg_config`: Configuración de conexión a PostgreSQL

  ## Retorna
    - `{:ok, count}` - Número de registros insertados
    - `{:error, reason}` - Si hay error
  """
  def insert_by_lote([], _batch_id, _pg_config), do: {:ok, 0}

  def insert_by_lote(batch, batch_id, pg_config)
      when is_list(batch) and is_binary(batch_id) do

    {grouped, keys} = group_by_unique_id(batch)

    records =
      keys
      |> Enum.map(fn key ->
        try do
          prepare_record_for_insert(key, Map.get(grouped, key))
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

    execute_insert_with_retry(records, pg_config, batch_id)
  end

  ################
  ### Función Principal: insert_by_lote_pooled (Modo Pool v2.1+)
  ################

  @doc """
  Inserta registros desde un batch usando pool de conexiones (recomendado).

  ## Parámetros
    - `batch`: Lista de payloads
    - `batch_id`: Identificador del batch
    - `pg_pool_name`: Nombre del pool de PostgreSQL

  ## Retorna
    - `{:ok, count}` - Número de registros insertados
    - `{:error, reason}` - Si hay error
  """
  def insert_by_lote_pooled([], _batch_id, _pg_pool_name), do: {:ok, 0}

  def insert_by_lote_pooled(batch, batch_id, pg_pool_name)
      when is_list(batch) and is_binary(batch_id) and is_atom(pg_pool_name) do

    {grouped, keys} = group_by_unique_id(batch)

    records =
      keys
      |> Enum.map(fn key ->
        try do
          prepare_record_for_insert(key, Map.get(grouped, key))
        rescue
          error ->
            handle_processing_error(batch_id, key, error, %{
              function: :insert_by_lote_pooled,
              module: __MODULE__
            })
            {:error, nil}
        end
      end)
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, record} -> record end)

    # Usar la versión pooled del macro
    execute_insert_with_retry_pooled(records, pg_pool_name, batch_id)
  end

  ################
  ### Override: build_data
  ################

  def build_data(payloads, stored_data, _additional_info) do
    stored_data = if is_list(stored_data), do: stored_data, else: []

    payloads
    |> Enum.reduce(stored_data, fn payload, acc ->
      differences =
        payload
        |> Payload.extract_with_format(attr_list(), false)
        |> apply_post_processing(acc, payload)
        |> list_subtraction(acc)

      update_fields(acc, differences)
    end)
  end

  ################
  ### Funciones Privadas
  ################

  defp prepare_record_for_insert(unique_id, payloads) do
    data =
      payloads
      |> build_data([], unique_id)
      |> ensure_timestamp()

    informacion_map = Enum.into(data, %{})

    record = %{
      id_nodo: unique_id,
      tipo: value_type(),
      informacion: informacion_map
    }

    {:ok, record}
  end

  defp ensure_timestamp(data) do
    case Keyword.get(data, :timestamp) do
      nil -> Keyword.put(data, :timestamp, Timex.now() |> Timex.to_unix())
      _ -> data
    end
  end

  defp update_fields(map, fields) do
    Enum.reduce(fields, map, fn {key, _} = tuple, acc ->
      List.keystore(acc, key, 0, tuple)
    end)
  end
end
```

---

## Paso 6: Crear la Entidad Task

`lib/entity/task/task.ex`

```elixir
defmodule Entity.Task.Task do
  @moduledoc """
  Entidad Task para procesar tareas del workflow.
  """

  use DataModel.TaskPg.Base
  use Cleaning.CleanableTable
  require Logger
  alias Struct.InfoAttr
  alias Common.Payload

  ################
  ### Atributos de la Tarea
  ################

  @contentref %InfoAttr{
    id: :contentref,
    id_payload: "contentref",
    type: :string
  }

  @executed_by %InfoAttr{
    id: :ejecutado_por,
    id_payload: "executedby",
    type: :string
  }

  @start_date %InfoAttr{
    id: :fecha_ini,
    id_payload: "ini",
    type: :timestamp
  }

  @end_date %InfoAttr{
    id: :fecha_fin,
    id_payload: "fin",
    type: :timestamp
  }

  @assigned_id %InfoAttr{
    id: :id_tareasig,
    id_payload: "id",
    type: :integer
  }

  @name %InfoAttr{
    id: :nombre,
    id_payload: "name",
    type: :string
  }

  @last_update %InfoAttr{
    id: :ultima_actualizacion,
    id_payload: "updated_at",
    type: :string
  }

  @status %InfoAttr{
    id: :estado,
    id_payload: "status",
    type: :string
  }

  ################
  ### Atributos Calculados
  ################

  @type_ %InfoAttr{
    id: :tipo,
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
  ### Clasificación de Tipos de Tarea (Opcional)
  ################

  @manual_process_tag "manual"
  @manual_process ["tarea_manual_1", "tarea_manual_2"]

  @automatic_process_tag "automatico"
  @automatic_process ["tarea_auto_1", "tarea_auto_2"]

  @unknown_process_tag "desconocido"

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
  ### CleanableTable Implementation
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
      table: Application.get_env(:mi_etl, :postgres)[:tables] |> List.first(),
      register_type: Application.get_env(:mi_etl, :postgres)[:register_type][:task]
    }
  end

  ################
  ### Listas de Atributos
  ################

  own_attributes [
    @contentref,
    @executed_by,
    @start_date,
    @end_date,
    @assigned_id,
    @name,
    @last_update,
    @status
  ]

  computed_attributes [
    @type_,
    @elapsed_working_time,
    @timestamp
  ]

  ################
  ### Generar funciones auxiliares
  ################

  generate_task_helper_functions()

  ################
  ### Override: build_data
  ################

  def build_data(payloads) do
    payload = List.last(payloads)

    name_process = Payload.extract_data(
      payload,
      @name.id_payload,
      @name.keys_to_search
    )

    payload
    |> Payload.extract_with_format(@own_attributes, false)
    |> Enum.concat([{@type_.id, get_type(name_process)}])
    |> calculate_elapsed_time()
  end

  ################
  ### Funciones Privadas
  ################

  defp get_type(name) do
    cond do
      name in @manual_process -> @manual_process_tag
      name in @automatic_process -> @automatic_process_tag
      true -> @unknown_process_tag
    end
  end
end
```

---

## Paso 7: Implementar el Worker

El Worker procesa los mensajes según el tipo de negocio. A partir de v2.1, soporta tanto modo pool como modo legacy.

`lib/impl/genserver/worker.ex`

```elixir
defimpl Genserver.Protocols.PWorker, for: List do
  @moduledoc """
  Implementación del protocolo Worker para procesar lotes de mensajes.
  Soporta modo pool (pg_pool_name) y modo legacy (pg_config).
  """

  require Logger
  alias Entity.Record.Record
  alias Entity.Task.Task
  import Notification.Notify, only: [notify_slack: 4]

  @doc """
  Procesa un batch de expedientes (records) - Modo Pool (recomendado v2.1+).
  """
  def perform(batch, batch_id, :record = business, %{pg_pool_name: pg_pool_name} = _info) do
    Logger.debug("Nuevo batch (pool mode). Negocio: #{inspect(business)}. Mensajes: #{length(batch)}")

    try do
      batch
      |> Enum.map(fn %{"current" => payload} -> payload end)
      |> Record.insert_by_lote_pooled(batch_id, pg_pool_name)

      Logger.debug("Batch procesado. Id: #{inspect(batch_id)}. Negocio: #{inspect(business)}")
    rescue
      error ->
        handle_error(batch_id, business, error)
    end
  end

  @doc """
  Procesa un batch de expedientes (records) - Modo Legacy.
  """
  def perform(batch, batch_id, :record = business, %{pg_config: pg_config} = _info) do
    Logger.debug("Nuevo batch (legacy mode). Negocio: #{inspect(business)}. Mensajes: #{length(batch)}")

    try do
      batch
      |> Enum.map(fn %{"current" => payload} -> payload end)
      |> Record.insert_by_lote(batch_id, pg_config)

      Logger.debug("Batch procesado. Id: #{inspect(batch_id)}. Negocio: #{inspect(business)}")
    rescue
      error ->
        handle_error(batch_id, business, error)
    end
  end

  @doc """
  Procesa un batch de tareas - Modo Pool (recomendado v2.1+).
  """
  def perform(batch, batch_id, :task = business, %{pg_pool_name: pg_pool_name} = _info) do
    Logger.debug("Nuevo batch (pool mode). Negocio: #{inspect(business)}. Mensajes: #{length(batch)}")

    try do
      batch
      |> Task.insert_by_lote_pooled(batch_id, pg_pool_name)

      Logger.debug("Batch procesado. Id: #{inspect(batch_id)}. Negocio: #{inspect(business)}")
    rescue
      error ->
        handle_error(batch_id, business, error)
    end
  end

  @doc """
  Procesa un batch de tareas - Modo Legacy.
  """
  def perform(batch, batch_id, :task = business, %{pg_config: pg_config} = _info) do
    Logger.debug("Nuevo batch (legacy mode). Negocio: #{inspect(business)}. Mensajes: #{length(batch)}")

    try do
      batch
      |> Task.insert_by_lote(batch_id, pg_config)

      Logger.debug("Batch procesado. Id: #{inspect(batch_id)}. Negocio: #{inspect(business)}")
    rescue
      error ->
        handle_error(batch_id, business, error)
    end
  end

  defp handle_error(batch_id, business, error) do
    msg = "Error procesando batch. Batch Id: #{inspect(batch_id)}. Negocio: #{inspect(business)}. Error: #{inspect(error)}"
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

> **Nota v2.1+**: La entidad Record debe implementar `insert_by_lote_pooled/3` para usar el modo pool.
> Esta función usa `execute_insert_with_retry_pooled/3` del macro base.

---

## Paso 8: Configurar ForcedLoad

`lib/impl/genserver/forced_load_config.ex`

```elixir
defmodule Impl.Genserver.ForcedLoadConfig do
  @moduledoc """
  Configuración para operaciones de carga forzada.
  """

  use ForcedLoad.Config
  import Type.PDocumentaryTypeOf
  alias Entity.Record.Record

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
  def unique_id_field, do: Record.unique_id().id

  @impl true
  def unique_id_payload_field, do: Record.unique_id().id_payload

  @impl true
  def last_update_field, do: Record.last_update().id

  @impl true
  def last_update_payload_field, do: Record.last_update().id_payload

  @impl true
  def time_step, do: 7  # Días por intervalo

  @impl true
  def batch_size, do: 400

  @impl true
  def batch_delay, do: 0  # Milisegundos entre batches

  @impl true
  def webhook_url_path, do: [:notification, :slack_webhook, :url, :notification]
end
```

---

## Paso 9: Configurar el Tipo Documental

`lib/impl/type/documentary_type_of.ex`

```elixir
defimpl Type.PDocumentaryTypeOf, for: Atom do
  @moduledoc """
  Mapeo de tipos de negocio a tipos documentales de ElasticSearch.
  """

  def documentary_type_of(:record), do: "mi_tipo_documental"
  def documentary_type_of(:task), do: "mi_tipo_documental"
  def documentary_type_of(_), do: nil
end
```

### Configuración de Tiempo Laboral (Opcional)

`lib/impl/time/my_time.ex`

```elixir
defimpl Time.PWorkingTimeForBusiness, for: Atom do
  @moduledoc """
  Configuración de horario laboral para el negocio.
  """

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

---

## Paso 10: Implementar Application

`lib/mi_etl/application.ex`

```elixir
defmodule MiEtl.Application do
  @moduledoc false

  use Application
  require Logger
  import Time.Timem, only: [notification_frequency: 1]
  import Notification.Notify, only: [notify_slack: 4]
  alias Impl.Genserver.ForcedLoadConfig

  @impl true
  def start(_type, _args) do
    Logger.info("Cargando variables globales de la aplicación")
    Application.load(:mi_etl)

    Logger.info("Iniciando conexión ODBC")
    Connection.Odbc.start()

    children = build_children()

    opts = [strategy: :one_for_one, name: MiEtl.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    # Crear tablas después de que el pool esté iniciado
    setup_postgres()

    send_startup_notification()

    {:ok, pid}
  end

  ################
  ### Construcción de Children
  ################

  defp build_children do
    [
      # IMPORTANTE: Los pools deben iniciarse PRIMERO
      child_postgres_pool(),
      child_bigquery_pool(),
      child_task_supervisor(),
      child_monitor(),
      child_bigquery_uploader(),
      child_cleaning_supervisor(),
      child_cleaning()
      # child_forced_load()  # Descomentar para activar carga forzada
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Kernel.++(rabbit_consumer_children())
  end

  ################
  ### Pools de Conexiones (v2.1+)
  ################

  defp child_postgres_pool do
    pg_config = Application.get_env(:mi_etl, :postgres)[:connection]

    {Pool.Postgres, %{
      name: :postgres_pool,
      config: pg_config,
      pool_size: 10
    }}
  end

  defp child_bigquery_pool do
    bq_config = Application.get_env(:mi_etl, :bigquery)[:configuration]

    {Pool.BigQuery, [
      name: :bigquery_pool,
      data_source: bq_config,
      pool_size: 5,
      max_overflow: 2
    ]}
  end

  ################
  ### GenServers
  ################

  defp child_task_supervisor do
    {Task.Supervisor, name: SupervisorTareas}
  end

  defp child_monitor do
    {Genserver.Monitor, {slack_webhook_url(), System.get_env("ENVIRONMENT")}}
  end

  defp child_bigquery_uploader do
    bq_config = Application.get_env(:mi_etl, :bigquery)
    pg_config = Application.get_env(:mi_etl, :postgres)

    # Modo pool (recomendado v2.1+)
    {Genserver.BigqueryUploader, %{
      business: :mi_negocio,
      pg_pool_name: :postgres_pool,      # Usar pool en lugar de config directa
      bq_pool_name: :bigquery_pool,      # Usar pool en lugar de data_source
      info: bigquery_upload_info(bq_config, pg_config),
      periodicity: Application.get_env(:mi_etl, :activation_time)[:bigquery_uploader][:periodicity],
      batch_size: Application.get_env(:mi_etl, :batch_size_process),
      webhook_url: slack_webhook_url()
    }}
  end

  defp bigquery_upload_info(bq_config, pg_config) do
    [
      {:record, List.first(pg_config[:tables])},
      {:task, List.first(pg_config[:tables])}
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
      bq_pool_name: :bigquery_pool,  # Nombre del pool de BigQuery
      pg_pool_name: :postgres_pool,  # Nombre del pool de PostgreSQL
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
    # Modo pool (recomendado v2.1+)
    info = %{
      pg_pool_name: :postgres_pool,      # Usar pool en lugar de pg_config
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

  ################
  ### Funciones de Conexión
  ################

  defp setup_postgres do
    Logger.info("Configurando PostgreSQL (creando tablas si no existen)")

    tables = Application.get_env(:mi_etl, :postgres)[:tables]

    Enum.each(tables, fn table_name ->
      # Usar el pool para crear tablas
      case Connection.PostgresPool.create_table_if_not_exists(:postgres_pool, table_name) do
        {:error, reason} ->
          Logger.error("Error creando tabla '#{table_name}': #{inspect(reason)}")
        _ -> 
          Logger.info("Tabla '#{table_name}' verificada/creada")
      end
    end)
  end

  defp slack_webhook_url do
    Application.get_env(:mi_etl, :notification)[:slack_webhook][:url][:bug]
  end

  defp send_startup_notification do
    message = "★,\n★★,\n★★★,\n★★★★,\n★★★★★,\nAPLICACION INICIADA: MI ETL..., \n★★★★★,\n★★★★,\n★★★,\n★★,\n★"

    notify_slack(
      slack_webhook_url(),
      Application.get_env(:mi_etl, :notification)[:slack_webhook][:headers],
      System.get_env("ENVIRONMENT"),
      message
    )
  end

  ################
  ### Función para Carga Masiva Manual
  ################

  @doc """
  Función para ejecutar carga masiva desde iex.
  Uso: MiEtl.Application.start_band_air()
  """
  def start_band_air do
    Logger.info("Activando carga forzada de registros")

    {
      Application.get_env(:mi_etl, :my_amqp_client)[:queue][:mi_negocio][:record][:business],
      [
        {{2024, 1, 1}, {0, 0, 0}},
        Timex.now() |> Timex.to_erl(),
        7,
        true,
        false
      ]
    }
    |> Genserver.ForcedLoad.start_link()
  end
end
```

---

## Paso 11: Archivos de Deployment

### 11.1 `k8s/canary/deployment.yml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $POD_NAME
  labels:
    name: $POD_NAME
spec:
  selector:
    matchLabels:
      app: $POD_NAME
  replicas: 1
  template:
    metadata:
      labels:
        app: $POD_NAME
    spec:
      terminationGracePeriodSeconds: 31
      containers:
        - name: $POD_NAME
          image: $IMAGE_NAME
          imagePullPolicy: "Always"
          ports:
            - containerPort: 8080
            - containerPort: 21123
          env:
            - name: MY_POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
            
            ### Generales
            - name: ENVIRONMENT
              value: "Canary"

            ### RabbitMQ
            - name: AMQP_HOST
              value: "10.142.0.37"
            - name: AMQP_PORT
              value: "5672"
            - name: AMQP_USERNAME
              value: "admin"
            - name: AMQP_PASSWORD
              value: "puma7selva"
            - name: AMQP_RECORD_QUEUE
              value: "expediente_mi_etl_pdatos"
            - name: AMQP_TASK_QUEUE
              value: "tarea_mi_etl_pdatos"

            ### BigQuery 
            - name: DNS
              value: "bigquery64"
            - name: DATAMART_MI_ETL
              value: "ttlchk-cloud.mi_etl_qa"
            - name: MI_ETL_SERVICE_TABLE
              value: "servicio"
            - name: MI_ETL_TASK_TABLE
              value: "tarea"

            ### Notification (Slack)
            - name: SLACK_WEBNOOK_FOR_BUGS 
              value: "https://hooks.slack.com/services/..."
            - name: SLACK_WEBNOOK_FOR_NOTIFICATIONS
              value: "https://hooks.slack.com/services/..."
            
            ### Servicios DOX
            - name: TICKET_ACCESS_URL  
              value: "https://canary-backofficedigital.totalcheck.cl/userservice/login?u=<username>&pw=<password>"
            - name: ELASTICSEARCH_HOST
              value: "10.142.0.96"
            - name: NODE_SERVICE_URL
              value: "https://canary-web.albertcs.com/nodeservice/tenant/system/node/<unique_id>?alf_ticket=<ticket>"
            - name: WORKFLOW_SERVICE_URL
              value: "https://canary-backofficedigital.totalcheck.cl/api/workflowservice/workflow/<type_documentary>/nodeid/<contentref>?alf_ticket=<ticket>"
            
            ### Credenciales
            - name: TOTALCHECK_USERNAME
              valueFrom:
                secretKeyRef:
                  name: alberto-auth-secret
                  key: ALBERTO_SYSTEM_USERNAME
            - name: TOTALCHECK_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: alberto-auth-secret
                  key: ALBERTO_SYSTEM_PASSWORD

            ### PostgreSQL (Buffer)
            - name: PG_HOST
              value: "10.0.32.3"
            - name: PG_PORT
              value: "5432"
            - name: PG_DATABASE
              value: "etl_buffer"
            - name: PG_USERNAME
              value: "etl_service"
            - name: PG_PASSWORD
              value: "Etl$3rv1c3_2024!"
            - name: PG_TABLE
              value: "mi_etl_buffer"

---
apiVersion: v1
kind: Service
metadata:
  name: $POD_NAME-service
  labels:
    app: $POD_NAME-service
spec:
  ports:
    - port: 8080
      name: "http"
      targetPort: 8080
    - port: 21123
      name: "https"
      targetPort: 21123
  selector:
    app: $POD_NAME
  type: NodePort
```

### 11.2 `startup-prod.sh`

```bash
#!/bin/sh

export ENVIRONMENT="prod-okteto"

### RabbitMQ
export AMQP_HOST="10.142.0.26"
export AMQP_PORT="5672"
export AMQP_USERNAME="admin"
export AMQP_PASSWORD="puma7selva"
export AMQP_RECORD_QUEUE="expediente_mi_etl_pdatos"
export AMQP_TASK_QUEUE="tarea_mi_etl_pdatos"

### BigQuery 
export DNS="bigquery64"
export DATAMART_MI_ETL="ttlchk-cloud.mi_etl_prod"
export MI_ETL_SERVICE_TABLE="servicio"
export MI_ETL_TASK_TABLE="tarea"

### Notification
export SLACK_WEBNOOK_FOR_BUGS="https://hooks.slack.com/services/..."
export SLACK_WEBNOOK_FOR_NOTIFICATIONS="https://hooks.slack.com/services/..."

### Servicios DOX
export TICKET_ACCESS_URL="https://backofficedigital.totalcheck.cl/userservice/login?u=<username>&pw=<password>"
export ELASTICSEARCH_HOST="10.142.0.61"
export NODE_SERVICE_URL="https://web.albertcs.com/nodeservice/tenant/system/node/<unique_id>?alf_ticket=<ticket>"
export WORKFLOW_SERVICE_URL="https://backofficedigital.totalcheck.cl/api/workflowservice/workflow/<type_documentary>/nodeid/<contentref>?alf_ticket=<ticket>"

### Credenciales
export TOTALCHECK_USERNAME="system"
export TOTALCHECK_PASSWORD="tigre5playa"

### PostgreSQL
export PG_HOST="10.0.32.3"
export PG_PORT="5432"
export PG_DATABASE="etl_buffer"
export PG_USERNAME="etl_service"
export PG_PASSWORD="Etl\$3rv1c3_2024!"
export PG_TABLE="mi_etl_buffer"

iex -S mix
```

### 11.3 `Dockerfile`

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

### 11.4 `rel/env.sh.eex`

```bash
#!/bin/sh

export RELEASE_DISTRIBUTION=name
export RELEASE_NODE=mi_etl@127.0.0.1
```

---

## Checklist Final

### Estructura de Archivos
- [ ] `mix.exs` con dependencias (etl_core vx.y)
- [ ] `config/config.exs` - Logger básico
- [ ] `config/runtime.exs` - **TODAS las variables de entorno**
- [ ] `lib/mi_etl/application.ex` - Supervisor tree con pools

### Pools de Conexiones (v2.1+)
- [ ] Pool PostgreSQL configurado en `build_children/0`
- [ ] Pool BigQuery configurado en `build_children/0`
- [ ] Pools iniciados ANTES que los GenServers que los usan

### Entidades
- [ ] `entity/record/subentities/record_base.ex` - Atributos base con `unique_id`, `last_update`, `timestamp`
- [ ] `entity/record/record.ex` - Entidad Record con `CleanableTable` e `insert_by_lote_pooled/3`
- [ ] `entity/task/task.ex` - Entidad Task con `CleanableTable` e `insert_by_lote_pooled/3`
- [ ] Sub-entidades adicionales según el negocio

### Implementaciones
- [ ] `impl/genserver/worker.ex` - Protocolo PWorker con soporte pool y legacy
- [ ] `impl/genserver/forced_load_config.ex` - Configuración ForcedLoad
- [ ] `impl/type/documentary_type_of.ex` - Tipo documental
- [ ] `impl/time/my_time.ex` - Tiempo laboral (si se usa)

### Configuración
- [ ] Variables de entorno documentadas
- [ ] Colas RabbitMQ definidas (record y task)
- [ ] Tablas BigQuery especificadas
- [ ] Conexión PostgreSQL configurada
- [ ] Webhooks de Slack configurados

### Deployment
- [ ] `Dockerfile` funcional
- [ ] `k8s/canary/deployment.yml`
- [ ] `k8s/production/deployment.yml`
- [ ] `startup-prod.sh` y `startup-qa.sh`
- [ ] `rel/env.sh.eex`

---

## Variables de Entorno Requeridas

```bash
# Ambiente
ENVIRONMENT=Canary|Production

# BigQuery
DNS=bigquery64
DATAMART_MI_ETL=ttlchk-cloud.mi_etl_prod
MI_ETL_SERVICE_TABLE=servicio
MI_ETL_TASK_TABLE=tarea

# Slack
SLACK_WEBNOOK_FOR_BUGS=https://hooks.slack.com/services/...
SLACK_WEBNOOK_FOR_NOTIFICATIONS=https://hooks.slack.com/services/...

# Credenciales del sistema
TOTALCHECK_USERNAME=system
TOTALCHECK_PASSWORD=***

# Servicios DOX
TICKET_ACCESS_URL=https://backofficedigital.totalcheck.cl/userservice/login?u=<username>&pw=<password>
ELASTICSEARCH_HOST=10.142.0.61
NODE_SERVICE_URL=https://web.albertcs.com/nodeservice/tenant/system/node/<unique_id>?alf_ticket=<ticket>
WORKFLOW_SERVICE_URL=https://backofficedigital.totalcheck.cl/api/workflowservice/workflow/<type_documentary>/nodeid/<contentref>?alf_ticket=<ticket>

# RabbitMQ
AMQP_HOST=10.142.0.26
AMQP_PORT=5672
AMQP_USERNAME=admin
AMQP_PASSWORD=***
AMQP_RECORD_QUEUE=expediente_mi_etl_pdatos
AMQP_TASK_QUEUE=tarea_mi_etl_pdatos

# PostgreSQL (Buffer)
PG_HOST=10.0.32.3
PG_PORT=5432
PG_DATABASE=etl_buffer
PG_USERNAME=etl_service
PG_PASSWORD=***
PG_TABLE=mi_etl_buffer
```

---

## Consejos y Mejores Prácticas

### 1. Nombrado de Atributos

- Usar nombres en español para columnas de BigQuery (ej: `marca_vehiculo`, `fecha_solicitud`)
- Mantener `id_payload` con el nombre exacto del campo en el JSON

### 2. Manejo de Errores

- Siempre envolver operaciones críticas en `try/rescue`
- Usar `handle_processing_error/4` para notificar a Slack
- Los errores individuales no deben detener el batch completo

### 3. Post-procesamiento

- Usar `special_post_processing/2` para lógica que depende del payload completo
- El timestamp debe calcularse siempre (usar `Timex.now() |> Timex.to_unix()`)

### 4. Testing

- Ejecutar localmente con `iex -S mix` y el script `startup-qa.sh`
- Verificar logs en Slack para errores
- Revisar PostgreSQL para ver registros en estado `sin_analizar`

### 5. Carga Masiva

- Para cargar datos históricos, usar la función `start_band_air/0`
- Ajustar `time_step` y `batch_size` según el volumen de datos
- Monitorear la cola de RabbitMQ durante la carga

### 6. Pools de Conexiones (v2.1+)

- **Orden de inicio**: Los pools deben iniciarse ANTES que los GenServers que los usan
- **Pool size**: Ajustar según la carga esperada (10 para PostgreSQL, 5 para BigQuery es un buen punto de partida)
- **Modo dual**: Usar `write_hostname` y `read_hostname` si tienes réplica de lectura
- **Migración**: Puedes migrar gradualmente de modo legacy a modo pool
- **Health checks**: El pool de BigQuery realiza health checks automáticos en cada checkout

