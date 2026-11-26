
defmodule DataModel.Schema.Differ do
    @moduledoc """
    Computes the list of schema-change operations needed to go from a
    previously generated BigQuery schema snapshot to the current desired one
    (both as produced by `DataModel.Schema.Introspector.desired_schema/2`).

    This is a pure, offline comparison — it never talks to BigQuery. The
    resulting operations are what `DataModel.Schema.Generator` writes into a
    migration file, and later what `DataModel.Schema.DdlBuilder` turns into
    actual DDL statements.
    """

    @type column :: DataModel.Schema.Introspector.column()
    @type operation :: map()

    @doc """
    Diffs a previous schema snapshot against the current desired one.

    ### Parameters:
        - previous: [column()]. The last generated schema for this entity, or
          `[]` if none exists yet (the entity's very first migration).
        - desired: [column()]. The schema computed right now from `attr_list()`.

    ### Returns:
        - [operation()]. Empty when `previous == desired` (nothing to migrate).
          When `previous == []`, a single `%{op: :create_table, columns: desired}`
          operation. Otherwise, one operation per added, dropped or changed
          column, ordered as: drops, then alters (type/mode/description), then
          adds.

    """
    @spec diff([column()], [column()]) :: [operation()]
    def diff([], desired), do: [%{op: :create_table, columns: desired}]

    def diff(previous, desired) do
        previous_by_name = Map.new(previous, &{&1.name, &1})
        desired_by_name = Map.new(desired, &{&1.name, &1})

        drop_ops =
            previous
            |> Enum.reject(&Map.has_key?(desired_by_name, &1.name))
            |> Enum.map(&%{op: :drop_column, name: &1.name})

        alter_ops =
            desired
            |> Enum.filter(&Map.has_key?(previous_by_name, &1.name))
            |> Enum.flat_map(&alter_operations(Map.fetch!(previous_by_name, &1.name), &1))

        add_ops =
            desired
            |> Enum.reject(&Map.has_key?(previous_by_name, &1.name))
            |> Enum.map(&%{op: :add_column, column: &1})

        drop_ops ++ alter_ops ++ add_ops
    end


    ################
    ### Helper functions
    ################

    #
    # Compares a column present in both schemas and returns one operation per
    # changed attribute (type, mode, description) — zero, one, two or all three.
    #
    # ### Parameters:
    #     - previous_column: column(). The column as it was in the last snapshot.
    #     - desired_column: column(). The column as it is now.
    #
    # ### Returns:
    #     - [operation()].
    #
    defp alter_operations(%{} = previous_column, %{} = desired_column) do
        []
        |> maybe_append(
            previous_column.type != desired_column.type,
            %{op: :alter_column_type, name: desired_column.name, type: desired_column.type}
        )
        |> maybe_append(
            previous_column.mode != desired_column.mode,
            %{op: :alter_column_mode, name: desired_column.name, mode: desired_column.mode}
        )
        |> maybe_append(
            previous_column.description != desired_column.description,
            %{op: :alter_column_description, name: desired_column.name, description: desired_column.description}
        )
    end

    #
    # Appends `op` to `ops` only when `changed?` is true.
    #
    # ### Parameters:
    #     - ops: [operation()].
    #     - changed?: Boolean.
    #     - op: operation().
    #
    # ### Returns:
    #     - [operation()].
    #
    defp maybe_append(ops, false, _op), do: ops
    defp maybe_append(ops, true, op), do: ops ++ [op]


end
