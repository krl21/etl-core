
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
    alias Connection.Http


    @doc """
    Child specification for the supervisor.

    Uses `restart: :temporary` so the process won't be restarted after it terminates.
    """
    def child_spec(arg) do
        %{
            id: __MODULE__,
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
    - Map with `:business`, `:params`, and optionally `:config` keys
    """
    def start_link({business, params, config}) when is_map(config) do
        GenServer.start_link(__MODULE__, %{business: business, params: params, config: config}, name: :"#{__MODULE__}.#{business}")
    end

    def start_link({business, params}) do
        GenServer.start_link(__MODULE__, %{business: business, params: params, config: nil}, name: :"#{__MODULE__}.#{business}")
    end

    def start_link(%{business: business} = info) do
        state = Map.merge(%{config: nil}, info)
        GenServer.start_link(__MODULE__, state, name: :"#{__MODULE__}.#{business}")
    end


    @impl true
    def init(%{business: business, config: config} = state) do
        Monitor.register(self(), to_string(__MODULE__) <> "." <> to_string(business))

        Logger.info("#{to_string(__MODULE__)}. CARGA FORZADA: Inicializando. Negocio: ---#{to_string(business)}---")

        notify_webhook(get_webhook_url(config), business, "started", "Proceso de carga forzada inicializado")

        :erlang.send_after(10_000, self(), :update)
        {:ok, state}
    end


    @impl true
    def handle_info(:update, %{business: business, params: params, config: nil} = state) do
        Logger.info("#{to_string(__MODULE__)}. Iniciando carga forzada en ---#{business}--- (usando protocolo)")

        try do
            Genserver.Protocols.PForcedLoad.run(business, params)
        rescue
            error ->
                reraise error, __STACKTRACE__
        end

        Logger.info("#{to_string(__MODULE__)}. Carga forzada completada. Terminando ---#{business}---")
        {:stop, :normal, state}
    end

    def handle_info(:update, %{business: business, params: params, config: config} = state) do
        webhook_url = get_webhook_url(config)
        Logger.info("#{to_string(__MODULE__)}. Iniciando carga forzada en ---#{business}--- (usando handler)")
        notify_webhook(webhook_url, business, "in_progress", "Carga forzada iniciada (usando handler)")

        try do
            ForcedLoadHandler.run(business, params, config)
            notify_webhook(webhook_url, business, "completed", "Carga forzada completada exitosamente")
        rescue
            error ->
                notify_webhook(webhook_url, business, "error", "Carga forzada fallida: #{inspect(error)}")
                reraise error, __STACKTRACE__
        end

        Logger.info("#{to_string(__MODULE__)}. Carga forzada completada. Terminando ---#{business}---")
        {:stop, :normal, state}
    end


    @impl true
    def terminate(:normal, %{business: business}) do
        Logger.info("#{to_string(__MODULE__)}. Proceso terminado normalmente. Negocio: ---#{business}---")
        :ok
    end

    def terminate(reason, %{business: business, config: config}) do
        Logger.warning("#{to_string(__MODULE__)}. Proceso terminado con razón: #{inspect(reason)}. Negocio: ---#{business}---")

        if reason != :normal do
            notify_webhook(get_webhook_url(config), business, "error", "Proceso terminado inesperadamente: #{inspect(reason)}")
        end

        :ok
    end


    # Private Functions

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
