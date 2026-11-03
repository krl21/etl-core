
defmodule Genserver.ForcedLoad do
    @moduledoc """
    GenServer for forced historical data loading.

    This GenServer coordinates the forced loading of records and tasks from external services to RabbitMQ queues.

    ## Usage

    ### With Protocol (Legacy - for backward compatibility)

    ```elixir
    # In application.ex
    {Genserver.ForcedLoad, {:record, [start_date, end_date, step, true, true]}}
    ```

    This mode uses `Genserver.Protocols.PForcedLoad` implementations.

    ### With Handler Configuration (Recommended)

    ```elixir
    # In application.ex
    config = %{
        app_name: :etl_leasing,
        business_name: "LEASING",
        documentary_type: "leasing",
        entity_module: Entity.Record,
        record_queue: "leasing.record",
        task_queue: "leasing.task"
    }

    {Genserver.ForcedLoad, {:record, [start_date, end_date, step, true, true], config}}
    ```

    ### With Webhook URL for Status Notifications

    ```elixir
    # In application.ex
    config = %{
        app_name: :etl_leasing,
        business_name: "LEASING",
        documentary_type: "leasing",
        record_queue: "leasing.record",
        task_queue: "leasing.task",
        webhook_url: "https://example.com/webhook/status"  # Optional
    }

    {Genserver.ForcedLoad, {:record, [start_date, end_date, step, true, true], config}}
    ```

    ### Several Forced Loads in Sequence

    ```elixir
    configs = [MyApp.ForcedLoadConfig.Mlt.build_config(), MyApp.ForcedLoadConfig.Cav.build_config()]

    {Genserver.ForcedLoad, {:record, [start_date, end_date], configs}}
    ```

    The forced loads run one after the other, each one with its direct load. If one fails, the error is notified and the next one runs; at the end, a summary is notified.

    ### Standalone Direct Load to BigQuery

    ```elixir
    Genserver.ForcedLoad.start_link({:direct_load, config})
    ```

    Runs only the direct load (see `ForcedLoad.Handler.run_direct_load/1`), in the background.

    ### Process Names

    Each process is registered with a name built from the business and the `:business_name` of the configuration (e.g. `:"Elixir.Genserver.ForcedLoad.record.IDAUTO (MLT)"`), so forced loads with different configurations can run at the same time. A sequence joins the business names with `+`. See `process_name/1`.

    The webhook will receive POST requests with JSON payloads containing:
    - `status`: One of "started", "in_progress", "completed", "error"
    - `business`: The business type being processed
    - `message`: Human-readable status message
    - `timestamp`: ISO 8601 timestamp

    See `ForcedLoad.Handler` for all available configuration options.
    """

    use GenServer, restart: :temporary
    require Logger
    alias Genserver.Monitor
    alias ForcedLoad.Handler, as: ForcedLoadHandler
    alias ForcedLoad.Handler.DirectLoad
    alias ForcedLoad.Helpers, as: ForcedLoadHelpers
    alias Connection.Http


    @doc """
    Child specification for the supervisor.

    Uses `restart: :temporary` so the process won't be restarted after it terminates.
    """
    def child_spec(arg) do
        %{
            id: process_name(arg),
            start: {__MODULE__, :start_link, [arg]},
            restart: :temporary,
            type: :worker
        }
    end


    @doc """
    Starts the ForcedLoad GenServer.

    ### Parameters

    Accepts either:
    - `{business, params}` - Legacy tuple format, uses PForcedLoad protocol
    - `{business, params, config}` - New format with handler configuration (config may include `:webhook_url`)
    - `{business, params, configs}` - List of configurations: the forced loads run in sequence
    - `{:direct_load, config}` - Standalone direct load to BigQuery
    - Map with `:business`, `:params`, and optionally `:config` keys
    """
    def start_link({:direct_load, config} = arg) when is_map(config), do:
        GenServer.start_link(__MODULE__, %{business: :direct_load, params: nil, config: config, mode: :direct_load}, name: process_name(arg))

    def start_link({business, params, configs} = arg) when is_list(configs) and configs != [], do:
        GenServer.start_link(__MODULE__, %{business: business, params: params, config: nil, configs: configs, mode: :sequence}, name: process_name(arg))

    def start_link({business, params, config} = arg) when is_map(config), do:
        GenServer.start_link(__MODULE__, %{business: business, params: params, config: config, mode: :single}, name: process_name(arg))

    def start_link({business, params} = arg), do:
        GenServer.start_link(__MODULE__, %{business: business, params: params, config: nil, mode: :single}, name: process_name(arg))

    def start_link(%{business: business} = info) do
        state = Map.merge(%{config: nil, mode: :single}, info)
        GenServer.start_link(__MODULE__, state, name: process_name({business, Map.get(info, :params), state.config}))
    end


    @doc """
    Returns the name the process is registered with: the module, the business and the `:business_name` of the configuration. Without configuration (legacy format), only the module and the business. For a sequence, the business names are joined with `+`.

    ### Parameters
        - arg: Same argument as `start_link/1`

    ### Returns
        - Atom. Name of the process (e.g. `:"Elixir.Genserver.ForcedLoad.record.IDAUTO (MLT)"`)
    """
    def process_name({:direct_load, config}) when is_map(config), do:
        :"#{__MODULE__}.direct_load.#{Map.get(config, :business_name, "UNKNOWN")}"

    def process_name({business, _params, configs}) when is_list(configs), do:
        :"#{__MODULE__}.#{business}.#{Enum.map_join(configs, "+", &Map.get(&1, :business_name, "UNKNOWN"))}"

    def process_name({business, _params, config}) when is_map(config), do:
        :"#{__MODULE__}.#{business}.#{Map.get(config, :business_name, "UNKNOWN")}"

    def process_name({business, _params, nil}), do:
        :"#{__MODULE__}.#{business}"

    def process_name({business, _params}), do:
        :"#{__MODULE__}.#{business}"

    def process_name(%{business: business, configs: configs} = info) when is_list(configs), do:
        process_name({business, Map.get(info, :params), configs})

    def process_name(%{business: business} = info), do:
        process_name({business, Map.get(info, :params), Map.get(info, :config)})


    #
    # Validates the configuration of the direct load to BigQuery before anything else. If it is invalid, it notifies the error and returns `:ignore`: the forced load does not run and the supervisor continues without this process. In a sequence, each configuration is validated right before its forced load.
    #
    @impl true
    def init(%{business: business, config: config} = state) do
        name = to_string(process_name(state))
        Logger.info("#{name}. CARGA FORZADA: Inicializando")

        try do
            case state do
                %{mode: :direct_load} -> ForcedLoadHelpers.validate_direct_load!(Map.put(config, :bigquery_direct_load, true))
                %{mode: :single} when config != nil -> ForcedLoadHelpers.validate_direct_load!(config)
                _ -> :ok
            end

            Monitor.register(self(), name)
            notify_webhook(get_webhook_url(config), business, "started", "Proceso de carga forzada inicializado")

            :erlang.send_after(10_000, self(), :update)
            {:ok, state}
        rescue
            error ->
                message = "CARGA FORZADA. Configuración inválida de la carga directa a BigQuery: #{Exception.message(error)}"
                ForcedLoadHelpers.notify(config, message, :error)
                notify_webhook(get_webhook_url(config), business, "error", message)
                :ignore
        end
    end


    @impl true
    def handle_info(:update, %{mode: :direct_load, config: config} = state) do
        Logger.info("#{to_string(process_name(state))}. Iniciando la carga directa a BigQuery")

        DirectLoad.load(config)

        {:stop, :normal, state}
    end

    def handle_info(:update, %{mode: :sequence, business: business, params: params, configs: configs} = state) do
        name = to_string(process_name(state))
        Logger.info("#{name}. Iniciando #{length(configs)} cargas forzadas en secuencia")

        results = Enum.map(configs, fn config -> {Map.get(config, :business_name, "UNKNOWN"), run_in_sequence(business, params, config)} end)
        failed = for {business_name, {:error, message}} <- results, do: {business_name, message}

        ForcedLoadHelpers.notify(List.first(configs),
            """
            *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
            CARGAS FORZADAS EN SECUENCIA. FIN
            Completadas: #{length(results) - length(failed)}/#{length(results)}
            #{Enum.map_join(results, "\n", fn {business_name, result} -> "\t#{business_name}: #{if result == :ok, do: "completada", else: "fallida"}" end)}
            #{Enum.map_join(failed, "\n", fn {business_name, message} -> "Error en #{business_name}: #{message}" end)}
            *-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
            """,
            if(failed == [], do: :info, else: :warning)
        )

        Logger.info("#{name}. Cargas forzadas en secuencia completadas")
        {:stop, :normal, state}
    end

    def handle_info(:update, %{business: business, params: params, config: nil} = state) do
        Logger.info("#{to_string(process_name(state))}. Iniciando carga forzada (usando protocolo)")

        try do
            Genserver.Protocols.PForcedLoad.run(business, params)
        rescue
            error ->
                reraise error, __STACKTRACE__
        end

        Logger.info("#{to_string(process_name(state))}. Carga forzada completada")
        {:stop, :normal, state}
    end

    def handle_info(:update, %{business: business, params: params, config: config} = state) do
        webhook_url = get_webhook_url(config)
        Logger.info("#{to_string(process_name(state))}. Iniciando carga forzada (usando handler)")
        notify_webhook(webhook_url, business, "in_progress", "Carga forzada iniciada (usando handler)")

        try do
            ForcedLoadHandler.run(business, params, config)
            notify_webhook(webhook_url, business, "completed", "Carga forzada completada exitosamente")
        rescue
            error ->
                notify_webhook(webhook_url, business, "error", "Carga forzada fallida: #{inspect(error)}")
                reraise error, __STACKTRACE__
        end

        Logger.info("#{to_string(process_name(state))}. Carga forzada completada")
        {:stop, :normal, state}
    end


    @impl true
    def terminate(:normal, state) do
        Logger.info("#{to_string(process_name(state))}. Proceso terminado normalmente")
        :ok
    end

    def terminate(reason, %{business: business, config: config} = state) do
        Logger.warning("#{to_string(process_name(state))}. Proceso terminado con razón: #{inspect(reason)}")

        if reason != :normal do
            notify_webhook(get_webhook_url(config), business, "error", "Proceso terminado inesperadamente: #{inspect(reason)}")
        end

        :ok
    end


    # Private Functions

    #
    # Runs one forced load of a sequence: validates its configuration and runs it. A failure does not stop the sequence: it is notified (log and Slack) and returned.
    #
    # ### Parameters
    #     - business: Atom. Business type (e.g. :record)
    #     - params: List. [start_date, end_date]
    #     - config: Map. Configuration of the forced load
    #
    # ### Returns
    #     - :ok | {:error, message}
    #
    defp run_in_sequence(business, params, config) do
        webhook_url = get_webhook_url(config)
        notify_webhook(webhook_url, business, "in_progress", "Carga forzada iniciada: #{Map.get(config, :business_name, "UNKNOWN")}")

        result =
            try do
                ForcedLoadHelpers.validate_direct_load!(config)

                case ForcedLoadHandler.run(business, params, config) do
                    :ok -> :ok
                    {:error, reason} -> {:error, inspect(reason)}
                end
            rescue
                error -> {:error, Exception.message(error)}
            catch
                :exit, reason -> {:error, inspect(reason)}
            end

        case result do
            :ok ->
                notify_webhook(webhook_url, business, "completed", "Carga forzada completada: #{Map.get(config, :business_name, "UNKNOWN")}")

            {:error, message} ->
                ForcedLoadHelpers.notify(config, "CARGA FORZADA. #{Map.get(config, :business_name, "UNKNOWN")}. Error: #{message}. Se continúa con la siguiente carga de la secuencia", :error)
                notify_webhook(webhook_url, business, "error", "Carga forzada fallida: #{message}")
        end

        result
    end


    defp get_webhook_url(nil), do: nil
    defp get_webhook_url(config) when is_map(config), do: Map.get(config, :webhook_url)

    defp notify_webhook(nil, _business, _status, _message), do: :ok

    defp notify_webhook(webhook_url, business, status, message) when is_binary(webhook_url) do
        payload = %{
            status: status,
            business: to_string(business),
            message: message,
            timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        Task.start(fn ->
            case Poison.encode(payload) do
                {:ok, body} ->
                    case Http.post(body, webhook_url, [{"Content-Type", "application/json"}]) do
                        {:ok, _response} ->
                            Logger.debug("#{__MODULE__}. Notificación webhook enviada: #{status}")
                        {:error, error} ->
                            Logger.warning("#{__MODULE__}. Error al enviar notificación webhook: #{inspect(error)}")
                    end
                {:error, error} ->
                    Logger.warning("#{__MODULE__}. Error al codificar payload del webhook: #{inspect(error)}")
            end
        end)

        :ok
    end

    defp notify_webhook(_webhook_url, _business, _status, _message), do: :ok


end
