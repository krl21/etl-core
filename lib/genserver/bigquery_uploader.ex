
defmodule Genserver.BigqueryUploader do
    @moduledoc"""
    GenServer for uploading pending records to BigQuery.
    Maintains persistent connections to both PostgreSQL and BigQuery (ODBC).
    """

    use GenServer
    require Logger
    alias Genserver.Monitor
    alias Genserver.Handlers.Bigquery
    alias Connection.Postgres
    alias Connection.Odbc
    import Time.Timem, only: [notification_frequency: 1]
    import Stuff, only: [random_string_generate: 1]


    @doc"""
    Starts the GenServer for data upload to BigQuery.

    ### Parameters:
        - args (map): Configuration map with the following keys:
            - :business (atom): Business/context identifier.
            - :data_source (list): ODBC connection configuration for BigQuery.
            - :pg_config (map): PostgreSQL connection configuration (used to establish persistent connection).
            - :info (list): List of maps with table configuration:
                - :bq_table (string): Full BigQuery table name.
                - :tipo (string): Type field value to filter records.
                - :pg_table (string): PostgreSQL table name for pending records.
            - :periodicity (map): Activation periodicity map:
                - :day (integer): Days.
                - :hour (integer): Hours.
                - :minute (integer): Minutes.
                - :second (integer): Seconds.
            - :batch_size (integer): Number of records to insert per batch.
            - :webhook_url (string): Slack webhook URL for error notifications.

    ### Returns:
        - {:ok, pid} | {:error, reason}
    """
    def start_link(%{business: business} = args) do
        GenServer.start_link(__MODULE__, args, name: :"#{__MODULE__}.#{business}")
    end

    @doc"""
    Initializes the GenServer state.

    ### Parameters:
        - args (map): Configuration map with the following keys:
            - :business (atom): Business identifier.
            - :data_source (list): ODBC connection configuration for BigQuery.
            - :pg_config (map): PostgreSQL connection configuration.
            - :info (list): List of table configurations.
            - :periodicity (map): Activation periodicity.
            - :batch_size (integer): Number of records per batch.
            - :webhook_url (string): Slack webhook URL for error notifications.

    ### Returns:
        - {:ok, state}
    """
    def init(%{business: business, data_source: data_source, pg_config: pg_config, info: info, periodicity: periodicity, batch_size: batch_size, webhook_url: webhook_url}) do
        Monitor.register(self(), to_string(__MODULE__) <> "." <> to_string(business))

        Logger.info("#{to_string(__MODULE__)}. Inicializando. Negocio: ---#{to_string(business)}---")

        {:ok, pg_conn} = Postgres.connect(pg_config)
        Logger.info("#{to_string(__MODULE__)}. Conexión a PostgreSQL establecida para negocio: #{to_string(business)}")

        bq_conn = Odbc.connect(data_source)
        Logger.info("#{to_string(__MODULE__)}. Conexión ODBC a BigQuery establecida para negocio: #{to_string(business)}")

        milliseconds_timeout = notification_frequency(periodicity)

        state = %{
            business: business,
            data_source: data_source,
            pg_conn: pg_conn,
            bq_conn: bq_conn,
            info: info,
            milliseconds_timeout: milliseconds_timeout,
            batch_size: batch_size,
            webhook_url: webhook_url
        }

        variable_wait(:start, milliseconds_timeout)

        {:ok, state}
    end

    @doc"""
    Handles the :update message that triggers the data upload to BigQuery.

    ### Parameters:
        - :update (atom): Activation message.
        - state (map): Current GenServer state.

    ### Returns:
        - {:noreply, state}
    """
    def handle_info(:update, state) do
        %{
            business: business,
            pg_conn: pg_conn,
            bq_conn: bq_conn,
            info: info,
            milliseconds_timeout: milliseconds_timeout,
            batch_size: batch_size,
            webhook_url: webhook_url
        } = state

        Logger.info("#{to_string(__MODULE__)}. Iniciando ciclo de carga a BigQuery para negocio: #{to_string(business)}")

        Enum.each(info, fn table_config ->
            batch_id = random_string_generate(15)

            bq_table = Map.fetch!(table_config, :bq_table)
            tipo = Map.fetch!(table_config, :tipo)
            pg_table = Map.fetch!(table_config, :pg_table)

            Bigquery.run(business, bq_conn, pg_conn, pg_table, bq_table, tipo, batch_id, batch_size, webhook_url)
        end)

        Logger.info("#{to_string(__MODULE__)}. Ciclo de carga a BigQuery finalizado para negocio: #{to_string(business)}")

        variable_wait(:later, milliseconds_timeout)
        {:noreply, state}
    end

    #
    # Adjusts the time for the genserver activation
    #
    # ### Parameters:
    #     - state: Atom. GenServer status. Possible values: :start and :later
    #     - milliseconds_timeout: Integer. Total milliseconds to reactivate the genserver.
    #
    defp variable_wait(:start, _milliseconds_timeout) do
        10 * 1_000
        |> :erlang.send_after(self(), :update)
    end

    defp variable_wait(:later, milliseconds_timeout) do
        milliseconds_timeout
        |> :erlang.send_after(self(), :update)
    end

    @impl true
    def terminate(reason, %{pg_conn: pg_conn, bq_conn: bq_conn, business: business}) do
        Logger.info("#{to_string(__MODULE__)}. Terminando para negocio: #{to_string(business)}. Razón: #{inspect(reason)}")

        if pg_conn do
            Postgres.disconnect(pg_conn)
            Logger.debug("#{to_string(__MODULE__)}. Conexión a PostgreSQL cerrada")
        end

        if bq_conn do
            Odbc.disconnect(bq_conn)
            Logger.debug("#{to_string(__MODULE__)}. Conexión ODBC a BigQuery cerrada")
        end

        :ok
    end

end
