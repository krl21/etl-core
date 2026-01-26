
defmodule DataModel.Task.Macro do
    @moduledoc """
    Macros for configuring and using DataModel.Task.Base.

    ## Philosophy

    This module provides **building blocks**, not a rigid pipeline.
    Each implementing module decides how to compose its own `insert_by_lote/2`.

    ## Available Macros

    ### Configuration Macros
    - `task_config/1` - Configure the task entity (app, table_key, group_by_keys, etc.)
    - `own_attributes/1` - Define the list of own attributes
    - `computed_attributes/1` - Define the list of computed/derived attributes

    ### Generation Macros
    - `generate_task_helper_functions/0` - Generate helper functions (building blocks)

    ## Usage

    ```elixir
    defmodule MyApp.Task do
        use DataModel.Task.Base

        # Define your attributes with %Struct.InfoAttr{}
        @contentref %Struct.InfoAttr{...}
        @name %Struct.InfoAttr{...}
        # ...

        task_config(
            app: :my_app,
            table_key: :task,
            group_by_keys: [@contentref, @name],
            elapsed_time_config: %{
                start_date_attr: @start_date,
                end_date_attr: @end_date,
                target_attr: @elapsed_working_time,
                business: :my_business
            }
        )

        own_attributes [
            @contentref,
            @name,
            @start_date,
            @end_date,
            @status,
            @executed_by
        ]

        computed_attributes [
            @elapsed_working_time,
            @timestamp
        ]

        generate_task_helper_functions()

        # Implement your own insert_by_lote using the helpers
        def insert_by_lote(batch, batch_id) do
            # Your custom pipeline using:
            # - group_by_composite_key/1
            # - prepare_insert_query/3
            # - build_data/1
            # - calculate_elapsed_time/1
            # - build_insert_tuples/1
            # - execute_insert/1
            # - handle_processing_error/4
        end
    end
    ```
    """

    # ============================================
    # CONFIGURATION MACROS
    # ============================================

    @doc """
    Macro to configure the Task entity.

    ### Parameters:
    - `opts`: Keyword list with:
        - `app`: Atom. Application name (for config)
        - `table_key`: Atom. Key to obtain the table name from [:bigquery, :table, table_key] (static)
        - `table_key_path`: List. Path to resolve table from config at runtime (e.g. [:bigquery, :table, :task])
        - `group_by_keys`: List of InfoAttr. Attributes to group payloads by (e.g., [@contentref, @name])
        - `timestamp`: InfoAttr. Timestamp attribute (optional, defaults to basic timestamp)
        - `elapsed_time_config`: Map with elapsed time configuration (optional):
            - `start_date_attr`: InfoAttr for start date
            - `end_date_attr`: InfoAttr for end date
            - `target_attr`: InfoAttr for the computed elapsed time field
            - `business`: Atom. Business type for working time calculation
            - `change_timezone`: Boolean. Whether to convert dates to business timezone (default: false)
        - `slack_webhook_url_path`: List. Path to resolve Slack webhook URL from config at runtime (optional)
        - `slack_env_var`: String. Environment variable name to read at runtime for slack_env (optional)
    """
    defmacro task_config(opts) do
        quote do
            opts = unquote(opts)

            unless Keyword.has_key?(opts, :app) do
                raise "task_config requires :app option"
            end

            unless Keyword.has_key?(opts, :table_key) or Keyword.has_key?(opts, :table_key_path) do
                raise "task_config requires :table_key or :table_key_path option"
            end

            unless Keyword.has_key?(opts, :group_by_keys) do
                raise "task_config requires :group_by_keys option"
            end

            @task_config opts

            @doc """
            Returns the application name configured in `task_config/1`.

            ### Returns:
                - Atom. The application name used for configuration lookup.
            """
            @spec application_name() :: atom()
            def application_name(), do: @task_config[:app]

            @doc """
            Returns the list of attributes used for grouping payloads.

            ### Returns:
                - List of `Struct.InfoAttr`
            """
            @spec group_by_keys() :: list(Struct.InfoAttr.t())
            def group_by_keys(), do: @task_config[:group_by_keys]

            @doc """
            Returns the timestamp attribute configuration.

            ### Returns:
                - `Struct.InfoAttr`
            """
            @spec timestamp_attr() :: Struct.InfoAttr.t()
            def timestamp_attr() do
                @task_config[:timestamp] || %Struct.InfoAttr{id: :timestamp, type: :integer}
            end

            @doc """
            Returns the elapsed time configuration if defined.

            ### Returns:
                - Map with elapsed time config or nil
            """
            @spec elapsed_time_config() :: map() | nil
            def elapsed_time_config(), do: @task_config[:elapsed_time_config]

            @doc """
            Returns the Slack webhook URL for error notifications.
            """
            def slack_webhook_url() do
                case @task_config[:slack_webhook_url_path] do
                    nil ->
                        @task_config[:slack_webhook_url]
                    path when is_list(path) ->
                        get_in(Application.get_env(@task_config[:app], hd(path)) || %{}, tl(path))
                end
            end

            @doc """
            Returns the environment name for Slack notifications.
            """
            def slack_env() do
                case @task_config[:slack_env_var] do
                    nil ->
                        @task_config[:slack_env] || "unknown"
                    var_name when is_binary(var_name) ->
                        System.get_env(var_name) || @task_config[:slack_env] || "unknown"
                end
            end
        end
    end

    @doc """
    Macro to define the list of own attributes of the Task.
    Automatically generates getter functions for each attribute.

    ### Example:
        own_attributes [
            @contentref,
            @name,
            @start_date,
            @end_date,
            @status
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
    Macro to define computed/derived attributes (e.g., elapsed_working_time, timestamp).
    Automatically generates getter functions for each attribute.

    ### Example:
        computed_attributes [
            @elapsed_working_time,
            @timestamp
        ]
    """
    defmacro computed_attributes(attributes) when is_list(attributes) do
        getter_functions = generate_getter_functions(attributes)
        quote do
            @computed_attributes unquote(attributes)
            unquote_splicing(getter_functions)
        end
    end

    # ============================================
    # GENERATION MACROS
    # ============================================

    @doc """
    Macro that generates helper functions (building blocks) for Task entities.

    These are tools you can use to build your own `insert_by_lote`.
    Each function is overridable.

    ## Generated Functions

    ### Required
    - `attr_list/0` - Returns complete list of attributes (own + computed)
    - `table_id/0` - Returns table identifier from config

    ### Helper Functions (Building Blocks)
    - `group_by_composite_key/1` - Groups payloads by composite key
    - `build_data/1` - Builds task data from payloads
    - `calculate_elapsed_time/1` - Calculates elapsed working time
    - `prepare_insert_query/3` - Prepares a single insert query
    - `build_insert_tuples/1` - Builds insertion tuples from list
    - `execute_insert/1` - Executes insert in database
    - `handle_processing_error/4` - Handles errors
    - `after_insert/2` - Hook for post-insert processing

    ## Note
    `insert_by_lote/2` is NOT generated. You must implement it yourself
    using these building blocks according to your business logic.
    """
    defmacro generate_task_helper_functions do
        quote do

            # ============================================
            # REQUIRED FUNCTIONS
            # ============================================

            @doc """
            Returns the complete list of attributes (own + computed)
            """
            def attr_list() do
                own_attrs = @own_attributes || []
                computed_attrs = @computed_attributes || []
                own_attrs ++ computed_attrs
            end

            @doc """
            Returns the identifier of the table in BigQuery.
            """
            def table_id() do
                case @task_config[:table_key_path] do
                    nil ->
                        # Legacy: use table_key to access [:bigquery, :table, table_key]
                        Application.get_env(application_name(), :bigquery)[:table][@task_config[:table_key]]
                    path when is_list(path) ->
                        get_in(Application.get_env(@task_config[:app], hd(path)) || %{}, tl(path))
                end
            end

            # ============================================
            # HELPER FUNCTIONS (Building Blocks)
            # ============================================

            @doc """
            Groups payloads by composite key based on configured group_by_keys.

            ### Parameters:
                - `batch`: List of maps (payloads)

            ### Returns:
                - `{map_grouped_by_key, list_of_keys}`
            """
            def group_by_composite_key(batch) do
                Common.Payload.reduce_by(batch, group_by_keys())
            end
            defoverridable group_by_composite_key: 1

            @doc """
            Builds the task data from payloads.
            Merges payloads keeping the most recent values.

            ### Parameters:
                - `payloads`: List of maps for the same composite key

            ### Returns:
                - Keyword list with task data
            """
            def build_data(payloads) do
                update_fields = fn map, fields ->
                    Enum.reduce(
                        fields,
                        map,
                        fn {key, _value} = tuple, acc ->
                            List.keystore(acc, key, 0, tuple)
                        end
                    )
                end

                payloads
                |> Enum.reduce(
                    [],
                    fn payload, acc ->
                        differences =
                            payload
                            |> Common.Payload.extract_with_format(@own_attributes, false)
                            |> calculate_elapsed_time()
                            |> Stuff.list_subtraction(acc)

                        update_fields.(acc, differences)
                    end
                )
            end
            defoverridable build_data: 1

            @doc """
            Calculates the elapsed working time between start and end dates.
            Uses the elapsed_time_config from task_config if defined.

            ### Parameters:
                - `values`: Keyword list with extracted values

            ### Returns:
                - Keyword list with elapsed_working_time added
            """
            def calculate_elapsed_time(values) do
                config = elapsed_time_config()

                if config do
                    start_date_id = config.start_date_attr.id
                    end_date_id = config.end_date_attr.id
                    target_id = config.target_attr.id
                    default_value = config.target_attr.default_value || -1
                    business = config.business
                    change_timezone = Map.get(config, :change_timezone, false)

                    start_date = List.keyfind(values, start_date_id, 0, {0, nil}) |> elem(1)
                    end_date = List.keyfind(values, end_date_id, 0, {0, nil}) |> elem(1)

                    elapsed_value =
                        if is_nil(start_date) or is_nil(end_date) do
                            default_value
                        else
                            case Time.WorkingTime.elapsed_time(start_date, end_date, business, [], change_timezone) do
                                {:ok, value} -> value
                                {:error, _msg} -> default_value
                            end
                        end

                    [{target_id, elapsed_value} | values]
                else
                    values
                end
            end
            defoverridable calculate_elapsed_time: 1

            @doc """
            Prepares and builds the insert query for a task.

            ### Parameters:
                - `batch_id`: String. Batch identifier
                - `composite_key`: String. Composite key (e.g., "contentref__name")
                - `payloads`: List of maps with payloads

            ### Returns:
                - `{:ok, query}` if successful
                - `{:error, nil}` if there's an error
            """
            def prepare_insert_query(batch_id, composite_key, payloads) do
                try do
                    timestamp_attr = timestamp_attr()

                    data =
                        build_data(payloads)
                        |> List.keystore(
                            timestamp_attr.id,
                            0,
                            {timestamp_attr.id, Timex.now() |> Timex.to_unix()}
                        )

                    {:ok, Statement.Sql.insert(table_id(), data)}
                rescue
                    error ->
                        handle_processing_error(batch_id, composite_key, error, %{
                            function: :prepare_insert_query,
                            module: __MODULE__
                        })
                        {:error, nil}
                end
            end
            defoverridable prepare_insert_query: 3

            @doc """
            Builds insertion tuples by combining multiple queries.

            ### Parameters:
                - `queries`: List of query strings

            ### Returns:
                - Merged query string or empty string if no queries
            """
            def build_insert_tuples([]), do: ""

            def build_insert_tuples(queries) do
                Statement.Sql.merge_inserts(queries)
            end
            defoverridable build_insert_tuples: 1

            @doc """
            Executes the insert operation in the database.

            ### Parameters:
                - `query`: String. The SQL query to execute
                - `batch_id`: String. Batch identifier

            ### Returns:
                - `:ok` if successful
                - `:error` if there's an error
            """
            def execute_insert("", _batch_id), do: :ok

            def execute_insert(query, batch_id) do
                try do
                    pid =
                        Application.get_env(application_name(), :bigquery)[:configuration]
                        |> Connection.Odbc.connect()

                    Connection.Odbc.insert(pid, query)
                    Process.exit(pid, :kill)
                    :ok
                rescue
                    error ->
                        handle_processing_error(batch_id, "-__-", error, %{
                            function: :execute_insert,
                            module: __MODULE__
                        })
                        :error
                end
            end
            defoverridable execute_insert: 2

            @doc """
            Hook for post-insert processing.
            Override this to add custom logic after successful insert.

            ### Parameters:
                - `batch`: Original batch of payloads
                - `batch_id`: String. Batch identifier

            ### Returns:
                - any
            """
            def after_insert(_batch, _batch_id), do: :ok
            defoverridable after_insert: 2

            @doc """
            Handles errors during task processing.
            Logs the error and sends a Slack notification if webhook is configured.

            ### Parameters:
                - `batch_id`: String. Batch identifier
                - `composite_key`: String. Task identifier (e.g., "contentref__name")
                - `error`: The error that occurred
                - `context`: Map with `:function` and `:module`
            """
            def handle_processing_error(batch_id, composite_key, error, context) do
                require Logger

                {contentref, name} = parse_composite_key(composite_key)

                msg = """
                [#{__MODULE__} Error]
                Module: #{inspect(context[:module] || __MODULE__)}
                Function: #{inspect(context[:function])}
                #{if contentref, do: "Contentref: #{inspect(contentref)}", else: ""}
                #{if name, do: "Name: #{inspect(name)}", else: ""}
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

            @doc """
            Parses a composite key into its components.

            ### Parameters:
                - `composite_key`: String. Key in "value1__value2" format

            ### Returns:
                - `{first_value, second_value}` tuple
            """
            def parse_composite_key(composite_key) when is_binary(composite_key) do
                if String.contains?(composite_key, "__") do
                    [first, second] = String.split(composite_key, "__", parts: 2)
                    {first, second}
                else
                    {composite_key, nil}
                end
            end

            def parse_composite_key(_), do: {nil, nil}

            # ============================================
            # DEFAULT INSERT_BY_LOTE IMPLEMENTATION
            # ============================================

            @doc """
            Default implementation of insert_by_lote.
            Override this to implement custom business logic.

            ### Parameters:
                - `batch`: List of map. Payloads.
                - `batch_id`: String. Batch identifier.

            ### Returns:
                - `:ok` | `:error`
            """
            def insert_by_lote([], _batch_id), do: :ok

            def insert_by_lote(batch, batch_id)
                when is_list(batch) and is_binary(batch_id) do

                {grouped_by_key, keys} = group_by_composite_key(batch)

                result =
                    keys
                    |> Enum.reduce(
                        [],
                        fn key, queries ->
                            prepare_insert_query(
                                batch_id,
                                key,
                                Map.get(grouped_by_key, key)
                            )
                            |> case do
                                {:error, _} -> queries
                                {:ok, query} -> queries ++ [query]
                            end
                        end
                    )
                    |> case do
                        [] -> :ok
                        list ->
                            list
                            |> build_insert_tuples()
                            |> execute_insert(batch_id)
                    end

                after_insert(batch, batch_id)

                result
            end
            defoverridable insert_by_lote: 2

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
