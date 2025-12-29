
defmodule ForcedLoad.Handler do
    @moduledoc """
    Handler module for forced load operations.

    Provides flexible, configurable logic for historical data loading from
    BigQuery/ElasticSearch and publishing to RabbitMQ queues.

    ## Configuration Options

    The handler accepts a config map with the following keys:

    ### Required
        - `:app_name` - Atom. Application name for config lookup (e.g., :etl_leasing)
        - `:business_name` - String. Human-readable name for notifications (e.g., "LEASING")
        - `:documentary_type` - String. Document type for ElasticSearch/WorkflowService
        - `:record_queue` - String. Queue name for record messages
        - `:task_queue` - String. Queue name for task messages

    ### Required - Field Identifiers (for BigQuery/ElasticSearch queries)
        - `:bigquery_table` - String. Full BigQuery table name (e.g., "dataset.table")
        - `:unique_id_field` - Atom. Field name for unique ID in BigQuery (e.g., :unique_id)
        - `:unique_id_payload_field` - String. Field name for unique ID in ElasticSearch/payload (e.g., "uniqueId")
        - `:last_update_field` - Atom. Field name for last update timestamp in BigQuery (e.g., :ultima_actualizacion)
        - `:last_update_payload_field` - String. Field name for last update in ElasticSearch (e.g., "lastUpdate")

    ### Optional - Data Sources (resolved from paths or provided directly)
        - `:bigquery_config` - Keyword list. BigQuery ODBC config
        - `:elasticsearch_url` - String. ElasticSearch URL
        - `:elasticsearch_headers` - List. ElasticSearch headers
        - `:amqp_config` - Keyword list. AMQP connection config
        - `:ticket_config` - Map. Custom ticket config with :url, :headers, :username, :password
        - `:nodeservice_config` - Map. Custom NodeService config with :url and :headers
        - `:workflowservice_config` - Map. Custom WorkflowService config with :url and :headers

    ### Optional - Filters
        - `:id_filter` - Function. `(list_of_ids) -> filtered_list`. Filter IDs after fetching
        - `:tenant_filter` - String | nil. Filter by tenant field value
        - `:task_name_filter` - List of Strings | nil. Filter tasks by name
        - `:record_filter` - Function. `(record_payload) -> boolean`. Filter individual records

    ### Optional - Callbacks
        - `:on_batch_start` - Function. `(batch, batch_number) -> :ok`. Called before processing each batch
        - `:on_batch_end` - Function. `(batch, batch_number, results) -> :ok`. Called after processing each batch
        - `:on_record_success` - Function. `(unique_id, payload) -> :ok`. Called after successful record load
        - `:on_record_error` - Function. `(unique_id, error) -> :ok`. Called on record load error
        - `:on_task_success` - Function. `(contentref, tasks) -> :ok`. Called after successful task load
        - `:on_task_error` - Function. `(contentref, error) -> :ok`. Called on task load error

    ### Optional - Custom Functions
        - `:get_ids_fn` - Function. `(start_date, end_date, config) -> list`. Custom BigQuery ID fetcher
        - `:get_ids_es_fn` - Function. `(start_date, end_date, config) -> list`. Custom ElasticSearch ID fetcher
        - `:load_record_fn` - Function. `(unique_id, ticket, channel, config) -> :ok | {:error, reason}`. Custom record loader
        - `:load_task_fn` - Function. `(contentref, ticket, channel, config) -> :ok | {:error, reason}`. Custom task loader
        - `:build_record_message_fn` - Function. `(payload) -> map`. Custom record message builder
        - `:build_task_message_fn` - Function. `(task) -> map`. Custom task message builder

    ### Optional - Behavior
        - `:batch_size` - Integer. Records per batch (default: 200)
        - `:batch_delay` - Integer. Milliseconds to wait between batches (default: 0)
        - `:skip_elasticsearch` - Boolean. Skip ElasticSearch queries (default: false)
        - `:skip_bigquery` - Boolean. Skip BigQuery queries (default: false)
        - `:notification_fn` - Function. `(message, level) -> :ok`. Custom notification function

    ## Example Usage

    ```elixir
    config = %{
        app_name: :etl_leasing,
        business_name: "LEASING",
        documentary_type: "leasing_doc",
        record_queue: "leasing.record",
        task_queue: "leasing.task",

        # Field identifiers
        bigquery_table: "dataset.records",
        unique_id_field: :unique_id,
        unique_id_payload_field: "uniqueId",
        last_update_field: :ultima_actualizacion,
        last_update_payload_field: "lastUpdate",

        # Optional filters
        tenant_filter: "tenant_abc",
        task_name_filter: ["task_1", "task_2"],
        batch_size: 100
    }

    ForcedLoad.Handler.run(:record, params, config)
    ```
    """

    require Logger
    alias Connection.Ticket
    alias Connection.ElasticSearch
    alias Connection.NodeService
    alias Connection.WorkflowService
    alias Connection.Odbc
    alias Statement.Sql
    import Time.Timem, only: [by_intervals: 3]


    @default_batch_size 200
    @default_batch_delay 0


    # ============================================
    # PUBLIC API
    # ============================================

    @doc """
    Runs the forced load process for records and/or tasks.

    ### Parameters
        - business: Atom. Business type (e.g., :record)
        - params: List. [start_date, end_date, step, includes_record, includes_task]
        - config: Map. Configuration options (see module docs)

    ### Returns
        - :ok on success
        - {:error, reason} on failure
    """
    def run(business, params, config) do
        case business do
            :record ->
                run_record_load(params, config)

            other ->
                Logger.warning("Unknown business type for forced load: #{inspect(other)}")
                {:error, :unknown_business}
        end
    end


    @doc """
    Runs record/task forced load with the given parameters and configuration.

    ### Parameters
        - params: List. Accepts multiple formats:
            - [start_date, end_date] - uses time_step from config, loads both records and tasks
            - [start_date, end_date, step] - uses provided step, loads both records and tasks
            - [start_date, end_date, step, includes_record, includes_task] - full control
        - config: Map. Configuration options

    ### Returns
        - :ok on success
    """
    def run_record_load([start_date, end_date], config) do
        step = Map.get(config, :time_step, 7)
        run_record_load([start_date, end_date, step, true, true], config)
    end

    def run_record_load([start_date, end_date, step], config) do
        run_record_load([start_date, end_date, step, true, true], config)
    end

    def run_record_load([start_date, end_date, step, includes_record, includes_task], config) do
        start_date = Timex.to_datetime(start_date)
        end_date = Timex.to_datetime(end_date)

        business_name = Map.get(config, :business_name, "UNKNOWN")

        notify(config,
            """
            *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
            FORCED LOAD. #{business_name}
            Period: #{to_string(start_date)} - #{to_string(end_date)}
            Record upload: #{to_string(includes_record)}
            Loading of tasks associated to the records: #{to_string(includes_task)}
            *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
            """,
            :info
        )

        {:ok, intervals} = by_intervals(start_date, end_date, step)

        # Open AMQP connection
        amqp_config = get_amqp_config(config)
        {:ok, connection} = AMQP.Connection.open(amqp_config)
        {:ok, channel} = AMQP.Channel.open(connection)

        try do
            intervals
            |> Enum.each(fn {start_date_, end_date_} ->
                process_interval(
                    start_date_,
                    end_date_,
                    channel,
                    includes_record,
                    includes_task,
                    config
                )
            end)

            notify(config,
                """
                *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
                FORCED LOAD. #{business_name}
                Period: #{to_string(start_date)} - #{to_string(end_date)}.
                END!!!
                *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
                """,
                :info
            )

            :ok
        after
            # Close AMQP connection
            if connection, do: AMQP.Connection.close(connection)
        end
    end


    # ============================================
    # INTERVAL PROCESSING
    # ============================================

    defp process_interval(start_date, end_date, channel, includes_record, includes_task, config) do
        notify(config,
            "Start of forced charge between #{to_string(start_date)} and #{to_string(end_date)}",
            :info
        )

        ids = fetch_all_ids(start_date, end_date, config)

        batch_size = Map.get(config, :batch_size, @default_batch_size)
        batch_delay = Map.get(config, :batch_delay, @default_batch_delay)

        ids
        |> Enum.chunk_every(batch_size)
        |> Enum.with_index(1)
        |> Enum.each(fn {batch, batch_number} ->
            # Callback: on_batch_start
            if callback = Map.get(config, :on_batch_start) do
                callback.(batch, batch_number)
            end

            # Get ticket for this batch
            ticket = get_ticket(config)

            results = %{
                records_loaded: load_records(batch, ticket, channel, includes_record, config),
                tasks_loaded: load_tasks(batch, ticket, channel, includes_task, config)
            }

            # Callback: on_batch_end
            if callback = Map.get(config, :on_batch_end) do
                callback.(batch, batch_number, results)
            end

            # Delay between batches if configured
            if batch_delay > 0, do: :timer.sleep(batch_delay)
        end)

        notify(config,
            "End of forced charge between #{to_string(start_date)} and #{to_string(end_date)}. Number of records processed: #{length(ids)}",
            :info
        )
    end


    # ============================================
    # ID FETCHING
    # ============================================

    defp fetch_all_ids(start_date, end_date, config) do
        bq_ids = fetch_ids_from_bigquery(start_date, end_date, config)
        es_ids = fetch_ids_from_elasticsearch(start_date, end_date, config)

        all_ids = (bq_ids ++ es_ids) |> Enum.uniq()

        # Apply ID filter if configured
        case Map.get(config, :id_filter) do
            nil -> all_ids
            filter_fn when is_function(filter_fn, 1) -> filter_fn.(all_ids)
        end
    end


    defp fetch_ids_from_bigquery(start_date, end_date, config) do
        if Map.get(config, :skip_bigquery, false) do
            []
        else
            # Use custom function if provided
            case Map.get(config, :get_ids_fn) do
                nil -> default_get_ids_bq(start_date, end_date, config)
                custom_fn -> custom_fn.(start_date, end_date, config)
            end
        end
    end


    defp fetch_ids_from_elasticsearch(start_date, end_date, config) do
        if Map.get(config, :skip_elasticsearch, false) do
            []
        else
            # Use custom function if provided
            case Map.get(config, :get_ids_es_fn) do
                nil -> default_get_ids_es(start_date, end_date, config)
                custom_fn -> custom_fn.(start_date, end_date, config)
            end
        end
    end


    defp default_get_ids_bq(start_date, end_date, config) do
        app_name = Map.fetch!(config, :app_name)
        bigquery_table = Map.fetch!(config, :bigquery_table)
        unique_id_field = Map.fetch!(config, :unique_id_field)
        last_update_field = Map.fetch!(config, :last_update_field)

        bq_config = Map.get(config, :bigquery_config) ||
            Application.get_env(app_name, :bigquery)[:configuration]

        statement = Sql.select(
            bigquery_table,
            [unique_id_field],
            [[
                {
                    last_update_field,
                    start_date |> Poison.encode!() |> Poison.decode!(),
                    :gte,
                    :timestamp
                },
                {
                    last_update_field,
                    end_date |> Poison.encode!() |> Poison.decode!(),
                    :lte,
                    :timestamp
                }
            ]],
            [:and]
        )

        pid = Odbc.connect(bq_config)

        try do
            Odbc.select(pid, statement)
            |> Enum.map(fn [{_, id}] -> id end)
        rescue
            error ->
                notify(config, "Error fetching IDs from BigQuery: #{inspect(error)}", :error)
                []
        after
            Process.exit(pid, :kill)
        end
    end


    defp default_get_ids_es(start_date, end_date, config) do
        app_name = Map.fetch!(config, :app_name)
        documentary_type = Map.fetch!(config, :documentary_type)
        unique_id_payload_field = Map.fetch!(config, :unique_id_payload_field)
        last_update_payload_field = Map.fetch!(config, :last_update_payload_field)

        es_url = Map.get(config, :elasticsearch_url) ||
            Application.get_env(app_name, :elasticsearch)[:url]

        es_headers = Map.get(config, :elasticsearch_headers) ||
            Application.get_env(app_name, :elasticsearch)[:headers]

        ElasticSearch.get_from_range(
            es_url,
            es_headers,
            documentary_type,
            ElasticSearch.mode(),
            start_date |> Poison.encode!() |> Poison.decode!(),
            end_date |> Poison.encode!() |> Poison.decode!(),
            last_update_payload_field,
            unique_id_payload_field
        )
        |> case do
            {:ok, list} -> list
            {:error, error} ->
                notify(config, "Error fetching IDs from ElasticSearch: #{inspect(error)}", :error)
                []
        end
    end


    # ============================================
    # RECORD LOADING
    # ============================================

    defp load_records(_ids, _ticket, _channel, false, _config), do: 0

    defp load_records(ids, ticket, channel, true, config) do
        # Use custom function if provided
        load_fn = Map.get(config, :load_record_fn, &default_load_record/4)

        ids
        |> Enum.reduce(0, fn unique_id, acc ->
            case load_fn.(unique_id, ticket, channel, config) do
                :ok -> acc + 1
                {:error, _} -> acc
            end
        end)
    end


    defp default_load_record(unique_id, ticket, channel, config) do
        app_name = Map.fetch!(config, :app_name)
        record_queue = Map.fetch!(config, :record_queue)

        ns_config = Map.get(config, :nodeservice_config) || %{
            url: Application.get_env(app_name, :nodeservice)[:url],
            headers: Application.get_env(app_name, :nodeservice)[:headers]
        }

        try do
            NodeService.get_details(unique_id, ns_config.url, ns_config.headers, ticket)
            |> case do
                {:error, error} ->
                    if callback = Map.get(config, :on_record_error) do
                        callback.(unique_id, error)
                    else
                        notify(config, "Error getting record #{unique_id} from NodeService: #{inspect(error)}", :error)
                    end
                    {:error, error}

                {:ok, %{"response" => %{"msg" => payload}}} ->
                    should_publish = case Map.get(config, :record_filter) do
                        nil -> true
                        filter_fn -> filter_fn.(payload)
                    end

                    if should_publish do
                        msg = case Map.get(config, :build_record_message_fn) do
                            nil -> %{"action" => "poblar_datos", "current" => payload}
                            builder_fn -> builder_fn.(payload)
                        end

                        AMQP.Basic.publish(channel, record_queue, "", Poison.encode!(msg))

                        if callback = Map.get(config, :on_record_success) do
                            callback.(unique_id, payload)
                        end
                    end

                    :ok
            end
        rescue
            error ->
                notify(config, "Error loading record #{unique_id} from NodeService: #{inspect(error)}", :error)
                {:error, error}
        end
    end


    # ============================================
    # TASK LOADING
    # ============================================

    defp load_tasks(_ids, _ticket, _channel, false, _config), do: 0

    defp load_tasks(ids, ticket, channel, true, config) do
        # Use custom function if provided
        load_fn = Map.get(config, :load_task_fn, &default_load_task/4)

        ids
        |> Enum.reduce(0, fn contentref, acc ->
            case load_fn.(contentref, ticket, channel, config) do
                :ok -> acc + 1
                {:error, _} -> acc
            end
        end)
    end


    defp default_load_task(contentref, ticket, channel, config) do
        app_name = Map.fetch!(config, :app_name)
        task_queue = Map.fetch!(config, :task_queue)
        documentary_type = Map.fetch!(config, :documentary_type)

        ws_config = Map.get(config, :workflowservice_config) || %{
            url: Application.get_env(app_name, :workflowservice)[:url],
            headers: Application.get_env(app_name, :workflowservice)[:headers]
        }

        try do
            WorkflowService.get_details(ws_config.url, ws_config.headers, documentary_type, contentref, ticket)
            |> case do
                {:error, error} ->
                    if callback = Map.get(config, :on_task_error) do
                        callback.(contentref, error)
                    else
                        notify(config, "Error getting tasks for #{contentref} from WorkflowService: #{inspect(error)}", :error)
                    end
                    {:error, error}

                {:ok, tasks} ->
                    filtered_tasks = case Map.get(config, :task_name_filter) do
                        nil -> tasks
                        allowed_names when is_list(allowed_names) ->
                            Enum.filter(tasks, fn task ->
                                task_name = Map.get(task, "name") || Map.get(task, "nombre")
                                task_name in allowed_names
                            end)
                    end

                    Enum.each(filtered_tasks, fn task ->
                        msg = case Map.get(config, :build_task_message_fn) do
                            nil -> task
                            builder_fn -> builder_fn.(task)
                        end

                        AMQP.Basic.publish(channel, task_queue, "", Poison.encode!(msg))
                    end)

                    if callback = Map.get(config, :on_task_success) do
                        callback.(contentref, filtered_tasks)
                    end

                    :ok
            end
        rescue
            error ->
                notify(config, "Error loading tasks for #{contentref} from WorkflowService: #{inspect(error)}", :error)
                {:error, error}
        end
    end


    # ============================================
    # HELPER FUNCTIONS
    # ============================================

    defp get_amqp_config(config) do
        case Map.get(config, :amqp_config) do
            nil ->
                app_name = Map.fetch!(config, :app_name)
                Application.get_env(app_name, :my_amqp_client)[:connection]
            amqp_config ->
                amqp_config
        end
    end


    defp get_ticket(config) do
        app_name = Map.fetch!(config, :app_name)

        ticket_config = Map.get(config, :ticket_config) || %{
            url: Application.get_env(app_name, :ticket)[:url],
            headers: Application.get_env(app_name, :ticket)[:headers],
            username: Application.get_env(app_name, :user)[:totalcheck][:username],
            password: Application.get_env(app_name, :user)[:totalcheck][:password]
        }

        try do
            Ticket.get(ticket_config.url, ticket_config.headers, ticket_config.username, ticket_config.password)
            |> case do
                {:ok, ticket} -> ticket
                {:error, error} ->
                    notify(config, "Failed to get ticket: #{inspect(error)}", :error)
                    nil
            end
        rescue
            error ->
                notify(config, "Error getting ticket: #{inspect(error)}", :error)
                nil
        end
    end


    defp notify(config, message, level) do
        case Map.get(config, :notification_fn) do
            nil -> default_notify(config, message, level)
            custom_fn -> custom_fn.(message, level)
        end
    end


    defp default_notify(config, message, level) do
        app_name = Map.get(config, :app_name)

        webhook_url = if app_name do
            Application.get_env(app_name, :notification)[:slack_webhook][:url][:notification]
        end

        headers = if app_name do
            Application.get_env(app_name, :notification)[:slack_webhook][:headers]
        end

        environment = System.get_env("ENVIRONMENT")

        if webhook_url && headers do
            Notification.Notify.notify_slack(webhook_url, headers, environment, message)
        end

        case level do
            :info -> Logger.info(message)
            :error -> Logger.error(message)
            :warning -> Logger.warning(message)
            _ -> Logger.debug(message)
        end
    end


end
