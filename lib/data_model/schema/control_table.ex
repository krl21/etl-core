
defmodule DataModel.Schema.ControlTable do
    @moduledoc """
    Reads and writes the BigQuery table that tracks, per entity, which schema
    migrations have already been applied — the one table this subsystem fully
    owns and can create on its own.
    """

    @table_regex ~r/^[A-Za-z0-9_\-]+(\.[A-Za-z0-9_\-]+){1,2}$/

    @doc """
    Creates the control table if it doesn't exist yet. Safe to call on every
    run — it never fails because the table is already there.

    ### Parameters:
        - pid: Process. ODBC connection to BigQuery.
        - control_table: String. Fully-qualified table name (`dataset.table`).

    ### Returns:
        - :ok.
    """
    @spec ensure_exists!(pid(), String.t()) :: :ok
    def ensure_exists!(pid, control_table) when is_pid(pid) and is_binary(control_table) do
        validate_table_name!(control_table)

        statement = """
        CREATE TABLE IF NOT EXISTS #{control_table} (
            business_key STRING NOT NULL,
            version INT64 NOT NULL,
            table_name STRING,
            operations_count INT64,
            applied_at TIMESTAMP NOT NULL,
            status STRING NOT NULL,
            error_message STRING
        )
        """

        EtlCore.Deps.odbc().execute(pid, statement)
        :ok
    end

    @doc """
    Returns the highest migration version recorded with `status = "applied"`
    for `business_key`.

    ### Parameters:
        - pid: Process. ODBC connection to BigQuery.
        - control_table: String. Fully-qualified table name (`dataset.table`).
        - business_key: Atom.

    ### Returns:
        - non_neg_integer() | nil. `nil` when no migration has been applied yet.
    """
    @spec last_applied_version(pid(), String.t(), atom()) :: non_neg_integer() | nil
    def last_applied_version(pid, control_table, business_key) when is_pid(pid) and is_binary(control_table) do
        validate_table_name!(control_table)

        statement = """
        SELECT version FROM #{control_table}
        WHERE business_key = #{quote_string(to_string(business_key))} AND status = "applied"
        ORDER BY version DESC
        LIMIT 1
        """

        case EtlCore.Deps.odbc().select(pid, statement) do
            [[{:version, version}]] -> String.to_integer(version)
            [] -> nil
        end
    end

    @doc """
    Records that `version` was successfully applied for `business_key`.

    ### Parameters:
        - pid: Process. ODBC connection to BigQuery.
        - control_table: String. Fully-qualified table name (`dataset.table`).
        - business_key: Atom.
        - version: pos_integer(). The applied migration's number.
        - entity_table: String. The entity's own BigQuery table name, for audit purposes.
        - operations_count: non_neg_integer(). How many DDL statements the migration ran.

    ### Returns:
        - :ok.
    """
    @spec record_applied(pid(), String.t(), atom(), pos_integer(), String.t(), non_neg_integer()) :: :ok
    def record_applied(pid, control_table, business_key, version, entity_table, operations_count) do
        insert_row(pid, control_table, %{
            business_key: business_key,
            version: version,
            table_name: entity_table,
            operations_count: operations_count,
            status: "applied",
            error_message: nil
        })
    end

    @doc """
    Records that `version` failed to apply for `business_key`.

    ### Parameters:
        - pid: Process. ODBC connection to BigQuery.
        - control_table: String. Fully-qualified table name (`dataset.table`).
        - business_key: Atom.
        - version: pos_integer(). The migration's number that failed.
        - entity_table: String. The entity's own BigQuery table name, for audit purposes.
        - error_message: String. BigQuery's own error message, verbatim.

    ### Returns:
        - :ok.
    """
    @spec record_failed(pid(), String.t(), atom(), pos_integer(), String.t(), String.t()) :: :ok
    def record_failed(pid, control_table, business_key, version, entity_table, error_message) do
        insert_row(pid, control_table, %{
            business_key: business_key,
            version: version,
            table_name: entity_table,
            operations_count: nil,
            status: "failed",
            error_message: error_message
        })
    end


    ################
    ### Helper functions
    ################

    #
    # Inserts one audit row into the control table.
    #
    # ### Parameters:
    #     - pid: Process. ODBC connection to BigQuery.
    #     - control_table: String.t(). Fully-qualified table name (`dataset.table`).
    #     - fields: Map. `:business_key`, `:version`, `:table_name`, `:operations_count`, `:status`, `:error_message`.
    #
    # ### Returns:
    #     - :ok.
    #
    defp insert_row(pid, control_table, fields) when is_pid(pid) and is_binary(control_table) do
        validate_table_name!(control_table)

        statement = """
        INSERT INTO #{control_table} (business_key, version, table_name, operations_count, applied_at, status, error_message)
        VALUES (
            #{quote_string(to_string(fields.business_key))},
            #{fields.version},
            #{sql_value(fields.table_name)},
            #{sql_value(fields.operations_count)},
            CURRENT_TIMESTAMP(),
            #{quote_string(fields.status)},
            #{sql_value(fields.error_message)}
        )
        """

        EtlCore.Deps.odbc().execute(pid, statement)
        :ok
    end

    #
    # Guards against an unsafe/malformed table name reaching a raw SQL string.
    #
    # ### Parameters:
    #     - table_name: String.t().
    #
    # ### Returns:
    #     - :ok.
    #
    # ### Raises:
    #     - ArgumentError. If `table_name` doesn't look like `dataset.table` (or `project.dataset.table`).
    #
    defp validate_table_name!(table_name) do
        if not Regex.match?(@table_regex, table_name) do
            raise ArgumentError, "Nombre de tabla de control inválido: #{inspect(table_name)}"
        end
    end

    #
    # Renders a value as a SQL literal suitable for an `INSERT ... VALUES (...)`.
    #
    # ### Parameters:
    #     - value: nil | integer() | String.t().
    #
    # ### Returns:
    #     - String.t().
    #
    defp sql_value(nil), do: "NULL"
    defp sql_value(value) when is_integer(value), do: Integer.to_string(value)
    defp sql_value(value) when is_binary(value), do: quote_string(value)

    #
    # Wraps a value in a double-quoted BigQuery string literal, escaping
    # backslashes and embedded double quotes.
    #
    # ### Parameters:
    #     - value: String.t().
    #
    # ### Returns:
    #     - String.t().
    #
    defp quote_string(value) do
        escaped =
            value
            |> String.replace("\\", "\\\\")
            |> String.replace("\"", "\\\"")

        "\"#{escaped}\""
    end
end
