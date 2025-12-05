
defmodule Entity.RecordBase.Macro do
    @moduledoc """
    Macros for configuring and using Entity.RecordBase.
    """

    @doc """
    Macro to configure the Record entity.

    ### Parameters:
    - `opts`: Keyword list with:
        - `app`: Atom. Application name (for config)
        - `table_key`: Atom. Key to obtain the table name (for reference only, does not automatically generate table_id)
        - `batch_size_key`: Atom. Key to obtain the batch size
        - `unique_id`: InfoAttr. Attribute that uniquely identifies the record
        - `timestamp`: InfoAttr. Timestamp attribute (optional)

    ### Important Note:
    The `table_id/0` function is NOT automatically generated. It must be implemented
    manually in each module, as it is required by `Entity.Behaviour`.
    """
    defmacro entity_config(opts) do
        quote bind_quoted: [opts: Macro.escape(opts, unquote: true)] do

            # Validate minimum configuration
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

            # Important: table_id() is NOT automatically generated, must be implemented manually and defined explicitly in each module

            @doc """
            Returns the attribute that uniquely identifies the record.

            ### Returns:
                - `Struct.InfoAttr`. The attribute defined as `unique_id` in `entity_config/1`
            """
            def unique_id_attr() do
                @entity_config[:unique_id]
            end

            @doc """
            Returns the attribute used for timestamp.

            ### Returns:
                - `Struct.InfoAttr`. The attribute defined as `timestamp` in `entity_config/1`,
                or a default attribute with `id: :timestamp` if not specified
            """
            def timestamp_attr() do
                @entity_config[:timestamp] || %Struct.InfoAttr{id: :timestamp}
            end

            @doc """
            Returns the application name configured in `entity_config/1`.

            ### Returns:
                - Atom. The application name used to obtain configuration
            """
            defp application_name() do
                @entity_config[:app]
            end

            @doc """
            Returns the batch size configured for this entity.

            Gets the value from `Application.get_env/2` using the application name
            and batch size key defined in `entity_config/1`.

            ### Returns:
                - Integer or nil. The configured batch size
            """
            defp batch_size() do
                Application.get_env(
                @entity_config[:app],
                @entity_config[:batch_size_key]
                )
            end
        end
    end

    @doc """
    Macro to define the list of own attributes of the Record.

    ### Parameters:
        - `attributes`: List of module attributes (e.g., `[@unique_id, @timestamp]`)

    ### Example:
        own_attributes [
            @unique_id,
            @timestamp,
            @is_deleted
        ]

    This will automatically generate the functions:
        - `unique_id/0` - Returns `@unique_id`
        - `timestamp/0` - Returns `@timestamp`
        - `is_deleted/0` - Returns `@is_deleted`
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

    ### Parameters:
        - `entities`: List of modules that implement `Entity.AttributeProvider`

    ### Example:
        subentities [
            Entity.Record.Buyer,
            Entity.Record.Vehicle,
            Entity.Record.Service
        ]
    """
    defmacro subentities(entities) do
        quote do
        @subentities unquote(entities)
        end
    end

    @doc """
    Macro to define sub-entities that need special post-processing.

    ### Parameters:
        - `entities`: List of modules that implement `special_post_processing`

    ### Example:
        special_post_processing [
            Entity.Record.Buyer,
            Entity.Record.Client
        ]
    """
    defmacro special_post_processing(entities) do
        quote do
        @special_post_processing unquote(entities)
        end
    end

    @doc """
    Macro that generates all common functions for the Record.

    This macro must be called after defining `own_attributes`, `subentities`, `entity_config`, etc.
    Generates the following functions:

    ### Public functions generated:
        - `attr_list/0` - Returns the complete list of attributes (own + sub-entities)
        - `insert_by_lote/3` - Inserts records from a batch

    ### Private functions generated (can be overridden):
        - `filter_batch/1` - Filters the batch before processing
        - `build_data/1` - Builds data from payloads
        - `reprocess_data/2` - Applies special post-processing
        - `prepare_and_build_insert_query/4` - Prepares and builds the insert query
        - `build_insert_tuples/1` - Builds insertion tuples
        - `insert/3` - Inserts into the database
        - `handle_error/4` - Handles errors during processing
    """
    defmacro generate_record_functions do
        quote do

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

            @doc """
            Insert the records from a batch. It iterates over them with the same identifier and keeps the updated data.

            ### Parameters:
                - batch: List of map. Payloads.
                - batch_id: String. Batch identifier.
                - additional_info: List. Additional information needed for processing.
            """
            def insert_by_lote([], _batch_id, _additional_info), do: :ok

            def insert_by_lote(batch, batch_id, additional_info)
                when is_list(batch) and is_binary(batch_id) and is_list(additional_info) do

                unique_id_attr = unique_id_attr()

                # Apply custom filter if exists
                filtered_batch = filter_batch(batch)

                {compressed_by_key, keys} =
                    filtered_batch
                    |> Common.Payload.reduce_by([unique_id_attr])

                keys
                    |> Enum.map(fn key ->
                        prepare_and_build_insert_query(
                            batch_id,
                            key,
                            Map.get(compressed_by_key, key),
                            additional_info
                        )
                    end)
                    |> Enum.reduce(
                        [],
                        fn
                            {:ok, info}, acc -> acc ++ [info]
                            {:error, _info}, acc -> acc
                        end
                    )
                    |> Enum.chunk_every(batch_size())
                    |> Enum.map(fn chunk ->
                        build_insert_tuples(chunk)
                    end)
                    |> insert(batch_id, additional_info)
            end

            @doc """
            Filters the batch before processing it. Can be overriden.

            ### Parameters:
                - `batch`: List of maps with the payloads

            ### Returns:
                - List of filtered maps
            """
            defp filter_batch(batch), do: batch

            @doc """
            Builds the record data from payloads. Must be overridden to implement custom data construction logic. By default uses the last payload in the list and extracts values according to attributes defined in `attr_list/0`.

            ### Parameters:
                - `payloads`: List of maps with payloads associated to the same `unique_id`

            ### Returns:
                - Keyword list with extracted and processed values
            """
            defp build_data(payloads) do
                # By default, use the last payload
                payload = List.last(payloads)

                payload
                |> Common.Payload.extract_with_format(attr_list(), false)
                |> reprocess_data(payload)
            end

            @doc """
            Applies special post-processing to extracted values. Must be overridden to implement custom post-processing logic.

            ### Parameters:
                - `values`: Keyword list with values extracted from the payload
                - `payload`: Map with the original payload

            ### Returns:
                - Keyword list with processed values
            """
            defp reprocess_data(values, payload) do
                entities = special_post_processing_entities()

                entities
                |> Enum.reduce(values, fn entity, acc ->
                    if function_exported?(entity, :special_post_processing, 2) do
                        entity.special_post_processing(acc, payload)
                    else
                        acc
                    end
                end)
            end

            @doc """
            Returns the list of entities that require special post-processing.

            ### Returns:
                - List of modules that implement `special_post_processing` or empty list
                    if no entities are defined
            """
            defp special_post_processing_entities() do
                @special_post_processing || []
            end

            @doc """
            Prepares and builds the SQL insert query for a record. Must be overridden to implement custom insert query construction logic.

            ### Parameters:
                - `batch_id`: String. Batch identifier
                - `unique_id`: String. Unique record identifier
                - `payloads`: List of maps with associated payloads
                - `additional_info`: List. Additional information for processing

            ### Returns:
                - `{:ok, {unique_id, query}}` if successful
                - `{:error, nil}` if there's an error (error is logged)
            """
            defp prepare_and_build_insert_query(batch_id, unique_id, payloads, additional_info) do
                try do
                    timestamp_attr = timestamp_attr()

                    record =
                        build_data(payloads)
                        |> Keyword.put(
                            timestamp_attr.id,
                            Timex.now() |> Timex.to_unix()
                        )

                    {
                        :ok,
                        {unique_id, Sql.insert(table_id(), record)}
                    }

                rescue
                    error ->
                        handle_error(batch_id, unique_id, error, inspect(__ENV__.function))
                        {:error, nil}
                end
            end

            @doc """
            Builds insertion tuples by combining multiple queries. Must be overridden to implement custom insertion tuple construction logic.

            ### Parameters:
                - `batches`: List of tuples `{unique_id, query}`

            ### Returns:
                - `[]` if the list is empty
                - Tuple `{keys, merged_query}` where `keys` is a list of identifiers
                    and `merged_query` is the combined query using `Statement.Sql.merge_inserts/1`
            """
            defp build_insert_tuples([]), do: []

            defp build_insert_tuples(batches) do
                {key, query} = hd(batches)

                {keys, queries} =
                    batches
                    |> tl()
                    |> Enum.reduce(
                        {[key], [query]},
                        fn {k, q}, {keys_acc, queries_acc} ->
                            {keys_acc ++ [k], queries_acc ++ [q]}
                        end
                    )

                {keys, Sql.merge_inserts(queries)}
            end

            @doc """
            Inserts data into BigQuery using ODBC connections. Must be overridden to implement custom insertion logic.

            ### Parameters:
                - `data`: List of tuples `{keys, query}` to insert
                - `batch_id`: String. Batch identifier
                - `_additional_info`: List. Additional information (not used in this function)

            ### Returns:
                - List of insertion results (`:ok` or `:error`)
            """
            defp insert(data, batch_id, _additional_info) do
                data
                |> Task.async_stream(
                    fn {ids, query} ->
                        try do
                        pid =
                            Application.get_env(application_name(), :bigquery)[:configuration]
                            |> Odbc.connect()

                        Odbc.insert(pid, query)

                        Process.exit(pid, :kill)
                        :ok
                        rescue
                        error ->
                            handle_error(batch_id, ids, error, inspect(__ENV__.function))
                            :error
                        end
                    end,
                    timeout: :infinity
                )
                |> Enum.to_list()
            end

            @doc """
            Handles errors during record processing. Must be overridden to implement custom error handling logic.

            ### Parameters:
                - `batch_id`: String. Batch identifier
                - `unique_id`: String or list of strings. Record identifier(s)
                - `error`: Exception or term. The error that occurred
                - `function`: String. Name of the function where the error occurred
            """
            defp handle_error(batch_id, unique_id, error, function) do
                require Logger

                msg = """
                Module: #{inspect(__MODULE__)}.
                Function: #{function}.
                Record Id: #{inspect(unique_id)}.
                Batch Id: #{inspect(batch_id)}.
                Error: #{inspect(error)}
                """

                Logger.error(msg)
            end
        end
    end

    @doc """
    Generates getter functions for each attribute in the list.

    ### Parameters:
        - `attributes`: AST representing the list of attributes

    ### Returns:
        - List of AST nodes representing the generated getter functions
    """
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

    @doc """
    Processes a list of module attributes and generates getter functions for each one.

    ### Parameters:
        - `list`: List of AST nodes representing module attributes

    ### Returns:
        - List of AST nodes representing the generated getter functions

    ### Example:
        Given the list `[{:@, _, [{:name, _, _}]}, {:@, _, [{:rut, _, _}]}]`,
        this function will generate the getter functions `name/0` and `rut/0`.
    """
    defp process_attribute_list(list) do
        list
        |> Enum.filter(fn
            {:@, _, [{name, _, _}]} when is_atom(name) ->
                true
            _ ->
                false
        end)
        |> Enum.map(fn
            {:@, _, [{name, _, _}]} ->
                function_name = name
                # Build the module attribute AST correctly
                attr_ast = {:@, [], [{name, [], nil}]}

                quote do
                    @doc """
                    Returns the information of the `#{unquote(function_name)}` attribute

                    ### Return:
                        - Struct.InfoAttr
                    """
                    def unquote(function_name)() do
                        unquote(attr_ast)
                    end
                end

            _ ->
                nil
            end
        )
        |> Enum.filter(&(!is_nil(&1)))
    end


end
