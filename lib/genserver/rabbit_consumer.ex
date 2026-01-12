
defmodule Genserver.RabbitConsumer do
    @moduledoc """
    Continuous consumer GenServer for RabbitMQ queues.

    Manages PostgreSQL connection internally with automatic reconnection.
    If PostgreSQL is unavailable, the consumer PAUSES (stops consuming messages) leaving them untouched in the queue. When PostgreSQL reconnects, consumption resumes.
    """

    require Logger
    import Genserver.Protocols.PWorker
    import Stuff, only: [random_string_generate: 1]
    alias Genserver.Monitor
    alias Notification.Notify
    alias Connection.Postgres

    @pg_reconnect_interval 20_000  # 20 seconds


    def start_link({%{config: %{queue: queue}} = _queue_info, _configuration_amqp, _info} = args) do
        GenServer.start_link(__MODULE__, args, name: :"#{__MODULE__}.#{queue}")
    end

    def init({%{business: business, config: %{queue: queue} = queue_info}, configuration_amqp, info}) do
        Monitor.register(self(), to_string(__MODULE__) <> "." <> to_string(business) <> "." <> to_string(queue))

        Logger.info("#{to_string(__MODULE__)}. Inicializando. Cola asociada: ---#{to_string(queue)}---")

        {:ok, connection} = configuration_amqp |> AMQP.Connection.open()
        {:ok, channel} = AMQP.Channel.open(connection)

        setup_queue(channel, queue_info)

        :ok = AMQP.Basic.qos(channel, prefetch_count: 1)

        pg_config = extract_pg_config(info)

        {pg_conn, consumer_tag} =
            case init_postgres_connection(pg_config) do
                {:ok, conn} ->
                    {:ok, tag} = AMQP.Basic.consume(channel, queue)
                    Logger.info("#{to_string(__MODULE__)}. Consumidor iniciado. Cola: #{queue}")
                    {conn, tag}

                {:error, reason} ->
                    Logger.error("#{to_string(__MODULE__)}. PostgreSQL no disponible: #{inspect(reason)}. Cola: #{queue}. Esperando reconexión antes de consumir...")
                    notify_error(info, "PostgreSQL no disponible al iniciar. Cola: #{queue}. Mensajes pausados hasta reconexión.")
                    schedule_pg_reconnect()
                    {nil, nil}
            end

        state = %{
            channel: channel,
            queue: queue,
            business: business,
            info: info,
            pg_conn: pg_conn,
            pg_config: pg_config,
            consumer_tag: consumer_tag,
            consuming: consumer_tag != nil
        }

        {:ok, state}
    end

    # Confirmation sent by the broker after registering this process as a consumer
    def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
        Logger.info("#{to_string(__MODULE__)}. Consumidor registrado con tag: #{consumer_tag}")
        {:noreply, %{state | consumer_tag: consumer_tag, consuming: true}}
    end

    # Sent by the broker when the consumer is unexpectedly cancelled
    def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, %{queue: queue, info: info} = state) do
        message = "#{to_string(__MODULE__)}. Consumidor cancelado inesperadamente: #{consumer_tag}. Cola: #{queue}"
        Logger.error(message)
        notify_error(info, message)
        {:stop, :consumer_cancelled, state}
    end

    # Confirmation sent by the broker to the consumer process after a Basic.cancel
    def handle_info({:basic_cancel_ok, %{consumer_tag: _consumer_tag}}, %{queue: queue} = state) do
        Logger.info("#{to_string(__MODULE__)}. Consumo pausado. Cola: #{queue}. Mensajes permanecen en cola sin tocar.")
        {:noreply, %{state | consumer_tag: nil, consuming: false}}
    end

    # Handle PostgreSQL reconnection attempt
    def handle_info(:pg_reconnect, %{pg_config: nil} = state) do
        # No PostgreSQL config, nothing to reconnect
        {:noreply, state}
    end

    def handle_info(:pg_reconnect, %{pg_config: pg_config, channel: channel, queue: queue, info: info, consuming: consuming} = state) do
        Logger.info("#{to_string(__MODULE__)}. Intentando reconexión a PostgreSQL. Cola: #{queue}")

        case Postgres.connect(pg_config) do
            {:ok, conn} ->
                Logger.info("#{to_string(__MODULE__)}. Reconexión a PostgreSQL exitosa. Cola: #{queue}")
                notify_success(info, "Reconexión a PostgreSQL exitosa. Cola: #{queue}")
                monitor_pg_connection(conn)

                # Reanudar el consumo si se había pausado
                new_state =
                    if not consuming do
                        {:ok, tag} = AMQP.Basic.consume(channel, queue)
                        Logger.info("#{to_string(__MODULE__)}. Reanudando consumo de mensajes. Cola: #{queue}")
                        %{state | pg_conn: conn, consumer_tag: tag, consuming: true}
                    else
                        %{state | pg_conn: conn}
                    end

                {:noreply, new_state}

            {:error, reason} ->
                message = "#{to_string(__MODULE__)}. Fallo en reconexión a PostgreSQL: #{inspect(reason)}. Cola: #{queue}. Reintentando en #{div(@pg_reconnect_interval, 1000)}s..."
                Logger.error(message)
                notify_error(info, message)
                schedule_pg_reconnect()
                {:noreply, state}
        end
    end

    # Handle incoming messages from the queue
    def handle_info({:basic_deliver, payload, %{delivery_tag: delivery_tag}}, state) do
        %{
            channel: channel,
            queue: queue,
            business: business,
            info: info,
            pg_conn: pg_conn,
            pg_config: pg_config,
            consumer_tag: consumer_tag
        } = state

        case verify_pg_connection(pg_conn) do
            :ok ->
                process_message(payload, delivery_tag, channel, queue, business, info, pg_conn)
                {:noreply, state}

            :error ->
                Logger.error("#{to_string(__MODULE__)}. Conexión PostgreSQL perdida durante procesamiento. Cola: #{queue}")
                notify_error(info, "Conexión PostgreSQL perdida. Cola: #{queue}. Pausando consumo...")

                AMQP.Basic.reject(channel, delivery_tag, requeue: true)

                if consumer_tag do
                    AMQP.Basic.cancel(channel, consumer_tag)
                end

                new_conn = try_immediate_reconnect(pg_config)

                if new_conn do
                    {:ok, new_tag} = AMQP.Basic.consume(channel, queue)
                    Logger.info("#{to_string(__MODULE__)}. Reconexión inmediata exitosa. Reanudando consumo. Cola: #{queue}")
                    {:noreply, %{state | pg_conn: new_conn, consumer_tag: new_tag, consuming: true}}
                else
                    schedule_pg_reconnect()
                    {:noreply, %{state | pg_conn: nil, consumer_tag: nil, consuming: false}}
                end
        end
    end

    # Handle process DOWN messages (for monitored PostgreSQL connection)
    def handle_info({:DOWN, _ref, :process, pid, reason}, %{pg_conn: pg_conn, queue: queue, info: info, channel: channel, consumer_tag: consumer_tag} = state) do
        if is_pg_connection_pid?(pg_conn, pid) do
            message = "#{to_string(__MODULE__)}. Conexión PostgreSQL perdida (proceso terminó): #{inspect(reason)}. Cola: #{queue}"
            Logger.error(message)
            notify_error(info, message)

            if consumer_tag do
                AMQP.Basic.cancel(channel, consumer_tag)
            end

            schedule_pg_reconnect()
            {:noreply, %{state | pg_conn: nil, consumer_tag: nil, consuming: false}}
        else
            {:noreply, state}
        end
    end

    #
    # Checks if a pid belongs to the PostgreSQL connection.
    #
    # ### Parameters:
    #     - pg_conn: pid | Map. PostgreSQL connection.
    #     - pid: pid. Process ID.
    #
    # ### Returns:
    #     - Boolean. True if the pid belongs to the PostgreSQL connection, false otherwise.
    #
    defp is_pg_connection_pid?(pg_conn, pid) when is_pid(pg_conn), do: pid == pg_conn
    defp is_pg_connection_pid?(%{mode: :dual, read: read, write: write}, pid), do: pid == read or pid == write
    defp is_pg_connection_pid?(_, _), do: false


    #
    # Extracts PostgreSQL config from info map.
    #
    # ### Parameters:
    #     - info: Map. Info map containing the PostgreSQL configuration.
    #
    # ### Returns:
    #     - Map. PostgreSQL configuration.
    #
    defp extract_pg_config(%{pg_config: pg_config}) when is_map(pg_config), do: pg_config
    defp extract_pg_config(_), do: nil

    #
    # Initializes PostgreSQL connection.
    #
    # ### Parameters:
    #     - pg_config: Map. PostgreSQL configuration.
    #
    # ### Returns:
    #     - {:ok, conn} | {:error, reason}. Connection or error.
    #
    defp init_postgres_connection(nil), do: {:ok, nil}

    defp init_postgres_connection(pg_config) when is_map(pg_config) do
        case Postgres.connect(pg_config) do
            {:ok, conn} ->
                Logger.info("#{to_string(__MODULE__)}. Conexión inicial a PostgreSQL establecida")
                monitor_pg_connection(conn)
                {:ok, conn}

            {:error, reason} ->
                {:error, reason}
        end
    end

    #
    # Monitors PostgreSQL connection process(es).
    #
    defp monitor_pg_connection(%{mode: :dual, read: read_conn, write: write_conn}) do
        Process.monitor(read_conn)
        Process.monitor(write_conn)
    end

    defp monitor_pg_connection(conn) when is_pid(conn) do
        Process.monitor(conn)
    end

    defp monitor_pg_connection(_), do: :ok

    #
    # Verifies PostgreSQL connection is alive.
    # Returns :ok or :error
    #
    defp verify_pg_connection(nil), do: :ok

    defp verify_pg_connection(%{mode: :dual, read: read_conn, write: write_conn}) do
        if Process.alive?(read_conn) and Process.alive?(write_conn), do: :ok, else: :error
    end

    defp verify_pg_connection(conn) when is_pid(conn) do
        if Process.alive?(conn), do: :ok, else: :error
    end

    #
    # Tries to reconnect immediately to PostgreSQL.
    #
    # ### Parameters:
    #     - pg_config: Map. PostgreSQL configuration.
    #
    # ### Returns:
    #     - pid | Map. PostgreSQL connection.
    #     - nil.
    #
    defp try_immediate_reconnect(nil), do: nil

    defp try_immediate_reconnect(pg_config) do
        case Postgres.connect(pg_config) do
            {:ok, conn} ->
                monitor_pg_connection(conn)
                conn
            {:error, _} ->
                nil
        end
    end

    #
    # Processes a message from the queue.
    #
    # ### Parameters:
    #     - payload: String. Message payload.
    #     - delivery_tag: Integer. Delivery tag.
    #     - channel: AMQP.Channel. Rabbit connection channel.
    #     - queue: String. Queue name.
    #     - business: String. Business name.
    #     - info: Map. Info map containing the PostgreSQL configuration.
    #     - pg_conn: pid | Map. PostgreSQL connection.
    #
    # ### Returns:
    #     - :ok.
    #
    defp process_message(payload, delivery_tag, channel, queue, business, info, pg_conn) do
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
                message = "#{to_string(__MODULE__)}. Error al decodificar mensaje: #{inspect(reason)}. Cola: #{queue}"
                Logger.error(message)
                notify_error(info, message)
                AMQP.Basic.reject(channel, delivery_tag, requeue: false)
        end
    end

    #
    # Schedules a PostgreSQL reconnection attempt.
    #
    defp schedule_pg_reconnect do
        Process.send_after(self(), :pg_reconnect, @pg_reconnect_interval)
    end

    #
    # Set up a queue. The configuration consists of creating the queues and establishing
    # the relevant connections to the exchanges.
    #
    # ### Parameters:
    #     - channel: AMQP.Channel. Rabbit connection channel.
    #     - queue: Map. Queue definition.
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
    # Sends error notification to Slack if webhook_url is configured in info map.
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
    # Sends success notification to Slack if webhook_url is configured.
    #
    defp notify_success(%{webhook_url: webhook_url}, message) when is_binary(webhook_url) and webhook_url != "" do
        Notify.notify_slack(
            webhook_url,
            [{"Content-type", "application/json"}],
            "RabbitMQ Consumer - Recuperación",
            message
        )
    end
    defp notify_success(_, _), do: :ok

end
