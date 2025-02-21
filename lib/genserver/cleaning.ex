
defmodule Genserver.Cleaning do
    @moduledoc"""
    Module/genserver oriented to delete the least updated rows in Bigquery. use the `timestamp` field
    """

    use GenServer
    require Logger
    import Connection.Odbc, only: [connect: 1]
    import Genserver.Protocols.PAutomaticClean
    alias Genserver.Monitor


    def start_link({business, _data_source, _milliseconds_timeout} = info) do
        GenServer.start_link(__MODULE__, info, name: :"#{__MODULE__}.#{business}")
    end

    def init({business, data_source, milliseconds_timeout}) do
        Monitor.register(self(), to_string(__MODULE__) <> "." <> to_string(business))

        Logger.info("#{to_string(__MODULE__)}. Initializing. Business: ---#{to_string(business)}---")

        Logger.info("#{to_string(__MODULE__)}. Created the process to communicate with ODBC-BigQuery")
        pid_odbc = data_source |> connect()

        variable_wait(:start, milliseconds_timeout)

        {:ok, {business, pid_odbc, milliseconds_timeout}}
    end

    def handle_info(:update, {business, pid_odbc, milliseconds_timeout}) do
        Logger.debug("#{to_string(__MODULE__)}. Applying duplicate/stale row cleanup in ---#{to_string(business)}---")

        run(business, pid_odbc, {})

        variable_wait(:later, milliseconds_timeout)
        {:noreply, {business, pid_odbc, milliseconds_timeout}}
    end

    #
    # Adjust the time for the activation of the genserver
    #
    # Parameter:
    #
    #     - state: Atom. Genserver status. Possible values: start and later
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
