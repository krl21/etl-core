# Cobertura de tests pendiente

## Grupo 3 (resto)
- `Common.Table.get_stored_values_in_bigquery/4` (Mox: Odbc)
- `Cleaning.Cleaner` (`build_cleanup_query` puro + `run`/`run_all` con Mox de Odbc/PostgresPool y `CleanableTableRegistry` real)

## Grupo 4 — consumidores de Connection.Http
- `Connection.Ticket`, `Connection.NodeService`, `Connection.WorkflowService`, `Connection.ElasticSearch`
- `Notification.Notify`
- `ForcedLoad.Handler.Ids.fetch_all/4` (camino puro con `skip_elasticsearch: true`)

## Grupo 5 — AMQP
- `Genserver.ConsumerSupervisor` (partes puras, sin mock)
- `Genserver.RabbitConsumer` / `RabbitConsumerByBatch` (Mox AMQP + fixture de protocolo PWorker)
- `Genserver.PostgresConsumer` (fixture PPostgresDb)
- `Genserver.ForcedLoad` (`process_name` puro + fixture PForcedLoad)

## Grupo 6 — Genserver de orquestación
- `Genserver.Monitor`
- `Genserver.BigqueryUploader` (`determine_mode`/`build_state` vía `init/1`)
- `Genserver.Cleaning` (`setup_bigquery_connection`/`setup_postgres_connection` vía `init/1`)

## Verificación final
- Confirmar explícitamente que `EtlCore.Deps.*` devuelve los módulos reales cuando `:etl_core, :deps` no está configurado (propiedad de "cero riesgo en producción" del plan).

## Fuera de alcance (ya documentado, no silencioso)
- `Connection.Gcs`/`Gcs.Helpers` más allá de lo puro
- `Tools.SystemStats`
- `ForcedLoad.Handler.DirectLoad.load/1` completo
- Los protocolos `PAutomaticClean`/`PBigqueryPostProcess` (sin implementaciones reales en etl-core)
