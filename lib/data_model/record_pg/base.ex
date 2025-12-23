
defmodule DataModel.RecordPg.Base do
    @moduledoc """
    Base module for entities that process and store data in PostgreSQL.

    Similar to `DataModel.Record.Base` but uses `EtlCore.Database.Postgres`
    instead of BigQuery for storage.

    ## Usage

        defmodule MyApp.RecordPg do
            use DataModel.RecordPg.Base

            # Configure the entity
            entity_config(
                app: :my_app,
                table_name: "my_table",
                batch_size_key: :batch_size_process,
                unique_id: @unique_id,
                timestamp: @timestamp
            )

            # Define attributes
            own_attributes [@unique_id, @timestamp, ...]
            subentities [MyApp.Record.Buyer, ...]
            special_post_processing [MyApp.Record.Buyer, ...]

            # Generate helper functions
            generate_helper_functions()

            # Implement your own insert_by_lote
            def insert_by_lote(batch, batch_id, pg_conn) do
                batch
                |> filter_batch()
                |> group_by_unique_id()
                |> process_and_insert(batch_id, pg_conn)
            end

            defp process_and_insert({grouped, keys}, batch_id, pg_conn) do
                records =
                    keys
                    |> Enum.map(fn key ->
                        prepare_record(key, Map.get(grouped, key), [], [])
                    end)
                    |> Enum.filter(&match?({:ok, _}, &1))
                    |> Enum.map(fn {:ok, record} -> record end)

                execute_insert(records, pg_conn, batch_id)
            end
        end

    ## Available Helper Functions

    After calling `generate_helper_functions/0`, you have access to:

    | Function | Purpose |
    |----------|---------|
    | `attr_list/0` | Complete list of attributes |
    | `filter_batch/1` | Filter batch before processing |
    | `group_by_unique_id/1` | Group payloads by unique_id |
    | `build_data/3` | Build record from payloads |
    | `apply_post_processing/3` | Apply post-processing |
    | `prepare_record/4` | Prepare single record for insert |
    | `execute_insert/3` | Execute insert in PostgreSQL |
    | `handle_processing_error/4` | Handle errors |

    All functions are `defoverridable` - override as needed.
    """

    defmacro __using__(_opts) do
        quote do
            @behaviour DataModel.Behaviour

            alias Struct.InfoAttr
            alias Common.Payload
            alias Database.Postgres
            alias Notification.Notify
            alias Timex

            import DataModel.RecordPg.Macro

            @before_compile unquote(__MODULE__)
        end
    end

    defmacro __before_compile__(_env) do
        quote do
            unless Module.has_attribute?(__MODULE__, :entity_config) do
                raise "DataModel.RecordPg.Base requires entity_config/1 to be called"
            end
        end
    end

end
