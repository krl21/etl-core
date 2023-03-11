
defmodule Genserver.PostgresConsumer do
    @moduledoc"""
    Genserver oriented to consume from a table in a database in Postgres

    For the correct operation, you must implement the Genserver.Utils.PPostgresDb protocol
    """

    require Logger
    import Genserver.Utils.PPostgresDb
    import Connection.Odbc, only: [connect: 1]


    def start_link(data) do
        GenServer.start_link(__MODULE__, data)
    end

    def init({%{table_name: table_name, business: business}, data_source, milliseconds_timeout}) do
        Logger.info("#{inspect __MODULE__}. Initializing ConsumerFromPostgres. Table name: ---#{inspect table_name}---. Business: ---#{inspect business}---")

        Logger.info("#{inspect __MODULE__}. Created the process to communicate with ODBC-BigQuery")
        pid_odbc = connect(data_source)

        variable_wait(:start, milliseconds_timeout)

        {:ok, {business, pid_odbc, milliseconds_timeout}}
    end

    def handle_info(:update, {business, pid_odbc, milliseconds_timeout}) do

        business
        |> get_data()
        |> load(pid_odbc, business)

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
