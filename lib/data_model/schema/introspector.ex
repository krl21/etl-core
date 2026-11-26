
defmodule DataModel.Schema.Introspector do
    @moduledoc """
    Turns an entity module (one that implements `Cleaning.CleanableTable` and
    exposes `attr_list/0` via `DataModel.Behaviour`) into the BigQuery schema it
    *should* have today — a plain, JSON-serializable list of column maps.

    This is the single place where a `Struct.InfoAttr` is translated into a
    BigQuery column definition; `DataModel.Schema.Differ`/`Generator`/`Migrator`
    only ever deal with the resulting column maps, never with `InfoAttr` itself.
    """

    alias Struct.InfoAttr
    alias DataModel.Schema.TypeMapping

    @type column :: %{name: String.t(), type: String.t(), mode: String.t(), description: String.t() | nil}

    @doc """
    Computes the desired BigQuery schema for an entity module, always honouring
    each `InfoAttr`'s `:constraint` as written — whether `:required` can
    actually take effect against BigQuery (only at table creation) is a
    migration-time concern, decided by `DataModel.Schema.Generator.generate/2`
    once it knows the entity's previous schema, not here.

    ### Parameters:
        - module: Atom. A module implementing `Cleaning.CleanableTable` and `DataModel.Behaviour` (`attr_list/0`).

    ### Returns:
        - [column()]. One entry per attribute returned by `module.attr_list()`.

    ### Raises:
        - ArgumentError. If two attributes share the same `id` with inconsistent
          definitions (type/mode/description) — this points at a composition bug
          across subentities.
    """
    @spec desired_schema(module()) :: [column()]
    def desired_schema(module) when is_atom(module) do
        module.attr_list()
        |> Enum.map(&to_bigquery_column/1)
        |> deduplicate_by_name()
    end

    @doc """
    Converts a single `Struct.InfoAttr` into a BigQuery column map.

    ### Parameters:
        - info_attr: Struct.InfoAttr.

    ### Returns:
        - column().
    """
    @spec to_bigquery_column(InfoAttr.t()) :: column()
    def to_bigquery_column(%InfoAttr{} = info_attr) do
        %{
            name: to_string(info_attr.id),
            type: TypeMapping.resolve(info_attr.type),
            mode: mode_for(info_attr),
            description: info_attr.description
        }
    end

    @doc """
    Returns the fully-qualified BigQuery table name configured for `module`.

    ### Parameters:
        - module: Atom. A module implementing `Cleaning.CleanableTable`.

    ### Returns:
        - String.
    """
    @spec table_id(module()) :: String.t()
    def table_id(module) when is_atom(module), do: module.bigquery_config().table

    @doc """
    Returns the stable business key used to identify `module`'s migration state
    (directory under `priv/schema_migrations/`, row in the control table).

    ### Parameters:
        - module: Atom. A module implementing `Cleaning.CleanableTable`.

    ### Returns:
        - Atom.
    """
    @spec business_key(module()) :: atom()
    def business_key(module) when is_atom(module), do: module.business_key()


    ################
    ### Helper functions
    ################

    #
    # Resolves the BigQuery column mode for an `InfoAttr`'s constraint.
    #
    # ### Parameters:
    #     - info_attr: Struct.InfoAttr.
    #
    # ### Returns:
    #     - String. `"NULLABLE"` or `"REQUIRED"`.
    #
    defp mode_for(%InfoAttr{constraint: :nullable}), do: "NULLABLE"
    defp mode_for(%InfoAttr{constraint: :required}), do: "REQUIRED"

    #
    # Deduplicates by `name`, preserving the original (first-seen) order —
    # `Enum.group_by/2` would lose it, since it returns a map.
    #
    # ### Parameters:
    #     - columns: [column()].
    #
    # ### Returns:
    #     - [column()].
    #
    # ### Raises:
    #     - ArgumentError. If the same `name` appears twice with different values.
    #
    defp deduplicate_by_name(columns) do
        {ordered, _seen} =
            Enum.reduce(columns, {[], %{}}, fn column, {acc, seen} ->
                case Map.fetch(seen, column.name) do
                    :error ->
                        {[column | acc], Map.put(seen, column.name, column)}
                    {:ok, ^column} ->
                        {acc, seen}
                    {:ok, other} ->
                        raise ArgumentError,
                            "Atributos inconsistentes para el campo #{inspect(column.name)}: #{inspect(other)} vs #{inspect(column)}"
                end
            end)

        Enum.reverse(ordered)
    end




end
