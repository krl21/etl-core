
defmodule DataModel.Record.Macro do
    @moduledoc """
    Macros for configuring and using DataModel.Record.Base.

    ## Philosophy

    This module provides **building blocks**, not a rigid pipeline.
    Each implementing module decides how to compose its own `insert_by_lote/2` or `/3`.

    ## Available Macros

    ### Configuration Macros
    - `entity_config/1` - Configure the entity (app, table_key, batch_size_key, unique_id)
    - `own_attributes/1` - Define the list of own attributes
    - `subentities/1` - Define the list of sub-entities
    - `special_post_processing/1` - Define entities for post-processing

    ### Generation Macros
    - `generate_helper_functions/0` - Generate helper functions (building blocks)

    ## Usage

    ```elixir
    defmodule MyApp.Record do
        use DataModel.Record.Base

        entity_config(...)
        own_attributes [...]
        subentities [...]
        special_post_processing [...]

        def table_id(), do: ...

        generate_helper_functions()

        # Implement your own insert_by_lote using the helpers
        def insert_by_lote(batch, batch_id) do
            # Your custom pipeline using:
            # - filter_batch/1
            # - group_by_unique_id/1
            # - fetch_stored_data/2
            # - build_data/3
            # - apply_post_processing/3
            # - build_insert_tuples/1
            # - execute_insert/2
            # - handle_processing_error/4
        end
    end
    ```
    """

    # ============================================
    # CONFIGURATION MACROS
    # ============================================

    @doc """
    Macro to configure the Record entity.

    ### Parameters:
    - `opts`: Keyword list with:
        - `app`: Atom. Application name (for config)
        - `table_key`: Atom. Key to obtain the table name from [:bigquery, :table, table_key] (static)
        - `table_key_path`: List. Path to resolve table from config at runtime (e.g. [:bigquery, :table, :record])
        - `batch_size_key`: Atom. Key to obtain the batch size
        - `unique_id`: InfoAttr. Attribute that uniquely identifies the record
        - `timestamp`: InfoAttr. Timestamp attribute (optional)
        - `slack_webhook_url_path`: List. Path to resolve Slack webhook URL from config at runtime (optional)
        - `slack_env_var`: String. Environment variable name to read at runtime for slack_env (optional)
    """
    defmacro entity_config(opts) do
        quote do
            opts = unquote(opts)

            unless Keyword.has_key?(opts, :app) do
                raise "entity_config requires :app option"
            end

            unless Keyword.has_key?(opts, :table_key) or Keyword.has_key?(opts, :table_key_path) do
                raise "entity_config requires :table_key or :table_key_path option"
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

            ### Returns:
                - `Struct.InfoAttr`
            """
            @spec unique_id_attr() :: Struct.InfoAttr.t()
            def unique_id_attr(), do: @entity_config[:unique_id] || %Struct.InfoAttr{id: :unique_id}

            @doc """
            Returns the attribute used for timestamp.

            ### Returns:
                - `Struct.InfoAttr`
            """
            @spec timestamp_attr() :: Struct.InfoAttr.t()
            def timestamp_attr() do
                @entity_config[:timestamp] || %Struct.InfoAttr{id: :timestamp}
            end

            @doc """
            Returns the application name configured in `entity_config/1`.

            ### Returns:
                - Atom. The application name used for configuration lookup.

            ### Example:
                MyApp.Record.application_name()
                # => :my_app
            """
            @spec application_name() :: atom()
            def application_name(), do: @entity_config[:app]

            @doc """
            Returns the BigQuery table identifier.

            ### Returns:
                - String. The full table name.
            """
            def table_id() do
                case @entity_config[:table_key_path] do
                    nil ->
                        # Legacy: use table_key to access [:bigquery, :table, table_key]
                        Application.get_env(@entity_config[:app], :bigquery)[:table][@entity_config[:table_key]]
                    path when is_list(path) ->
                        get_in(Application.get_env(@entity_config[:app], hd(path)) || %{}, tl(path))
                end
            end

            @doc """
            Returns the batch size for chunking insert operations.

            Gets the value from `Application.get_env/2` using the application name
            and batch size key defined in `entity_config/1`.

            ### Returns:
                - Integer. The configured batch size.

            ### Example:
                MyApp.Record.batch_size()
                # => 100
            """
            @spec batch_size() :: integer()
            def batch_size() do
                Application.get_env(
                    @entity_config[:app],
                    @entity_config[:batch_size_key]
                ) || 100
            end

            @doc """
            Returns the Slack webhook URL for error notifications.
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
            """
            def slack_env() do
                case @entity_config[:slack_env_var] do
                    nil ->
                        @entity_config[:slack_env] || "unknown"
                    var_name when is_binary(var_name) ->
                        System.get_env(var_name) || @entity_config[:slack_env] || "unknown"
                end
            end
        end
    end

    @doc """
    Macro to define the list of own attributes of the Record.
    Automatically generates getter functions for each attribute.

    ### Example:
        own_attributes [
            @unique_id,
            @timestamp,
            @is_deleted
        ]
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

    ### Example:
        subentities [
            DataModel.Record.Buyer,
            DataModel.Record.Vehicle
        ]
    """
    defmacro subentities(entities) do
        quote do
            @subentities unquote(entities)
        end
    end

    @doc """
    Macro to define sub-entities that need special post-processing.

    ### Example:
        special_post_processing [
            DataModel.Record.Buyer,
            DataModel.Record.Client
        ]
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
    Macro that generates helper functions (building blocks).

    These are tools you can use to build your own `insert_by_lote`.
    Each function is overridable.

    ## Generated Functions

    ### Required (by Behaviour)
    - `attr_list/0` - Returns complete list of attributes

    ### Helper Functions (Building Blocks)
    - `filter_batch/1` - Filter batch before processing
    - `group_by_unique_id/1` - Group payloads by unique_id
    - `fetch_stored_data/2` - Fetch existing data from storage
    - `build_data/3` - Build record data from payloads
    - `apply_post_processing/3` - Apply special post-processing
    - `prepare_insert_query/4` - Prepare a single insert query
    - `build_insert_tuples/1` - Build insertion tuples from list
    - `execute_insert/2` - Execute insert in database
    - `handle_processing_error/4` - Handle errors

    ## Note
    `insert_by_lote/2` or `/3` is NOT generated. You must implement it yourself
    using these building blocks according to your business logic.
    """
    defmacro generate_helper_functions do
        quote do

            # ============================================
            # REQUIRED FUNCTIONS
            # ============================================

            @doc """
            Returns the complete list of attributes (own + subentities)
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

            ### Parameters:
                - `batch`: List of maps (payloads)

            ### Returns:
                - Filtered list of maps
            """
            def filter_batch(batch), do: batch
            defoverridable filter_batch: 1

            @doc """
            Groups payloads by unique_id attribute.

            ### Parameters:
                - `batch`: List of maps (payloads)

            ### Returns:
                - `{map_grouped_by_key, list_of_keys}`
            """
            def group_by_unique_id(batch) do
                Common.Payload.reduce_by(batch, [unique_id_attr()])
            end
            defoverridable group_by_unique_id: 1

            @doc """
            Fetches existing data from storage for the given keys.
            Override to implement storage lookup (e.g., BigQuery).

            ### Parameters:
                - `keys`: List of unique identifiers
                - `additional_info`: Additional context

            ### Returns:
                - `{:ok, %{key => stored_data}}` or `{:error, reason}`
            """
            def fetch_stored_data(_keys, _additional_info), do: {:ok, %{}}
            defoverridable fetch_stored_data: 2

            @doc """
            Builds the record data from payloads.
            Override to implement custom data construction logic.

            ### Parameters:
                - `payloads`: List of maps for the same unique_id
                - `stored_data`: Previously stored data (keyword list or empty)
                - `additional_info`: Additional context

            ### Returns:
                - Keyword list with record data
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

            ### Parameters:
                - `new_values`: Keyword list with newly extracted values
                - `stored_values`: Keyword list with previously stored values
                - `payload`: Original payload map

            ### Returns:
                - Keyword list with processed values
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
            Prepares and builds the insert query for a single record.
            Override to implement custom query preparation logic.

            ### Parameters:
                - `unique_id`: String. Unique record identifier
                - `payloads`: List of maps with associated payloads
                - `stored_data`: Keyword list with stored data (or empty)
                - `additional_info`: Additional context

            ### Returns:
                - `{:ok, {unique_id, query}}` if successful
                - `{:error, reason}` if there's an error
            """
            def prepare_insert_query(unique_id, payloads, stored_data, additional_info) do
                timestamp_attr = timestamp_attr()

                record =
                    build_data(payloads, stored_data, additional_info)
                    |> Keyword.put(
                        timestamp_attr.id,
                        Timex.now() |> Timex.to_unix()
                    )

                {:ok, {unique_id, Statement.Sql.insert(table_id(), record)}}
            end
            defoverridable prepare_insert_query: 4

            @doc """
            Builds insertion tuples by combining multiple queries.
            Override to implement custom tuple building logic.

            ### Parameters:
                - `records`: List of tuples `{unique_id, query}`

            ### Returns:
                - `{list_of_keys, merged_query}` or `[]` if empty
            """
            def build_insert_tuples([]), do: []

            def build_insert_tuples(records) do
                {key, query} = hd(records)

                {keys, queries} =
                    records
                    |> tl()
                    |> Enum.reduce(
                        {[key], [query]},
                        fn {k, q}, {keys_acc, queries_acc} ->
                            {keys_acc ++ [k], queries_acc ++ [q]}
                        end
                    )

                {keys, Statement.Sql.merge_inserts(queries)}
            end
            defoverridable build_insert_tuples: 1

            @doc """
            Executes the insert operation in the database.

            ### Parameters:
                - `data`: List of tuples `{keys, query}` to insert

            ### Returns:
                - List of tuples `{:ok, ids}` | `{:error, {ids, error}}`
            """
            def execute_insert(data) do
                Enum.map(data, fn {ids, query} ->
                    try do
                        pid =
                            Application.get_env(application_name(), :bigquery)[:configuration]
                            |> Connection.Odbc.connect()

                        Connection.Odbc.insert(pid, query)
                        Process.exit(pid, :kill)
                        {:ok, ids}
                    rescue
                        error ->
                            {:error, {ids, error}}
                    end
                end)
            end
            defoverridable execute_insert: 1

            @doc """
            Executes insertion with divide-and-conquer retry strategy.
            If an error occurs, splits the data in half and retries each part.
            Continues until individual failing records are isolated.

            ### Parameters:
                - `data`: List of tuples `{unique_id, query}` to insert
                - `batch_id`: Batch identifier for error logging

            ### Returns:
                - List of results (`:ok` | `:error`)
            """
            def execute_insert_with_retry([], _batch_id), do: []

            def execute_insert_with_retry(data, batch_id) do
                insert_tuples =
                    data
                    |> Enum.chunk_every(batch_size())
                    |> Enum.map(&build_insert_tuples/1)
                    |> Enum.reject(&(&1 == []))

                results = execute_insert(insert_tuples)

                has_errors? = Enum.any?(results, fn
                    {:error, _} -> true
                    _ -> false
                end)

                case {has_errors?, length(data)} do
                    {false, _} ->
                        Enum.map(results, fn {:ok, _ids} -> :ok end)

                    {true, 1} ->
                        Enum.map(results, fn
                            {:ok, _ids} -> :ok
                            {:error, {ids, error}} ->
                                handle_processing_error(batch_id, ids, error, %{
                                    function: :execute_insert_with_retry,
                                    module: __MODULE__
                                })
                                :error
                        end)

                    {true, _} ->
                        require Logger
                        Logger.info("Insert batch failed, splitting data in half and retrying...")

                        mid = div(length(data), 2)
                        {first_half, second_half} = Enum.split(data, mid)

                        # Retry each half recursively
                        first_results = execute_insert_with_retry(first_half, batch_id)
                        second_results = execute_insert_with_retry(second_half, batch_id)

                        first_results ++ second_results
                end
            end
            defoverridable execute_insert_with_retry: 2

            @doc """
            Handles errors during record processing.
            Logs the error and sends a Slack notification if webhook is configured.

            ### Parameters:
                - `batch_id`: Batch identifier
                - `unique_id`: Record identifier (String or list)
                - `error`: The error that occurred
                - `context`: Map with `:function` and `:module`
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

    #
    # Generates getter functions for each attribute in the list.
    #
    # ### Parameters:
    #     - `attributes`: AST representing the list of attributes.
    #       Can be a `{:__block__, _, list}` tuple or a plain list.
    #
    # ### Returns:
    #     - List of AST nodes representing the generated getter functions.
    #
    # ### Example:
    #     Given `[@name, @rut]`, generates:
    #     - `def name(), do: @name`
    #     - `def rut(), do: @rut`
    #
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

    #
    # Processes a list of module attributes and generates getter functions.
    #
    # ### Parameters:
    #     - `list`: List of AST nodes representing module attributes.
    #
    # ### Returns:
    #     - List of AST nodes (quoted expressions) for the getter functions.
    #
    # ### Generated Function Format:
    #     Each generated function has:
    #     - `@doc` with description and return type
    #     - Public `def` that returns the module attribute value
    #
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

                    ### Returns:
                        - `Struct.InfoAttr`
                    """
                    def unquote(function_name)(), do: unquote(attr_ast)
                end

            _ ->
                nil
        end)
        |> Enum.filter(&(!is_nil(&1)))
    end


end
