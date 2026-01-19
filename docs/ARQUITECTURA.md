# Arquitectura del Sistema ETL

Este documento describe la arquitectura concebida para el sistema ETL basado en `etl-core` v2.1.

---

## Tabla de Contenidos

1. [Visión General](#visión-general)
2. [Diagrama de Arquitectura](#diagrama-de-arquitectura)
3. [Flujo de Datos](#flujo-de-datos)
4. [Componentes del Sistema](#componentes-del-sistema)
5. [Patrones de Diseño](#patrones-de-diseño)
6. [Capas de la Aplicación](#capas-de-la-aplicación)
7. [Gestión de Conexiones](#gestión-de-conexiones)
8. [Modelo de Concurrencia](#modelo-de-concurrencia)
9. [Estrategias de Resiliencia](#estrategias-de-resiliencia)
10. [Extensibilidad](#extensibilidad)

---

## Visión General

El sistema ETL está diseñado como una aplicación Elixir/OTP que sigue el patrón **Extract-Transform-Load**:

- **Extract**: Obtiene datos de RabbitMQ (tiempo real) o ElasticSearch/servicios externos (carga forzada)
- **Transform**: Procesa y normaliza los datos según el modelo de negocio definido
- **Load**: Persiste los datos primero en PostgreSQL (staging) y luego en BigQuery (destino final)

### Principios Arquitectónicos

| Principio | Descripción |
|-----------|-------------|
| **Desacoplamiento** | Los componentes se comunican mediante protocolos y behaviours |
| **Resiliencia** | Tolerancia a fallos con estrategias de retry y supervisión OTP |
| **Extensibilidad** | Macros y configuración declarativa para nuevos ETLs |
| **Persistencia Intermedia** | PostgreSQL como buffer para garantizar durabilidad |
| **Procesamiento por Lotes** | Optimización mediante batch processing |

---

## Diagrama de Arquitectura

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                    FUENTES DE DATOS                                 │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                     │
│   ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│   │   RabbitMQ   │    │ ElasticSearch│    │ NodeService  │    │WorkflowService│     │
│   │   (Eventos)  │    │   (Búsqueda) │    │ (Expedientes)│    │   (Tareas)   │      │
│   └──────┬───────┘    └──────┬───────┘    └──────┬───────┘    └──────┬───────┘      │
│          │                   │                   │                   │              │
└──────────┼───────────────────┼───────────────────┼───────────────────┼──────────────┘
           │                   └───────────────────┴───────────────────┘
           │                                       │
           ▼                                       ▼
┌─────────────────────────┐           ┌─────────────────────────┐
│    RabbitConsumer       │           │      ForcedLoad         │
│    (Tiempo Real)        │           │   (Carga Histórica)     │
│                         │           │                         │
│  ┌───────────────────┐  │           │  ┌───────────────────┐  │
│  │ Consume mensajes  │  │           │  │ Consulta ES/APIs  │  │
│  │ de colas AMQP     │  │           │  │ por rangos fecha  │  │
│  └─────────┬─────────┘  │           │  └─────────┬─────────┘  │
│            │            │           │            │            │
└────────────┼────────────┘           └────────────┼────────────┘
             │                                     │
             └─────────────────┬───────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              CAPA DE PROCESAMIENTO                                  │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                     │
│   ┌─────────────────────────────────────────────────────────────────────────────┐   │
│   │                          Worker (PWorker Protocol)                          │   │
│   │                                                                             │   │
│   │    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                    │   │
│   │    │   :record   │    │   :task     │    │  :other...  │                    │   │
│   │    └──────┬──────┘    └──────┬──────┘    └──────┬──────┘                    │   │
│   │           │                  │                  │                           │   │
│   └───────────┼──────────────────┼──────────────────┼───────────────────────────┘   │
│               │                  │                  │                               │
│               ▼                  ▼                  ▼                               │
│   ┌─────────────────────────────────────────────────────────────────────────────┐   │
│   │                         Entidades (DataModel)                               │   │
│   │                                                                             │   │
│   │    ┌────────────────────────────────────────────────────────────────────┐   │   │
│   │    │                        Record Entity                               │   │   │
│   │    │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │   │   │
│   │    │  │ RecordBase  │  │   Buyer     │  │  Vehicle    │  ...            │   │   │
│   │    │  │ (atributos) │  │(subentidad) │  │(subentidad) │                 │   │   │
│   │    │  └─────────────┘  └─────────────┘  └─────────────┘                 │   │   │
│   │    └────────────────────────────────────────────────────────────────────┘   │   │
│   │                                                                             │   │
│   │    ┌────────────────────────────────────────────────────────────────────┐   │   │
│   │    │                         Task Entity                                │   │   │
│   │    │  own_attributes + computed_attributes                              │   │   │
│   │    │  (elapsed_time, timestamp, etc.)                                   │   │   │
│   │    └────────────────────────────────────────────────────────────────────┘   │   │
│   └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                     │
│   Pipeline de Procesamiento:                                                        │
│   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐         │
│   │ filter_batch │ → │ group_by_id  │ → │  build_data  │ → │ post_process │         │
│   └──────────────┘   └──────────────┘   └──────────────┘   └──────────────┘         │
│                                                                                     │
└───────────────────────────────────────────┬─────────────────────────────────────────┘
                                            │
                                            ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              CAPA DE PERSISTENCIA                                   │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                     │
│   ┌─────────────────────────────────────────────────────────────────────────────┐   │
│   │                            PostgreSQL (Staging)                             │   │
│   │                                                                             │   │
│   │   Tabla: records_staging                                                    │   │
│   │   ┌─────────────────────────────────────────────────────────────────────┐   │   │
│   │   │ id | id_nodo | tipo | informacion (JSONB)  | fecha_creado | estado  │   │   │
│   │   │    │         │      │                      │              │ analisis│   │   │
│   │   └─────────────────────────────────────────────────────────────────────┘   │   │
│   │                                                                             │   │
│   │   Estados: sin_analizar → analizado_en_bq → (eliminado)                     │   │
│   │                       └→ con_problemas                                      │   │
│   └──────────────────────────────────────┬──────────────────────────────────────┘   │
│                                          │                                          │
│                                          ▼                                          │
│   ┌─────────────────────────────────────────────────────────────────────────────┐   │
│   │                         BigqueryUploader (Periódico)                        │   │
│   │                                                                             │   │
│   │   1. Lee registros con estado = "sin_analizar"                              │   │
│   │   2. Transforma informacion (JSONB) → columnas BigQuey                      │   │
│   │   3. Inserta en BigQuery vía ODBC                                           │   │
│   │   4. Marca como "analizado_en_bq" en PostgreSQL                             │   │
│   └──────────────────────────────────────┬──────────────────────────────────────┘   │
│                                          │                                          │
│                                          ▼                                          │
│   ┌─────────────────────────────────────────────────────────────────────────────┐   │
│   │                              BigQuery (Destino)                             │   │
│   │                                                                             │   │
│   │   Tablas estructuradas con esquema definido:                                │   │
│   │   - X (de acuerdo el negocio, solo existe una)                              │   │
│   └─────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              PROCESOS DE MANTENIMIENTO                              │
├─────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                     │
│   ┌────────────────────────┐    ┌────────────────────────┐    ┌─────────────────┐   │
│   │    Cleaning GenServer  │    │    Monitor GenServer   │    │  Notificaciones │   │
│   │                        │    │                        │    │     (Slack)     │   │
│   │  • Elimina duplicados  │    │  • Heartbeat procesos  │    │                 │   │
│   │    en BigQuery         │    │  • Registro GenServers │    │  • Errores      │   │
│   │  • Limpia registros    │    │  • Health checks       │    │  • Estado       │   │
│   │    procesados en       │    │                        │    │  • Alertas      │   │
│   │    Postgres            │    │                        │    │                 │   │
│   └────────────────────────┘    └────────────────────────┘    └─────────────────┘   │
│                                                                                     │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Flujo de Datos

### Flujo en Tiempo Real (RabbitMQ)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   1. EVENTO EN RABBIT                                                       │
│   ┌─────────────────┐                                                       │
│   │ on_created_xxx  │ ──► Exchange ──► Queue                                │
│   └─────────────────┘                    │                                  │
│                                          ▼                                  │
│   2. CONSUMO                                                                │
│   ┌─────────────────────────────────────────────────────────────────┐       │
│   │ RabbitConsumer                                                  │       │
│   │   • Recibe mensaje                                              │       │
│   │   • Decodifica JSON                                             │       │
│   │   • Genera batch_id                                             │       │
│   │   • Invoca Worker.perform(batch, batch_id, business, info)      │       │
│   └─────────────────────────────────────────────────────────────────┘       │
│                                          │                                  │
│                                          ▼                                  │
│   3. PROCESAMIENTO                                                          │
│   ┌─────────────────────────────────────────────────────────────────┐       │
│   │ Entity.Record.insert_by_lote(batch, batch_id, pg_config)        │       │
│   │                                                                 │       │
│   │   batch                                                         │       │
│   │     │                                                           │       │
│   │     ├──► filter_batch()      # Filtrar por algún tipo, si aplica│       │
│   │     │                                                           │       │
│   │     ├──► group_by_unique_id()  # Agrupar por ID único           │       │
│   │     │                                                           │       │
│   │     ├──► Para cada grupo:                                       │       │
│   │     │      └──► build_data()                                    │       │
│   │     │            • extract_with_format() # Mapear payload→attrs │       │
│   │     │            • apply_post_processing() # Lógica especial    │       │
│   │     │                                                           │       │
│   │     ├──► prepare_record()      # Crear estructura para Postgres │       │
│   │     │                                                           │       │
│   │     └──► execute_insert_with_retry() # Insertar con reintento   │       │
│   └─────────────────────────────────────────────────────────────────┘       │
│                                          │                                  │
│                                          ▼                                  │
│   4. PERSISTENCIA                                                           │
│   ┌─────────────────────────────────────────────────────────────────┐       │
│   │ PostgreSQL                                                      │       │
│   │   INSERT INTO tabla (id_nodo, tipo, informacion, fecha_creado,  │       │
│   │                      estado_analisis)                           │       │
│   │   VALUES (uuid, 'expediente', {json}, now(), 'sin_analizar')    │       │
│   └─────────────────────────────────────────────────────────────────┘       │
│                                          │                                  │
│                                          ▼                                  │
│   5. ACK                                                                    │
│   ┌─────────────────────────────────────────────────────────────────┐       │
│   │ AMQP.Basic.ack(channel, delivery_tag)                           │       │
│   │   • Confirma procesamiento exitoso                              │       │
│   │   • Si error: AMQP.Basic.reject(requeue: false)                 │       │
│   └─────────────────────────────────────────────────────────────────┘       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Flujo de Carga Forzada (ForcedLoad)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   1. INICIO                                                                 │
│   ┌─────────────────────────────────────────────────────────────────┐       │
│   │ ForcedLoad GenServer                                            │       │
│   │   • Recibe: (business, [start_date, end_date], config)          │       │
│   │   • Divide rango en intervalos de N días (time_step)            │       │
│   └─────────────────────────────────────────────────────────────────┘       │
│                                          │                                  │
│                                          ▼                                  │
│   2. CONSULTA ELASTICSEARCH (Opcional)                                      │
│   ┌─────────────────────────────────────────────────────────────────┐       │
│   │ Para cada intervalo [fecha_inicio, fecha_fin]:                  │       │
│   │                                                                 │       │
│   │   Query ES:                                                     │       │
│   │   {                                                             │       │
│   │     "query": {                                                  │       │
│   │       "range": {                                                │       │
│   │         "updated_at": { "gte": "start", "lte": "end" }          │       │
│   │       }                                                         │       │
│   │     }                                                           │       │
│   │   }                                                             │       │
│   │                                                                 │       │
│   │   Resultado: Lista de IDs de documentos                         │       │
│   └─────────────────────────────────────────────────────────────────┘       │
│                                          │                                  │
│                                          ▼                                  │
│   3. FILTRAR POR BIGQUERY (Opcional)                                        │
│   ┌─────────────────────────────────────────────────────────────────┐       │
│   │   • Consultar BigQuery para obtener timestamps existentes       │       │
│   │   • Filtrar IDs donde ES.updated_at > BQ.timestamp              │       │
│   │   • Solo procesar registros realmente actualizados              │       │
│   └─────────────────────────────────────────────────────────────────┘       │
│                                          │                                  │
│                                          ▼                                  │
│   4. OBTENER DATOS COMPLETOS                                                │
│   ┌─────────────────────────────────────────────────────────────────┐       │
│   │ Para cada batch de IDs (batch_size):                            │       │
│   │                                                                 │       │
│   │   NodeService/WorkflowService:                                  │       │
│   │     • GET /api/document/{id}?ticket={auth_ticket}               │       │
│   │     • Obtiene payload completo del documento                    │       │
│   │                                                                 │       │
│   │   Publicar a RabbitMQ:                                          │       │
│   │     • record_queue ← payload de expedientes                     │       │
│   │     • task_queue ← payload de tareas asociadas                  │       │
│   └─────────────────────────────────────────────────────────────────┘       │
│                                          │                                  │
│                                          ▼                                  │
│   5. PROCESAMIENTO NORMAL                                                   │
│   ┌─────────────────────────────────────────────────────────────────┐       │
│   │   Los mensajes en RabbitMQ son consumidos por RabbitConsumer    │       │
│   │   y procesados con el flujo normal de tiempo real               │       │
│   └─────────────────────────────────────────────────────────────────┘       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Flujo de Subida a BigQuery

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   BIGQUERY UPLOADER (Periódico)                                             │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────┐       │
│   │ Cada N minutos (configurable):                                  │       │
│   │                                                                 │       │
│   │   1. Leer de PostgreSQL:                                        │       │
│   │      SELECT * FROM tabla WHERE estado_analisis = 'sin_analizar' │       │
│   │                                                                 │       │
│   │   2. Agrupar por id_nodo (quedarse con el más reciente)         │       │
│   │      • Los registros antiguos del mismo id_nodo se marcan       │       │
│   │        como 'analizado_en_bq' ya que el más actualizado         │       │
│   │        los representa                                           │       │
│   │                                                                 │       │
│   │   3. Transformar informacion (JSONB) → INSERT SQL para BigQuery │       │
│   │      • Normalizar caracteres especiales                         │       │
│   │      • Escapar strings                                          │       │
│   │      • Convertir tipos                                          │       │
│   │                                                                 │       │
│   │   4. Ejecutar INSERT en BigQuery via ODBC                       │       │
│   │      • En batches de batch_size registros                       │       │
│   │      • Reintento con divide-y-conquista en caso de error        │       │
│   │      • Si un registro falla definitivamente:                    │       │
│   │        - Se marca como 'con_problemas'                          │       │
│   │        - Se continúa con el siguiente registro más actualizado  │       │
│   │                                                                 │       │
│   │   5. Actualizar PostgreSQL:                                     │       │
│   │      UPDATE tabla SET estado_analisis = 'analizado_en_bq'       │       │
│   │      WHERE id IN (ids_procesados)                               │       │
│   └─────────────────────────────────────────────────────────────────┘       │
│                                                                             │
│   Manejo de registros duplicados por id_nodo:                               │
│   ┌─────────────────────────────────────────────────────────────────┐       │
│   │                                                                 │       │
│   │   id_nodo: ABC-123                                              │       │
│   │   ┌─────────────────────────────────────────────────────────┐   │       │
│   │   │ Registro 1: fecha_creado = 10:00 ──► analizado_en_bq    │   │       │
│   │   │ Registro 2: fecha_creado = 10:05 ──► analizado_en_bq    │   │       │
│   │   │ Registro 3: fecha_creado = 10:10 ──► SE SUBE A BIGQUERY │   │       │
│   │   └─────────────────────────────────────────────────────────┘   │       │
│   │                                                                 │       │
│   │   El registro más reciente representa el estado actual          │       │
│   │   Los anteriores se marcan como procesados sin subirlos         │       │
│   └─────────────────────────────────────────────────────────────────┘       │
│                                                                             │
│   Manejo de errores:                                                        │
│   ┌─────────────────────────────────────────────────────────────────┐       │
│   │                                                                 │       │
│   │   Si el INSERT a BigQuery falla para un registro:               │       │
│   │                                                                 │       │
│   │   1. Se marca el registro como 'con_problemas'                  │       │
│   │   2. Se notifica el error (Slack)                               │       │
│   │   3. Se continúa procesando los demás registros                 │       │
│   │   4. Los registros con problemas quedan para revisión manual    │       │
│   │                                                                 │       │
│   └─────────────────────────────────────────────────────────────────┘       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Componentes del Sistema

### GenServers Principales

| GenServer | Responsabilidad | Ciclo de Vida |
|-----------|-----------------|---------------|
| **RabbitConsumer** | Consume mensajes de RabbitMQ en tiempo real | Permanente |
| **ForcedLoad** | Ejecuta cargas históricas | Temporal - termina al completar |
| **BigqueryUploader** | Sube datos de PostgreSQL a BigQuery | Permanente, periódico |
| **Cleaning** | Limpia duplicados y registros procesados | Permanente, periódico |
| **Monitor** | Monitorea health de otros GenServers | Permanente |

### Árbol de Supervisión

```
                    ┌─────────────────────┐
                    │   Application.ex    │
                    │    (Supervisor)     │
                    └─────────┬───────────┘
                              │
   ┌──────────────────────────┼──────────────────────────┐
   │                          │                          │
   ▼                          ▼                          ▼
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│  Pool.Postgres  │   │  Pool.BigQuery  │   │Task.Supervisor  │
│  (Supervisor)   │   │  (NimblePool)   │   │                 │
└─────────────────┘   └─────────────────┘   └─────────────────┘
        │
        ├─────────────────────┬─────────────────────┐
        ▼                     ▼                     ▼
┌───────────────┐    ┌───────────────┐    ┌────────────────┐
│    Monitor    │    │   Cleaning    │    │BigqueryUploader│
│               │    │  Supervisor   │    │                │
└───────────────┘    └───────┬───────┘    └────────────────┘
                             │
                    ┌────────┴────────┐
                    ▼                 ▼
             ┌───────────┐     ┌───────────┐
             │ Registry  │     │ Cleaning  │
             │ (Tables)  │     │ GenServer │
             └───────────┘     └───────────┘
                 │
                 ├─────────────────────┐
                 ▼                     ▼
       ┌───────────────┐    ┌───────────────┐
       │RabbitConsumer │    │RabbitConsumer │
       │   (:record)   │    │   (:task)     │
       └───────────────┘    └───────────────┘
```

**Nota:** Los pools `Pool.Postgres` y `Pool.BigQuery` deben iniciarse **antes** que los
GenServers que los usan (BigqueryUploader, RabbitConsumer, etc.).

---

## Patrones de Diseño

### 1. Protocol Pattern

Los protocolos de Elixir permiten polimorfismo para diferentes tipos de negocio:

```elixir
# Definición del protocolo
defprotocol Genserver.Protocols.PWorker do
  def perform(batch, batch_id, business, info)
end

# Implementación para List
defimpl Genserver.Protocols.PWorker, for: List do
  def perform(batch, batch_id, :record, info) do
    # Procesar records
  end
  
  def perform(batch, batch_id, :task, info) do
    # Procesar tasks
  end
end
```

### 2. Behaviour Pattern

Los behaviours definen contratos para módulos:

```elixir
# Behaviour para tablas limpiables
@callback business_key() :: atom()
@callback bigquery_config() :: map()
@callback postgres_config() :: map()

# Behaviour para configuración de ForcedLoad
@callback app_name() :: atom()
@callback documentary_type() :: String.t()
# ...
```

### 3. Macro Pattern

Los macros generan código boilerplate:

```elixir
# En el módulo de la entidad
use DataModel.RecordPg.Base

entity_config(...)
subentities [...]
generate_helper_functions()

# El macro genera:
# - def attr_list/0
# - def filter_batch/1
# - def group_by_unique_id/1
# - def build_data/3
# - ...
```

### 4. Pipeline Pattern

El procesamiento sigue un patrón de pipeline funcional:

```elixir
batch
|> filter_batch()
|> group_by_unique_id()
|> Enum.map(&prepare_record/1)
|> execute_insert_with_retry()
```

### 5. Building Blocks Pattern

Las funciones generadas son "bloques de construcción" que pueden componerse:

```elixir
# Implementación personalizada usando los building blocks
def insert_by_lote(batch, batch_id, pg_config) do
  batch
  |> filter_batch()           # Override si es necesario
  |> custom_preprocessing()   # Lógica personalizada
  |> group_by_unique_id()     # Building block estándar
  |> Enum.map(&build_data/1)  # Building block estándar
  |> post_processing()        # Lógica personalizada
  |> execute_insert()         # Building block estándar
end
```

---

## Capas de la Aplicación

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           CAPA DE APLICACIÓN                            │
│                                                                         │
│   Application.ex                                                        │
│   • Configuración del supervisor tree                                   │
│   • Inicialización de conexiones                                        │
│   • Registro de GenServers                                              │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           CAPA DE GENSERVERS                            │
│                                                                         │
│   genserver/                                                            │
│   • RabbitConsumer - Consumo de mensajes                                │
│   • ForcedLoad - Carga histórica                                        │
│   • BigqueryUploader - Subida a BQ                                      │
│   • Cleaning - Limpieza de datos                                        │
│   • Monitor - Monitoreo de salud                                        │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          CAPA DE IMPLEMENTACIÓN                         │
│                                                                         │
│   impl/                                                                 │
│   • Worker - Implementación de PWorker                                  │
│   • ForcedLoadConfig - Configuración de carga                           │
│   • DocumentaryTypeOf - Mapeo de tipos                                  │
│   • MyTime - Configuración de horarios                                  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           CAPA DE ENTIDADES                             │
│                                                                         │
│   entity/                                                               │
│   • Record - Entidad principal de expedientes                           │
│   • Task - Entidad de tareas                                            │
│   • Subentidades (Buyer, Vehicle, etc.)                                 │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          CAPA DE DATA MODEL                             │
│                             (etl-core)                                  │
│                                                                         │
│   data_model/                                                           │
│   • Record.Base / RecordPg.Base - Base para records                     │
│   • Task.Base / TaskPg.Base - Base para tasks                           │
│   • Attribute.Provider - Proveedor de atributos                         │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          CAPA DE CONEXIONES                             │
│                             (etl-core)                                  │
│                                                                         │
│   connection/                        database/                          │
│   • Odbc - BigQuery via ODBC         • Postgres - PostgreSQL            │
│   • Http - Peticiones HTTP                                              │
│   • Ticket - Autenticación                                              │
│   • ElasticSearch - Búsquedas                                           │
│   • NodeService - Datos de nodos                                        │
│   • WorkflowService - Tareas                                            │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          CAPA DE UTILIDADES                             │
│                             (etl-core)                                  │
│                                                                         │
│   • Common.Payload - Extracción de datos                                │
│   • Type.Type - Conversiones de tipos                                   │
│   • Statement.Sql - Generación de SQL                                   │
│   • Time.WorkingTime - Cálculo de tiempos                               │
│   • Notification.Notify - Notificaciones Slack                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Gestión de Conexiones

### Estrategia de Conexiones

A partir de la versión 1.2.0, el sistema soporta **dos modos de conexión**:

| Modo | Descripción | Cuándo Usar |
|------|-------------|-------------|
| **Pool Mode** | Usa pools de conexiones gestionados | Producción, alto volumen |
| **Legacy Mode** | Crea conexiones temporales por operación | Desarrollo, compatibilidad |

### Pool de Conexiones (Recomendado - v2.1+)

El sistema implementa pools de conexiones para PostgreSQL y BigQuery que proporcionan:

| Característica | PostgreSQL (Pool.Postgres) | BigQuery (Pool.BigQuery) |
|----------------|----------------------------|--------------------------|
| **Librería base** | Postgrex (DBConnection) | NimblePool + ODBC |
| **Reconexión automática** | Gestionada por DBConnection | Con health checks |
| **Supervisión** | Como parte del árbol OTP | Como parte del árbol OTP |
| **Pool size configurable** | Via opción `:pool_size` | Via opción `:pool_size` |
| **Modo dual (read/write)** | Soportado | N/A |

### Arquitectura del Pool

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            POOL DE CONEXIONES                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                        Pool.Postgres (Supervisor)                   │   │
│   │                                                                     │   │
│   │   Modo Simple:                     Modo Dual:                       │   │
│   │   ┌─────────────────┐              ┌─────────────────┐              │   │
│   │   │  Postgrex Pool  │              │  Write Pool     │              │   │
│   │   │   (name: atom)  │              │  (writes only)  │              │   │
│   │   └─────────────────┘              └─────────────────┘              │   │
│   │                                    ┌─────────────────┐              │   │
│   │                                    │  Read Pool      │              │   │
│   │                                    │  (reads only)   │              │   │
│   │                                    └─────────────────┘              │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                        Pool.BigQuery (NimblePool)                   │   │
│   │                                                                     │   │
│   │   ┌─────────────────────────────────────────────────────────────┐   │   │
│   │   │  Worker 1  │  Worker 2  │  Worker 3  │  ...  │  Worker N    │   │   │
│   │   │   (ODBC)   │   (ODBC)   │   (ODBC)   │       │   (ODBC)     │   │   │
│   │   └─────────────────────────────────────────────────────────────┘   │   │
│   │                                                                     │   │
│   │   • Health checks en checkout                                       │   │
│   │   • Auto-descarte de conexiones muertas                             │   │
│   │   • Reconexión automática al devolver al pool                       │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Componentes y Modos de Conexión

| Componente | Pool Mode | Legacy Mode |
|------------|-----------|-------------|
| **RabbitConsumer** | Usa `pg_pool_name` | Conexión temporal por inserción |
| **BigqueryUploader** | Usa `pg_pool_name` + `bq_pool_name` | Conexión por ciclo |
| **Cleaning** | Usa pools configurados | Conexión temporal por operación |
| **ForcedLoad** | Via config con pools | Via config legacy |

### Modo Pool: Uso del Pool de Conexiones

```elixir
# Con pool de conexiones (modo pool - recomendado)
# Las conexiones se toman del pool y se devuelven automáticamente.

def execute_insert_pooled(records, pg_pool_name, batch_id) do
  # No se abre ni cierra conexión - el pool lo gestiona
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

### Modo Legacy: Ciclo de Vida de Conexiones

```elixir
# Conexión bajo demanda para PostgreSQL (modo legacy)
# Se crea una conexión temporal y se cierra inmediatamente después.

def execute_insert(records, pg_config, batch_id) do
  try do
    case Connection.Postgres.connect(pg_config) do
      {:ok, pg_conn} ->
        try do
          result = Connection.Postgres.insert_many(pg_conn, table_name(), records)
          result
        after
          Connection.Postgres.disconnect(pg_conn)
        end
      {:error, reason} ->
        Logger.error("Error conectando a PostgreSQL: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Error inesperado: #{inspect(error)}")
      {:error, error}
  end
end

# BigqueryUploader: conexiones creadas por ciclo de ejecución (modo legacy)
def handle_info(:update, state) do
  {:ok, pg_conn} = Postgres.connect(pg_config)
  bq_conn = Odbc.connect(data_source)
  
  try do
    Enum.each(info, fn table_config ->
      Bigquery.run(business, bq_conn, pg_conn, ...)
    end)
  after
    Postgres.disconnect(pg_conn)
    Odbc.disconnect(bq_conn)
  end
end
```

### Modo Dual de PostgreSQL

> **SOPORTE DUAL CONNECTION**: El sistema permite configurar **dos conexiones 
> PostgreSQL simultáneas** - una para escritura (primaria) y otra para lectura (réplica).

```
┌─────────────────────────────────────────────────────────────────┐
│                     PostgreSQL Dual Mode                        │
│                                                                 │
│   ┌─────────────────┐              ┌─────────────────┐          │
│   │  Write Primary  │◄── INSERT ───│   Application   │          │
│   │                 │    UPDATE    │                 │          │
│   └────────┬────────┘    DELETE    └────────┬────────┘          │
│            │                                │                   │
│            │ Replication                    │ SELECT            │
│            ▼                                ▼                   │
│   ┌─────────────────┐              ┌─────────────────┐          │
│   │  Read Replica   │◄─────────────│   Application   │          │
│   └─────────────────┘              └─────────────────┘          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Nota**: Si no se configura la réplica, el sistema usa la conexión principal para ambas operaciones.

---

## Modelo de Concurrencia

### Procesamiento Paralelo

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│   RabbitMQ                                                              │
│   ┌───────┐  ┌───────┐  ┌───────┐                                       │
│   │Queue 1│  │Queue 2│  │Queue 3│                                       │
│   └───┬───┘  └───┬───┘  └───┬───┘                                       │
│       │          │          │                                           │
│       ▼          ▼          ▼                                           │
│   ┌───────┐  ┌───────┐  ┌───────┐                                       │
│   │Consumer│ │Consumer│ │Consumer│  ◄── GenServers independientes       │
│   │   1   │  │   2   │  │   3   │                                       │
│   └───┬───┘  └───┬───┘  └───┬───┘                                       │
│       │          │          │                                           │
│       └──────────┼──────────┘                                           │
│                  │                                                      │
│                  ▼                                                      │
│       ┌─────────────────────┐                                           │
│       │    PostgreSQL       │  ◄── Conexiones concurrentes              │
│       │  (Connection Pool)  │      con control de transacciones         │
│       └─────────────────────┘                                           │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Prefetch y ACK

```elixir
# Configuración de prefetch
AMQP.Basic.qos(channel, prefetch_count: 1)

# ACK después de procesamiento exitoso
AMQP.Basic.ack(channel, delivery_tag)

# REJECT sin requeue en caso de error irrecuperable
AMQP.Basic.reject(channel, delivery_tag, requeue: false)
```

---

## Estrategias de Resiliencia

### 1. Retry con Divide-and-Conquer

```
┌─────────────────────────────────────────────────────────────────┐
│   execute_insert_with_retry([r1, r2, r3, r4, r5, r6, r7, r8])   │
│                                │                                │
│                           [ERROR]                               │
│                                │                                │
│                    ┌───────────┴───────────┐                    │
│                    ▼                       ▼                    │
│           [r1, r2, r3, r4]         [r5, r6, r7, r8]             │
│                 │                         │                     │
│               [OK]                     [ERROR]                  │
│                                           │                     │
│                                ┌──────────┴──────────┐          │
│                                ▼                     ▼          │
│                         [r5, r6]              [r7, r8]          │
│                              │                     │            │
│                            [OK]                 [ERROR]         │
│                                                    │            │
│                                         ┌──────────┴──────────┐ │
│                                         ▼                     ▼ │
│                                       [r7]                 [r8] │
│                                         │                     │ │
│                                       [OK]              [ERROR] ◄─ Log + Notify
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 2. Dead Letter Queues

```
┌───────────────────────────────────────────────────────────────────────┐
│                                                                       │
│   ┌─────────────┐                     ┌─────────────────────────┐     │
│   │    Queue    │ ── mensaje ──►      │      Consumer           │     │
│   │   records   │                     │                         │     │
│   └─────────────┘                     └───────────┬─────────────┘     │
│                                                   │                   │
│                                            ┌──────┴──────┐            │
│                                            │   Error?    │            │
│                                            └──────┬──────┘            │
│                                                   │                   │
│                                     ┌─────────────┴─────────────┐     │
│                                     │                           │     │
│                                     ▼                           ▼     │
│                              ┌─────────────┐             ┌─────────┐  │
│                              │    ACK      │             │  REJECT │  │
│                              │  (success)  │             │(no req) │  │
│                              └─────────────┘             └────┬────┘  │
│                                                               │       │
│                                                               ▼       │
│                                                    ┌─────────────────┐│
│                                                    │  Dead Letter    ││
│                                                    │  Queue (DLQ)    ││
│                                                    │  records_error  ││
│                                                    └─────────────────┘│
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

### 3. Supervisión OTP

```elixir
# Estrategia de reinicio
opts = [strategy: :one_for_one, name: MiEtl.Supervisor]

# Tipos de reinicio por GenServer
%{
  id: RabbitConsumer,
  restart: :permanent  # Siempre reiniciar
}

%{
  id: ForcedLoad,
  restart: :temporary  # No reiniciar (proceso de una sola vez)
}
```

### 4. Notificaciones de Error

```elixir
def handle_processing_error(batch_id, id, error, context) do
  # 1. Log local
  Logger.error(msg)
  
  # 2. Notificación a Slack
  Notify.notify_slack(webhook_url, headers, env, msg)
end
```

---

## Extensibilidad

### Agregar Nueva Entidad

1. **Definir atributos** (`entity/nuevo/base.ex`):
```elixir
defmodule Entity.Nuevo.Base do
  use DataModel.Attribute.Provider
  
  @campo1 %Struct.InfoAttr{id: :campo1, id_payload: "campo1", type: :string}
  
  attr_list [@campo1, ...]
end
```

2. **Crear entidad principal** (`entity/nuevo/nuevo.ex`):
```elixir
defmodule Entity.Nuevo do
  use DataModel.RecordPg.Base
  
  entity_config(...)
  subentities [Entity.Nuevo.Base, ...]
  generate_helper_functions()
end
```

3. **Implementar Worker**:
```elixir
def perform(batch, batch_id, :nuevo, info) do
  Entity.Nuevo.insert_by_lote(batch, batch_id, info.pg_config)
end
```

### Agregar Nuevo Tipo de Negocio

1. **Configurar colas en `runtime.exs`**
2. **Implementar `documentary_type_of/1`**
3. **Agregar caso en Worker**
4. **Configurar ForcedLoadConfig si es necesario**

### Personalizar Procesamiento

```elixir
# Override de cualquier función generada
defoverridable filter_batch: 1

def filter_batch(batch) do
  batch
  |> super()  # Llamar implementación base
  |> custom_filter()  # Agregar lógica personalizada
end
```

---

## Consideraciones de Rendimiento

### Periodicidades Típicas

| GenServer | Periodicidad | Razón |
|-----------|--------------|-------|
| BigqueryUploader | 1-2 minutos | Frecuencia vs carga |
| Cleaning | 90 minutos | Operación costosa |
| ForcedLoad | Una vez | Proceso finito |

---

## Diagrama de Estados de Datos

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│                         CICLO DE VIDA DEL DATO                              │
│                                                                             │
│   ┌────────────┐                                                            │
│   │  RabbitMQ  │                                                            │
│   │  (Evento)  │                                                            │
│   └─────┬──────┘                                                            │
│         │                                                                   │
│         ▼                                                                   │
│   ┌────────────┐      ┌────────────┐      ┌────────────┐                    │
│   │ PostgreSQL │ ───► │ PostgreSQL │ ───► │ PostgreSQL │                    │
│   │sin_analizar│      │analizado_bq│      │ (eliminado)│                    │
│   └─────┬──────┘      └─────┬──────┘      └──────▲─────┘                    │
│         │                   │                    │                          │
│         │                   │ Cleaning           │                          │
│         │                   └────────────────────┘                          │
│         │                                                                   │
│         │ BigqueryUploader                                                  │
│         ▼                                                                   │
│   ┌────────────┐                                                            │
│   │  BigQuery  │                                                            │
│   │  (Tabla)   │                                                            │
│   └─────┬──────┘                                                            │
│         │                                                                   │
│         │ Cleaning                                                          │
│         ▼                                                                   │
│   ┌────────────┐                                                            │
│   │  BigQuery  │                                                            │
│   │ (Limpio)   │                                                            │
│   └────────────┘                                                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Resumen

La arquitectura del sistema ETL está diseñada para:

1. **Procesar eventos en tiempo real** desde RabbitMQ
2. **Cargar datos históricos** bajo demanda con ForcedLoad
3. **Persistir de forma durable** usando PostgreSQL como staging
4. **Consolidar en BigQuery** para análisis
5. **Mantener limpio** los datos con procesos periódicos
6. **Ser extensible** mediante protocolos, behaviours y macros
7. **Ser resiliente** con estrategias de retry y supervisión OTP

