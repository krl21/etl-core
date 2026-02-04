
defmodule Genserver.Cleaning do
    @moduledoc """
    Module/genserver oriented to delete the least updated rows in Bigquery and analyzed records in PostgreSQL. Uses the `timestamp` field to determine freshness of records.

    ## Modes of Operation

    This GenServer supports two modes:

    1. **Single business mode**: Pass a specific business key to clean only that table
       ```elixir
       {Genserver.Cleaning, %{business: :record, pg_pool_name: :postgres_pool, bq_pool_name: :bigquery_pool, periodicity: 60_000}}
       ```

    2. **All tables mode**: Pass `:all` to clean all registered CleanableTable modules
       ```elixir
       {Genserver.Cleaning, %{business: :all, pg_pool_name: :postgres_pool, bq_pool_name: :bigquery_pool, periodicity: 60_000}}
       ```

    ## Configuration

    Tables must be registered via the CleanableTable behaviour to be cleaned.

    """

    use GenServer
    require Logger
    alias Genserver.Monitor
    alias Cleaning.Cleaner
    alias Connection.Postgres


    @doc """
    Starts the cleaning GenServer.

    ### Parameters
        - config: Map with:
            - :business - Atom. :all to clean all tables, or specific business key (e.g., :record)
            - :bq_pool_name - Atom. BigQuery pool name (required)
            - :pg_pool_name - Atom. PostgreSQL pool name (required)
            - :periodicity - Integer. Interval between cleaning cycles in milliseconds
            - :webhook_url - String. Slack webhook URL for error notifications (optional)
    """
    def start_link(%{business: business} = config) do
        GenServer.start_link(__MODULE__, config, name: :"#{__MODULE__}.#{business}")
    end



    @doc """
    Initializes the GenServer state.
    """
    @impl true
    def init(%{business: business, periodicity: periodicity} = config) do
        Monitor.register(self(), to_string(__MODULE__) <> "." <> to_string(business))

        Logger.info("#{to_string(__MODULE__)}. Inicializando. Negocio: ---#{to_string(business)}---")

        bq_pool_name = Map.get(config, :bq_pool_name)
        pg_pool_name = Map.get(config, :pg_pool_name)
        webhook_url = Map.get(config, :webhook_url)

        # Setup BigQuery connection using pool
        bq_mode = setup_bigquery_connection(bq_pool_name)

        # Setup PostgreSQL connection using pool
        pg_mode = setup_postgres_connection(pg_pool_name)

        state = %{
            business: business,
            bq_pool_name: bq_pool_name,
            bq_mode: bq_mode,
            pg_pool_name: pg_pool_name,
            pg_mode: pg_mode,
            periodicity: periodicity,
            webhook_url: webhook_url
        }

        variable_wait(:start, periodicity)

        {:ok, state}
    end


    @doc """
    Handles the periodic :update message to perform cleaning.
    """
    @impl true
    def handle_info(:update, %{business: business, bq_mode: bq_mode, pg_mode: pg_mode, periodicity: periodicity, webhook_url: webhook_url} = state) do
        Logger.debug("#{to_string(__MODULE__)}. Aplicando limpieza de filas duplicadas/obsoletas en ---#{to_string(business)}---")

        opts = if webhook_url, do: [webhook_url: webhook_url], else: []

        if bq_mode != :none do
            try do
                case business do
                    :all ->
                        Cleaner.run_all(state.bq_pool_name, opts)

                    business_key ->
                        Cleaner.run(business_key, state.bq_pool_name, opts)
                end
            rescue
                error ->
                    Logger.error("#{to_string(__MODULE__)}. Error en limpieza de BigQuery (business: #{inspect(business)}): #{inspect(error)}")
            end
        end

        if pg_mode != :none do
            try do
                case business do
                    :all ->
                        Cleaner.run_all_postgres(state.pg_pool_name, pg_mode, opts)

                    business_key ->
                        Cleaner.run_postgres(business_key, state.pg_pool_name, pg_mode, opts)
                end
            rescue
                error ->
                    Logger.error("#{to_string(__MODULE__)}. Error en limpieza de PostgreSQL (business: #{inspect(business)}): #{inspect(error)}")
            end
        end

        variable_wait(:later, periodicity)
        {:noreply, state}
    end


    @doc """
    Handles GenServer termination.
    """
    @impl true
    def terminate(reason, %{business: business}) do
        Logger.info("#{to_string(__MODULE__)}. Terminando (#{inspect(reason)}). Negocio: ---#{to_string(business)}---")
        :ok
    end


    # ============================================
    # PRIVATE FUNCTIONS
    # ============================================

    #
    # Configures the BigQuery connection using the pool.
    #
    # ### Parameters
    #     - bq_pool_name: Atom | nil. BigQuery pool name
    #
    # ### Returns
    #     - :pool if pool name is provided
    #     - :none if pool name is not provided
    #
    defp setup_bigquery_connection(bq_pool_name) do
        if not is_nil(bq_pool_name) do
            Logger.info("#{to_string(__MODULE__)}. Usando pool de BigQuery: #{bq_pool_name}")
            :pool
        else
            Logger.warning("#{to_string(__MODULE__)}. No se proporcionó bq_pool_name, omitiendo limpieza de BigQuery")
            :none
        end
    end

    #
    # Configures the PostgreSQL connection using the pool.
    #
    # ### Parameters
    #     - pg_pool_name: Atom | nil. PostgreSQL pool name
    #
    # ### Returns
    #     - :pool if pool name is provided
    #     - :none if pool name is not provided
    #
    defp setup_postgres_connection(pg_pool_name) do
        if not is_nil(pg_pool_name) do
            Logger.info("#{to_string(__MODULE__)}. Usando pool de PostgreSQL: #{pg_pool_name}")
            :pool
        else
            Logger.warning("#{to_string(__MODULE__)}. No se proporcionó pg_pool_name, omitiendo limpieza de PostgreSQL")
            :none
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
