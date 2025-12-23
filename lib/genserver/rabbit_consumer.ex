
defmodule Genserver.RabbitConsumer do
    @moduledoc """
    Continuous consumer GenServer for RabbitMQ queues.
    """

    require Logger
    import Genserver.Protocols.PWorker
    # import Stuff, only: [random_string_generate: 1]
    alias Genserver.Monitor

    def start_link({%{config: %{queue: queue}} = _queue_info, _configuration_amqp, _info} = args) do
        GenServer.start_link(__MODULE__, args, name: :"#{__MODULE__}.#{queue}")
    end

    def init({%{business: business, config: %{queue: queue} = queue_info}, configuration_amqp, info}) do
        Monitor.register(self(), to_string(__MODULE__) <> "." <> to_string(business) <> "." <> to_string(queue))

        Logger.info("#{to_string(__MODULE__)}. Initializing. Associated queue: ---#{to_string(queue)}---")

        {:ok, connection} = configuration_amqp |> AMQP.Connection.open()
        {:ok, channel} = AMQP.Channel.open(connection)

        setup_queue(channel, queue_info)

        :ok = AMQP.Basic.qos(channel, prefetch_count: 1)

        {:ok, _consumer_tag} = AMQP.Basic.consume(channel, queue)

        {:ok, {channel, queue, business, info}}
    end

    # Confirmation sent by the broker after registering this process as a consumer
    def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
        Logger.info("#{to_string(__MODULE__)}. Consumer registered with tag: #{consumer_tag}")
        {:noreply, state}
    end

    # Sent by the broker when the consumer is unexpectedly cancelled
    def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, state) do
        Logger.error("#{to_string(__MODULE__)}. Consumer cancelled unexpectedly: #{consumer_tag}")
        {:stop, :consumer_cancelled, state}
    end

    # Confirmation sent by the broker to the consumer process after a Basic.cancel
    def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, state) do
        Logger.info("#{to_string(__MODULE__)}. Consumer cancel confirmed: #{consumer_tag}")
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
                    nil, #random_string_generate(15),
                    business,
                    info
                )

                AMQP.Basic.ack(channel, delivery_tag)

            {:error, reason} ->
                Logger.error("#{to_string(__MODULE__)}. Failed to decode message: #{inspect(reason)}")
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
        Logger.info("#{to_string(__MODULE__)}. Configuring the queue ---#{to_string(queue)}---")

        {:ok, _} = AMQP.Queue.declare(channel, queue_error, durable: true)
        {:ok, info} = AMQP.Queue.declare(channel, queue, durable: true, arguments: queue_arguments)

        Logger.debug("#{to_string(__MODULE__)}. State: #{inspect(info)}")

        :ok = AMQP.Exchange.fanout(channel, exchange, durable: true)
        :ok = AMQP.Queue.bind(channel, queue, exchange)

        Enum.each(listen, fn exchange_to_hear ->
            :ok = AMQP.Exchange.fanout(channel, exchange_to_hear, durable: true)
            :ok = AMQP.Exchange.bind(channel, exchange, exchange_to_hear)
        end)
    end



end
