
defmodule Genserver.RabbitConsumer do
    @moduledoc """
    Continuous consumer GenServer for RabbitMQ queues.
    """

    require Logger
    import Genserver.Protocols.PWorker
    import Stuff, only: [random_string_generate: 1]
    alias Genserver.Monitor
    alias Notification.Notify
    alias Connection.Postgres


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

        {:ok, _consumer_tag} = AMQP.Basic.consume(channel, queue)

        pg_conn = open_postgres_connection(info[:pg_config], queue)
        info_with_conn = Map.put(info, :pg_conn, pg_conn)

        {:ok, {channel, queue, business, info_with_conn}}
    end

    # Confirmation sent by the broker after registering this process as a consumer
    def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
        Logger.info("#{to_string(__MODULE__)}. Consumidor registrado con tag: #{consumer_tag}")
        {:noreply, state}
    end

    # Sent by the broker when the consumer is unexpectedly cancelled
    def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, {_channel, queue, _business, info} = state) do
        message = "#{to_string(__MODULE__)}. Consumidor cancelado inesperadamente: #{consumer_tag}. Cola: #{queue}"
        Logger.error(message)
        notify_error(info, message)
        {:stop, :consumer_cancelled, state}
    end

    # Confirmation sent by the broker to the consumer process after a Basic.cancel
    def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, state) do
        Logger.info("#{to_string(__MODULE__)}. Cancelación de consumidor confirmada: #{consumer_tag}")
        {:noreply, state}
    end

    # Handle incoming messages from the queue
    def handle_info({:basic_deliver, payload, %{delivery_tag: delivery_tag}}, {channel, queue, business, info} = state) do
        Logger.debug("#{to_string(__MODULE__)}. Mensaje recibido en cola: #{queue}")

        case ensure_postgres_connection(info, queue) do
            {:ok, updated_info} ->
                # Conexión activa, procesar mensaje normalmente
                process_message(payload, delivery_tag, channel, queue, business, updated_info)
                {:noreply, {channel, queue, business, updated_info}}

            {:retry, updated_info} ->
                Logger.warning("#{to_string(__MODULE__)}. Mensaje retenido en proceso hasta que se restablezca conexión a PostgreSQL. Cola: #{queue}")
                notify_error(info, "Mensaje retenido en proceso hasta que se restablezca conexión a PostgreSQL. Cola: #{queue}")
                pending_message = %{payload: payload, delivery_tag: delivery_tag}
                updated_info_with_pending = Map.put(updated_info, :pending_message, pending_message)
                {:noreply, {channel, queue, business, updated_info_with_pending}}
        end
    end

    # Handle retry connection after 20 seconds
    def handle_info(:retry_postgres_connection, {channel, queue, business, info} = state) do
        Logger.info("#{to_string(__MODULE__)}. Reintentando conexión a PostgreSQL después de 20 segundos. Cola: #{queue}")

        case reconnect_postgres(info, queue) do
            {:ok, new_conn} ->
                Logger.info("#{to_string(__MODULE__)}. Reconexión a PostgreSQL exitosa. Cola: #{queue}")
                updated_info = Map.put(info, :pg_conn, new_conn)

                # Procesar mensaje pendiente si existe
                case Map.get(info, :pending_message) do
                    nil ->
                        Logger.debug("#{to_string(__MODULE__)}. No hay mensajes pendientes. Cola: #{queue}")
                        {:noreply, {channel, queue, business, updated_info}}

                    %{payload: payload, delivery_tag: delivery_tag} ->
                        Logger.info("#{to_string(__MODULE__)}. Procesando mensaje pendiente después de reconexión. Cola: #{queue}")
                        process_message(payload, delivery_tag, channel, queue, business, updated_info)
                        updated_info_clean = Map.delete(updated_info, :pending_message)
                        {:noreply, {channel, queue, business, updated_info_clean}}
                end

            {:error, reason} ->
                Logger.error("#{to_string(__MODULE__)}. Fallo en reintento de conexión a PostgreSQL: #{inspect(reason)}. Cola: #{queue}. Programando nuevo reintento en 20 segundos.")
                notify_error(info, "Fallo en reintento de conexión a PostgreSQL: #{inspect(reason)}. Cola: #{queue}. Programando nuevo reintento en 20 segundos.")
                schedule_retry_connection()
                {:noreply, state}
        end
    end

    #
    # Processes a message from the queue.
    # Decodes the payload, performs the business logic, and acknowledges or rejects the message.
    #
    defp process_message(payload, delivery_tag, channel, queue, business, info) do
        payload
        |> Poison.decode()
        |> case do
            {:ok, msg_decode} ->
                Logger.debug("#{to_string(__MODULE__)}. Procesando mensaje. Cola: #{queue}")

                [msg_decode]
                |> perform(
                    random_string_generate(15),
                    business,
                    info
                )

                AMQP.Basic.ack(channel, delivery_tag)
                Logger.debug("#{to_string(__MODULE__)}. Mensaje procesado y confirmado. Cola: #{queue}")

            {:error, reason} ->
                message = "#{to_string(__MODULE__)}. Error al decodificar mensaje: #{inspect(reason)}. Cola: #{queue}"
                Logger.error(message)
                notify_error(info, message)
                AMQP.Basic.reject(channel, delivery_tag, requeue: false)
        end
    end

    #
    # Ensures the PostgreSQL connection is active before processing a message.
    # If not active, attempts to reconnect. If reconnection fails, schedules a retry.
    #
    # ### Parameters
    #     - info: Map. Current info map containing :pg_conn and :pg_config
    #     - queue: String. Queue name for logging purposes
    #
    # ### Returns
    #     - {:ok, updated_info} - Connection is active or was successfully reconnected
    #     - {:retry, updated_info} - Reconnection failed, retry scheduled
    #
    defp ensure_postgres_connection(%{pg_conn: nil} = info, queue) do
        Logger.warning("#{to_string(__MODULE__)}. Conexión a PostgreSQL es nil. Intentando reconectar. Cola: #{queue}")
        attempt_reconnection(info, queue)
    end

    defp ensure_postgres_connection(%{pg_conn: pg_conn} = info, queue) do
        if connection_alive?(pg_conn) do
            Logger.debug("#{to_string(__MODULE__)}. Conexión a PostgreSQL activa. Cola: #{queue}")
            {:ok, info}
        else
            Logger.warning("#{to_string(__MODULE__)}. Conexión a PostgreSQL no está activa. Intentando reconectar. Cola: #{queue}")
            attempt_reconnection(info, queue)
        end
    end

    defp ensure_postgres_connection(info, queue) do
        Logger.warning("#{to_string(__MODULE__)}. No existe pg_conn en info. Intentando crear conexión. Cola: #{queue}")
        attempt_reconnection(info, queue)
    end

    #
    # Checks if the PostgreSQL connection process is alive.
    #
    # ### Parameters
    #     - conn: pid | Map. PostgreSQL connection (simple or dual mode)
    #
    # ### Returns
    #     - true - Connection is alive
    #     - false - Connection is dead
    #
    defp connection_alive?(%{mode: :dual, read: read_conn, write: write_conn}) do
        read_alive = Process.alive?(read_conn)
        write_alive = Process.alive?(write_conn)

        unless read_alive and write_alive do
            Logger.debug("#{to_string(__MODULE__)}. Estado conexión dual - read: #{read_alive}, write: #{write_alive}")
        end

        read_alive and write_alive
    end

    defp connection_alive?(conn) when is_pid(conn) do
        Process.alive?(conn)
    end

    defp connection_alive?(_), do: false

    #
    # Attempts to reconnect to PostgreSQL.
    # If successful, returns {:ok, updated_info}.
    # If failed, schedules a retry in 20 seconds and returns {:retry, info}.
    #
    # ### Parameters:
    #     - info: Map. Current info map containing :pg_config
    #     - queue: String. Queue name for logging purposes
    #
    # ### Returns:
    #     - {:ok, updated_info} - Connection is active or was successfully reconnected
    #     - {:retry, updated_info} - Reconnection failed, retry scheduled
    #
    defp attempt_reconnection(info, queue) do
        case reconnect_postgres(info, queue) do
            {:ok, new_conn} ->
                Logger.info("#{to_string(__MODULE__)}. Reconexión a PostgreSQL exitosa. Cola: #{queue}")
                {:ok, Map.put(info, :pg_conn, new_conn)}

            {:error, reason} ->
                Logger.error("#{to_string(__MODULE__)}. Error al reconectar a PostgreSQL: #{inspect(reason)}. Cola: #{queue}. Reintentando en 20 segundos.")
                schedule_retry_connection()
                {:retry, info}
        end
    end

    #
    # Reconnects to PostgreSQL using the stored configuration.
    #
    defp reconnect_postgres(%{pg_config: pg_config}, queue) when not is_nil(pg_config) do
        Logger.info("#{to_string(__MODULE__)}. Iniciando reconexión a PostgreSQL. Cola: #{queue}")
        Postgres.connect(pg_config)
    end

    defp reconnect_postgres(info, queue) do
        Logger.error("#{to_string(__MODULE__)}. No hay configuración de PostgreSQL disponible para reconectar. Cola: #{queue}")
        {:error, :no_pg_config}
    end

    #
    # Schedules a retry connection attempt after 20 seconds.
    #
    defp schedule_retry_connection do
        Process.send_after(self(), :retry_postgres_connection, 20_000)
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
    # Opens a PostgreSQL connection if configuration is provided.
    #
    # ### Parameters
    #     - pg_config: Map | nil. PostgreSQL connection configuration
    #     - queue: String. Queue name for logging purposes
    #
    # ### Returns
    #     - pid | Map | nil
    #
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
    # Terminates the GenServer and closes the PostgreSQL connection.
    #
    def terminate(reason, {_channel, queue, _business, info}) do
        Logger.info("#{to_string(__MODULE__)}. Terminando (#{inspect(reason)}). Cola: ---#{queue}---")

        if info[:pg_conn] do
            Logger.debug("#{to_string(__MODULE__)}. Cerrando conexión a PostgreSQL")
            Postgres.disconnect(info[:pg_conn])
        end

        :ok
    end

end
