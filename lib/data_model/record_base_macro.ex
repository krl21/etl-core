
defmodule DataModel.RecordBase.Macro do
    @moduledoc """
    Macros for configuring and using DataModel.RecordBase.

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
        use DataModel.RecordBase

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
        - `table_key`: Atom. Key to obtain the table name
        - `batch_size_key`: Atom. Key to obtain the batch size
        - `unique_id`: InfoAttr. Attribute that uniquely identifies the record
        - `timestamp`: InfoAttr. Timestamp attribute (optional)
    """
    defmacro entity_config(opts) do
        quote do
            opts = unquote(opts)

            unless Keyword.has_key?(opts, :app) do
                raise "entity_config requires :app option"
            end

            unless Keyword.has_key?(opts, :table_key) do
                raise "entity_config requires :table_key option"
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
                )
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
    `insert_by_lote/2` or `/3` is NOT generated. You must implement it yourself using these building blocks according to your business logic.
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
            Builds insertion tuples by combining multiple queries. Override to implement custom tuple building logic.

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
            Override to implement custom insertion logic.

            ### Parameters:
                - `data`: List of tuples `{keys, query}` to insert
                - `batch_id`: Batch identifier for error logging

            ### Returns:
                - List of results (`:ok` | `:error`)
            """
            def execute_insert(data, batch_id) do
                data
                |> Task.async_stream(
                    fn {ids, query} ->
                        try do
                            pid =
                                Application.get_env(application_name(), :bigquery)[:configuration]
                                |> Connection.Odbc.connect()

                            Connection.Odbc.insert(pid, query)
                            Process.exit(pid, :kill)
                            :ok
                        rescue
                            error ->
                                handle_processing_error(batch_id, ids, error, %{
                                    function: :execute_insert,
                                    module: __MODULE__
                                })
                                :error
                        end
                    end,
                    timeout: :infinity
                )
                |> Enum.to_list()
            end
            defoverridable execute_insert: 2

            @doc """
            Handles errors during record processing.
            Override to implement custom error handling (e.g., Slack notifications).

            ### Parameters:
                - `batch_id`: Batch identifier
                - `unique_id`: Record identifier (String or list)
                - `error`: The error that occurred
                - `context`: Map with `:function` and `:module`
            """
            def handle_processing_error(batch_id, unique_id, error, context) do
                require Logger

                msg = """
                Module: #{inspect(context[:module] || __MODULE__)}.
                Function: #{inspect(context[:function])}.
                Record Id: #{inspect(unique_id)}.
                Batch Id: #{inspect(batch_id)}.
                Error: #{inspect(error)}
                """

                Logger.error(msg)
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
