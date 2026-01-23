
defmodule Pool.BigQuery do
    @moduledoc """
    Child specification for the BigQuery pool.
    """

    require Logger
    alias Pool.BigQuery.Worker

    @default_pool_size 5
    @default_max_overflow 2
    @default_checkout_timeout 70_000 # 70 segundos

    @doc """
    Returns the child specification for the pool.
    """
    def child_spec(opts) do
        name = Keyword.fetch!(opts, :name)

        %{
            id: name,
            start: {__MODULE__, :start_link, [opts]},
            type: :supervisor,
            restart: :permanent,
            shutdown: 5000
        }
    end

    @doc """
    Starts the BigQuery connection pool.

    ### Parameters
        - opts: Keyword. Configuration options:
            - :name: Atom. Pool name
            - :data_source: List. ODBC configuration.
            - :pool_size: Integer. Pool size (default: 5)
            - :max_overflow: Integer. Extra workers under load (default: 2)
            - :checkout_timeout: Integer. Timeout to get connection in ms (default: 70000)

    ### Returns
        - {:ok, pid} Pool started successfully
        - {:error, reason} Error starting the pool
    """
    def start_link(opts) do
        name = Keyword.fetch!(opts, :name)
        data_source = Keyword.fetch!(opts, :data_source)
        pool_size = Keyword.get(opts, :pool_size, @default_pool_size)
        max_overflow = Keyword.get(opts, :max_overflow, @default_max_overflow)
        checkout_timeout = Keyword.get(opts, :checkout_timeout, @default_checkout_timeout)

        # Guardar el timeout configurado para este pool
        :persistent_term.put({__MODULE__, :checkout_timeout, name}, checkout_timeout)

        Logger.info("#{__MODULE__}. Iniciando pool '#{name}' con #{pool_size} conexiones (overflow: #{max_overflow}, timeout: #{checkout_timeout}ms)")

        pool_config = [
            name: {:local, name},
            worker_module: Worker,
            size: pool_size,
            max_overflow: max_overflow
        ]

        :poolboy.start_link(pool_config, data_source)
    end

    @doc """
    Executes a function with a connection from the pool.

    ### Parameters
        - pool_name: Atom. Pool name
        - fun: Function. Function that receives the ODBC connection and executes operations
        - opts: Keyword, optional. Options:
            - :timeout: Integer. Timeout to get connection (uses pool's configured timeout by default)

    ### Returns
        - The result of executing `fun.(conn)`
        - Raises exception if operation fails
    """
    def with_connection(pool_name, fun, opts \\ []) do
        timeout = Keyword.get(opts, :timeout, get_checkout_timeout(pool_name))

        :poolboy.transaction(
            pool_name,
            fn worker_pid ->
                Worker.execute(worker_pid, fun, timeout)
                |> case do
                    {:ok, result} -> result
                    {:error, error} -> raise error
                end
            end,
            timeout
        )
    end

    @doc """
    Executes a function with a connection, returning {:ok, result} or {:error, reason}.

    Similar a `with_connection/3` pero no lanza excepciones.

    ### Parameters
        - pool_name: Atom. Pool name
        - fun: Function. Function that receives the ODBC connection
        - opts: Keyword, optional. Options:
            - :timeout: Integer. Timeout to get connection (uses pool's configured timeout by default)

    ### Returns
        - {:ok, result} - Operación exitosa
        - {:error, reason} - Error en la operación
    """
    def with_connection_safe(pool_name, fun, opts \\ []) do
        timeout = Keyword.get(opts, :timeout, get_checkout_timeout(pool_name))

        try do
            result =
                :poolboy.transaction(
                    pool_name,
                    fn worker_pid ->
                        Worker.execute(worker_pid, fun, timeout)
                    end,
                    timeout
                )

            case result do
                {:ok, _} = success -> success
                {:error, _} = error -> error
            end
        catch
            :exit, {:timeout, _} ->
                {:error, :pool_timeout}

            :exit, reason ->
                {:error, {:pool_exit, reason}}
        end
    end

    # Obtiene el timeout configurado para el pool, o el default si no está configurado
    defp get_checkout_timeout(pool_name) do
        try do
            :persistent_term.get({__MODULE__, :checkout_timeout, pool_name})
        rescue
            ArgumentError -> @default_checkout_timeout
        end
    end

    @doc """
    Checks the pool status.

    ### Parameters
        - pool_name: Atom. Pool name to check

    ### Returns
        - {:ok, :running} Pool is active
        - {:error, :pool_not_found} Pool does not exist
    """
    def status(pool_name) do
        case Process.whereis(pool_name) do
        nil -> {:error, :pool_not_found}
        _pid -> {:ok, :running}
        end
    end

    @doc """
    Returns pool statistics.

    ### Parameters
        - pool_name: Atom. Pool name

    ### Returns
        - Map with :available_workers, :overflow_workers, :checked_out
    """
    def pool_stats(pool_name) do
        status = :poolboy.status(pool_name)

        case status do
        {state, available, overflow, checked_out} when is_atom(state) ->
            %{
                state: state,
                available_workers: available,
                overflow_workers: overflow,
                checked_out: checked_out
            }

        _ ->
            %{raw: status}
        end
    end
end
