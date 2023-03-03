
defmodule Connection.Odbc do
    @moduledoc"""
    Module for working with the ODBC library. It frees you from having to know how Erlang's :odbc library works.
    """
alias Connection.Odbc

    require Logger
    import Type.Type, only: [convert: 2]
    use Decoratorm


    ################
    ### Functions
    ################

    @doc"""
    Start the ODBC application

    ### Return:

        - :ok | exception. If the ODBC application has not been started or if it has already been started, return the atom. Otherwise, it throws an exception with the error.

    """
    def start() do
        :odbc.start()
        |> case do
            :ok ->
                Logger.debug("Connection started with ODBC")
                :ok
            {:error, {:already_started, :odbc}} ->
                Logger.debug("Previously started connection with ODBC")
                :ok
            {:error, error} ->
                raise("Unhandled error trying to \":odbc.start/0\", Error: #{inspect error}")
        end
    end

    @doc"""
    Stop the ODBC application

    ### Return:

        - :ok | exception. If the ODBC application has not been stopped or if it has already been stopped, return the atom. Otherwise, it throws an exception with the error.

    """
    def stop() do
        :odbc.stop()
        |> case do
            :ok ->
                Logger.debug("Connection stop with ODBC")
                :ok
            {:error, {:not_started, :odbc}} ->
                Logger.debug("Previously stopped connection with ODBC")
                :ok
            {:error, error} ->
                raise("Unhandled error trying to \":odbc.stop/0\", Error: #{inspect error}")
        end
    end

    @doc"""
    Establishes the connection to Data Source

    ### Parameter:

        - data_source: List. Data source information.

    ### Return:

        - PID | Exception. If the connection can be established with the parameters defined in the configuration files, process identifier is returned. Otherwise, it throws an exception with the error.

    """
    def connect(data_source) when is_list(data_source) do
        data_source
        |> Enum.reduce("", fn {key, value}, acc -> acc <> "#{key}=#{value};" end)
        |> Kernel.to_charlist()
        |> :odbc.connect([])
        |> case do
            {:ok, pid} -> pid
            {:error, error} ->
                raise("Unhandled error trying to \":odbc.connect/2\", Error: #{inspect error}")
        end
    end

    @doc"""
    Genera un UUID

    ### Parameter:

        - pid: Process.

    ### Return:

        - string | Exception. If the query succeeds, it returns the UUID; otherwise, it raises an exception from `:odbc.sql_query/2` statement.

    """
    def get_uuid(pid) when is_pid(pid) do
        query = Statement.Sql.generate_uuid() |> Kernel.to_charlist()

        :odbc.sql_query(pid, query)
        |> case do
            {_, _, [{uuid}]} -> List.to_string(uuid)
            {:error, error} -> raise(inspect error)
            unknown -> raise("Not match. Entity: #{inspect __MODULE__}. Environment: #{inspect __ENV__.function}. Value: #{inspect unknown}.")
        end
    end

    @doc"""
    Inserts an object into the specified table

    ### Parameters:

        - pid: Process. Process connecting Elixir and ODBC.

        - statement: String. SQL Statement.

    ### Return:

        - {:inserted, 1} | Exception

    """
    def insert(pid, statement)
        when is_pid(pid) and is_binary(statement)
        do
            query = Kernel.to_charlist(statement)

            :odbc.sql_query(pid, query)
            |> case do
                {:error, error} -> raise("#{inspect(error)}. Statement: #{statement}")
                result -> result
            end
    end

    @doc"""
    Create and execute an SQL statement of type `SELECT xx FROM x WHERE xxx. It is assumed that WHERE condition will only have the AND operator. Para

    ### Parameters:

        - pid: Process. Process connecting Elixir and ODBC.

        - statement: String. SQL Statement.

    ### Return:

        - list of (list of tuples ({:atom, :string})) | Exception. Fields with null values are ignored.

    """
    def select(pid, statement) when is_pid(pid) and is_binary(statement) do
        query = Kernel.to_charlist(statement)

        :odbc.sql_query(pid, query)
        |> build_format()
    end

    @doc"""
    Update an object into the specified table. It uses the `retry` decorator to retry the execution of the statement, in case of a concurrency error issued by BigQuery.
    ### Parameters:

        - pid: Process. Process connecting Elixir and ODBC.

        - statement: String. SQL Statement.

    ### Return:

        - Exception | {:updated, n} where n is the number of records updated

    """
    @decorate retry()
    def update(pid, statement) when is_pid(pid) and is_binary(statement) do
        query = Kernel.to_charlist(statement)

        :odbc.sql_query(pid, query)
        |> case do
            {:error, error} -> raise(inspect error)
            result -> result
        end
    end

    @doc"""
    Delete rows from the specified table

    ### Parameters:

        - pid: Process. Process connecting Elixir and ODBC.

        - statement: String. SQL Statement.

    ### Return:

        - Exception | {:updated, n} where n is the number of records deleted

    """
    def delete(pid, statement) when is_pid(pid) and is_binary(statement) do
        query = Kernel.to_charlist(statement)

        :odbc.sql_query(pid, query)
        |> case do
            {:error, error} -> raise(inspect error)
            result -> result
        end
    end


    ################
    ### Helper functions
    ################

    #
    # Given the return of a query, build the structure: list of (list of tuples ({:atom, :string})), or return the exception of having made the query. Tuples with null values are ignored.
    #
    #
    defp build_format(rq) do
        case rq do
            {_, cols, result} ->
                cols = cols
                        |> Enum.map(fn c ->
                            convert(c, :string)
                            |> convert(:atom)
                        end)

                result
                |> Enum.map(fn r ->
                    tmp = r
                        |> Tuple.to_list()
                        |> Enum.map(fn
                            :null -> nil
                            e -> convert(e, :string)
                        end)
                    Enum.zip(cols, tmp)
                end)
                |> Enum.map(fn list ->
                    list
                    |> Enum.filter(fn {_, value} -> not is_nil(value) end)
                end)

            {:error, error} ->
                raise(inspect error)

            unknown ->
                raise("Not match. Value: #{inspect unknown }. Entity: #{inspect __MODULE__}")
        end
    end


end
