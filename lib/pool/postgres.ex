
defmodule Pool.Postgres do
    @moduledoc """
    Connection pool supervisor for PostgreSQL using Postgrex.

    ### Features

    - **Supervised pool**: Connections are managed and restarted automatically
    - **Automatic reconnection**: If a connection fails, Postgrex reconnects it
    - **Dual mode**: Supports read replicas (write_hostname + read_hostname)
    - **Flexible configuration**: pool_size, queue_target, queue_interval

    ### Usage

    Add to the supervision tree:

        {Pool.Postgres,
            name: :postgres_pool,
            config: postgres_config,
            pool_size: 10
        }

    Then use the pool:

        Pool.Postgres.query(:postgres_pool, "SELECT 1", [])

        # With transaction
        Pool.Postgres.transaction(:postgres_pool, fn conn ->
            Postgrex.query!(conn, "INSERT ...", [])
        end)

    ### Configuration

    - `:name` (atom, required) - Pool name
    - `:config` (map, required) - PostgreSQL connection configuration
    - `:pool_size` (integer, optional) - Pool size (default: 10). Maximum number of connections.
      **Note:** `max_overflow` is set to 0 to ensure the pool never exceeds `pool_size`.
    - `:queue_target` (integer, optional) - Queue target in ms (default: 50)
    - `:queue_interval` (integer, optional) - Queue interval in ms (default: 1000)
    """

    use Supervisor
    require Logger

    @default_pool_size 3
    @default_queue_target 1000
    @default_queue_interval 10000


    @doc """
    Returns the child specification for the pool.
    """
    def child_spec(opts) do
        %{
            id: Keyword.get(opts, :name, __MODULE__),
            start: {__MODULE__, :start_link, [opts]},
            type: :supervisor,
            restart: :permanent,
            shutdown: :infinity
        }
    end

    @doc """
    Starts the PostgreSQL pool supervisor.

    ### Parameters
        - opts: Keyword. Configuration options:
            - :name: Atom. Pool name
            - :config: Map. Connection configuration with:
                - :hostname: String. Hostname
                - :port: Integer. Port (default: 5432)
                - :database: String. Database name
                - :username: String. Username (required)
                - :password: String. Password (required)
                - :ssl: Boolean. Use SSL (default: false)
            - :pool_size: Integer. Pool size (default: 10)
            - :queue_target: Integer. Queue target (default: 50)
            - :queue_interval: Integer. Queue interval (default: 1000)

    ### Returns
        - {:ok, pid} Pool started successfully
        - {:error, reason} Error starting the pool
    """
    def start_link(opts) do
        name = Keyword.fetch!(opts, :name)
        Supervisor.start_link(__MODULE__, opts, name: :"#{__MODULE__}.Supervisor.#{name}")
    end

    @impl true
    def init(opts) do
        name = Keyword.fetch!(opts, :name)
        config = Keyword.fetch!(opts, :config)
        pool_size = Keyword.get(opts, :pool_size, @default_pool_size) || @default_pool_size
        queue_target = Keyword.get(opts, :queue_target, @default_queue_target) || @default_queue_target
        queue_interval = Keyword.get(opts, :queue_interval, @default_queue_interval) || @default_queue_interval

        Logger.info("#{__MODULE__}. Iniciando pool '#{name}' con #{pool_size} conexiones")

        children = build_children(name, config, pool_size, queue_target, queue_interval)

        Supervisor.init(children, strategy: :one_for_one)
    end

    #
    # Builds the children list for the supervisor
    #
    # Parameters:
    #     - name: String. Pool name
    #     - config: Map. Connection configuration
    #     - pool_size: Integer. Pool size
    #     - queue_target: Integer. Queue target
    #     - queue_interval: Integer. Queue interval
    #
    # Returns:
    #     - List of children for the supervisor
    #
    defp build_children(name, config, pool_size, queue_target, queue_interval) do
        hostname = get_write_hostname(config)

        base_opts = [
            name: name,
            hostname: hostname,
            port: Map.get(config, :port, 5432),
            database: Map.fetch!(config, :database),
            username: Map.fetch!(config, :username),
            password: Map.fetch!(config, :password),
            ssl: Map.get(config, :ssl, false),
            pool_size: pool_size,
            max_overflow: 0,
            queue_target: queue_target,
            queue_interval: queue_interval
        ]

        children = [
            %{
                id: :"#{name}_write",
                start: {Postgrex, :start_link, [base_opts]}
            }
        ]

        # For dual mode (read replicas), add read pool
        if Map.has_key?(config, :read_hostname) do
            read_name = :"#{name}_read"
            read_opts = Keyword.put(base_opts, :name, read_name)
                        |> Keyword.put(:hostname, Map.fetch!(config, :read_hostname))

            children ++ [
                %{
                    id: read_name,
                    start: {Postgrex, :start_link, [read_opts]}
                }
            ]
        else
            children
        end
    end

    #
    # Gets the write hostname from the configuration
    #
    # Parameters:
    #     - config: Map. Connection configuration
    #
    # Returns:
    #     - String. Write hostname
    #
    defp get_write_hostname(config) do
        cond do
        Map.has_key?(config, :write_hostname) ->
            Map.fetch!(config, :write_hostname)

        Map.has_key?(config, :hostname) ->
            Map.fetch!(config, :hostname)

        true ->
            raise ArgumentError, "Configuration must include :hostname or :write_hostname"
        end
    end

    @doc """
    Executes a query using a connection from the pool.

    ### Parameters
        - pool_name: Atom. Pool name
        - sql: String. SQL query to execute
        - params: List. Query parameters
        - opts: Keyword, optional. Additional options for Postgrex

    ### Returns
        - {:ok, %Postgrex.Result{}} Query executed successfully
        - {:error, %Postgrex.Error{}} Query error
    """
    def query(pool_name, sql, params, opts \\ []) do
        Postgrex.query(pool_name, sql, params, opts)
    end

    @doc """
    Executes a query using the read pool (for dual mode).

    ### Parameters
        - pool_name: Atom. Main pool name
        - sql: String. SQL query to execute
        - params: List. Query parameters
        - opts: Keyword, optional. Additional options for Postgrex

    ### Returns
        - {:ok, %Postgrex.Result{}} Query executed successfully
        - {:error, %Postgrex.Error{}} Query error
    """
    def query_read(pool_name, sql, params, opts \\ []) do
        read_pool = :"#{pool_name}_read"

        if Process.whereis(read_pool) do
            Postgrex.query(read_pool, sql, params, opts)
        else
            Postgrex.query(pool_name, sql, params, opts)
        end
    end

    @doc """
    Executes a transaction using a connection from the pool.

    ### Parameters
        - pool_name: Atom. Pool name
        - fun: Function. Function that receives the connection and executes operations
        - opts: Keyword, optional. Additional options for the transaction

    ### Returns
        - {:ok, result} Transaction completed, result is what fun returns
        - {:error, reason} Transaction failed or rolled back
    """
    def transaction(pool_name, fun, opts \\ []) do
        Postgrex.transaction(pool_name, fun, opts)
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
        Process.whereis(pool_name)
        |> case do
            nil ->
                {:error, :pool_not_found}
            pid when is_pid(pid) ->
                if Process.alive?(pid) do
                    {:ok, :running}
                else
                    {:error, :pool_not_running}
                end
        end
    end

    @doc """
    Checks if the pool is in dual mode (with read replica).

    ### Parameters
        - pool_name: Atom. Pool name to check

    ### Returns
        - true: Pool has read replica configured
        - false: Pool is simple (no read replica)
    """
    def dual_mode?(pool_name) do
        read_pool = :"#{pool_name}_read"
        Process.whereis(read_pool) != nil
    end


end
