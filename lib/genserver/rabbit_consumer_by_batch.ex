
defmodule Genserver.RabbitConsumerByBatch do
    @moduledoc"""
    Batch-oriented genserver of rabbit queues

    For the correct operation, you must implement the Genserver.utils.pWorker protocol
    """

    require Logger
    import Genserver.Utils.PWorker
    import Stuff, only: [random_string_generate: 1]
    import Connection.Odbc, only: [connect: 1]


    def start_link({%{config: %{queue: queue}} = _queue_info, _configuration_amqp, _batch_size, _data_source, _seconds_timeout} = info) do
        GenServer.start_link(__MODULE__, info, name: :"#{__MODULE__}.#{queue}")
    end

    def init({%{business: business, config: %{queue: queue} = queue_info}, configuration_amqp, batch_size, data_source, seconds_timeout}) do
        Logger.info("#{inspect __MODULE__}. Initializing RabbitConsumerByBatch. Associated queue: ---#{queue}---. Batch size: #{batch_size}")

        {:ok, connection} = configuration_amqp |> AMQP.Connection.open()
        {:ok, channel} = AMQP.Channel.open(connection)

        Logger.info("#{inspect __MODULE__}. Created the process to communicate with ODBC-BigQuery")
        pid_odbc = data_source |> connect()

        setup_queue(channel, queue_info)
        variable_wait(channel, queue, seconds_timeout)

        {:ok, {channel, queue, pid_odbc, batch_size, seconds_timeout, business}}
    end

    def handle_info(:update, {channel, queue, pid_odbc, batch_size, seconds_timeout, business}) do
        get_messages(channel, queue, batch_size)
        |> perform(
            random_string_generate(15),
            pid_odbc,
            business
        )

        variable_wait(channel, queue, seconds_timeout)

        {:noreply, {channel, queue, pid_odbc, batch_size, seconds_timeout}}
    end

    #
    # Set up a queue. The configuration consists of creating the queues and establishing the relevant connections to the exchanges
    #
    # ### Parameters:
    #
    #     - channel: AMQP.Channel. Rabbit connection channel.
    #
    #     - queue: Map. Queue definition.
    #
    defp setup_queue(channel, %{queue: queue, exchange: exchange, queue_error: queue_error, queue_arguments: queue_arguments, listen: listen}) do
        Logger.info("#{inspect __MODULE__}. Configuring the queue ---#{inspect queue}---")

        {:ok, _} = AMQP.Queue.declare(channel, queue_error, durable: true)
        {:ok, info} = AMQP.Queue.declare(channel, queue, durable: true, arguments: queue_arguments)

        Logger.debug("#{inspect __MODULE__}. State: #{inspect info}")

        :ok = AMQP.Exchange.fanout(channel, exchange, durable: true)
        :ok = AMQP.Queue.bind(channel, queue, exchange)

        Enum.each(listen, fn exchange_to_hear ->
            :ok = AMQP.Exchange.fanout(channel, exchange_to_hear, durable: true)
            :ok = AMQP.Exchange.bind(channel, exchange, exchange_to_hear)
        end)
    end

    #
    # Adjust the time for the activation of the genserver
    #
    # Parameter:
    #
    #     - queue_info: Map. Queue information from which your messages will be consumed.
    #
    #     - channel: AMQP.Channel. Channel.
    #
    #     - seconds_timeout: Integer. total seconds to reactivate the genserver.
    #
    defp variable_wait(channel, queue, seconds_timeout) do
        milliseconds =
            AMQP.Queue.message_count(channel, queue)
            |> Kernel.>(0)
            |> if do
                0
            else
                seconds_timeout * 1_000
            end

        # Logger.info("#{inspect __MODULE__}. Delay to execute: #{Tools.Stuff.convert_seconds_to_humans(milliseconds |> Kernel./(1_000) |> Type.convert(:integer))}")

        :erlang.send_after(milliseconds, self(), :update)
    end

    #
    # Gets the decoded messages from the queue to consume. In case of not being able to decode the messages, it sends them to the corresponding error queue.
    #
    # ### Parameters:
    #
    #     - channel: AMQP.Channel. Channel.
    #
    #     - queue: String. Name of the queue to consume.
    #
    #     - count: Integer. Number of messages to get. Positive value.
    #
    # ### Return:
    #
    #     - List of map. List of decoded messages.
    #
    defp get_messages(channel, queue, count) do
        get_messages(channel, queue, count, [])
    end

    defp get_messages(_, _, 0, acc) do
        acc
    end

    defp get_messages(channel, queue, count, acc) do
        AMQP.Basic.get(channel, queue)
        |> case do
            {:ok, msg, %{delivery_tag: delivery_tag}} ->
                payload =
                    msg
                    |> Poison.decode()
                    |> case do
                        {:ok, msg_decode} ->
                            AMQP.Basic.ack(channel, delivery_tag)
                            [msg_decode]

                        {:error, _} ->
                            AMQP.Basic.reject(channel, delivery_tag, requeue: false)
                            []
                    end

                get_messages(
                    channel,
                    queue,
                    count - 1,
                    acc ++ payload
                )

            {:empty, _} ->
                get_messages(
                    channel,
                    queue,
                    0,
                    acc
                )
        end
    end







end
