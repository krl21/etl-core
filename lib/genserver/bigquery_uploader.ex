
defmodule Genserver.BigqueryUploader do
    @moduledoc"""
    GenServer for uploading pending records to BigQuery.
    """

    use GenServer
    require Logger
    import Genserver.Protocols.PBigqueryUploader
    alias Genserver.Monitor
    import Time.Timem, only: [notification_frequency: 1]
    import Stuff, only: [random_string_generate: 1]


    @doc"""
    Starts the GenServer for data upload to BigQuery.

    ### Parameters:
        - business (atom): Business/context identifier.
        - data_source (list): ODBC connection configuration for BigQuery.
        - pg_config (map): PostgreSQL connection configuration.
        - info (list): List of maps with table configuration:
            - :bq_table (string): Full BigQuery table name.
            - :tipo (string): Type field value to filter records.
            - :pg_table (string): PostgreSQL table name for pending records.
        - periodicity (map): Activation periodicity map:
            - :day (integer): Days.
            - :hour (integer): Hours.
            - :minute (integer): Minutes.
            - :second (integer): Seconds.

    ### Returns:
        - {:ok, pid} | {:error, reason}
    """
    def start_link({business, _data_source, _pg_config, _info, _periodicity} = args) do
        GenServer.start_link(__MODULE__, args, name: :"#{__MODULE__}.#{business}")
    end

    @doc"""
    Initializes the GenServer state.

    ### Parameters:
        - Tuple with:
            - business (atom): Business identifier.
            - data_source (list): ODBC connection configuration for BigQuery.
            - pg_config (map): PostgreSQL connection configuration.
            - info (list): List of table configurations.
            - periodicity (map): Activation periodicity.

    ### Returns:
        - {:ok, state}
    """
    def init({business, data_source, pg_config, info, periodicity}) do
        Monitor.register(self(), to_string(__MODULE__) <> "." <> to_string(business))

        Logger.info("#{to_string(__MODULE__)}. Initializing. Business: ---#{to_string(business)}---")

        milliseconds_timeout = notification_frequency(periodicity)

        state = %{
            business: business,
            data_source: data_source,
            pg_config: pg_config,
            info: info,
            milliseconds_timeout: milliseconds_timeout
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
            data_source: data_source,
            pg_config: pg_config,
            info: info,
            milliseconds_timeout: milliseconds_timeout
        } = state

        batch_id = random_string_generate(15)

        Enum.each(info, fn table_config ->
            bq_table = Map.fetch!(table_config, :bq_table)
            tipo = Map.fetch!(table_config, :tipo)
            pg_table = Map.fetch!(table_config, :pg_table)

            run(business, data_source, pg_config, pg_table, bq_table, tipo, batch_id)
        end)

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

end
