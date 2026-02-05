
defmodule Cleaning.Cleaner do
    @moduledoc """
    Core cleaning logic that uses CleanableTable configurations.
    ```
    """

    require Logger
    import Connection.Odbc, only: [select: 2, update: 2]
    alias Statement.Sql
    alias Connection.PostgresPool
    alias Type.Type
    alias Notification.Notify
    alias Pool.BigQuery
    import Stuff, only: [convert_seconds_to_humans: 1]


    @doc """
    Runs cleaning for a specific business type using its CleanableTable configuration.

    ### Parameters
        - business_key: Atom. The business key (e.g., :record, :task)
        - bq_pool_name: Atom. BigQuery pool name
        - opts: List. Optional list of options

    ### Returns
        - {:ok, count} on success with number of rows removed
        - {:error, :not_registered} if module not found
        - {:error, reason} if cleaning fails
    """
    def run(business_key, bq_pool_name, opts \\ []) when is_atom(business_key) and is_atom(bq_pool_name) do
        case Cleaning.CleanableTableRegistry.get(business_key) do
            nil ->
                Logger.warning("No hay CleanableTable registrada para la llave: #{inspect(business_key)}")
                {:error, :not_registered}

            module ->
                run_for_module(module, bq_pool_name, opts)
        end
    end


    @doc """
    Runs cleaning for all enabled CleanableTable modules.

    ### Parameters
        - bq_pool_name: Atom. BigQuery pool name
        - opts: List. Optional list of options

    ### Returns
        - List of tuples {business_key, {:ok, count} | {:error, reason}}
    """
    def run_all(bq_pool_name, opts \\ []) when is_atom(bq_pool_name) do
        start = Timex.now()

        results =
            Cleaning.CleanableTableRegistry.enabled()
            |> Enum.map(fn module ->
                {module.business_key(), run_for_module(module, bq_pool_name, opts)}
            end)

        total_time = Timex.diff(Timex.now(), start, :second)
        Logger.info("Limpieza de todas las tablas finalizada. Duración: #{convert_seconds_to_humans(total_time)}")

        results
    end

    @doc """
    Runs cleaning for a specific module implementing CleanableTable.

    ### Parameters
        - module: Module. A module implementing CleanableTable behaviour
        - bq_pool_name: Atom. BigQuery pool name
        - opts: List. Optional list of options

    ### Returns
        - {:ok, count} with number of rows removed
        - {:error, reason} if cleaning fails
    """
    def run_for_module(module, bq_pool_name, opts \\ []) when is_atom(bq_pool_name) do
        webhook_url = Keyword.get(opts, :webhook_url)

        try do
            bq_config = module.bigquery_config()

            if is_nil(bq_config) do
                Logger.debug("Omitiendo limpieza de BigQuery para #{inspect(module)} - no hay definida bigquery_config")
                {:ok, 0}
            else
                run_bigquery_cleanup(module, bq_config, bq_pool_name, webhook_url)
            end
        rescue
            error ->
                message = "Error en limpieza de BigQuery #{inspect(module)}: #{inspect(error)}"
                Logger.error(message)
                notify_error(webhook_url, message)
                {:error, error}
        end
    end

    defp run_bigquery_cleanup(module, bq_config, bq_pool_name, webhook_url) do
        start = Timex.now()
        business_key = module.business_key()

        Logger.debug("Iniciando limpieza para #{inspect(business_key)} - Tabla: #{bq_config.table}")

        result = BigQuery.with_connection_safe(bq_pool_name, fn conn ->
            cleanup_query = build_cleanup_query(bq_config)
            update(conn, cleanup_query)
        end)

        case result do
            {:ok, _} ->
                duration = Timex.diff(Timex.now(), start, :second)
                Logger.debug("Limpieza de #{inspect(business_key)} finalizada. Duración: #{convert_seconds_to_humans(duration)}")
                {:ok, 0}

            {:error, reason} = error ->
                message = "Error al limpiar tabla de BigQuery #{bq_config.table}: #{inspect(reason)}"
                Logger.error(message)
                notify_error(webhook_url, message)
                error
        end
    end


    # ============================================
    # POSTGRESQL CLEANING FUNCTIONS
    # ============================================

    @doc """
    Runs PostgreSQL cleaning for a specific business type. Deletes records with estado_analisis = "analizado_en_bq" from the configured table.

    ### Parameters
        - business_key: Atom. The business key (e.g., :record, :task)
        - pg_pool_name: Atom. PostgreSQL pool name
        - opts: List. Optional list of options

    ### Returns
        - {:ok, count} on success with number of rows removed
        - {:error, :not_registered} if module not found
        - {:error, reason} if cleaning fails
    """
    def run_postgres(business_key, pg_pool_name, opts \\ []) when is_atom(business_key) and is_atom(pg_pool_name) do
        case Cleaning.CleanableTableRegistry.get(business_key) do
            nil ->
                Logger.warning("No hay CleanableTable registrada para la llave: #{inspect(business_key)}")
                {:error, :not_registered}

            module ->
                run_postgres_for_module(module, pg_pool_name, opts)
        end
    end

    @doc """
    Runs PostgreSQL cleaning for all enabled CleanableTable modules.

    ### Parameters
        - pg_pool_name: Atom. PostgreSQL pool name
        - opts: List. Optional list of options

    ### Returns
        - List of tuples {business_key, {:ok, count} | {:error, reason}}
    """
    def run_all_postgres(pg_pool_name, opts \\ []) when is_atom(pg_pool_name) do
        start = Timex.now()
        total_deleted = :counters.new(1, [:atomics])

        results =
            Cleaning.CleanableTableRegistry.enabled()
            |> Enum.map(fn module ->
                result = run_postgres_for_module(module, pg_pool_name, opts)

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
        - pg_pool_name: Atom. PostgreSQL pool name
        - opts: List. Optional list of options

    ### Returns
        - {:ok, count} with number of rows removed
        - {:error, reason} if cleaning fails
    """
    def run_postgres_for_module(module, pg_pool_name, opts \\ []) when is_atom(pg_pool_name) do
        webhook_url = Keyword.get(opts, :webhook_url)

        try do
            pg_config = module.postgres_config()

            if is_nil(pg_config) do
                Logger.debug("Omitiendo limpieza de PostgreSQL para #{inspect(module)} - no hay definida postgres_config")
                {:ok, 0}
            else
                run_postgres_cleanup(module, pg_config, pg_pool_name, webhook_url)
            end
        rescue
            error ->
                message = "Error en limpieza de PostgreSQL para #{inspect(module)}: #{inspect(error)}"
                Logger.error(message)
                notify_error(webhook_url, message)
                {:error, error}
        end
    end

    defp run_postgres_cleanup(module, pg_config, pg_pool_name, webhook_url) do
        business_key = module.business_key()
        table_name = pg_config.table
        register_type = Map.get(pg_config, :register_type, nil)

        Logger.debug("Iniciando limpieza de PostgreSQL para #{inspect(business_key)} - Tabla: #{table_name}, Tipo: #{inspect(register_type)}")

        delete_opts = if register_type, do: [register_type: register_type], else: []

        PostgresPool.delete_analyzed_records(pg_pool_name, table_name, delete_opts)
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
    # Builds a CREATE OR REPLACE TABLE query with QUALIFY to remove duplicates.
    #
    # ### Parameters
    #     - config: Map. Must contain :table, :id_fields (list of Struct.InfoAttr), and :timestamp_field (Struct.InfoAttr) keys
    #
    # ### Returns
    #     - String. SQL query for CREATE OR REPLACE TABLE
    #
    defp build_cleanup_query(%{table: table, id_fields: id_fields, timestamp_field: ts_field}) do
        id_columns =
            id_fields
            |> Enum.map(fn info_attr ->
                to_string(info_attr.id)
            end)
            |> Enum.join(", ")
        ts_column = to_string(ts_field.id)

        """
        CREATE OR REPLACE TABLE #{table} AS
        SELECT *
        FROM #{table}
        QUALIFY
          ROW_NUMBER() OVER (
            PARTITION BY #{id_columns}
            ORDER BY #{ts_column} DESC
          ) = 1
        """
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
