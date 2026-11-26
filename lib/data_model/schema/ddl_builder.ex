
defmodule DataModel.Schema.DdlBuilder do
    @moduledoc """
    Turns the operations computed by `DataModel.Schema.Differ` (as stored in a
    migration file) into the BigQuery DDL statements needed to apply them.

    Operations of the same kind are combined into multi-clause `ALTER TABLE`
    statements (e.g. several `ADD COLUMN`s in one statement), capped at
    `:batch_size` columns per statement — BigQuery limits how many standalone
    DDL statements can modify the same table in quick succession, so batching
    reduces the number of statements sent instead of issuing one per column.

    `build/3` never talks to BigQuery itself — it only builds strings.
    `DataModel.Schema.Migrator` is the one that feeds each resulting statement,
    one at a time, to `Connection.Odbc.execute/2`.
    """

    @type column :: DataModel.Schema.Introspector.column()
    @type operation :: DataModel.Schema.Differ.operation()

    @default_batch_size 50
    @ops_order [:drop_column, :alter_column_type, :alter_column_mode, :alter_column_description, :add_column]

    @doc """
    Builds the DDL statements for a migration's operations, batching same-kind
    operations together.

    ### Parameters:
        - table_name: String. Fully-qualified BigQuery table name (`dataset.table`).
        - operations: [operation()]. Usually every operation of a single migration file.
        - opts: Keyword list.
            - `:batch_size` (pos_integer(), default `50`). Maximum number of columns
              combined into a single multi-clause statement.

    ### Returns:
        - [String.t()]. One DDL statement per batch: `:create_table` first (if
          present, always including every `REQUIRED` column regardless of
          `:batch_size` — BigQuery only allows a `REQUIRED` column at table
          creation, never via a later `ADD COLUMN`, so those can never be
          deferred to an overflow batch), any overflow `ADD COLUMN` batches for
          `NULLABLE` columns that didn't fit, then every other operation kind,
          each batched by `:batch_size`.

    ### Raises:
        - ArgumentError. For an `:alter_column_mode` operation that tries to tighten
          an existing column to `"REQUIRED"` — BigQuery's `ALTER COLUMN` only
          supports relaxing a column to `NULLABLE` (`DROP NOT NULL`); there is no
          DDL clause to add `NOT NULL` to a column that already exists, so there is
          no valid statement to attempt. Everything else is sent to BigQuery as-is
          and left to BigQuery's own validation (e.g. narrowing a type may fail on
          a table that already has rows).
    """
    @spec build(String.t(), [operation()], keyword()) :: [String.t()]
    def build(table_name, operations, opts \\ []) when is_binary(table_name) and is_list(operations) do
        batch_size = Keyword.get(opts, :batch_size, @default_batch_size)

        operations
        |> group_operations(batch_size)
        |> Enum.map(&build_statement(table_name, &1))
    end


    ################
    ### Helper functions
    ################

    #
    # Splits `operations` into the groups that each become a single DDL
    # statement: `:create_table`'s columns go through `create_table_groups/2`;
    # every other operation kind is collected (regardless of its original
    # position) and chunked into groups of at most `batch_size`, in a fixed
    # kind order (`@ops_order`) so the result stays deterministic.
    #
    # ### Parameters:
    #     - operations: [operation()].
    #     - batch_size: pos_integer().
    #
    # ### Returns:
    #     - [{atom(), [operation()]} | {:create_table, [column()]}]. One group per statement.
    #
    defp group_operations(operations, batch_size) do
        {create_table_ops, rest} = Enum.split_with(operations, &(&1.op == :create_table))

        create_table_groups =
            case create_table_ops do
                [] -> []
                [%{columns: columns}] -> create_table_groups(columns, batch_size)
            end

        other_groups =
            Enum.flat_map(@ops_order, fn op ->
                rest
                |> Enum.filter(&(&1.op == op))
                |> Enum.chunk_every(batch_size)
                |> Enum.map(&{op, &1})
            end)

        create_table_groups ++ other_groups
    end

    #
    # Splits a `:create_table`'s columns into the `CREATE TABLE` statement's own
    # columns and, if there are more than `batch_size`, one or more overflow
    # `ADD COLUMN` groups for the rest. Every `REQUIRED` column always goes into
    # the `CREATE TABLE` statement itself, no matter how many there are — only
    # `NULLABLE` columns can overflow into a later `ADD COLUMN` batch, since
    # BigQuery only allows a `REQUIRED` column at table creation.
    #
    # ### Parameters:
    #     - columns: [column()].
    #     - batch_size: pos_integer().
    #
    # ### Returns:
    #     - [{:create_table, [column()]} | {:add_column, [%{column: column()}]}].
    #
    defp create_table_groups(columns, batch_size) do
        {required, nullable} = Enum.split_with(columns, &(&1.mode == "REQUIRED"))
        nullable_room = max(batch_size - length(required), 0)

        first_batch = required ++ Enum.take(nullable, nullable_room)
        overflow = Enum.drop(nullable, nullable_room)

        overflow_groups =
            overflow
            |> Enum.chunk_every(batch_size)
            |> Enum.map(fn chunk -> {:add_column, Enum.map(chunk, &%{column: &1})} end)

        [{:create_table, first_batch} | overflow_groups]
    end

    #
    # Builds the DDL statement for a single group.
    #
    # ### Parameters:
    #     - table_name: String.t(). Fully-qualified BigQuery table name (`dataset.table`).
    #     - group: {atom(), [operation()]} | {:create_table, [column()]}.
    #
    # ### Returns:
    #     - String.t().
    #
    defp build_statement(table_name, {:create_table, columns}) do
        clauses = Enum.map_join(columns, ", ", &column_clause/1)
        "CREATE TABLE IF NOT EXISTS #{table_name} (#{clauses})"
    end

    defp build_statement(table_name, {:add_column, ops}) do
        clauses = Enum.map_join(ops, ", ", fn %{column: column} -> "ADD COLUMN #{column_clause(column)}" end)
        "ALTER TABLE #{table_name} #{clauses}"
    end

    defp build_statement(table_name, {:drop_column, ops}) do
        clauses = Enum.map_join(ops, ", ", fn %{name: name} -> "DROP COLUMN #{name}" end)
        "ALTER TABLE #{table_name} #{clauses}"
    end

    defp build_statement(table_name, {:alter_column_type, ops}) do
        clauses = Enum.map_join(ops, ", ", fn %{name: name, type: type} -> "ALTER COLUMN #{name} SET DATA TYPE #{type}" end)
        "ALTER TABLE #{table_name} #{clauses}"
    end

    defp build_statement(table_name, {:alter_column_mode, ops}) do
        clauses = Enum.map_join(ops, ", ", fn %{name: name, mode: mode} -> "ALTER COLUMN #{name} #{mode_clause(mode)}" end)
        "ALTER TABLE #{table_name} #{clauses}"
    end

    defp build_statement(table_name, {:alter_column_description, ops}) do
        clauses =
            Enum.map_join(ops, ", ", fn %{name: name, description: description} ->
                "ALTER COLUMN #{name} SET OPTIONS(description=#{quote_description(description)})"
            end)

        "ALTER TABLE #{table_name} #{clauses}"
    end

    #
    # Builds a `name TYPE [NOT NULL] [OPTIONS(description="...")]` column
    # definition, shared by `create_table` and `add_column`.
    #
    # ### Parameters:
    #     - column: column().
    #
    # ### Returns:
    #     - String.t().
    #
    defp column_clause(%{name: name, type: type, mode: mode} = column) do
        base = "#{name} #{type}#{not_null_clause(mode)}"

        case Map.get(column, :description) do
            description when description in [nil, ""] -> base
            description -> base <> " OPTIONS(description=#{quote_string(description)})"
        end
    end

    #
    # BigQuery DDL has no `REQUIRED`/`NULLABLE` keywords — those are schema-API
    # terms. A column definition is just `name TYPE`, optionally followed by
    # `NOT NULL`; there is no DDL keyword for nullable at all (it's the default).
    #
    # ### Parameters:
    #     - mode: String.t(). `"NULLABLE"` or `"REQUIRED"`.
    #
    # ### Returns:
    #     - String.t(). `""` or `" NOT NULL"`.
    #
    defp not_null_clause("NULLABLE"), do: ""
    defp not_null_clause("REQUIRED"), do: " NOT NULL"

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
