
defmodule Genserver.ConsumerBootstrap do
    @moduledoc """
    Registers the configured RabbitMQ consumers under `Genserver.ConsumerSupervisor` on init.

    `Genserver.ConsumerSupervisor` only rebuilds its ETS registry when it (re)starts; it does
    not know which consumers to start. This module carries that list and (re)starts them
    every time it initializes.

    Meant to run as the child immediately after `Genserver.ConsumerSupervisor` inside a
    `:rest_for_one` supervisor, e.g.:

        %{
            id: MyApp.ConsumersTree,
            start: {Supervisor, :start_link, [
                [
                    Genserver.ConsumerSupervisor,
                    {Genserver.ConsumerBootstrap, consumers}
                ],
                [strategy: :rest_for_one, name: MyApp.ConsumersTree]
            ]},
            type: :supervisor
        }

    If `ConsumerSupervisor` crashes (e.g. its restart intensity is exceeded by repeated AMQP
    connection drops) and gets restarted, `:rest_for_one` restarts this process too, which
    re-registers every consumer. Without this, consumers started only once at application
    boot would be lost for good after such a crash.
    """

    use GenServer
    require Logger

    @doc """
    Starts the bootstrap process.

    ## Parameters
        - `consumers` (list) - List of `{module, args}` tuples, same shape accepted by
          `Genserver.ConsumerSupervisor.start_consumers/1`.
    """
    def start_link(consumers) when is_list(consumers) do
        GenServer.start_link(__MODULE__, consumers, name: __MODULE__)
    end

    @impl true
    def init(consumers) do
        Logger.info("#{to_string(__MODULE__)}. Registrando #{length(consumers)} consumidor(es) de RabbitMQ.")
        Genserver.ConsumerSupervisor.start_consumers(consumers)
        {:ok, consumers}
    end
end
