
defmodule Genserver.BigqueryUploader do
    @moduledoc """
    GenServer to upload pending records to BigQuery.

    Supports two modes of operation:

    - **Pool Mode** (recommended): Uses connection pools for PostgreSQL and BigQuery.
        Configure with `pg_pool_name` and `bq_pool_name`.

    - **Legacy Mode**: Opens and closes connections in each cycle.
        Configure with `data_source` and `pg_config`.

    ## Pool Mode

    The pool mode offers better performance by reusing connections:

        {Genserver.BigqueryUploader, %{
            business: :my_business,
            pg_pool_name: :postgres_pool,
            bq_pool_name: :bigquery_pool,
            info: [...],
            periodicity: %{...},
            batch_size: 100,
            webhook_url: "https://..."
        }}

    ## Legacy Mode

    Compatible with previous versions:

        {Genserver.BigqueryUploader, %{
            business: :my_business,
            data_source: bq_config,
            pg_config: pg_config,
            info: [...],
            periodicity: %{...},
            batch_size: 100,
            webhook_url: "https://..."
        }}
    """

    use GenServer
    require Logger
    alias Genserver.Monitor
    alias Genserver.Handlers.Bigquery
    alias Connection.Postgres
    alias Connection.Odbc
    import Time.Timem, only: [notification_frequency: 1]
    import Stuff, only: [random_string_generate: 1]


    @doc """
    Starts the GenServer to upload data to BigQuery.

    ## Parameters

    - `args` (map) - Configuration map:

        ### Modo Pool (recomendado)

        - `:business` (atom) - Business identifier/context
        - `:pg_pool_name` (atom) - PostgreSQL pool name
        - `:bq_pool_name` (atom) - BigQuery pool name
        - `:info` (list) - List of maps with table configuration:
        - `:bq_table` (string) - Full table name in BigQuery
        - `:tipo` (string) - Value of the tipo field to filter
        - `:pg_table` (string) - Table name in PostgreSQL
        - `:periodicity` (map) - Activation periodicity
        - `:batch_size` (integer) - Number of records per batch
        - `:webhook_url` (string) - URL of the Slack webhook for errors

        ### Modo Legacy

        - `:business` (atom) - Business identifier/context
        - `:data_source` (list) - ODBC configuration for BigQuery
        - `:pg_config` (map) - PostgreSQL connection configuration
        - `:info` (list) - List of table configurations
        - `:periodicity` (map) - Activation periodicity
        - `:batch_size` (integer) - Number of records per batch
        - `:webhook_url` (string) - URL of the Slack webhook for errors

    ## Retorna
        - `{:ok, pid}` - GenServer iniciado
        - `{:error, reason}` - Error al iniciar
    """
    def start_link(%{business: business} = args) do
        GenServer.start_link(__MODULE__, args, name: :"#{__MODULE__}.#{business}")
    end

    @doc """
    Initializes the GenServer state.
    """
    def init(args) do
        business = Map.fetch!(args, :business)
        Monitor.register(self(), to_string(__MODULE__) <> "." <> to_string(business))

        Logger.info("#{to_string(__MODULE__)}. Inicializando. Negocio: ---#{to_string(business)}---")

        periodicity = Map.fetch!(args, :periodicity)
        milliseconds_timeout = notification_frequency(periodicity)

        # Determinar modo según las claves proporcionadas
        mode = determine_mode(args)
        Logger.info("#{to_string(__MODULE__)}. Modo de operación: #{mode}")

        state = build_state(args, mode, milliseconds_timeout)

        variable_wait(:start, milliseconds_timeout)

        {:ok, state}
    end

    #
    # Determines the operation mode according to the keys in args
    #
    # Parameters:
    # - args: map with the configuration
    #
    # Returns:
    #     - :pool: if the keys :pg_pool_name and :bq_pool_name are present
    #     - :legacy: if the keys :data_source and :pg_config are present
    #     - raises ArgumentError if neither of the keys are present
    #
    defp determine_mode(args) do
        cond do
            Map.has_key?(args, :pg_pool_name) and Map.has_key?(args, :bq_pool_name) ->
                :pool

            Map.has_key?(args, :data_source) and Map.has_key?(args, :pg_config) ->
                :legacy

            true ->
                raise ArgumentError,
                "BigqueryUploader requires (pg_pool_name, bq_pool_name) or (data_source, pg_config)"
        end
    end

    #
    # Builds the state for pool mode
    #
    # Parameters:
    #     - args: map with the configuration
    #     - :pool: operation mode
    #     - milliseconds_timeout: timeout in milliseconds
    #
    # Returns:
    #     - map with the state
    #
    defp build_state(args, :pool, milliseconds_timeout) do
        %{
            mode: :pool,
            business: args.business,
            pg_pool_name: args.pg_pool_name,
            bq_pool_name: args.bq_pool_name,
            info: args.info,
            milliseconds_timeout: milliseconds_timeout,
            batch_size: args.batch_size,
            webhook_url: args.webhook_url
        }
    end

    #
    # Builds the state for legacy mode
    #
    # Parameters:
    #     - args: map with the configuration
    #     - :legacy: operation mode
    #     - milliseconds_timeout: timeout in milliseconds
    #
    # Returns:
    #     - map with the state
    #
    defp build_state(args, :legacy, milliseconds_timeout) do
        %{
        mode: :legacy,
        business: args.business,
        data_source: args.data_source,
        pg_config: args.pg_config,
        info: args.info,
        milliseconds_timeout: milliseconds_timeout,
        batch_size: args.batch_size,
        webhook_url: args.webhook_url
        }
    end

    @doc """
    Handles the `:update` message that triggers the upload of data to BigQuery.

    The behavior depends on the configured mode:

    - **Pool**: Uses `Pool.BigQuery.with_connection/2` to get a connection
    - **Legacy**: Opens connections with `Postgres.connect/1` and `Odbc.connect/1`

    ## Parameters
        - `:state` (map) - Map with the state

    ## Returns
        - `:noreply` - If the message is handled successfully
        - `{:error, reason}` - If the message is not handled successfully
    """
    def handle_info(:update, %{mode: :pool} = state) do
        handle_update_pool_mode(state)
    end

    def handle_info(:update, %{mode: :legacy} = state) do
        handle_update_legacy_mode(state)
    end

    #
    # Handles the `:update` message for pool mode
    #
    # Parameters:
    #     - state: map with the state
    #
    # Returns:
    #     - :noreply: if the message is handled successfully
    #     - {:error, reason}: if the message is not handled successfully
    #
    defp handle_update_pool_mode(state) do
        %{
            business: business,
            pg_pool_name: pg_pool_name,
            bq_pool_name: bq_pool_name,
            info: info,
            milliseconds_timeout: milliseconds_timeout,
            batch_size: batch_size,
            webhook_url: webhook_url
        } = state

        try do
            Pool.BigQuery.with_connection(bq_pool_name, fn bq_conn ->
                Enum.each(info, fn table_config ->
                    batch_id = random_string_generate(15)
                    bq_table = Map.fetch!(table_config, :bq_table)
                    tipo = Map.fetch!(table_config, :tipo)
                    pg_table = Map.fetch!(table_config, :pg_table)
                    Bigquery.run_with_pool(business, bq_conn, pg_pool_name, pg_table, bq_table, tipo, batch_id, batch_size, webhook_url)
                end)
            end)
        rescue
            error ->
                Logger.error("#{to_string(__MODULE__)}. Error in cycle load (pool mode): #{inspect(error)}")
        end

        variable_wait(:later, milliseconds_timeout)
        {:noreply, state}
    end

    #
    # Handles the `:update` message for legacy mode
    #
    # Parameters:
    #     - state: map with the state
    #
    # Returns:
    #     - :noreply: if the message is handled successfully
    #     - {:error, reason}: if the message is not handled successfully
    #
    defp handle_update_legacy_mode(state) do
        %{
            business: business,
            data_source: data_source,
            pg_config: pg_config,
            info: info,
            milliseconds_timeout: milliseconds_timeout,
            batch_size: batch_size,
            webhook_url: webhook_url
        } = state

        Logger.info("#{to_string(__MODULE__)}. Iniciando ciclo de carga a BigQuery para negocio: #{to_string(business)}")

        {:ok, pg_conn} = Postgres.connect(pg_config)
        Logger.debug("#{to_string(__MODULE__)}. Conexión a PostgreSQL establecida para ciclo de negocio")

        bq_conn = Odbc.connect(data_source)
        Logger.debug("#{to_string(__MODULE__)}. Conexión ODBC a BigQuery establecida para ciclo de negocio")

        try do
            Enum.each(info, fn table_config ->
                batch_id = random_string_generate(15)

                bq_table = Map.fetch!(table_config, :bq_table)
                tipo = Map.fetch!(table_config, :tipo)
                pg_table = Map.fetch!(table_config, :pg_table)

                Bigquery.run(business, bq_conn, pg_conn, pg_table, bq_table, tipo, batch_id, batch_size, webhook_url)
            end)

            Logger.info("#{to_string(__MODULE__)}. Ciclo de carga a BigQuery finalizado para negocio: #{to_string(business)}")
        after
            Postgres.disconnect(pg_conn)
            Logger.debug("#{to_string(__MODULE__)}. Conexión a PostgreSQL cerrada para ciclo de negocio: #{to_string(business)}")

            Odbc.disconnect(bq_conn)
            Logger.debug("#{to_string(__MODULE__)}. Conexión ODBC a BigQuery cerrada para ciclo de negocio: #{to_string(business)}")
        end

        variable_wait(:later, milliseconds_timeout)
        {:noreply, state}
    end

    #
    # Adjusts the time for the activation of the genserver
    #
    # Parameters:
    #     - :start: if the message is sent to start the genserver
    #     - milliseconds_timeout: timeout in milliseconds
    #
    # Returns:
    #     - :ok: if the message is sent successfully
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
    def terminate(reason, %{business: business}) do
        Logger.info("#{to_string(__MODULE__)}. Terminando para negocio: #{to_string(business)}. Razón: #{inspect(reason)}")
        :ok
    end

end
