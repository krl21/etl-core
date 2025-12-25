
defmodule Genserver.Cleaning do
    @moduledoc """
    Module/genserver oriented to delete the least updated rows in Bigquery and analyzed records in PostgreSQL. Uses the `timestamp` field to determine freshness of records.

    ## Modes of Operation

    This GenServer supports two modes:

    1. **Single business mode**: Pass a specific business key to clean only that table
       ```elixir
       {Genserver.Cleaning, %{business: :record, bq_config: bq_config, pg_config: pg_config, periodicity: 60_000}}
       ```

    2. **All tables mode**: Pass `:all` to clean all registered CleanableTable modules
       ```elixir
       {Genserver.Cleaning, %{business: :all, bq_config: bq_config, pg_config: pg_config, periodicity: 60_000}}
       ```

    ## Configuration

    Tables must be registered via the CleanableTable behaviour to be cleaned.
    See `Cleaning.CleanableTable` for more information.

    ## Connection Management

    Connections to BigQuery (ODBC) and PostgreSQL are opened once at startup and reused
    for all cleaning cycles. They are properly closed when the GenServer terminates.
    """

    use GenServer
    require Logger
    import Connection.Odbc, only: [connect: 1, disconnect: 1]
    alias Genserver.Monitor
    alias Cleaning.Cleaner
    alias Database.Postgres


    @doc """
    Starts the cleaning GenServer.

    ### Parameters
        - config: Map with:
            - :business - Atom. :all to clean all tables, or specific business key (e.g., :record)
            - :bq_config - List. ODBC connection configuration for BigQuery
            - :pg_config - Map. PostgreSQL connection configuration (optional, if nil skips PG cleaning)
            - :periodicity - Integer. Interval between cleaning cycles in milliseconds
            - :webhook_url - String. Slack webhook URL for error notifications (optional)
    """
    def start_link(%{business: business} = config) do
        GenServer.start_link(__MODULE__, config, name: :"#{__MODULE__}.#{business}")
    end

    # Legacy support for tuple format
    def start_link({business, bq_config, periodicity}) do
        start_link(%{
            business: business,
            bq_config: bq_config,
            pg_config: nil,
            periodicity: periodicity
        })
    end


    @doc """
    Initializes the GenServer state.

    Opens connections to BigQuery and PostgreSQL (if configured), registers with Monitor
    and schedules first cleaning cycle.
    """
    @impl true
    def init(%{business: business, bq_config: bq_config, periodicity: periodicity} = config) do
        Monitor.register(self(), to_string(__MODULE__) <> "." <> to_string(business))

        Logger.info("#{to_string(__MODULE__)}. Initializing. Business: ---#{to_string(business)}---")

        pg_config = Map.get(config, :pg_config)
        webhook_url = Map.get(config, :webhook_url)

        # Open BigQuery connection
        Logger.debug("#{to_string(__MODULE__)}. Opening BigQuery ODBC connection")
        pid_odbc = connect(bq_config)

        # Open PostgreSQL connection if configured
        pid_pg = open_postgres_connection(pg_config)

        state = %{
            business: business,
            bq_config: bq_config,
            pg_config: pg_config,
            periodicity: periodicity,
            pid_odbc: pid_odbc,
            pid_pg: pid_pg,
            webhook_url: webhook_url
        }

        variable_wait(:start, periodicity)

        {:ok, state}
    end


    @doc """
    Handles the periodic :update message to perform cleaning.

    Uses existing connections to clean both BigQuery and PostgreSQL.
    """
    @impl true
    def handle_info(:update, %{business: business, pid_odbc: pid_odbc, pid_pg: pid_pg, periodicity: periodicity, webhook_url: webhook_url} = state) do
        Logger.debug("#{to_string(__MODULE__)}. Applying duplicate/stale row cleanup in ---#{to_string(business)}---")

        opts = if webhook_url, do: [webhook_url: webhook_url], else: []

        # Clean BigQuery
        case business do
            :all ->
                Cleaner.run_all(pid_odbc, opts)

            business_key ->
                Cleaner.run(business_key, pid_odbc, opts)
        end

        # Clean PostgreSQL (if connection exists)
        if pid_pg do
            case business do
                :all ->
                    Cleaner.run_all_postgres(pid_pg, opts)

                business_key ->
                    Cleaner.run_postgres(business_key, pid_pg, opts)
            end
        end

        variable_wait(:later, periodicity)
        {:noreply, state}
    end


    @doc """
    Handles GenServer termination by closing connections.
    """
    @impl true
    def terminate(reason, %{pid_odbc: pid_odbc, pid_pg: pid_pg, business: business}) do
        Logger.info("#{to_string(__MODULE__)}. Terminating (#{inspect(reason)}). Business: ---#{to_string(business)}---")

        # Close BigQuery connection
        if pid_odbc do
            Logger.debug("#{to_string(__MODULE__)}. Closing BigQuery ODBC connection")
            disconnect(pid_odbc)
        end

        # Close PostgreSQL connection
        if pid_pg do
            Logger.debug("#{to_string(__MODULE__)}. Closing PostgreSQL connection")
            Postgres.disconnect(pid_pg)
        end

        :ok
    end


    # ============================================
    # PRIVATE FUNCTIONS
    # ============================================

    #
    # Opens a PostgreSQL connection if configuration is provided.
    #
    # ### Parameters
    #     - pg_config: Map | nil. PostgreSQL connection configuration
    #
    # ### Returns
    #     - pid | Map | nil
    #
    defp open_postgres_connection(nil) do
        Logger.debug("#{to_string(__MODULE__)}. No PostgreSQL configuration provided, skipping PG cleaning")
        nil
    end

    defp open_postgres_connection(pg_config) do
        Logger.debug("#{to_string(__MODULE__)}. Opening PostgreSQL connection")

        case Postgres.connect(pg_config) do
            {:ok, conn} ->
                Logger.info("#{to_string(__MODULE__)}. PostgreSQL connection established")
                conn

            {:error, reason} ->
                Logger.error("#{to_string(__MODULE__)}. Failed to connect to PostgreSQL: #{inspect(reason)}")
                nil
        end
    end

    #
    # Adjusts the time for the activation of the genserver.
    #
    # ### Parameters
    #     - state: Atom. Genserver status. Possible values: :start and :later
    #     - periodicity: Integer. Total milliseconds to reactivate the genserver.
    #
    defp variable_wait(:start, _periodicity) do
        10 * 1_000
        |> :erlang.send_after(self(), :update)
    end

    defp variable_wait(:later, periodicity) do
        periodicity
        |> :erlang.send_after(self(), :update)
    end


end
