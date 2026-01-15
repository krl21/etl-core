
defmodule Pool.BigQuery do
    @moduledoc """
    Pool de conexiones para BigQuery via ODBC usando NimblePool.

    ## Uso

    Agregar al árbol de supervisión:

        {Pool.BigQuery,
            name: :bigquery_pool,
            data_source: bq_config,
            pool_size: 5
        }

    Luego usar el pool:

        Pool.BigQuery.with_connection(:bigquery_pool, fn conn ->
            Connection.Odbc.select(conn, "SELECT * FROM table")
        end)

    ## Manejo de Errores

    - Si una conexión falla durante una operación, el error se propaga al llamador
    - La conexión problemática se descarta y se crea una nueva
    - Los errores de conexión inicial se loguean y reintentan
    - No se envían notificaciones a Slack desde este módulo (responsabilidad del llamador)

    ## Configuración

    - `:name` (atom, requerido) - Nombre del pool
    - `:data_source` (list, requerido) - Configuración ODBC para BigQuery
    - `:pool_size` (integer, opcional) - Tamaño del pool (default: 5)
    """

    @behaviour NimblePool
    require Logger
    alias Connection.Odbc

    @default_pool_size 5
    @checkout_timeout 30_000

    @doc """
    Starts the BigQuery connection pool.

    ## Parameters
        - opts: Keyword. Configuration options:
            - :name: Atom. Pool name
            - :data_source: List. ODBC configuration.
            - :pool_size: Integer. Pool size (default: 5)

    ## Returns
        - {:ok, pid} Pool started successfully
        - {:error, reason} Error starting the pool
    """
    def start_link(opts) do
        name = Keyword.fetch!(opts, :name)
        data_source = Keyword.fetch!(opts, :data_source)
        pool_size = Keyword.get(opts, :pool_size, @default_pool_size)

        Logger.info("#{__MODULE__}. Iniciando pool '#{name}' con #{pool_size} conexiones")

        # Asegurar que ODBC esté iniciado
        Odbc.start()

        NimblePool.start_link(
            worker: {__MODULE__, data_source},
            pool_size: pool_size,
            name: name
        )
    end


    @doc """
    Executes a function with a connection from the pool.

    ## Parameters
        - pool_name: Atom. Pool name
        - fun: Function. Function that receives the ODBC connection and executes operations
        - opts: Keyword, optional. Options:
            - :timeout: Integer. Timeout to get connection (default: 30000ms)

    ## Returns
        - The result of executing `fun.(conn)`
        - Propagates any exception that occurs within `fun`
    """
    def with_connection(pool_name, fun, opts \\ []) do
        timeout = Keyword.get(opts, :timeout, @checkout_timeout)

        NimblePool.checkout!(
            pool_name,
            :checkout,
            fn _pool_state, conn ->
                try do
                    result = fun.(conn)
                    # Retornar resultado y conexión para reusar
                    {result, conn}
                rescue
                    error ->
                    # En caso de error, loguear pero dejar que NimblePool maneje la conexión
                    Logger.error("#{__MODULE__}. Error ejecutando operación: #{inspect(error)}")
                    reraise error, __STACKTRACE__
                end
            end,
            timeout
        )
    end

    @doc """
    Checks the pool status.

    ## Parameters
        - pool_name: Atom. Pool name to check

    ## Returns
        - {:ok, :running} Pool is active
        - {:error, :pool_not_found} Pool does not exist
    """
    def status(pool_name) do
        Process.whereis(pool_name)
        |> case do
            nil -> {:error, :pool_not_found}
            _pid -> {:ok, :running}
        end
    end

    #
    # Initializes the worker
    #
    # Parameters:
    #     - data_source: List. ODBC configuration
    #
    # Returns:
    #     - {:ok, conn, data_source} - Successful connection
    #     - {:error, reason} - Error initializing the worker
    #
    @doc false
    @impl NimblePool
    def init_worker(data_source) do
        Logger.debug("#{__MODULE__}. Inicializando worker de conexión ODBC")

        create_connection(data_source)
        |> case do
            {:ok, conn} ->
                Logger.debug("#{__MODULE__}. Conexión ODBC establecida")
                {:ok, conn, data_source}

            {:error, reason} ->
                Logger.error("#{__MODULE__}. Error al conectar: #{inspect(reason)}")
                {:error, reason}
        end
    end

    @doc false
    @impl NimblePool
    def handle_checkout(:checkout, _from, conn, pool_state) do
        {:ok, conn, conn, pool_state}
    end

    @doc false
    @impl NimblePool
    def handle_checkin(conn, _from, _old_conn, pool_state) do
        # Podríamos agregar health check aquí si fuera necesario
        {:ok, conn, pool_state}
    end

    @doc false
    @impl NimblePool
    def terminate_worker(_reason, conn, pool_state) do
        Logger.debug("#{__MODULE__}. Terminando worker de conexión ODBC")

        try do
            Odbc.disconnect(conn)
        rescue
            _ -> :ok
        catch
            _, _ -> :ok
        end

        {:ok, pool_state}
    end

    @doc false
    @impl NimblePool
    def handle_ping(conn, pool_state) do
        # Health check simple - intentar una query básica
        case health_check(conn) do
            :ok ->
                {:ok, conn, pool_state}

            :error ->
                Logger.warning("#{__MODULE__}. Health check fallido, removiendo conexión")
                {:remove, :connection_dead}
        end
    end

    #
    # Creates an ODBC connection using Connection.Odbc
    #
    # Parameters:
    #     - data_source: List. ODBC configuration
    #
    # Returns:
    #     - {:ok, conn} - Successful connection
    #     - {:error, reason} - Error creating the connection
    defp create_connection(data_source) do
        try do
            conn = Odbc.connect(data_source)
            {:ok, conn}
        rescue
            error ->
                {:error, error}
        end
    end

    #
    # Checks if the connection is active
    #
    # Parameters:
    #     - conn: pid. Connection
    #
    # Returns:
    #     - :ok - Successful health check
    #     - :error - Error checking the health
    #
    defp health_check(conn) do
        try do
            case :odbc.sql_query(conn, ~c"SELECT 1") do
                {:error, _} -> :error
                _ -> :ok
            end
        rescue
            _ -> :error
        catch
            _, _ -> :error
        end
    end

end
