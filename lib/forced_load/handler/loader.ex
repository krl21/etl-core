
defmodule ForcedLoad.Handler.Loader do
    @moduledoc """
    Processing of each interval of `ForcedLoad.Handler`: fetches the IDs, splits them into batches and publishes the records and tasks to RabbitMQ. See `process_interval/7`.
    """

    alias Connection.NodeService
    alias Connection.WorkflowService
    alias ForcedLoad.Handler.Ids
    alias ForcedLoad.Helpers


    @default_batch_size 200
    @default_batch_delay 0


    @doc """
    Processes a single time interval: fetches IDs, splits into batches, and loads records/tasks.

    ### Parameters
        - start_date: DateTime. Start of the interval
        - end_date: DateTime. End of the interval
        - channel: AMQP.Channel. Channel for publishing messages
        - bq_pid: pid | nil. BigQuery ODBC connection process
        - includes_record: boolean. Whether to load records
        - includes_task: boolean. Whether to load tasks
        - config: map. Configuration options

    ### Returns
        - :ok
    """
    def process_interval(start_date, end_date, channel, bq_pid, includes_record, includes_task, config) do
        Helpers.notify(config,
            "Inicio de carga forzada entre #{to_string(start_date)} y #{to_string(end_date)}",
            :info
        )

        ids = Ids.fetch_all(start_date, end_date, bq_pid, config)

        batch_size = Map.get(config, :batch_size, @default_batch_size)
        batch_delay = Map.get(config, :batch_delay, @default_batch_delay)

        batches = Enum.chunk_every(ids, batch_size)
        total_batches = length(batches)

        Helpers.notify(config, "Total de IDs a procesar: #{length(ids)} en #{total_batches} lotes", :info)

        batches
        |> Enum.with_index(1)
        |> Enum.each(fn {batch, batch_number} ->
            Helpers.notify(config, "Lote #{batch_number}/#{total_batches} - Procesando #{length(batch)} IDs", :info)

            # Callback: on_batch_start
            if callback = Map.get(config, :on_batch_start) do
                callback.(batch, batch_number)
            end

            ticket = Helpers.get_ticket(config)

            # Load records
            records_loaded = if includes_record do
                Helpers.notify(config, "\tCargando expedientes...", :info)
                count = load_records(batch, ticket, channel, true, config)
                Helpers.notify(config, "\tExpedientes cargados: #{count}/#{length(batch)}", :info)
                count
            else
                0
            end

            # Load tasks
            tasks_loaded = if includes_task do
                Helpers.notify(config, "\tCargando tareas...", :info)
                count = load_tasks(batch, ticket, channel, true, config)
                Helpers.notify(config, "\tTareas cargadas: #{count}/#{length(batch)}", :info)
                count
            else
                0
            end

            results = %{records_loaded: records_loaded, tasks_loaded: tasks_loaded}

            # Callback: on_batch_end
            if callback = Map.get(config, :on_batch_end) do
                callback.(batch, batch_number, results)
            end

            Helpers.notify(config, "Lote #{batch_number}/#{total_batches} - Completado", :info)

            if batch_delay > 0, do: :timer.sleep(batch_delay)
        end)

        Helpers.notify(config,
            "Fin de carga forzada entre #{to_string(start_date)} y #{to_string(end_date)}. Número de registros procesados: #{length(ids)}",
            :info
        )

        :ok
    end


    # ============================================
    # RECORD LOADING
    # ============================================

    #
    # Loads records for a batch of IDs and publishes them to AMQP queue.
    #
    # ### Parameters
    #     - ids: list. List of unique IDs to load
    #     - ticket: String | nil. Authentication ticket for NodeService
    #     - channel: AMQP.Channel. Channel for publishing messages
    #     - enabled: boolean. If false, returns 0 immediately
    #     - config: map. Configuration options
    #
    # ### Returns
    #     - integer. Number of records successfully loaded
    #
    defp load_records(_ids, _ticket, _channel, false, _config), do: 0

    defp load_records(ids, ticket, channel, true, config) do
        load_fn = Map.get(config, :load_record_fn, &default_load_record/4)

        ids
        |> Enum.reduce(0, fn unique_id, acc ->
            case load_fn.(unique_id, ticket, channel, config) do
                :ok -> acc + 1
                {:error, _} -> acc
            end
        end)
    end


    #
    # Default implementation for loading a single record.
    # Fetches record from NodeService and publishes to AMQP queue.
    #
    # ### Parameters
    #     - unique_id: String. Unique identifier of the record
    #     - ticket: String | nil. Authentication ticket
    #     - channel: AMQP.Channel. Channel for publishing
    #     - config: map. Must contain :record_queue, optionally :record_filter, :build_record_message_fn
    #
    # ### Returns
    #     - :ok on success
    #     - {:error, reason} on failure
    #
    defp default_load_record(unique_id, ticket, channel, config) do
        record_queue = Map.fetch!(config, :record_queue)
        ns_config = Helpers.get_nodeservice_config(config)

        try do
            NodeService.get_details(unique_id, ns_config.url, ns_config.headers, ticket)
            |> case do
                {:error, error} ->
                    if callback = Map.get(config, :on_record_error) do
                        callback.(unique_id, error)
                    else
                        Helpers.notify(config, "Error al obtener expediente #{unique_id} de NodeService: #{inspect(error)}", :error)
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
                Helpers.notify(config, "Error al cargar expediente #{unique_id} de NodeService: #{inspect(error)}", :error)
                {:error, error}
        end
    end


    # ============================================
    # TASK LOADING
    # ============================================

    #
    # Loads tasks for a batch of content references and publishes them to AMQP queue.
    #
    # ### Parameters
    #     - ids: list. List of content references to load tasks for
    #     - ticket: String | nil. Authentication ticket for WorkflowService
    #     - channel: AMQP.Channel. Channel for publishing messages
    #     - enabled: boolean. If false, returns 0 immediately
    #     - config: map. Configuration options
    #
    # ### Returns
    #     - integer. Number of content references with tasks successfully loaded
    #
    defp load_tasks(_ids, _ticket, _channel, false, _config), do: 0

    defp load_tasks(ids, ticket, channel, true, config) do
        load_fn = Map.get(config, :load_task_fn, &default_load_task/4)

        ids
        |> Enum.reduce(0, fn contentref, acc ->
            case load_fn.(contentref, ticket, channel, config) do
                :ok -> acc + 1
                {:error, _} -> acc
            end
        end)
    end


    #
    # Default implementation for loading tasks for a single content reference.
    # Fetches tasks from WorkflowService and publishes each to AMQP queue.
    #
    # ### Parameters
    #     - contentref: String. Content reference to fetch tasks for
    #     - ticket: String | nil. Authentication ticket
    #     - channel: AMQP.Channel. Channel for publishing
    #     - config: map. Must contain :task_queue, :documentary_type, optionally :task_name_filter
    #
    # ### Returns
    #     - :ok on success
    #     - {:error, reason} on failure
    #
    defp default_load_task(contentref, ticket, channel, config) do
        task_queue = Map.fetch!(config, :task_queue)
        documentary_type = Map.fetch!(config, :documentary_type)
        ws_config = Helpers.get_workflowservice_config(config)

        try do
            WorkflowService.get_details(ws_config.url, ws_config.headers, documentary_type, contentref, ticket)
            |> case do
                {:error, error} ->
                    if callback = Map.get(config, :on_task_error) do
                        callback.(contentref, error)
                    else
                        Helpers.notify(config, "Error al obtener tareas para #{contentref} de WorkflowService: #{inspect(error)}", :error)
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
                Helpers.notify(config, "Error al cargar tareas para #{contentref} de WorkflowService: #{inspect(error)}", :error)
                {:error, error}
        end
    end


end
