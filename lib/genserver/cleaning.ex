
defmodule Genserver.Cleaning do
    @moduledoc """
    Module/genserver oriented to delete the least updated rows in Bigquery. Uses the `timestamp` field to determine freshness of records.

    ## Modes of Operation

    This GenServer supports two modes:

    1. **Single business mode**: Pass a specific business key to clean only that table
       ```elixir
       {Genserver.Cleaning, {:record, data_source, 60_000}}
       ```

    2. **All tables mode**: Pass `:all` to clean all registered CleanableTable modules
       ```elixir
       {Genserver.Cleaning, {:all, data_source, 60_000}}
       ```

    ## Configuration

    Tables must be registered via the CleanableTable behaviour to be cleaned.
    See `Cleaning.CleanableTable` for more information.
    """

    use GenServer
    require Logger
    import Connection.Odbc, only: [connect: 1, disconnect: 1]
    alias Genserver.Monitor
    alias Cleaning.Cleaner


    @doc """
    Starts the cleaning GenServer.

    ### Parameters
        - info: Tuple. {business, data_source, milliseconds_timeout}
            - business: Atom. :all to clean all tables, or specific business key (e.g., :record)
            - data_source: List. ODBC connection configuration for BigQuery
            - milliseconds_timeout: Integer. Interval between cleaning cycles in milliseconds
    """
    def start_link({business, _data_source, _milliseconds_timeout} = info) do
        GenServer.start_link(__MODULE__, info, name: :"#{__MODULE__}.#{business}")
    end


    @doc """
    Initializes the GenServer state.

    Registers with Monitor and schedules first cleaning cycle.
    """
    @impl true
    def init({business, data_source, milliseconds_timeout}) do
        Monitor.register(self(), to_string(__MODULE__) <> "." <> to_string(business))

        Logger.info("#{to_string(__MODULE__)}. Initializing. Business: ---#{to_string(business)}---")

        variable_wait(:start, milliseconds_timeout)

        {:ok, {business, data_source, milliseconds_timeout}}
    end


    @doc """
    Handles the periodic :update message to perform cleaning.

    Creates an ODBC connection, executes cleaning using `Cleaning.Cleaner`,
    then closes the connection. Uses configurations defined via `Cleaning.CleanableTable`.
    """
    @impl true
    def handle_info(:update, {business, data_source, milliseconds_timeout}) do
        Logger.debug("#{to_string(__MODULE__)}. Applying duplicate/stale row cleanup in ---#{to_string(business)}---")

        Logger.debug("#{to_string(__MODULE__)}. Creating ODBC connection for cleanup")
        pid_odbc = data_source |> connect()

        # Use the new Cleaner module with CleanableTable configurations
        case business do
            :all ->
                Cleaner.run_all(pid_odbc)

            business_key ->
                Cleaner.run(business_key, pid_odbc)
        end

        Logger.debug("#{to_string(__MODULE__)}. Closing ODBC connection after cleanup")
        disconnect(pid_odbc)

        variable_wait(:later, milliseconds_timeout)
        {:noreply, {business, data_source, milliseconds_timeout}}
    end


    #
    # Adjusts the time for the activation of the genserver.
    #
    # ### Parameters
    #
    #     - state: Atom. Genserver status. Possible values: :start and :later
    #
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
