
defmodule Genserver.PostgresConsumer do
    @moduledoc"""
    Genserver oriented to consume from a table in a database in Postgres

    For the correct operation, you must implement the Genserver.Protocols.PPostgresDb protocol
    """

    require Logger
    import Genserver.Protocols.PPostgresDb
    import Connection.Odbc, only: [connect: 1]
    import Stuff, only: [random_string_generate: 1]
    alias Genserver.Monitor


    def start_link(data) do
        GenServer.start_link(__MODULE__, data)
    end

    def init({%{table_name: table_name, business: business}, data_source, milliseconds_timeout}) do
        Monitor.register(self(), to_string(__MODULE__) <> "." <> to_string(business) <> "." <> to_string(table_name))

        Logger.info("#{inspect __MODULE__}. Initializing ConsumerFromPostgres. Table name: ---#{inspect table_name}---. Business: ---#{inspect business}---")

        Logger.info("#{inspect __MODULE__}. Created the process to communicate with ODBC-BigQuery")
        pid_odbc = connect(data_source)

        variable_wait(:start, milliseconds_timeout)

        {:ok, {business, pid_odbc, milliseconds_timeout}}
    end

    def handle_info(:update, {business, pid_odbc, milliseconds_timeout}) do

        perform(
            business,
            pid_odbc,
            random_string_generate(15)
        )

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
