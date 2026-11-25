
defmodule Genserver.Amqp.Adapter do
    @moduledoc """
    Default, real implementation of `Genserver.Amqp.Behaviour` — a thin
    passthrough to the actual `AMQP.*` functions. This is what
    `EtlCore.Deps.amqp/0` resolves to unless a test overrides it.
    """

    @behaviour Genserver.Amqp.Behaviour

    @impl true
    def connection_open(config), do: AMQP.Connection.open(config)

    @impl true
    def connection_close(connection), do: AMQP.Connection.close(connection)

    @impl true
    def channel_open(connection), do: AMQP.Channel.open(connection)

    @impl true
    def channel_close(channel), do: AMQP.Channel.close(channel)

    @impl true
    def queue_declare(channel, name, opts), do: AMQP.Queue.declare(channel, name, opts)

    @impl true
    def queue_bind(channel, queue, exchange), do: AMQP.Queue.bind(channel, queue, exchange)

    @impl true
    def queue_message_count(channel, queue), do: AMQP.Queue.message_count(channel, queue)

    @impl true
    def exchange_fanout(channel, exchange, opts), do: AMQP.Exchange.fanout(channel, exchange, opts)

    @impl true
    def exchange_bind(channel, destination, source), do: AMQP.Exchange.bind(channel, destination, source)

    @impl true
    def basic_qos(channel, opts), do: AMQP.Basic.qos(channel, opts)

    @impl true
    def basic_consume(channel, queue), do: AMQP.Basic.consume(channel, queue)

    @impl true
    def basic_get(channel, queue), do: AMQP.Basic.get(channel, queue)

    @impl true
    def basic_ack(channel, delivery_tag), do: AMQP.Basic.ack(channel, delivery_tag)

    @impl true
    def basic_reject(channel, delivery_tag, opts), do: AMQP.Basic.reject(channel, delivery_tag, opts)

    @impl true
    def basic_publish(channel, exchange, routing_key, payload), do: AMQP.Basic.publish(channel, exchange, routing_key, payload)
end
