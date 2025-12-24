
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
    alias Type.Type
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

        IO.inspect(bq_config, label: ">>> [1] bq_config")
        IO.inspect(business_key, label: ">>> [2] business_key")
        Logger.debug("Starting cleanup for #{inspect(business_key)} - Table: #{bq_config.table}")

        duplicate_ids = get_duplicate_ids(pid, bq_config)
        IO.inspect(duplicate_ids, label: ">>> [3] duplicate_ids (all)")
        IO.inspect(length(duplicate_ids), label: ">>> [4] duplicate_ids count")

        count =
            duplicate_ids
            |> Enum.chunk_every(500)
            |> Enum.reduce(0, fn batch, acc ->
                IO.inspect(batch, label: ">>> [5] processing batch")
                rows_to_keep = get_rows_to_keep(batch, pid, bq_config)
                IO.inspect(rows_to_keep, label: ">>> [6] rows_to_keep")
                deleted = delete_duplicates(rows_to_keep, pid, bq_config)
                IO.inspect(deleted, label: ">>> [7] deleted count in batch")
                deleted + acc
            end)

        duration = Timex.diff(Timex.now(), start, :second)
        IO.inspect(count, label: ">>> [8] total deleted")
        Logger.debug("Finished cleaning #{inspect(business_key)}. Rows removed: #{count}. Duration: #{convert_seconds_to_humans(duration)}")

        {:ok, count}
    rescue
        error ->
            IO.inspect(error, label: ">>> [ERROR] Exception")
            IO.inspect(__STACKTRACE__, label: ">>> [ERROR] Stacktrace")
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
    #     - config: Map. Must contain :table and :id_fields keys (list of Struct.InfoAttr)
    #
    # ### Returns
    #     - List of IDs (single values if one id_field, tuples if multiple)
    #
    defp get_duplicate_ids(pid, %{table: table, id_fields: id_fields}) do
        id_columns = Enum.map(id_fields, fn info_attr -> to_string(info_attr.id) end) |> Enum.join(", ")

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
    #     - config: Map. Must contain :table, :id_fields (list of Struct.InfoAttr), and :timestamp_field (Struct.InfoAttr) keys
    #
    # ### Returns
    #     - List of tuples containing (id_values..., timestamp) for rows to keep
    #
    defp get_rows_to_keep([], _pid, _config), do: []

    defp get_rows_to_keep(ids, pid, %{table: table, id_fields: id_fields, timestamp_field: ts_field}) do
        id_columns = Enum.map(id_fields, fn info_attr -> to_string(info_attr.id) end) |> Enum.join(", ")
        ts_column = to_string(ts_field.id)
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
    #     - config: Map. Must contain :table, :id_fields (list of Struct.InfoAttr), and :timestamp_field (Struct.InfoAttr) keys
    #
    # ### Returns
    #     - Integer. Number of rows deleted
    #
    defp delete_duplicates([], _pid, _config), do: 0

    defp delete_duplicates(rows_to_keep, pid, %{table: table, id_fields: id_fields, timestamp_field: ts_field}) do
        IO.inspect(rows_to_keep, label: ">>> [DELETE-1] rows_to_keep input")
        IO.inspect(id_fields, label: ">>> [DELETE-2] id_fields")
        IO.inspect(ts_field, label: ">>> [DELETE-3] ts_field")

        conditions =
            Enum.map(rows_to_keep, fn row_tuple ->
                IO.inspect(row_tuple, label: ">>> [DELETE-4] processing row_tuple")
                row_values = Tuple.to_list(row_tuple)
                IO.inspect(row_values, label: ">>> [DELETE-5] row_values")
                id_values = Enum.take(row_values, length(id_fields))
                IO.inspect(id_values, label: ">>> [DELETE-6] id_values")
                ts_value = List.last(row_values)
                IO.inspect(ts_value, label: ">>> [DELETE-7] ts_value (raw from BQ)")
                IO.inspect(ts_field.type, label: ">>> [DELETE-8] ts_field.type")

                # Match on ID fields but NOT on the timestamp (delete older ones)
                id_conditions =
                    Enum.zip(id_fields, id_values)
                    |> Enum.map(fn {info_attr, val} ->
                        IO.inspect({info_attr.id, val, info_attr.type}, label: ">>> [DELETE-9] id condition (field, val, type)")
                        {info_attr.id, val, :eq}
                    end)

                IO.inspect(id_conditions, label: ">>> [DELETE-10] id_conditions built")
                ts_condition = {ts_field.id, ts_value, :neq}
                IO.inspect(ts_condition, label: ">>> [DELETE-11] ts_condition built")

                id_conditions ++ [ts_condition]
            end)

        IO.inspect(conditions, label: ">>> [DELETE-12] all conditions")
        statement = Sql.delete(table, conditions, [:and, :or])
        IO.inspect(statement, label: ">>> [DELETE-13] SQL statement to execute")

        result = delete(pid, statement)
        IO.inspect(result, label: ">>> [DELETE-14] delete result")
        result |> elem(1)
    end

    #
    # Builds a WHERE clause for filtering rows by their IDs.
    # Optimizes for single ID field using IN clause, otherwise uses OR conditions.
    #
    # ### Parameters
    #     - ids: List. List of ID values or tuples
    #     - id_fields: List. List of Struct.InfoAttr that form the ID
    #
    # ### Returns
    #     - String. SQL WHERE clause content (without the WHERE keyword)
    #
    defp build_where_clause(ids, id_fields) when length(id_fields) == 1 do
        IO.inspect({ids, id_fields}, label: ">>> [WHERE-1] single id_field clause")
        info_attr = hd(id_fields)
        field = info_attr.id |> to_string()
        values = Enum.map(ids, &mconvert_for_bigquery(&1, info_attr.type)) |> Enum.join(", ")
        result = "#{field} IN (#{values})"
        IO.inspect(result, label: ">>> [WHERE-2] built IN clause")
        result
    end

    defp build_where_clause(ids, id_fields) do
        IO.inspect({ids, id_fields}, label: ">>> [WHERE-3] multiple id_fields clause")
        conditions =
            Enum.map(ids, fn id_tuple ->
                id_values = if is_tuple(id_tuple), do: Tuple.to_list(id_tuple), else: [id_tuple]
                IO.inspect({id_tuple, id_values}, label: ">>> [WHERE-4] id_tuple -> id_values")

                Enum.zip(id_fields, id_values)
                |> Enum.map(fn {info_attr, val} ->
                    converted = mconvert_for_bigquery(val, info_attr.type)
                    IO.inspect({info_attr.id, val, info_attr.type, converted}, label: ">>> [WHERE-5] field, val, type, converted")
                    "#{info_attr.id} = #{converted}"
                end)
                |> Enum.join(" AND ")
                |> then(&"(#{&1})")
            end)
            |> Enum.join(" OR ")

        result = "(#{conditions})"
        IO.inspect(result, label: ">>> [WHERE-6] built OR clause")
        result
    end

    #
    # Converts a value to its BigQuery SQL representation based on the type from InfoAttr.
    # First converts the value to the correct type, then formats it for BigQuery.
    #
    # ### Parameters
    #     - value: Any. The value to convert
    #     - type: Atom. The type from InfoAttr (:string, :integer, :float, :timestamp, etc.)
    #
    # ### Returns
    #     - String. SQL-safe representation for BigQuery
    #
    defp mconvert_for_bigquery(value, type) do
        value
        |> Type.convert(type)
        |> Type.convert_for_bigquery()
    end


end
