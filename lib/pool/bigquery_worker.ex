
defmodule Pool.BigQuery.Worker do
    @moduledoc """
    Worker GenServer for ODBC connections to BigQuery.
    """

    use GenServer
    require Logger
    alias Connection.Odbc

    @doc false
    def start_link(data_source) do
        GenServer.start_link(__MODULE__, data_source)
    end

    @doc """
    Executes a function with the ODBC connection of the worker.

    ### Parameters
        - worker: pid of the worker
        - fun: function that receives the ODBC connection
        - timeout: timeout for the operation (default: 30_000ms)

    ### Returns
        - The result of executing `fun.(conn)`
        - {:error, reason} if there is an error
    """
    def execute(worker, fun, timeout \\ 30_000) do
        GenServer.call(worker, {:execute, fun}, timeout)
    end

    @impl true
    def init(data_source) do
        Logger.debug("#{__MODULE__}. Inicializando worker ODBC")

        # Asegurar que ODBC esté iniciado
        Odbc.start()

        case create_connection(data_source) do
        {:ok, conn} ->
            Logger.debug("#{__MODULE__}. Conexión ODBC establecida")
            {:ok, %{conn: conn, data_source: data_source}}

        {:error, reason} ->
            Logger.error("#{__MODULE__}. Error al conectar: #{inspect(reason)}")
            {:stop, reason}
        end
    end

    @impl true
    def handle_call({:execute, fun}, _from, %{conn: conn} = state) do
        result =
            try do
                {:ok, fun.(conn)}
            rescue
                error ->
                    Logger.error("#{__MODULE__}. Error ejecutando operación: #{inspect(error)}")
                    {:error, error}
            end

        {:reply, result, state}
    end

    @impl true
    def terminate(reason, %{conn: conn}) do
        Logger.debug("#{__MODULE__}. Terminando worker: #{inspect(reason)}")

        try do
            Odbc.disconnect(conn)
        rescue
            _ -> :ok
        catch
            _ -> :ok
        end

        :ok
    end

    defp create_connection(data_source) do
        try do
            conn = Odbc.connect(data_source)
            {:ok, conn}
        rescue
            error ->
                {:error, error}
        end
    end


end
