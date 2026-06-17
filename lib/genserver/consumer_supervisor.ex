
defmodule Genserver.ConsumerSupervisor do
    @moduledoc """
    DynamicSupervisor for RabbitMQ consumers.
    """

    use DynamicSupervisor
    require Logger

    @table :consumer_supervisor_registry

    @doc """
    Starts the supervisor and registers it under its own module name.
    """
    def start_link(opts \\ []) do
        DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @doc """
    Initialises the supervisor and creates the ETS registry if it does not already exist.
    Safe to call more than once (e.g. after a supervisor crash and restart).
    """
    def init(_opts) do
        case :ets.whereis(@table) do
            :undefined ->
                :ets.new(@table, [:named_table, :public, :set])
            _tid ->
                @table
        end

        DynamicSupervisor.init(strategy: :one_for_one)
    end

    @doc """
    Starts a single consumer child under this supervisor.

    Behaviour depends on the current state of the queue:
      - :not_found — starts a new consumer with the given args.
      - :running   — returns the existing pid without restarting.
      - :stopped   — removes the stale entry and restarts with the given args.

    ## Parameters
      - module — consumer module (Genserver.RabbitConsumer or Genserver.RabbitConsumerByBatch).
      - args   — startup tuple passed to module.start_link/1. Must have %{config: %{queue: queue_name}} as first element.

    ## Returns
      - {:ok, pid} — consumer started (or already running).
      - {:error, reason} — supervisor failed to start the child.
    """
    def start_consumer(module, args) do
        queue_name = extract_queue_name(args)

        case consumer_status(queue_name) do
            :not_found ->
                do_start_consumer(module, args, queue_name)

            :running ->
                pid = find_pid(queue_name, module)
                Logger.info("#{__MODULE__} Consumer for #{queue_name} is already running. Returning existing pid.")
                {:ok, pid}

            :stopped ->
                Logger.info("#{__MODULE__} Consumer for #{queue_name} is registered but stopped. Restarting.")
                stop_consumer(queue_name)
                do_start_consumer(module, args, queue_name)
        end
    end

    @doc """
    Starts multiple consumers at once.
    Typically called from Application.start/2 right after Supervisor.start_link/2.

    ## Parameters
      - consumers — list of {module, args} tuples.

    ## Returns
      - :ok — all consumers processed (individual failures are logged but do not abort the rest).
    """
    def start_consumers(consumers) when is_list(consumers) do
        Enum.each(consumers, fn {module, args} -> start_consumer(module, args) end)
    end

    @doc """
    Stops the consumer for the given queue name.

    The consumer is terminated cleanly: its terminate/2 callback runs, the AMQP connection
    is closed, and unacked messages are requeued by RabbitMQ. The entry is removed from the
    registry and the consumer will not restart automatically.

    ## Parameters
      - queue_name — name of the RabbitMQ queue whose consumer should be stopped.

    ## Returns
      - :ok — consumer stopped (or was already not running).
      - {:error, :not_found} — no consumer is registered for that queue name.
    """
    def stop_consumer(queue_name) do
        case :ets.lookup(@table, queue_name) do
            [] ->
                {:error, :not_found}

            [{^queue_name, module, _args}] ->
                case find_pid(queue_name, module) do
                    nil ->
                        Logger.warning("#{__MODULE__} Consumer para #{queue_name} ya estaba detenido.")
                        :ok

                    pid ->
                        result = DynamicSupervisor.terminate_child(__MODULE__, pid)
                        Logger.info("#{__MODULE__} Consumer detenido para cola: #{queue_name}")
                        result
                end
        end
    end

    @doc """
    Stops the consumer and removes it permanently from the registry.

    Unlike `stop_consumer/1`, which keeps the entry so `restart_consumer/1` can bring it
    back, this function deletes the record entirely. After this call,
    `restart_consumer/1` will return `{:error, :not_found}`.

    ## Parameters
      - `queue_name` — name of the RabbitMQ queue whose consumer should be removed.

    ## Returns
      - `:ok` — consumer stopped and removed.
      - `{:error, :not_found}` — no consumer was registered for that queue name.
    """
    def remove_consumer(queue_name) do
        result = stop_consumer(queue_name)
        :ets.delete(@table, queue_name)
        result
    end

    @doc """
    Restarts the consumer for the given queue using its originally stored args.

    Useful to recover a consumer in :stopped state without supplying the configuration again.

    ## Parameters
      - queue_name — name of the RabbitMQ queue whose consumer should be restarted.

    ## Returns
      - {:ok, pid} — consumer restarted successfully.
      - {:error, :not_found} — no consumer has ever been registered for that queue name.
      - {:error, reason} — consumer failed to start.
    """
    def restart_consumer(queue_name) do
        case :ets.lookup(@table, queue_name) do
            [] ->
                {:error, :not_found}

            [{^queue_name, module, args}] ->
                Logger.info("#{__MODULE__} Restarting consumer for #{queue_name} with stored args.")
                start_consumer(module, args)
        end
    end

    @doc """
    Restarts the consumer for the given queue with new module and args.
    The registry is updated with the new values.

    ## Parameters
      - queue_name — name of the RabbitMQ queue whose consumer should be restarted.
      - module — new consumer module.
      - args — new startup args.

    ## Returns
      - {:ok, pid} — consumer restarted successfully.
      - {:error, reason} — consumer failed to start.
    """
    def restart_consumer(queue_name, module, args) do
        Logger.info("#{__MODULE__} Restarting consumer for #{queue_name} with new args.")
        start_consumer(module, args)
    end

    @doc """
    Returns a list of all consumers registered in this supervisor with their current status.

    ## Returns
      - List of maps with keys :queue, :module, :pid, and :status (:running | :stopped).
    """
    def list_consumers do
        :ets.tab2list(@table)
        |> Enum.map(fn {queue_name, module, _args} ->
        pid = find_pid(queue_name, module)
        %{
            queue:  queue_name,
            module: module,
            pid:    pid,
            status: if(pid != nil and Process.alive?(pid), do: :running, else: :stopped)
        }
        end)
    end

    @doc """
    Returns the status of the consumer for the given queue name.

    ## Parameters
      - queue_name — name of the RabbitMQ queue to query.

    ## Returns
      - :running   — process is alive and consuming messages.
      - :stopped   — consumer is registered but its process is not alive.
      - :not_found — no consumer has been started for this queue.
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


    # Starts a child under the DynamicSupervisor and records it in ETS.
    defp do_start_consumer(module, args, queue_name) do
        child_spec = %{
            id:      {module, queue_name},
            start:   {module, :start_link, [args]},
            restart: :transient
        }

        case DynamicSupervisor.start_child(__MODULE__, child_spec) do
            {:ok, _pid} = result ->
                :ets.insert(@table, {queue_name, module, args})
                Logger.info("#{__MODULE__} Consumer started for queue: #{queue_name}")
                result

            {:error, reason} = result ->
                Logger.error("#{__MODULE__} Failed to start consumer for #{queue_name}. Reason: #{inspect(reason)}")
                result
        end
    end

    #
    # Extracts the queue name from the args tuple of either consumer type.
    # RabbitConsumer:        {queue_info, amqp_config, info}
    # RabbitConsumerByBatch: {queue_info, amqp_config, batch_size, timeout, info}
    #
    defp extract_queue_name({%{config: %{queue: queue}}, _, _}),          do: queue
    defp extract_queue_name({%{config: %{queue: queue}}, _, _, _, _}),    do: queue

    #
    # Resolves the current PID via the registered name each consumer sets on start_link.
    #
    defp find_pid(queue_name, module) do
        Process.whereis(:"#{module}.#{queue_name}")
    end


end
