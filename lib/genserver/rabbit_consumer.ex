
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
        # Logger.debug("#{to_string(__MODULE__)}. Message received on queue: #{queue}")

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

        {:noreply, state}
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
