
defmodule Genserver.ConsumerSupervisor do
    @moduledoc """
    DynamicSupervisor for RabbitMQ consumers.

    Manages the lifecycle of `Genserver.RabbitConsumer` and `Genserver.RabbitConsumerByBatch` children, allowing consumers to be started, stopped, and restarted at runtime by queue name.

    Maintains an internal ETS registry that maps queue names to their module and original startup args, so consumers can be restarted without the caller needing to keep the config.

    ## Adding to the supervision tree

        # In Application.start/2:
        children = [Pool.Postgres, Pool.BigQuery, Genserver.ConsumerSupervisor]
        {:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)
        Genserver.ConsumerSupervisor.start_consumers(rabbit_consumer_configs())

    ## Runtime control

        # Start a consumer
        ConsumerSupervisor.start_consumer(Genserver.RabbitConsumer, {queue_info, amqp_config, info})

        # Stop a consumer by queue name
        ConsumerSupervisor.stop_consumer("my_queue")

        # Restart a consumer (uses original startup args)
        ConsumerSupervisor.restart_consumer("my_queue")

        # Inspect all consumers
        ConsumerSupervisor.list_consumers()
        ConsumerSupervisor.consumer_status("my_queue")  # :running | :stopped | :not_found
    """

    use DynamicSupervisor
    require Logger

    @table :consumer_supervisor_registry

    def start_link(opts \\ []) do
        DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
    end

    def init(_opts) do
        :ets.new(@table, [:named_table, :public, :set])
        DynamicSupervisor.init(strategy: :one_for_one)
    end

    @doc """
    Starts a single consumer child under this supervisor.

    ### Parameters:
        - module: Atom. Consumer module to start (`Genserver.RabbitConsumer` or `Genserver.RabbitConsumerByBatch`).
        - args: Tuple. Args passed directly to `module.start_link/1`. Must include `%{config: %{queue: queue_name}}` as first element.

    ### Returns:
        - `{:ok, pid}`: Consumer started successfully.
        - `{:error, :already_running}`: A consumer for that queue is already active.
        - `{:error, reason}`: Supervisor failed to start the child.
    """
    def start_consumer(module, args) do
        queue_name = extract_queue_name(args)

        case consumer_status(queue_name) do
            :running ->
                Logger.warning("#{__MODULE__}. Consumer already running for queue: #{queue_name}")
                {:error, :already_running}

            _ ->
                child_spec = %{
                    id: {module, queue_name},
                    start: {module, :start_link, [args]},
                    restart: :permanent
                }

                case DynamicSupervisor.start_child(__MODULE__, child_spec) do
                    {:ok, pid} = result ->
                        :ets.insert(@table, {queue_name, module, args})
                        Logger.info("#{__MODULE__}. Consumer started for queue: #{queue_name}")
                        result

                    {:error, reason} = result ->
                        Logger.error("#{__MODULE__}. Failed to start consumer for queue: #{queue_name}. Reason: #{inspect(reason)}")
                        result
                end
        end
    end

    @doc """
    Starts multiple consumers at once.
    Typically called from the Application module right after `Supervisor.start_link/2`.

    ### Parameters:
        - consumers: List. List of `{module, args}` tuples, one per consumer to start.

    ### Returns:
        - `:ok`: All consumers have been processed (individual failures are logged but do not abort the rest).
    """
    def start_consumers(consumers) when is_list(consumers) do
        Enum.each(consumers, fn {module, args} -> start_consumer(module, args) end)
    end

    @doc """
    Stops the consumer for the given queue name.

    The consumer is terminated cleanly: its `terminate/2` callback runs, the AMQP connection
    is closed, and unacked messages are requeued by RabbitMQ. Once stopped, the consumer
    is removed from the supervisor and will not restart automatically.

    ### Parameters:
        - queue_name: String. Name of the RabbitMQ queue whose consumer should be stopped.

    ### Returns:
        - `:ok`: Consumer stopped successfully (or was already not running).
        - `{:error, :not_found}`: No consumer is registered for that queue name.
    """
    def stop_consumer(queue_name) do
        case :ets.lookup(@table, queue_name) do
            [] ->
                {:error, :not_found}

            [{^queue_name, module, _args}] ->
                :ets.delete(@table, queue_name)

                case find_pid(queue_name, module) do
                    nil ->
                        Logger.warning("#{__MODULE__}. Consumer for queue #{queue_name} was registered but not running.")
                        :ok

                    pid ->
                        result = DynamicSupervisor.terminate_child(__MODULE__, pid)
                        Logger.info("#{__MODULE__}. Consumer stopped for queue: #{queue_name}")
                        result
                end
        end
    end

    @doc """
    Stops and restarts the consumer for the given queue name using its original startup args.

    Useful to recover a consumer that is in a `:stopped` state without needing to supply
    the configuration again, since the supervisor retains the original args.

    ### Parameters:
        - queue_name: String. Name of the RabbitMQ queue whose consumer should be restarted.

    ### Returns:
        - `{:ok, pid}`: Consumer restarted successfully.
        - `{:error, :not_found}`: No consumer has ever been registered for that queue name.
        - `{:error, reason}`: Consumer failed to start after being stopped.
    """
    def restart_consumer(queue_name) do
        case :ets.lookup(@table, queue_name) do
            [] ->
                {:error, :not_found}

            [{^queue_name, module, args}] ->
                Logger.info("#{__MODULE__}. Restarting consumer for queue: #{queue_name}")
                stop_consumer(queue_name)
                start_consumer(module, args)
        end
    end

    @doc """
    Returns a list of all consumers registered in this supervisor, with their current status.

    ### Returns:
        - List of Map: Each entry contains:
            - `:queue` — String. Queue name.
            - `:module` — Atom. Consumer module.
            - `:pid` — PID or `nil`. Current process identifier, `nil` if not running.
            - `:status` — Atom. `:running` if the process is alive, `:stopped` otherwise.
    """
    def list_consumers do
        :ets.tab2list(@table)
        |> Enum.map(fn {queue_name, module, _args} ->
            pid = find_pid(queue_name, module)
            %{
                queue: queue_name,
                module: module,
                pid: pid,
                status: if(pid != nil and Process.alive?(pid), do: :running, else: :stopped)
            }
        end)
    end

    @doc """
    Returns the status of the consumer for the given queue name.

    ### Parameters:
        - queue_name: String. Name of the RabbitMQ queue to query.

    ### Returns:
        - `:running`: Process is alive and consuming messages.
        - `:stopped`: Consumer is registered but its process is not alive (e.g. exceeded `max_restarts`).
        - `:not_found`: No consumer has been started for this queue through this supervisor.
    """
    def consumer_status(queue_name) do
        case :ets.lookup(@table, queue_name) do
            [] ->
                :not_found

            [{^queue_name, module, _args}] ->
                pid = find_pid(queue_name, module)
                if pid != nil and Process.alive?(pid), do: :running, else: :stopped
        end
    end

    # Extracts the queue name from the args tuple of either consumer type.
    # RabbitConsumer:        {queue_info, amqp_config, info}
    # RabbitConsumerByBatch: {queue_info, amqp_config, batch_size, timeout, info}
    defp extract_queue_name({%{config: %{queue: queue}}, _, _}), do: queue
    defp extract_queue_name({%{config: %{queue: queue}}, _, _, _, _}), do: queue

    # Resolves the current PID via the registered name that each consumer sets on start_link.
    defp find_pid(queue_name, module) do
        Process.whereis(:"#{module}.#{queue_name}")
    end
end
