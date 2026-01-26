# Historial de Versiones - ETL-Core

Este documento describe las versiones de `etl-core`, sus características principales y los cambios introducidos en cada versión.

---

## Tabla de Contenidos

1. [Versión 2.2 (Actual)](#versión-22-actual)
2. [Versión 2.1](#versión-21)
3. [Versión 1.2.0](#versión-120)
4. [Versiones Anteriores](#versiones-anteriores)

---

## Versión 2.2 (Actual)

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

**v2.1 → v2.2**: Ninguno
- Cambios son aditivos
- Compatibilidad total con código existente

**v1.2.0 → v2.1**: Ninguno (modo legacy compatible)
- El código existente sigue funcionando
- Migración a pools es opcional

---

## Roadmap Futuro

### Versión 2.3 (Planeada)

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
- `docs/MODULOS_REFERENCIA.md` - Referencia de módulos
- `docs/GUIA_CREAR_ETL.md` - Guía para crear nuevos ETLs

