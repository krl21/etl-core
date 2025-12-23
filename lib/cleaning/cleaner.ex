
defmodule Cleaning.Cleaner do
    @moduledoc """
    Core cleaning logic that uses CleanableTable configurations.

    This module provides the actual cleaning operations using the configurations defined via the CleanableTable behaviour.

    ## Usage

    ```elixir
    # Clean a specific business type in BigQuery
    Cleaning.Cleaner.run(:record, pid_odbc)

    # Clean all registered tables in BigQuery
    Cleaning.Cleaner.run_all(pid_odbc)

    # Clean a specific business type in PostgreSQL
    Cleaning.Cleaner.run_postgres(:record, pid_pg)

    # Clean all registered tables in PostgreSQL
    Cleaning.Cleaner.run_all_postgres(pid_pg)
    ```
    """

    require Logger
    import Connection.Odbc, only: [select: 2, delete: 2]
    alias Statement.Sql
    alias Database.Postgres
    import Stuff, only: [convert_seconds_to_humans: 1]


    @doc """
    Runs cleaning for a specific business type using its CleanableTable configuration.

    ### Parameters
        - business_key: Atom. The business key (e.g., :record, :task)
        - pid: Process. ODBC connection to BigQuery

    ### Returns
        - {:ok, count} on success with number of rows removed
        - {:error, :not_registered} if module not found
        - {:error, reason} if cleaning fails
    """
    def run(business_key, pid) when is_atom(business_key) do
        case Cleaning.CleanableTableRegistry.get(business_key) do
            nil ->
                Logger.warning("No CleanableTable registered for business_key: #{inspect(business_key)}")
                {:error, :not_registered}

            module ->
                run_for_module(module, pid)
        end
    end


    @doc """
    Runs cleaning for all enabled CleanableTable modules.

    ### Parameters
        - pid: Process. ODBC connection to BigQuery

    ### Returns
        - List of tuples {business_key, {:ok, count} | {:error, reason}}
    """
    def run_all(pid) do
        start = Timex.now()

        results =
            Cleaning.CleanableTableRegistry.enabled()
            |> Enum.map(fn module ->
                {module.business_key(), run_for_module(module, pid)}
            end)

        total_time = Timex.diff(Timex.now(), start, :second)
        Logger.info("Finished cleaning all tables. Duration: #{convert_seconds_to_humans(total_time)}")

        results
    end

    @doc """
    Runs cleaning for a specific module implementing CleanableTable.

    ### Parameters
        - module: Module. A module implementing CleanableTable behaviour
        - pid: Process. ODBC connection to BigQuery

    ### Returns
        - {:ok, count} with number of rows removed
        - {:error, reason} if cleaning fails
    """
    def run_for_module(module, pid) do
        start = Timex.now()
        bq_config = module.bigquery_config()
        business_key = module.business_key()

        Logger.debug("Starting cleanup for #{inspect(business_key)} - Table: #{bq_config.table}")

        count =
            get_duplicate_ids(pid, bq_config)
            |> Enum.chunk_every(500)
            |> Enum.reduce(0, fn batch, acc ->
                batch
                |> get_rows_to_keep(pid, bq_config)
                |> delete_duplicates(pid, bq_config)
                |> Kernel.+(acc)
            end)

        duration = Timex.diff(Timex.now(), start, :second)
        Logger.debug("Finished cleaning #{inspect(business_key)}. Rows removed: #{count}. Duration: #{convert_seconds_to_humans(duration)}")

        {:ok, count}
    rescue
        error ->
            Logger.error("Error cleaning #{inspect(module)}: #{inspect(error)}")
            {:error, error}
    end


    # ============================================
    # POSTGRESQL CLEANING FUNCTIONS
    # ============================================

    @doc """
    Runs PostgreSQL cleaning for a specific business type. Deletes records with estado_analisis = "analizado_en_bq" from the configured table.

    ### Parameters
        - business_key: Atom. The business key (e.g., :record, :task)
        - pid_pg: pid | Map. PostgreSQL connection

    ### Returns
        - {:ok, count} on success with number of rows removed
        - {:error, :not_registered} if module not found
        - {:error, reason} if cleaning fails
    """
    def run_postgres(business_key, pid_pg) when is_atom(business_key) do
        case Cleaning.CleanableTableRegistry.get(business_key) do
            nil ->
                Logger.warning("CleanableTable registered for business_key: #{inspect(business_key)}")
                {:error, :not_registered}

            module ->
                run_postgres_for_module(module, pid_pg)
        end
    end

    @doc """
    Runs PostgreSQL cleaning for all enabled CleanableTable modules.

    ### Parameters
        - pid_pg: pid | Map. PostgreSQL connection

    ### Returns
        - List of tuples {business_key, {:ok, count} | {:error, reason}}
    """
    def run_all_postgres(pid_pg) do
        start = Timex.now()
        total_deleted = :counters.new(1, [:atomics])

        results =
            Cleaning.CleanableTableRegistry.enabled()
            |> Enum.map(fn module ->
                result = run_postgres_for_module(module, pid_pg)

                case result do
                    {:ok, count} -> :counters.add(total_deleted, 1, count)
                    _ -> :ok
                end

                {module.business_key(), result}
            end)

        total_time = Timex.diff(Timex.now(), start, :second)
        total_count = :counters.get(total_deleted, 1)

        Logger.info("PostgreSQL cleanup completed. Total records deleted: #{total_count}. Duration: #{convert_seconds_to_humans(total_time)}")

        results
    end

    @doc """
    Runs PostgreSQL cleaning for a specific module implementing CleanableTable.

    ### Parameters
        - module: Module. A module implementing CleanableTable behaviour
        - pid_pg: pid | Map. PostgreSQL connection

    ### Returns
        - {:ok, count} with number of rows removed
        - {:error, reason} if cleaning fails
    """
    def run_postgres_for_module(module, pid_pg) do
        pg_config = module.postgres_config()
        business_key = module.business_key()
        table_name = pg_config.table

        Logger.debug("Starting PostgreSQL cleanup for #{inspect(business_key)} - Table: #{table_name}")

        case Postgres.delete_analyzed_records(pid_pg, table_name) do
            {:ok, count} ->
                Logger.info("PostgreSQL cleanup for #{inspect(business_key)}: #{count} records deleted from #{table_name}")
                {:ok, count}

            {:error, reason} = error ->
                Logger.error("Error cleaning PostgreSQL table #{table_name}: #{inspect(reason)}")
                error
        end
    rescue
        error ->
            Logger.error("Error cleaning PostgreSQL for #{inspect(module)}: #{inspect(error)}")
            {:error, error}
    end


    # ============================================
    # PRIVATE FUNCTIONS - BIGQUERY
    # ============================================

    #
    # Gets IDs that have duplicate rows in the table.
    #
    # ### Parameters
    #     - pid: Process. ODBC connection to BigQuery
    #     - config: Map. Must contain :table and :id_fields keys
    #
    # ### Returns
    #     - List of IDs (single values if one id_field, tuples if multiple)
    #
    defp get_duplicate_ids(pid, %{table: table, id_fields: id_fields}) do
        id_columns = Enum.map(id_fields, &to_string/1) |> Enum.join(", ")

        statement = """
        SELECT #{id_columns}
        FROM #{table}
        GROUP BY #{id_columns}
        HAVING COUNT(*) > 1
        """

        select(pid, statement)
        |> Enum.map(fn row ->
            values = Enum.map(row, fn {_col, value} -> value end)

            case length(id_fields) do
                1 -> hd(values)
                _ -> List.to_tuple(values)
            end
        end)
    end

    #
    # Gets the most recent row for each duplicate ID (the one to keep).
    #
    # ### Parameters
    #     - ids: List. List of duplicate IDs to process
    #     - pid: Process. ODBC connection to BigQuery
    #     - config: Map. Must contain :table, :id_fields, and :timestamp_field keys
    #
    # ### Returns
    #     - List of tuples containing (id_values..., timestamp) for rows to keep
    #
    defp get_rows_to_keep([], _pid, _config), do: []

    defp get_rows_to_keep(ids, pid, %{table: table, id_fields: id_fields, timestamp_field: ts_field}) do
        id_columns = Enum.map(id_fields, &to_string/1) |> Enum.join(", ")
        ts_column = to_string(ts_field)
        all_columns = "#{id_columns}, #{ts_column}"

        where_clause = build_where_clause(ids, id_fields)

        statement = """
        WITH ranked AS (
            SELECT #{all_columns},
                   ROW_NUMBER() OVER(PARTITION BY #{id_columns} ORDER BY #{ts_column} DESC) AS rn
            FROM #{table}
            WHERE #{where_clause}
        )
        SELECT #{all_columns}
        FROM ranked
        WHERE rn = 1
        """

        select(pid, statement)
        |> Enum.map(fn row ->
            values = Enum.map(row, fn {_col, value} -> value end)
            List.to_tuple(values)
        end)
    end

    #
    # Deletes duplicate rows, keeping the one with the most recent timestamp.
    #
    # ### Parameters
    #     - rows_to_keep: List. List of tuples with (id_values..., timestamp) for rows to preserve
    #     - pid: Process. ODBC connection to BigQuery
    #     - config: Map. Must contain :table, :id_fields, and :timestamp_field keys
    #
    # ### Returns
    #     - Integer. Number of rows deleted
    #
    defp delete_duplicates([], _pid, _config), do: 0

    defp delete_duplicates(rows_to_keep, pid, %{table: table, id_fields: id_fields, timestamp_field: ts_field}) do
        conditions =
            Enum.map(rows_to_keep, fn row_tuple ->
                row_values = Tuple.to_list(row_tuple)
                id_values = Enum.take(row_values, length(id_fields))
                ts_value = List.last(row_values)

                # Match on ID fields but NOT on the timestamp (delete older ones)
                id_conditions =
                    Enum.zip(id_fields, id_values)
                    |> Enum.map(fn {field, val} -> {field, val, :eq} end)

                ts_condition = {ts_field, ts_value, :neq}

                id_conditions ++ [ts_condition]
            end)

        statement = Sql.delete(table, conditions, [:and, :or])

        delete(pid, statement)
        |> elem(1)
    end

    #
    # Builds a WHERE clause for filtering rows by their IDs.
    # Optimizes for single ID field using IN clause, otherwise uses OR conditions.
    #
    # ### Parameters
    #     - ids: List. List of ID values or tuples
    #     - id_fields: List. List of field atoms that form the ID
    #
    # ### Returns
    #     - String. SQL WHERE clause content (without the WHERE keyword)
    #
    defp build_where_clause(ids, id_fields) when length(id_fields) == 1 do
        field = hd(id_fields) |> to_string()
        values = Enum.map(ids, &format_value/1) |> Enum.join(", ")
        "#{field} IN (#{values})"
    end

    defp build_where_clause(ids, id_fields) do
        conditions =
            Enum.map(ids, fn id_tuple ->
                id_values = if is_tuple(id_tuple), do: Tuple.to_list(id_tuple), else: [id_tuple]

                Enum.zip(id_fields, id_values)
                |> Enum.map(fn {field, val} -> "#{field} = #{format_value(val)}" end)
                |> Enum.join(" AND ")
                |> then(&"(#{&1})")
            end)
            |> Enum.join(" OR ")

        "(#{conditions})"
    end


    #
    # Formats a value for use in SQL statements.
    #
    # ### Parameters
    #     - val: Any. The value to format
    #
    # ### Returns
    #     - String. SQL-safe representation of the value
    #
    defp format_value(val) when is_binary(val), do: "'#{val}'"
    defp format_value(val) when is_integer(val), do: to_string(val)
    defp format_value(val) when is_float(val), do: to_string(val)
    defp format_value(val), do: "'#{to_string(val)}'"


end
