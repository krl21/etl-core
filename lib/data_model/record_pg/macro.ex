
defmodule DataModel.RecordPg.Macro do
    @moduledoc """
    Macros for configuring and using DataModel.RecordPg.Base.

    Similar to `DataModel.Record.Macro` but uses `Connection.Postgres`
    instead of BigQuery for storage.

    ## Available Macros

    ### Configuration Macros
    - `entity_config/1` - Configure the entity (app, table_name, batch_size_key, unique_id)
    - `own_attributes/1` - Define the list of own attributes
    - `subentities/1` - Define the list of sub-entities
    - `special_post_processing/1` - Define entities for post-processing

    ### Generation Macros
    - `generate_helper_functions/0` - Generate helper functions (building blocks)

    ## Usage

    ```elixir
    defmodule MyApp.RecordPg do
        use DataModel.RecordPg.Base

        entity_config(
            app: :my_app,
            table_name: "my_records",
            batch_size_key: :batch_size_process,
            unique_id: @unique_id
        )

        own_attributes [...]
        subentities [...]
        special_post_processing [...]

        generate_helper_functions()

        def insert_by_lote(batch, batch_id, pg_conn) do
            # Your custom pipeline using the helpers
        end
    end
    ```
    """

    # ============================================
    # CONFIGURATION MACROS
    # ============================================

    @doc """
    Macro to configure the RecordPg entity.

    ### Parameters
        - opts (Keyword) - Configuration options:
            - app (Atom) - Application name for config lookup
            - table_name (String) - PostgreSQL table name (static value)
            - table_name_path (List) - Path to resolve table name from config at runtime (e.g. [:postgres, :tables]). Use this instead of table_name for releases where env vars are set at runtime.
            - batch_size_key (Atom) - Key to obtain batch size from config
            - unique_id (InfoAttr) - Attribute that uniquely identifies the record
            - timestamp (InfoAttr, optional) - Timestamp attribute
            - value_type (String) - Value for the 'tipo' field in records (static value)
            - value_type_path (List) - Path to resolve value_type from config at runtime
            - slack_webhook_url (String, optional) - Slack webhook URL for error notifications
            - slack_webhook_url_path (List, optional) - Path to resolve Slack webhook URL from config at runtime
            - slack_env (String, optional) - Environment name for Slack notifications. Defaults to "unknown"
            - slack_env_var (String, optional) - Environment variable name to read at runtime for slack_env
    """
    defmacro entity_config(opts) do
        quote do
            opts = unquote(opts)

            unless Keyword.has_key?(opts, :app) do
                raise "entity_config requires :app option"
            end

            unless Keyword.has_key?(opts, :table_name) or Keyword.has_key?(opts, :table_name_path) do
                raise "entity_config requires :table_name or :table_name_path option"
            end

            unless Keyword.has_key?(opts, :batch_size_key) do
                raise "entity_config requires :batch_size_key option"
            end

            unless Keyword.has_key?(opts, :unique_id) do
                raise "entity_config requires :unique_id option"
            end

            @entity_config opts

            @doc """
            Returns the attribute that uniquely identifies the record.
            """
            def unique_id_attr(), do: @entity_config[:unique_id] || %Struct.InfoAttr{id: :unique_id}

            @doc """
            Returns the attribute used for timestamp.
            """
            def timestamp_attr() do
                @entity_config[:timestamp] || %Struct.InfoAttr{id: :timestamp}
            end

            @doc """
            Returns the application name.
            """
            def application_name(), do: @entity_config[:app]

            @doc """
            Returns the PostgreSQL table name.
            Resolves at runtime if table_name_path is configured.
            """
            def table_name() do
                case @entity_config[:table_name_path] do
                    nil ->
                        @entity_config[:table_name]
                    path when is_list(path) ->
                        get_in(Application.get_env(@entity_config[:app], hd(path)) || %{}, tl(path))
                        |> case do
                            list when is_list(list) -> List.first(list)
                            value -> value
                        end
                end
            end

            @doc """
            Returns the value for the 'tipo' field in records.
            Resolves at runtime if value_type_path is configured.
            """
            def value_type() do
                case @entity_config[:value_type_path] do
                    nil ->
                        @entity_config[:value_type] || table_name()
                    path when is_list(path) ->
                        get_in(Application.get_env(@entity_config[:app], hd(path)) || %{}, tl(path)) || table_name()
                end
            end

            @doc """
            Returns the Slack webhook URL for error notifications.
            Resolves at runtime if slack_webhook_url_path is configured.
            """
            def slack_webhook_url() do
                case @entity_config[:slack_webhook_url_path] do
                    nil ->
                        @entity_config[:slack_webhook_url]
                    path when is_list(path) ->
                        get_in(Application.get_env(@entity_config[:app], hd(path)) || %{}, tl(path))
                end
            end

            @doc """
            Returns the environment name for Slack notifications.
            Reads from environment variable at runtime if slack_env_var is configured.
            """
            def slack_env() do
                case @entity_config[:slack_env_var] do
                    nil ->
                        @entity_config[:slack_env] || "unknown"
                    var_name when is_binary(var_name) ->
                        System.get_env(var_name) || @entity_config[:slack_env] || "unknown"
                end
            end

            @doc """
            Returns the batch size for chunking insert operations.
            """
            def batch_size() do
                Application.get_env(
                    @entity_config[:app],
                    @entity_config[:batch_size_key]
                ) || 100
            end
        end
    end

    @doc """
    Macro to define the list of own attributes.
    Automatically generates getter functions for each attribute.
    """
    defmacro own_attributes(attributes) when is_list(attributes) do
        getter_functions = generate_getter_functions(attributes)
        quote do
            @own_attributes unquote(attributes)
            unquote_splicing(getter_functions)
        end
    end

    @doc """
    Macro to define the list of sub-entities.
    """
    defmacro subentities(entities) do
        quote do
            @subentities unquote(entities)
        end
    end

    @doc """
    Macro to define sub-entities that need special post-processing.
    """
    defmacro special_post_processing(entities) do
        quote do
            @special_post_processing unquote(entities)
        end
    end

    # ============================================
    # GENERATION MACROS
    # ============================================

    @doc """
    Macro that generates helper functions for PostgreSQL storage.

    ## Generated Functions

    ### Required
        - `attr_list/0` - Returns complete list of attributes

    ### Helper Functions
        - `filter_batch/1` - Filter batch before processing
        - `group_by_unique_id/1` - Group payloads by unique_id
        - `build_data/3` - Build record data from payloads
        - `apply_post_processing/3` - Apply special post-processing
        - `prepare_record/4` - Prepare one or more records for insert
        - `execute_insert/3` - Execute insert in PostgreSQL
        - `execute_insert_with_retry/3` - Execute with retry strategy
        - `handle_processing_error/4` - Handle errors
    """
    defmacro generate_helper_functions do
        quote do

            # ============================================
            # REQUIRED FUNCTIONS
            # ============================================

            @doc """
            Returns the complete list of attributes (own + subentities).
            """
            def attr_list() do
                own_attrs = @own_attributes || []
                subentities = @subentities || []

                own_attrs ++
                Enum.reduce(subentities, [], fn entity, acc ->
                    acc ++ entity.attr_list()
                end)
            end

            # ============================================
            # HELPER FUNCTIONS (Building Blocks)
            # ============================================

            @doc """
            Filters the batch before processing.
            Override to implement custom filtering logic.
            """
            def filter_batch(batch), do: batch
            defoverridable filter_batch: 1

            @doc """
            Groups payloads by unique_id attribute.

            ### Returns
                - `{map_grouped_by_key, list_of_keys}`
            """
            def group_by_unique_id(batch) do
                Common.Payload.reduce_by(batch, [unique_id_attr()])
            end
            defoverridable group_by_unique_id: 1

            @doc """
            Builds the record data from payloads.
            Override to implement custom data construction logic.

            ### Parameters
                - payloads (List) - List of maps for the same unique_id
                - stored_data (Keyword) - Previously stored data
                - additional_info (any) - Additional context

            ### Returns
                - Keyword list with record data for a single row, or List of keyword lists (one keyword list per DB row) when the entity expands one message into several inserts
            """
            def build_data(payloads, stored_data, _additional_info) do
                payload = List.last(payloads)

                payload
                |> Common.Payload.extract_with_format(attr_list(), false)
                |> apply_post_processing(stored_data, payload)
            end
            defoverridable build_data: 3

            @doc """
            Applies special post-processing to extracted values.
            Override to implement custom post-processing logic.
            """
            def apply_post_processing(new_values, stored_values, payload) do
                entities = @special_post_processing || []

                entities
                |> Enum.reduce(new_values, fn entity, acc ->
                    cond do
                        function_exported?(entity, :special_post_processing, 3) ->
                            entity.special_post_processing(acc, stored_values, payload)
                        function_exported?(entity, :special_post_processing, 2) ->
                            entity.special_post_processing(acc, payload)
                        true ->
                            acc
                    end
                end)
            end
            defoverridable apply_post_processing: 3

            @doc """
            Prepares one or more PostgreSQL rows from `build_data/3`.

            ### Parameters
                - unique_id (String) - Unique record identifier
                - payloads (List) - List of maps with associated payloads
                - stored_data (Keyword) - Previously stored data
                - additional_info (any) - Additional context

            ### Returns
                - `{:ok, :single, record_map}` when `build_data/3` returns a keyword list (one row), or `{:ok, :multi, [record_map, ...]}` when it returns a list of keyword lists (several rows)
                - `{:error, reason}` - If there's an error
            """
            def prepare_record(unique_id, payloads, stored_data, additional_info) do
                try do
                    data = build_data(payloads, stored_data, additional_info)

                    case records_from_build_data(unique_id, data) do
                        {:single, record} ->
                            {:ok, :single, record}

                        {:multi, records} ->
                            {:ok, :multi, records}
                    end
                rescue
                    error -> {:error, error}
                end
            end
            defoverridable prepare_record: 4

            #
            # Converts the build_data result into a record map or a list of record maps.
            #
            # ### Parameters:
            #     - unique_id (String) - Unique record identifier
            #     - data (Keyword list) - Record data
            #
            # ### Returns:
            #     - `{:single, record_map}` when `data` is a keyword list (one row), or `{:multi, [record_map, ...]}` when it is a list of keyword lists (several rows)
            #
            defp records_from_build_data(unique_id, data) do
                data
                |> List.first()
                |> is_list()
                |> case do
                    true ->
                        {:multi, Enum.map(data, &record_from_row_keywords(unique_id, &1))}
                    false ->
                        {:single, record_from_row_keywords(unique_id, data)}
                end
            end

            #
            # Converts a list of keyword lists into a record map.
            #
            # ### Parameters:
            #     - id (String) - Unique record identifier
            #     - row_kw (Keyword list) - Record data

            # ### Returns:
            #     - Map
            #
            defp record_from_row_keywords(id, row_kw) when is_list(row_kw) do
                %{
                    id_nodo: id_nodo,
                    tipo: value_type(),
                    informacion: Enum.into(info_kw, %{})
                }
            end

            @doc """
            Executes the insert operation in PostgreSQL using insert_many.

            ## Parameters:
                - `records` (list) - List of record maps to insert
                - `pg_config` (map) - PostgreSQL connection configuration
                - `batch_id` (string) - Batch identifier for logging

            ## Returns:
                - `{:ok, count}` - Number of records inserted
                - `{:error, reason}` - If there's an error
            """
            def execute_insert([], _pg_config, _batch_id), do: {:ok, 0}

            def execute_insert(records, pg_config, batch_id) do
                require Logger

                try do
                    case Connection.Postgres.connect(pg_config) do
                        {:ok, pg_conn} ->
                            try do
                                records
                                |> Enum.chunk_every(batch_size())
                                |> Enum.reduce({:ok, 0}, fn chunk, acc ->
                                    case acc do
                                        {:ok, total} ->
                                            Connection.Postgres.insert_many(pg_conn, table_name(), chunk)
                                            |> case do
                                                {:ok, count} ->
                                                    {:ok, total + count}

                                                {:error, reason} = error ->
                                                    handle_processing_error(batch_id, Enum.map(chunk, & &1.id_nodo), reason, %{
                                                        function: :execute_insert,
                                                        module: __MODULE__
                                                    })
                                                    error
                                            end

                                        error ->
                                            error
                                    end
                                end)
                            after
                                Connection.Postgres.disconnect(pg_conn)
                            end

                        {:error, reason} = error ->
                            msg = "Error al conectar a PostgreSQL en execute_insert: #{inspect(reason)}"
                            Logger.error("#{__MODULE__}. #{msg}")
                            handle_processing_error(batch_id, Enum.map(records, & &1.id_nodo), reason, %{
                                function: :execute_insert,
                                module: __MODULE__,
                                step: :connection
                            })
                            error
                    end
                rescue
                    error ->
                        msg = "Excepción en execute_insert: #{inspect(error)}"
                        Logger.error("#{__MODULE__}. #{msg}")
                        handle_processing_error(batch_id, Enum.map(records, & &1.id_nodo), error, %{
                            function: :execute_insert,
                            module: __MODULE__,
                            step: :rescue
                        })
                        {:error, error}
                end
            end
            defoverridable execute_insert: 3

            @doc """
            Executes the insert operation using a PostgreSQL connection pool.

            ## Parameters:
                - `records` (list) - List of record maps to insert
                - `pg_pool_name` (atom) - PostgreSQL pool name
                - `batch_id` (string) - Batch identifier for logging

            ## Returns:
                - `{:ok, count}` - Number of records inserted
                - `{:error, reason}` - If there's an error
            """
            def execute_insert_pooled([], _pg_pool_name, _batch_id), do: {:ok, 0}

            def execute_insert_pooled(records, pg_pool_name, batch_id) do
                require Logger

                try do
                    records
                    |> Enum.chunk_every(batch_size())
                    |> Enum.reduce({:ok, 0}, fn chunk, acc ->
                        case acc do
                            {:ok, total} ->
                                Connection.PostgresPool.insert_many(pg_pool_name, table_name(), chunk)
                                |> case do
                                    {:ok, count} ->
                                        {:ok, total + count}

                                    {:error, reason} = error ->
                                        handle_processing_error(batch_id, Enum.map(chunk, & &1.id_nodo), reason, %{
                                            function: :execute_insert_pooled,
                                            module: __MODULE__
                                        })
                                        error
                                end

                            error ->
                                error
                        end
                    end)
                rescue
                    error ->
                        msg = "Excepción en execute_insert_pooled: #{inspect(error)}"
                        Logger.error("#{__MODULE__}. #{msg}")
                        handle_processing_error(batch_id, Enum.map(records, & &1.id_nodo), error, %{
                            function: :execute_insert_pooled,
                            module: __MODULE__
                        })
                        {:error, error}
                end
            end
            defoverridable execute_insert_pooled: 3

            @doc """
            Executes insertion with divide-and-conquer retry strategy (legacy mode).

            ## Parameters:
                - `records` (list) - List of record maps to insert
                - `pg_config` (map) - PostgreSQL connection configuration
                - `batch_id` (string) - Batch identifier for logging

            ## Returns:
                - `{:ok, count}` - Total records inserted
                - `{:error, reason}` - If all retries fail
            """
            def execute_insert_with_retry([], _pg_config, _batch_id), do: {:ok, 0}

            def execute_insert_with_retry(records, pg_config, batch_id) do
                require Logger

                try do
                    case Connection.Postgres.connect(pg_config) do
                        {:ok, pg_conn} ->
                            try do
                                case Connection.Postgres.insert_many(pg_conn, table_name(), records) do
                                    {:ok, count} ->
                                        {:ok, count}

                                    {:error, reason} when length(records) == 1 ->
                                        # Single record failed, log and skip
                                        [record] = records
                                        handle_processing_error(batch_id, record.id_nodo, reason, %{
                                            function: :execute_insert_with_retry,
                                            module: __MODULE__
                                        })
                                        {:ok, 0}

                                    {:error, _reason} ->
                                        # Close connection before splitting
                                        Connection.Postgres.disconnect(pg_conn)

                                        # Split and retry
                                        Logger.info("#{__MODULE__}. Inserción de lote fallida, dividiendo datos a la mitad y reintentando...")

                                        mid = div(length(records), 2)
                                        {first_half, second_half} = Enum.split(records, mid)

                                        result1 = execute_insert_with_retry(first_half, pg_config, batch_id)
                                        result2 = execute_insert_with_retry(second_half, pg_config, batch_id)

                                        case {result1, result2} do
                                            {{:ok, c1}, {:ok, c2}} -> {:ok, c1 + c2}
                                            {{:error, _} = err, _} -> err
                                            {_, {:error, _} = err} -> err
                                        end
                                end
                            after
                                # Only disconnect if we haven't already (in the split case)
                                if Process.alive?(pg_conn) do
                                    Connection.Postgres.disconnect(pg_conn)
                                end
                            end

                        {:error, reason} = error ->
                            msg = "Error al conectar a PostgreSQL en execute_insert_with_retry: #{inspect(reason)}"
                            Logger.error("#{__MODULE__}. #{msg}")
                            handle_processing_error(batch_id, Enum.map(records, & &1.id_nodo), reason, %{
                                function: :execute_insert_with_retry,
                                module: __MODULE__,
                                step: :connection
                            })
                            error
                    end
                rescue
                    error ->
                        msg = "Excepción en execute_insert_with_retry: #{inspect(error)}"
                        Logger.error("#{__MODULE__}. #{msg}")
                        handle_processing_error(batch_id, Enum.map(records, & &1.id_nodo), error, %{
                            function: :execute_insert_with_retry,
                            module: __MODULE__,
                            step: :rescue
                        })
                        {:error, error}
                end
            end
            defoverridable execute_insert_with_retry: 3

            @doc """
            Executes insertion with divide-and-conquer retry strategy using pool.

            ## Parameters:
                - `records` (list) - List of record maps to insert
                - `pg_pool_name` (atom) - PostgreSQL pool name
                - `batch_id` (string) - Batch identifier for logging

            ## Returns:
                - `{:ok, count}` - Total records inserted
                - `{:error, reason}` - If all retries fail
            """
            def execute_insert_with_retry_pooled([], _pg_pool_name, _batch_id), do: {:ok, 0}

            def execute_insert_with_retry_pooled(records, pg_pool_name, batch_id) do
                require Logger

                try do
                    case Connection.PostgresPool.insert_many(pg_pool_name, table_name(), records) do
                        {:ok, count} ->
                            {:ok, count}

                        {:error, _reason} when length(records) == 1 ->
                            # Registro individual falló, registrar y saltar
                            [record] = records
                            handle_processing_error(batch_id, record.id_nodo, "Insert failed", %{
                                function: :execute_insert_with_retry_pooled,
                                module: __MODULE__
                            })
                            {:ok, 0}

                        {:error, _reason} ->
                            # Dividir y reintentar
                            Logger.info("#{__MODULE__}. Inserción de lote fallida, dividiendo datos a la mitad y reintentando...")

                            mid = div(length(records), 2)
                            {first_half, second_half} = Enum.split(records, mid)

                            result1 = execute_insert_with_retry_pooled(first_half, pg_pool_name, batch_id)
                            result2 = execute_insert_with_retry_pooled(second_half, pg_pool_name, batch_id)

                            case {result1, result2} do
                                {{:ok, c1}, {:ok, c2}} -> {:ok, c1 + c2}
                                {{:error, _} = err, _} -> err
                                {_, {:error, _} = err} -> err
                            end
                    end
                rescue
                    error ->
                        msg = "Excepción en execute_insert_with_retry_pooled: #{inspect(error)}"
                        Logger.error("#{__MODULE__}. #{msg}")
                        handle_processing_error(batch_id, Enum.map(records, & &1.id_nodo), error, %{
                            function: :execute_insert_with_retry_pooled,
                            module: __MODULE__
                        })
                        {:error, error}
                end
            end
            defoverridable execute_insert_with_retry_pooled: 3

            @doc """
            Handles errors during record processing.

            ## Parameters
                - `batch_id` (string) - Batch identifier
                - `unique_id` (string | list) - Record identifier
                - `error` (any) - The error that occurred
                - `context` (map) - Context with additional information

            ## Returns:
                - `:ok`
            """
            def handle_processing_error(batch_id, unique_id, error, context) do
                require Logger

                msg = """
                [#{__MODULE__} Error]
                Module: #{inspect(context[:module] || __MODULE__)}
                Function: #{inspect(context[:function])}
                Record Id: #{inspect(unique_id)}
                Batch Id: #{inspect(batch_id)}
                Error: #{inspect(error)}
                """

                Logger.error(msg)

                # Send to Slack if webhook is configured
                case slack_webhook_url() do
                    nil -> :ok
                    url when is_binary(url) and url != "" ->
                        Notification.Notify.notify_slack(
                            url,
                            [{"Content-Type", "application/json"}],
                            slack_env(),
                            msg
                        )
                    _ -> :ok
                end
            end
            defoverridable handle_processing_error: 4

        end
    end

    # ============================================
    # PRIVATE HELPER FUNCTIONS
    # ============================================

    @doc false
    defp generate_getter_functions(attributes) do
        case attributes do
            {:__block__, _, list} when is_list(list) ->
                process_attribute_list(list)

            list when is_list(list) ->
                process_attribute_list(list)

            _ ->
                []
        end
    end

    @doc false
    defp process_attribute_list(list) do
        list
        |> Enum.filter(fn
            {:@, _, [{name, _, _}]} when is_atom(name) -> true
            _ -> false
        end)
        |> Enum.map(fn
            {:@, _, [{name, _, _}]} ->
                function_name = name
                attr_ast = {:@, [], [{name, [], nil}]}

                quote do
                    @doc """
                    Returns the `#{unquote(function_name)}` attribute.
                    """
                    def unquote(function_name)(), do: unquote(attr_ast)
                end

            _ ->
                nil
        end)
        |> Enum.filter(&(!is_nil(&1)))
    end



end
