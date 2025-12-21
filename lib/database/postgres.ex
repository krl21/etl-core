
defmodule Database.Postgres do
    @moduledoc """
    Module for working with PostgreSQL databases.

    ## Table Structure

    The created table has the following fields:
    - `id` - Autoincremental integer (PRIMARY KEY)
    - `id_nodo` - String (UUID of the node that generated the record)
    - `tipo` - String (record type/category)
    - `informacion` - JSONB (record data in JSON format)
    - `fecha_creado` - Timestamp (creation date and time)
    - `en_bq` - Boolean (default: false, indicates if sent to BigQuery)

    ## Connection Modes

    - **Simple**: use `hostname` for single server
    - **Dual**: use `write_hostname` + `read_hostname` for read replica setup
    """

    require Logger
    alias Database.Helpers


    ############
    # Connection
    ############

    @doc """
    Establishes a database connection.

    ### Parameters
        - config (Map) - Configuration map with:

            #### Simple Mode
            - :hostname - PostgreSQL server host
            - :port - Port (default 5432)
            - :database - Database name
            - :username - User
            - :password - Password
            - :ssl - Use SSL (optional, default false)
            - :pool_size - Pool size (optional, default 5)

            #### Dual Mode (Read Replica)
            - :write_hostname - Primary host (INSERT/UPDATE/DELETE)
            - :read_hostname - Replica host (SELECT)
            - Same options as simple mode

    ### Returns
        - {:ok, conn} - Successful connection
        - {:error, reason} - Connection error
    """
    def connect(config) do
        cond do
            Map.has_key?(config, :write_hostname) and Map.has_key?(config, :read_hostname) ->
                connect_dual(config)

            Map.has_key?(config, :hostname) ->
                connect_single(config)

            true ->
                {:error, "Invalid configuration: must include 'hostname' or 'write_hostname' and 'read_hostname'"}
        end
    end

    #
    # Establishes a connection to a single PostgreSQL server.
    #
    defp connect_single(config) do
        opts = Helpers.build_connection_opts(config, Map.fetch!(config, :hostname))

        case Postgrex.start_link(opts) do
            {:ok, conn} ->
                # Logger.info("Connection established with PostgreSQL: #{config.database}@#{config.hostname}")
                {:ok, conn}

            {:error, reason} = error ->
                Logger.error("Error connecting to PostgreSQL: #{inspect(reason)}")
                error
        end
    end

    #
    # Establishes a connection to a dual PostgreSQL server.
    #
    defp connect_dual(config) do
        write_hostname = Map.fetch!(config, :write_hostname)
        read_hostname = Map.fetch!(config, :read_hostname)

        write_opts = Helpers.build_connection_opts(config, write_hostname)
        read_opts = Helpers.build_connection_opts(config, read_hostname)

        with {:ok, write_conn} <- Postgrex.start_link(write_opts),
             {:ok, read_conn} <- Postgrex.start_link(read_opts) do

            # Logger.info("Dual connection established with PostgreSQL: #{config.database}")
            {:ok, %{read: read_conn, write: write_conn, mode: :dual}}
        else
            {:error, reason} = error ->
                Logger.error("Error connecting to PostgreSQL in dual mode: #{inspect(reason)}")
                error
        end
    end

    @doc """
    Closes the database connection.

    ### Parameters
        - conn (pid | Map) - Active connection (simple or dual)

    ### Returns
        - :ok
    """
    def disconnect(%{mode: :dual, read: read_conn, write: write_conn}) do
        GenServer.stop(read_conn)
        GenServer.stop(write_conn)
        Logger.info("Dual connections closed")
        :ok
    end

    def disconnect(conn) when is_pid(conn) do
        GenServer.stop(conn)
        :ok
    end

    ############
    # Helpers to get the correct connection
    ############

    #
    # Returns the read connection.
    #
    defp get_read_conn(%{mode: :dual, read: read_conn}), do: read_conn
    defp get_read_conn(conn) when is_pid(conn), do: conn

    #
    # Returns the write connection.
    #
    defp get_write_conn(%{mode: :dual, write: write_conn}), do: write_conn
    defp get_write_conn(conn) when is_pid(conn), do: conn

    ############
    # Table verification and creation
    ############

    @doc """
    Checks if a table exists in the database.

    ### Parameters
        - conn (pid | Map) - Active connection
        - table_name (String) - Table name

    ### Returns
        - {:ok, true} - Table exists
        - {:ok, false} - Table does not exist
        - {:error, reason} - Verification error
    """
    def table_exists?(conn, table_name) do
        read_conn = get_read_conn(conn)

        query = """
        SELECT EXISTS (
            SELECT FROM information_schema.tables
            WHERE table_schema = 'public'
                AND table_name = $1
        );
        """

        Postgrex.query(read_conn, query, [table_name])
        |> case do
            {:ok, %{rows: [[exists]]}} ->
                {:ok, exists}

            {:error, reason} = error ->
                Logger.error("Error verifying table #{table_name}: #{inspect(reason)}")
                error
        end
    end

    @doc """
    Creates the table if it doesn't exist, using default comments.

    ### Parameters
        - conn (pid | Map) - Active connection
        - table_name (String) - Table name to create

    ### Returns
        - :ok - Table created or already existed
        - {:error, reason} - Creation error
    """
    def create_table_if_not_exists(conn, table_name) do
        create_table_if_not_exists(conn, table_name, Helpers.default_column_comments())
    end

    @doc """
    Creates the table if it doesn't exist, with custom column comments.

    ### Parameters
        - conn (pid | Map) - Active connection
        - table_name (String) - Table name to create
        - column_comments (Map) - Descriptions for each column

    ### Returns
        - :ok - Table created or already existed
        - {:error, reason} - Creation error
    """
    def create_table_if_not_exists(conn, table_name, column_comments) do
        write_conn = get_write_conn(conn)
        sanitized_name = Helpers.sanitize_identifier(table_name)

        query = """
        CREATE TABLE IF NOT EXISTS #{sanitized_name} (
            id SERIAL PRIMARY KEY,
            id_nodo VARCHAR(36) NOT NULL,
            tipo VARCHAR(100),
            informacion JSONB NOT NULL,
            fecha_creado TIMESTAMP NOT NULL,
            en_bq BOOLEAN DEFAULT FALSE
        );
        """

        index_query = """
        CREATE INDEX IF NOT EXISTS idx_#{sanitized_name}_en_bq
        ON #{sanitized_name} (en_bq)
        WHERE en_bq = FALSE;
        """

        tipo_index_query = """
        CREATE INDEX IF NOT EXISTS idx_#{sanitized_name}_tipo
        ON #{sanitized_name} (tipo);
        """

        with {:ok, _} <- Postgrex.query(write_conn, query, []),
            {:ok, _} <- Postgrex.query(write_conn, index_query, []),
            {:ok, _} <- Postgrex.query(write_conn, tipo_index_query, []),
            :ok <- add_column_comments(write_conn, sanitized_name, column_comments) do

            Logger.info("Table #{table_name} created/verified successfully")
            :ok
        else
            {:error, reason} = error ->
                Logger.error("Error creating table #{table_name}: #{inspect(reason)}")
                error
        end
    end

    defp add_column_comments(conn, table_name, comments) when is_map(comments) do
        results =
            comments
            |> Enum.map(fn {column, description} ->
                escaped = Helpers.escape_sql_string(description)
                comment_query = "COMMENT ON COLUMN #{table_name}.#{column} IS '#{escaped}';"
                Postgrex.query(conn, comment_query, [])
            end)

        Enum.find(results, fn result -> match?({:error, _}, result) end)
        |> case do
            nil -> :ok
            error -> error
        end
    end


    @doc """
    Drops a table from the database.

    ### Parameters
        - conn (pid | Map) - Active connection
        - table_name (String) - Table name to drop

    ### Returns
        - :ok - Table dropped successfully
        - {:error, reason} - Drop error
    """
    def drop_table(conn, table_name) do
        write_conn = get_write_conn(conn)
        sanitized_name = Helpers.sanitize_identifier(table_name)

        query = "DROP TABLE IF EXISTS #{sanitized_name};"

        Postgrex.query(write_conn, query, [])
        |> case do
            {:ok, _} ->
                Logger.info("Table #{table_name} dropped successfully")
                :ok

            {:error, reason} = error ->
                Logger.error("Error dropping table #{table_name}: #{inspect(reason)}")
                error
        end
    end


    ############
    # WRITE Operations (use write connection)
    ############

    @doc """
    Inserts a new record into the table.

    ### Parameters
        - conn (pid | Map) - Active connection
        - table_name (String) - Table name
        - record (Map) - Record data with:
            - :id_nodo (String) - Node UUID (required)
            - :tipo (String) - Type/category (optional)
            - :informacion (Map) - JSON data (required)

    ### Returns
        - {:ok, id} - Inserted record ID
        - {:error, reason} - Insert error
    """
    def insert(conn, table_name, record) do
        insert_many(conn, table_name, [record])
    end

    @doc """
    Inserts multiple records into the table efficiently.

    ### Parameters
        - conn (pid | Map) - Active connection
        - table_name (String) - Table name
        - records (List) - List of maps with data (same structure as `insert/3`)

    ### Returns
        - {:ok, count} - Number of inserted records
        - {:error, reason} - Insert error
    """
    def insert_many(conn, table_name, records) when is_list(records) do
        if Enum.empty?(records) do
            {:ok, 0}
        else
            write_conn = get_write_conn(conn)
            sanitized_name = Helpers.sanitize_identifier(table_name)

            {values_sql, params, _} =
                records
                |> Enum.reduce({"", [], 1}, fn record, {sql, params, idx} ->
                    id_nodo = Map.fetch!(record, :id_nodo)
                    tipo = Map.get(record, :tipo)
                    informacion = Helpers.to_json(Map.fetch!(record, :informacion))
                    fecha_creado = DateTime.utc_now()
                    en_bq = false

                    value_sql = "($#{idx}, $#{idx + 1}, $#{idx + 2}::jsonb, $#{idx + 3}, $#{idx + 4})"
                    new_sql = if sql == "", do: value_sql, else: "#{sql}, #{value_sql}"

                    {new_sql, params ++ [id_nodo, tipo, informacion, fecha_creado, en_bq], idx + 5}
                end)

            query = """
            INSERT INTO #{sanitized_name} (id_nodo, tipo, informacion, fecha_creado, en_bq)
            VALUES #{values_sql};
            """

            Postgrex.query(write_conn, query, params)
            |> case do
                {:ok, %{num_rows: count}} ->
                    {:ok, count}

                {:error, reason} = error ->
                    Logger.error("Error inserting multiple records into #{table_name}: #{inspect(reason)}")
                    error
            end
        end
    end


    ############
    # READ Operations (use read connection)
    ############

    @doc """
    Gets all records where `en_bq == false`.

    ### Parameters
        - conn (pid | Map) - Active connection
        - table_name (String) - Table name
        - register_type (String | nil) - Optional type filter. If nil, returns all pending records.

    ### Returns
        - {:ok, records} - List of maps with records
        - {:error, reason} - Query error
    """
    def get_pending_bq(conn, table_name, register_type \\ nil) do
        read_conn = get_read_conn(conn)
        sanitized_name = Helpers.sanitize_identifier(table_name)

        {query, params} =
            register_type
            |> case do
                nil ->
                    {"""
                    SELECT id, id_nodo, tipo, informacion, fecha_creado, en_bq
                    FROM #{sanitized_name}
                    WHERE NOT en_bq;
                    """, []}

                _ ->
                    {"""
                    SELECT id, id_nodo, tipo, informacion, fecha_creado, en_bq
                    FROM #{sanitized_name}
                    WHERE tipo = $1 AND NOT en_bq;
                    """, [register_type]}
            end

        Postgrex.query(read_conn, query, params)
        |> case do
            {:ok, result} ->
                {:ok, Helpers.parse_query_result(result)}

            {:error, reason} = error ->
                Logger.error("Error getting pending records from #{table_name}: #{inspect(reason)}")
                error
        end
    end

    ############
    # Change Operations (use write connection)
    ############

    @doc """
    Deletes records by a list of IDs.

    ### Parameters
        - conn (pid | Map) - Active connection
        - table_name (String) - Table name
        - ids (List) - List of IDs to delete

    ### Returns
        - {:ok, count} - Number of deleted records
        - {:error, reason} - Delete error
    """
    def delete_by_ids(conn, table_name, ids) when is_list(ids) do
        if Enum.empty?(ids) do
            {:ok, 0}
        else
            write_conn = get_write_conn(conn)
            sanitized_name = Helpers.sanitize_identifier(table_name)
            placeholders = Helpers.build_placeholders(length(ids))

            query = """
            DELETE FROM #{sanitized_name}
            WHERE id IN (#{placeholders});
            """

            Postgrex.query(write_conn, query, ids)
            |> case do
                {:ok, %{num_rows: count}} ->
                    Logger.info("Deleted #{count} records from #{table_name}")
                    {:ok, count}

                {:error, reason} = error ->
                    Logger.error("Error deleting records from #{table_name}: #{inspect(reason)}")
                    error
            end
        end
    end

    @doc """
    Updates the `en_bq` field to `true` for the specified records.

    ### Parameters
        - conn (pid | Map) - Active connection
        - table_name (String) - Table name
        - ids (List) - List of record IDs to update

    ### Returns
        - {:ok, count} - Number of updated records
        - {:error, reason} - Update error
    """
    def mark_as_sent_to_bq(conn, table_name, ids) when is_list(ids) do
        if Enum.empty?(ids) do
            {:ok, 0}
        else
            write_conn = get_write_conn(conn)
            sanitized_name = Helpers.sanitize_identifier(table_name)
            placeholders = Helpers.build_placeholders(length(ids))

            query = """
            UPDATE #{sanitized_name}
            SET en_bq = TRUE
            WHERE id IN (#{placeholders});
            """

            Postgrex.query(write_conn, query, ids)
            |> case do
                {:ok, %{num_rows: count}} ->
                    {:ok, count}

                {:error, reason} = error ->
                    Logger.error("Error updating en_bq in #{table_name}: #{inspect(reason)}")
                    error
            end
        end
    end

    ############
    # Utility Functions
    ############

    @doc """
    Checks if the connection is in dual mode.

    ### Parameters
        - conn (pid | Map) - Active connection

    ### Returns
        - true - Dual connection (separate read/write)
        - false - Simple connection
    """
    def dual_mode?(%{mode: :dual}), do: true
    def dual_mode?(_), do: false

    @doc """
    Gets information about the current connection.

    ### Parameters
        - conn (pid | Map) - Active connection

    ### Returns
        - Map - Connection information
    """
    def connection_info(%{mode: :dual, read: read_conn, write: write_conn}) do
        %{
            mode: :dual,
            read_pid: read_conn,
            write_pid: write_conn,
            read_alive: Process.alive?(read_conn),
            write_alive: Process.alive?(write_conn)
        }
    end

    def connection_info(conn) when is_pid(conn) do
        %{
            mode: :single,
            pid: conn,
            alive: Process.alive?(conn)
        }
    end
end
