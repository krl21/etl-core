
defmodule Genserver.RabbitConsumer do
    @moduledoc """
    GenServer continuous consumer for RabbitMQ queues.

    Supports two operation modes for PostgreSQL:

    - **Pool Mode** (recommended): Uses a connection pool.
        Configure with `pg_pool_name` in the `info` map.

    - **Legacy Mode**: Opens a dedicated connection at startup.
        Configure with `pg_config` in the `info` map.

    If the AMQP connection drops (e.g. `socket_closed`), the process stops so the
    application supervisor can restart it and consumption resumes. Unacked messages
    are requeued by RabbitMQ.

    ## Pool Mode

        info = %{
            pg_pool_name: :postgres_pool,
            webhook_url: "https://..."
        }

    ## Legacy Mode

        info = %{
            pg_config: postgres_config,
            webhook_url: "https://..."
        }
    """

    require Logger
    import Genserver.Protocols.PWorker
    import Stuff, only: [random_string_generate: 1]
    alias Genserver.Monitor
    alias Notification.Notify
    alias Connection.Postgres

    @doc """
    Starts the RabbitMQ consumer GenServer.

    ## Parameters
        - `args` (tuple) - Tuple with three elements:
            - `queue_info` (map) - Queue configuration with:
            - `:business` (atom) - Business identifier
            - `:config` (map) - RabbitMQ queue configuration
            - `configuration_amqp` - AMQP connection configuration
            - `info` (map) - Additional information with:
            - `:pg_pool_name` (atom, optional) - PostgreSQL pool name (pool mode)
            - `:pg_config` (map, optional) - PostgreSQL configuration (legacy mode)
            - `:webhook_url` (string) - URL for Slack notifications

    ## Returns
        - `{:ok, pid}` - GenServer started
        - `{:error, reason}` - Error starting the GenServer
    """
    def start_link({%{config: %{queue: queue}} = _queue_info, _configuration_amqp, _info} = args) do
        GenServer.start_link(__MODULE__, args, name: :"#{__MODULE__}.#{queue}")
    end

    @doc """
    Initializes the GenServer.
    """
    def init({%{business: business, config: %{queue: queue} = queue_info}, configuration_amqp, info}) do
        Monitor.register(self(), to_string(__MODULE__) <> "." <> to_string(business) <> "." <> to_string(queue))

        Logger.info("#{to_string(__MODULE__)}. Inicializando. Cola asociada: ---#{to_string(queue)}---")

        {:ok, connection} = configuration_amqp |> AMQP.Connection.open()
        {:ok, channel} = AMQP.Channel.open(connection)
        Process.link(channel.pid)

        setup_queue(channel, queue_info)

        prefetch_count = Map.get(queue_info, :prefetch_count, 50)
        :ok = AMQP.Basic.qos(channel, prefetch_count: prefetch_count)

        {:ok, _consumer_tag} = AMQP.Basic.consume(channel, queue)

        info_with_conn = setup_postgres_connection(info, queue)

        conn_monitor = Process.monitor(connection.pid)

        {:ok, %{
            channel: channel,
            connection: connection,
            queue: queue,
            business: business,
            info: info_with_conn,
            conn_monitor: conn_monitor
        }}
    end

    @doc """
    Handles the confirmation of registration as a consumer.
    """
    def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
        Logger.info("#{to_string(__MODULE__)}. Consumidor registrado con tag: #{consumer_tag}")
        {:noreply, state}
    end

    @doc """
    Handles the unexpected cancellation of the consumer.
    """
    def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, %{queue: queue, info: info} = state) do
        message = "#{to_string(__MODULE__)}. Consumidor cancelado inesperadamente: #{consumer_tag}. Cola: #{queue}"
        Logger.error(message)
        notify_error(info, message)
        {:stop, :consumer_cancelled, state}
    end

    @doc """
    Handles the confirmation of cancellation of the consumer.
    """
    def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, state) do
        Logger.info("#{to_string(__MODULE__)}. Cancelación de consumidor confirmada: #{consumer_tag}")
        {:noreply, state}
    end

    @doc """
    AMQP connection process died (e.g. socket closed). Stop so the supervisor restarts the consumer.
    """
    def handle_info(
          {:DOWN, ref, :process, _pid, reason},
          %{conn_monitor: ref, queue: queue, info: info} = state
        ) do
        Process.demonitor(ref, [:flush])

        message =
            "#{to_string(__MODULE__)}. Conexión AMQP caída (#{inspect(reason)}). Cola: #{queue}. El supervisor reiniciará el consumidor; mensajes sin ack volverán a la cola."

        Logger.error(message)
        notify_error(info, message)
        {:stop, {:amqp_connection_down, reason}, state}
    end

    @doc """
    Handles incoming messages from the queue.
    """
    def handle_info(
          {:basic_deliver, payload, %{delivery_tag: delivery_tag}},
          %{channel: channel, queue: queue, business: business, info: info} = state
        ) do

        try do
            payload
            |> Poison.decode()
            |> case do
                {:ok, msg_decode} ->
                    [msg_decode]
                    |> perform(
                        random_string_generate(15),
                        business,
                        info
                    )

                    AMQP.Basic.ack(channel, delivery_tag)

                {:error, reason} ->
                    message =
                        "#{to_string(__MODULE__)}. Error al decodificar mensaje: #{inspect(reason)}. Cola: #{queue}"

                    Logger.error(message)
                    notify_error(info, message)
                    AMQP.Basic.reject(channel, delivery_tag, requeue: false)
            end
        rescue
            e ->
                stacktrace = __STACKTRACE__

                message =
                    "#{to_string(__MODULE__)}. Error inesperado al procesar mensaje: #{Exception.message(e)}. Cola: #{queue} \nPayload: #{inspect(payload)}"

                Logger.error(message)
                Logger.error(Exception.format(:error, e, stacktrace))
                AMQP.Basic.reject(channel, delivery_tag, requeue: false)
                notify_error(info, message)

        end

        {:noreply, state}
    end

    #
    # Configures a RabbitMQ queue
    #
    # Parameters:
    #     - channel: channel with the channel
    #     - queue: map with the queue configuration
    #
    # Returns:
    #     - :ok: if the queue is configured successfully
    #     - :error: if the queue is not configured successfully
    #
    defp setup_queue(channel, %{queue: queue, exchange: exchange, queue_error: queue_error, queue_arguments: queue_arguments, listen: listen}) do
        Logger.info("#{to_string(__MODULE__)}. Configurando la cola ---#{to_string(queue)}---")

        {:ok, _} = AMQP.Queue.declare(channel, queue_error, durable: true)
        {:ok, info} = AMQP.Queue.declare(channel, queue, durable: true, arguments: queue_arguments)

        Logger.debug("#{to_string(__MODULE__)}. Estado: #{inspect(info)}")

        :ok = AMQP.Exchange.fanout(channel, exchange, durable: true)
        :ok = AMQP.Queue.bind(channel, queue, exchange)

        Enum.each(listen, fn exchange_to_hear ->
            :ok = AMQP.Exchange.fanout(channel, exchange_to_hear, durable: true)
            :ok = AMQP.Exchange.bind(channel, exchange, exchange_to_hear)
        end)
    end

    #
    # Sends an error notification to Slack
    #
    # Parameters:
    #     - webhook_url: string with the webhook URL
    #     - message: string with the message
    #
    # Returns:
    #     - :ok: if the notification is sent successfully
    #
    defp notify_error(%{webhook_url: webhook_url}, message) when is_binary(webhook_url) and webhook_url != "" do
        Notify.notify_slack(
            webhook_url,
            [{"Content-type", "application/json"}],
            "RabbitMQ Consumer",
            message
        )
    end

    defp notify_error(_, _), do: :ok

    #
    # Opens a PostgreSQL connection (only legacy mode)
    #
    # Parameters:
    #     - pg_config: map with the PostgreSQL configuration
    #     - queue: string with the queue name
    #
    # Returns:
    #     - :ok: if the connection is opened successfully
    defp open_postgres_connection(nil, queue) do
        Logger.warning("#{to_string(__MODULE__)}. No se proporcionó configuración de PostgreSQL para la cola: #{queue}")
        nil
    end

    defp open_postgres_connection(pg_config, queue) do
        Logger.debug("#{to_string(__MODULE__)}. Abriendo conexión a PostgreSQL para la cola: #{queue}")

        case Postgres.connect(pg_config) do
            {:ok, conn} ->
                Logger.info("#{to_string(__MODULE__)}. Conexión a PostgreSQL establecida para la cola: #{queue}")
                conn

            {:error, reason} ->
                Logger.error("#{to_string(__MODULE__)}. Error al conectar a PostgreSQL para la cola #{queue}: #{inspect(reason)}")
                nil
        end
    end

    #
    # Configures the PostgreSQL connection according to the available mode
    #
    # Parameters:
    #     - info: map with the information
    #     - queue: string with the queue name
    #
    # Returns:
    #     - map with the information
    #
    defp setup_postgres_connection(info, queue) do
        cond do
            Map.has_key?(info, :pg_pool_name) ->
                Logger.info("#{to_string(__MODULE__)}. Usando pool de PostgreSQL: #{info.pg_pool_name} para cola: #{queue}")
                Map.put(info, :pg_mode, :pool)

            Map.has_key?(info, :pg_config) ->
                pg_conn = open_postgres_connection(info[:pg_config], queue)

                info
                |> Map.put(:pg_conn, pg_conn)
                |> Map.put(:pg_mode, :legacy)

            true ->
                Logger.warning("#{to_string(__MODULE__)}. No se proporcionó configuración de PostgreSQL para la cola: #{queue}")
                Map.put(info, :pg_mode, :none)
        end
    end

    @doc """
    Handles the termination of the GenServer.
    """
    def terminate(reason, %{queue: queue, info: info, connection: connection}) do
        Logger.info("#{to_string(__MODULE__)}. Terminando (#{inspect(reason)}). Cola: ---#{queue}---")

        close_amqp_safely(connection)

        if info[:pg_mode] == :legacy and info[:pg_conn] do
            Logger.debug("#{to_string(__MODULE__)}. Cerrando conexión a PostgreSQL")
            Postgres.disconnect(info[:pg_conn])
        end

        :ok
    end

    #
    # Closes the AMQP connection safely.
    # Closing the connection also closes all its channels (AMQP protocol guarantee).
    #
    defp close_amqp_safely(%AMQP.Connection{pid: pid} = connection) when is_pid(pid) do
        if Process.alive?(pid) do
            try do
                AMQP.Connection.close(connection)
            catch
                _, _ -> :ok
            end
        else
            :ok
        end
    end

    defp close_amqp_safely(_), do: :ok

end
