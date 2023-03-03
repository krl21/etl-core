
defmodule Genserver.Cleaning do
    @moduledoc"""
    Module/genserver oriented to delete the least updated rows in Bigquery. use the `timestamp` field
    """

    use GenServer
    require Logger
    import Connection.Odbc, only: [connect: 1]
    import Genserver.Utils.PAutomaticClean

    def start_link({business, _data_source, _seconds_timeout} = info) do
        GenServer.start_link(__MODULE__, info, name: :"#{__MODULE__}.#{business}")
    end

    def init({business, data_source, seconds_timeout}) do
        Logger.info("#{inspect __MODULE__}. Initializing Cleaning. Business: ---#{business}---")

        Logger.info("#{inspect __MODULE__}. Created the process to communicate with ODBC-BigQuery")
        pid_odbc = data_source |> connect()

        variable_wait(:start, seconds_timeout)

        {:ok, {business, pid_odbc, seconds_timeout}}
    end

    def handle_info(:update, {business, pid_odbc, seconds_timeout}) do
        Logger.debug("#{__MODULE__}. Applying duplicate/stale row cleanup in ---#{business}---")

        run(business, pid_odbc, {})

        variable_wait(:later, seconds_timeout)
        {:noreply, {business, pid_odbc, seconds_timeout}}
    end

    #
    # Adjust the time for the activation of the genserver
    #
    # Parameter:
    #
    #     - state: Atom. Genserver status. Possible values: start and later
    #
    #     - seconds_timeout: Integer. total seconds to reactivate the genserver.
    #
    defp variable_wait(:start, _seconds_timeout) do
        10 * 1_000
        |> :erlang.send_after(self(), :update)
    end

    defp variable_wait(:later, seconds_timeout) do
        seconds_timeout * 1_000
        |> :erlang.send_after(self(), :update)
    end





end
