
defmodule DataModel.Record.Base do
    @moduledoc """
    Base module for main entities (Records) that process and store data.

    ## Usage

        defmodule MyApp.Record do
            use DataModel.Record.Base

            # Configure the entity
            entity_config(
                app: :my_app,
                table_key: :record_table,
                batch_size_key: :batch_size_process,
                unique_id: @unique_id,
                timestamp: @timestamp
            )

            # Define attributes
            own_attributes [@unique_id, @timestamp, ...]
            subentities [MyApp.Record.Buyer, ...]
            special_post_processing [MyApp.Record.Buyer, ...]

            # Required: table_id
            def table_id(), do: Application.get_env(:my_app, :bigquery)[:table][:record]

            # Generate helper functions
            generate_helper_functions()

            # Implement your own insert_by_lote
            def insert_by_lote(batch, batch_id) do
                batch
                |> filter_batch()
                |> group_by_unique_id()
                |> process_and_insert(batch_id)
            end

            defp process_and_insert({grouped, keys}, batch_id) do
                keys
                |> Enum.map(fn key ->
                    prepare_insert_query(key, Map.get(grouped, key), [], [])
                end)
                |> Enum.filter(&match?({:ok, _}, &1))
                |> Enum.map(fn {:ok, data} -> data end)
                |> Enum.chunk_every(batch_size())
                |> Enum.map(&build_insert_tuples/1)
                |> execute_insert(batch_id)
            end
        end

    ## Available Helper Functions

    After calling `generate_helper_functions/0`, you have access to:

    | Function | Purpose |
    |----------|---------|
    | `attr_list/0` | Complete list of attributes |
    | `filter_batch/1` | Filter batch before processing |
    | `group_by_unique_id/1` | Group payloads by unique_id |
    | `fetch_stored_data/2` | Fetch existing data from storage |
    | `build_data/3` | Build record from payloads |
    | `apply_post_processing/3` | Apply post-processing |
    | `prepare_insert_query/4` | Prepare single insert query |
    | `build_insert_tuples/1` | Combine queries |
    | `execute_insert/2` | Execute in database |
    | `handle_processing_error/4` | Handle errors |

    All functions are `defoverridable` - override as needed.
    """

    @doc """
    Callback invoked when `use DataModel.Record.Base` is called.
    """
    defmacro __using__(_opts) do
        quote do
            @behaviour DataModel.Behaviour

            alias Struct.InfoAttr
            alias Common.Payload
            alias Connection.Odbc
            alias Statement.Sql
            alias Timex

            import DataModel.Record.Macro

            @before_compile unquote(__MODULE__)
        end
    end

    @doc """
    Callback invoked before the module is compiled.
    Validates that required configurations have been defined.
    """
    defmacro __before_compile__(_env) do
        quote do
            unless Module.has_attribute?(__MODULE__, :entity_config) do
                raise "DataModel.Record.Base requires entity_config/1 to be called"
            end
        end
    end


end
