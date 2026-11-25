
defmodule DataModel.Schema.DdlBuilder do
    @moduledoc """
    Turns the operations computed by `DataModel.Schema.Differ` (as stored in a
    migration file) into the BigQuery DDL statements needed to apply them.

    `build/2` never talks to BigQuery itself — it only builds strings.
    `DataModel.Schema.Migrator` is the one that feeds each resulting statement,
    one at a time, to `Connection.Odbc.execute/2`.
    """

    @type column :: DataModel.Schema.Introspector.column()
    @type operation :: DataModel.Schema.Differ.operation()

    @doc """
    Builds one DDL statement per operation.

    ### Parameters:
        - table_name: String. Fully-qualified BigQuery table name (`dataset.table`).
        - operations: [operation()]. Usually every operation of a single migration file.

    ### Returns:
        - [String.t()]. One DDL statement per operation, in the same order.

    ### Raises:
        - ArgumentError. For an `:alter_column_mode` operation that tries to tighten
          an existing column to `"REQUIRED"` — BigQuery's `ALTER COLUMN` only
          supports relaxing a column to `NULLABLE` (`DROP NOT NULL`); there is no
          DDL clause to add `NOT NULL` to a column that already exists, so there is
          no valid statement to attempt. Everything else is sent to BigQuery as-is
          and left to BigQuery's own validation (e.g. adding a `REQUIRED` column or
          narrowing a type may fail on a table that already has rows).

    """
    @spec build(String.t(), [operation()]) :: [String.t()]
    def build(table_name, operations) when is_binary(table_name) and is_list(operations) do
        Enum.flat_map(operations, &build_operation(table_name, &1))
    end


    ################
    ### Helper functions
    ################

    #
    # Builds the DDL statement for a single operation map.
    #
    # ### Parameters:
    #     - table_name: String.t(). Fully-qualified BigQuery table name (`dataset.table`).
    #     - operation: operation().
    #
    # ### Returns:
    #     - [String.t()]. A single-element list, so `build/2` can `flat_map` over operations.
    #
    defp build_operation(table_name, %{op: :create_table, columns: columns}) do
        clauses = Enum.map_join(columns, ", ", &column_clause/1)
        ["CREATE TABLE IF NOT EXISTS #{table_name} (#{clauses})"]
    end

    defp build_operation(table_name, %{op: :add_column, column: column}) do
        ["ALTER TABLE #{table_name} ADD COLUMN #{column_clause(column)}"]
    end

    defp build_operation(table_name, %{op: :drop_column, name: name}) do
        ["ALTER TABLE #{table_name} DROP COLUMN #{name}"]
    end

    defp build_operation(table_name, %{op: :alter_column_type, name: name, type: type}) do
        ["ALTER TABLE #{table_name} ALTER COLUMN #{name} SET DATA TYPE #{type}"]
    end

    defp build_operation(table_name, %{op: :alter_column_mode, name: name, mode: mode}) do
        ["ALTER TABLE #{table_name} ALTER COLUMN #{name} #{mode_clause(mode)}"]
    end

    defp build_operation(table_name, %{op: :alter_column_description, name: name, description: description}) do
        ["ALTER TABLE #{table_name} ALTER COLUMN #{name} SET OPTIONS(description=#{quote_description(description)})"]
    end

    #
    # Builds a `name TYPE MODE [OPTIONS(description="...")]` column definition,
    # shared by `create_table` and `add_column`.
    #
    # ### Parameters:
    #     - column: column().
    #
    # ### Returns:
    #     - String.t().
    #
    defp column_clause(%{name: name, type: type, mode: mode} = column) do
        base = "#{name} #{type} #{mode}"

        case Map.get(column, :description) do
            description when description in [nil, ""] -> base
            description -> base <> " OPTIONS(description=#{quote_string(description)})"
        end
    end

    #
    # `DROP NOT NULL` is the only BigQuery-documented way to alter an existing
    # column's nullability — there is no "add NOT NULL" counterpart, so a
    # tightening request can never be turned into a valid statement.
    #
    # ### Parameters:
    #     - mode: String.t(). `"NULLABLE"` or `"REQUIRED"`.
    #
    # ### Returns:
    #     - String.t(). The `ALTER COLUMN` clause to append after the column name.
    #
    # ### Raises:
    #     - ArgumentError. When `mode` is `"REQUIRED"` — there is no valid statement to attempt.
    #
    defp mode_clause("NULLABLE"), do: "DROP NOT NULL"
    defp mode_clause("REQUIRED") do
        raise ArgumentError,
            "BigQuery no soporta agregar NOT NULL a una columna existente vía ALTER COLUMN; " <>
            "ese cambio requiere recrear la tabla manualmente."
    end

    #
    # Quotes a column description for use inside `OPTIONS(description=...)`,
    # or the literal `NULL` when there is none.
    #
    # ### Parameters:
    #     - description: String.t() | nil.
    #
    # ### Returns:
    #     - String.t().
    #
    defp quote_description(nil), do: "NULL"
    defp quote_description(description), do: quote_string(description)

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
