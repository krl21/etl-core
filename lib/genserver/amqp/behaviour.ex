
defmodule Genserver.Amqp.Behaviour do
    @moduledoc """
    Contract wrapping only the `AMQP.*` functions actually called in this
    library (`Genserver.RabbitConsumer`, `Genserver.RabbitConsumerByBatch`,
    `ForcedLoad.Handler.Loader`), so a test double can be generated with
    `Mox.defmock/2` and swapped in via `EtlCore.Deps.amqp/0`.

    Named with one prefixed function per underlying `AMQP.<Submodule>.<fun>`
    (e.g. `connection_open/1` for `AMQP.Connection.open/1`), since a single
    flat behaviour can't otherwise mirror several AMQP submodules at once.
    """

    @callback connection_open(config :: keyword()) :: {:ok, term()} | {:error, term()}
    @callback connection_close(connection :: term()) :: :ok
    @callback channel_open(connection :: term()) :: {:ok, term()} | {:error, term()}
    @callback channel_close(channel :: term()) :: :ok
    @callback queue_declare(channel :: term(), name :: String.t(), opts :: keyword()) :: {:ok, map()} | {:error, term()}
    @callback queue_bind(channel :: term(), queue :: String.t(), exchange :: String.t()) :: :ok
    @callback queue_message_count(channel :: term(), queue :: String.t()) :: non_neg_integer()
    @callback exchange_fanout(channel :: term(), exchange :: String.t(), opts :: keyword()) :: :ok
    @callback exchange_bind(channel :: term(), destination :: String.t(), source :: String.t()) :: :ok
    @callback basic_qos(channel :: term(), opts :: keyword()) :: :ok
    @callback basic_consume(channel :: term(), queue :: String.t()) :: {:ok, String.t()} | {:error, term()}
    @callback basic_get(channel :: term(), queue :: String.t()) :: term()
    @callback basic_ack(channel :: term(), delivery_tag :: term()) :: :ok
    @callback basic_reject(channel :: term(), delivery_tag :: term(), opts :: keyword()) :: :ok
    @callback basic_publish(channel :: term(), exchange :: String.t(), routing_key :: String.t(), payload :: String.t()) :: :ok
end
