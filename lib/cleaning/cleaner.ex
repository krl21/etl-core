
defmodule Cleaning.Cleaner do
    @moduledoc """
    Core cleaning logic that uses CleanableTable configurations.
    ```
    """

    require Logger
    import Connection.Odbc, only: [select: 2, delete: 2]
    alias Statement.Sql
    alias Database.Postgres
    alias Type.Type
    alias Notification.Notify
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
    def run(business_key, pid, opts \\ []) when is_atom(business_key) do
        case Cleaning.CleanableTableRegistry.get(business_key) do
            nil ->
                Logger.warning("No hay CleanableTable registrada para la llave: #{inspect(business_key)}")
                {:error, :not_registered}

            module ->
                run_for_module(module, pid, opts)
        end
    end


    @doc """
    Runs cleaning for all enabled CleanableTable modules.

    ### Parameters
        - pid: Process. ODBC connection to BigQuery

    ### Returns
        - List of tuples {business_key, {:ok, count} | {:error, reason}}
    """
    def run_all(pid, opts \\ []) do
        start = Timex.now()

        results =
            Cleaning.CleanableTableRegistry.enabled()
            |> Enum.map(fn module ->
                {module.business_key(), run_for_module(module, pid, opts)}
            end)

        total_time = Timex.diff(Timex.now(), start, :second)
        Logger.info("Limpieza de todas las tablas finalizada. Duración: #{convert_seconds_to_humans(total_time)}")

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
    def run_for_module(module, pid, opts \\ []) do
        webhook_url = Keyword.get(opts, :webhook_url)

        try do
            bq_config = module.bigquery_config()

            if is_nil(bq_config) do
                Logger.debug("Omitiendo limpieza de BigQuery para #{inspect(module)} - no hay definida bigquery_config")
                {:ok, 0}
            else
                run_bigquery_cleanup(module, bq_config, pid, webhook_url)
            end
        rescue
            error ->
                message = "Error en limpieza de BigQuery #{inspect(module)}: #{inspect(error)}"
                Logger.error(message)
                notify_error(webhook_url, message)
                {:error, error}
        end
    end

    defp run_bigquery_cleanup(module, bq_config, pid, _webhook_url) do
        start = Timex.now()
        business_key = module.business_key()

        Logger.debug("Iniciando limpieza para #{inspect(business_key)} - Tabla: #{bq_config.table}")

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
        Logger.debug("Limpieza de #{inspect(business_key)} finalizada. Filas eliminadas: #{count}. Duración: #{convert_seconds_to_humans(duration)}")

        {:ok, count}
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
    def run_postgres(business_key, pid_pg, opts \\ []) when is_atom(business_key) do
        case Cleaning.CleanableTableRegistry.get(business_key) do
            nil ->
                Logger.warning("No hay CleanableTable registrada para la llave: #{inspect(business_key)}")
                {:error, :not_registered}

            module ->
                run_postgres_for_module(module, pid_pg, opts)
        end
    end

    @doc """
    Runs PostgreSQL cleaning for all enabled CleanableTable modules.

    ### Parameters
        - pid_pg: pid | Map. PostgreSQL connection

    ### Returns
        - List of tuples {business_key, {:ok, count} | {:error, reason}}
    """
    def run_all_postgres(pid_pg, opts \\ []) do
        start = Timex.now()
        total_deleted = :counters.new(1, [:atomics])

        results =
            Cleaning.CleanableTableRegistry.enabled()
            |> Enum.map(fn module ->
                result = run_postgres_for_module(module, pid_pg, opts)

                case result do
                    {:ok, count} -> :counters.add(total_deleted, 1, count)
                    _ -> :ok
                end

                {module.business_key(), result}
            end)

        total_time = Timex.diff(Timex.now(), start, :second)
        total_count = :counters.get(total_deleted, 1)

        Logger.info("Limpieza de PostgreSQL completada. Total de registros eliminados: #{total_count}. Duración: #{convert_seconds_to_humans(total_time)}")

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
    def run_postgres_for_module(module, pid_pg, opts \\ []) do
        webhook_url = Keyword.get(opts, :webhook_url)

        try do
            pg_config = module.postgres_config()

            if is_nil(pg_config) do
                Logger.debug("Omitiendo limpieza de PostgreSQL para #{inspect(module)} - no hay definida postgres_config")
                {:ok, 0}
            else
                run_postgres_cleanup(module, pg_config, pid_pg, webhook_url)
            end
        rescue
            error ->
                message = "Error en limpieza de PostgreSQL para #{inspect(module)}: #{inspect(error)}"
                Logger.error(message)
                notify_error(webhook_url, message)
                {:error, error}
        end
    end

    defp run_postgres_cleanup(module, pg_config, pid_pg, webhook_url) do
        business_key = module.business_key()
        table_name = pg_config.table
        register_type = Map.get(pg_config, :register_type, nil)

        Logger.debug("Iniciando limpieza de PostgreSQL para #{inspect(business_key)} - Tabla: #{table_name}, Tipo: #{inspect(register_type)}")

        delete_opts = if register_type, do: [register_type: register_type], else: []

        Postgres.delete_analyzed_records(pid_pg, table_name, delete_opts)
        |> case do
            {:ok, count} ->
                Logger.info("Limpieza de PostgreSQL para #{inspect(business_key)}: #{count} registros eliminados de #{table_name}")
                {:ok, count}

            {:error, reason} = error ->
                message = "Error al limpiar tabla de PostgreSQL #{table_name}: #{inspect(reason)}"
                Logger.error(message)
                notify_error(webhook_url, message)
                error
        end
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
            raw_values = Enum.map(row, fn {_col, value} -> value end)

            id_values =
                raw_values
                |> Enum.take(length(id_fields))
                |> Enum.zip(id_fields)
                |> Enum.map(fn {val, info_attr} -> Type.convert(val, info_attr.type) end)

            ts_value =
                raw_values
                |> List.last()
                |> Type.convert(ts_field.type)

            (id_values ++ [ts_value]) |> List.to_tuple()
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
        conditions =
            Enum.map(rows_to_keep, fn row_tuple ->
                row_values = Tuple.to_list(row_tuple)
                id_values = Enum.take(row_values, length(id_fields))
                ts_value = List.last(row_values)

                # Match on ID fields but NOT on the timestamp (delete older ones)
                id_conditions =
                    Enum.zip(id_fields, id_values)
                    |> Enum.map(fn {info_attr, val} -> {info_attr.id, val, :eq} end)

                ts_condition = {ts_field.id, ts_value, :neq}

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
    #     - id_fields: List. List of Struct.InfoAttr that form the ID
    #
    # ### Returns
    #     - String. SQL WHERE clause content (without the WHERE keyword)
    #
    defp build_where_clause(ids, id_fields) when length(id_fields) == 1 do
        info_attr = hd(id_fields)
        field = info_attr.id |> to_string()
        values = Enum.map(ids, &mconvert_for_bigquery(&1, info_attr.type)) |> Enum.join(", ")
        "#{field} IN (#{values})"
    end

    defp build_where_clause(ids, id_fields) do
        conditions =
            Enum.map(ids, fn id_tuple ->
                id_values = if is_tuple(id_tuple), do: Tuple.to_list(id_tuple), else: [id_tuple]

                Enum.zip(id_fields, id_values)
                |> Enum.map(fn {info_attr, val} -> "#{info_attr.id} = #{mconvert_for_bigquery(val, info_attr.type)}" end)
                |> Enum.join(" AND ")
                |> then(&"(#{&1})")
            end)
            |> Enum.join(" OR ")

        "(#{conditions})"
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

    #
    # Sends error notification to Slack if webhook_url is provided.
    #
    defp notify_error(nil, _message), do: :ok
    defp notify_error("", _message), do: :ok
    defp notify_error(webhook_url, message) when is_binary(webhook_url) do
        Notify.notify_slack(
            webhook_url,
            [{"Content-type", "application/json"}],
            "Cleaning Service",
            message
        )
    end

end
