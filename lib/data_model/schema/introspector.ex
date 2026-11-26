
defmodule DataModel.Schema.Introspector do
    @moduledoc """
    Turns an entity module (one that implements `Cleaning.CleanableTable` and
    exposes `attr_list/0` via `DataModel.Behaviour`) into the BigQuery schema it
    *should* have today — a plain, JSON-serializable list of column maps.

    This is the single place where a `Struct.InfoAttr` is translated into a
    BigQuery column definition; `DataModel.Schema.Differ`/`Generator`/`Migrator`
    only ever deal with the resulting column maps, never with `InfoAttr` itself.
    """

    require Logger
    alias Struct.InfoAttr
    alias DataModel.Schema.TypeMapping

    @type column :: %{name: String.t(), type: String.t(), mode: String.t(), description: String.t() | nil}

    @doc """
    Computes the desired BigQuery schema for an entity module.

    ### Parameters:
        - module: Atom. A module implementing `Cleaning.CleanableTable` and `DataModel.Behaviour` (`attr_list/0`).
        - opts: Keyword list.
            - `:allow_required` (boolean, default `true`). When `false`, any `InfoAttr`
              with `constraint: :required` is resolved to a `"NULLABLE"` column mode
              instead and a warning is logged. Used by `DataModel.Schema.Generator.generate/2`
              to enforce that `:required` only has an effect when the entity's BigQuery
              table does not exist yet (its first, `:create_table` migration) — BigQuery
              only allows a `REQUIRED` column at table creation, never via `ALTER TABLE`
              on an existing one. `DataModel.Schema.Generator.bootstrap/2` always passes
              `false`, since it is only used for tables that already exist.

    ### Returns:
        - [column()]. One entry per attribute returned by `module.attr_list()`.

    ### Raises:
        - ArgumentError. If two attributes share the same `id` with inconsistent
          definitions (type/mode/description) — this points at a composition bug
          across subentities.
    """
    @spec desired_schema(module(), keyword()) :: [column()]
    def desired_schema(module, opts \\ []) when is_atom(module) do
        module.attr_list()
        |> Enum.map(&to_bigquery_column(&1, opts))
        |> deduplicate_by_name()
    end

    @doc """
    Converts a single `Struct.InfoAttr` into a BigQuery column map.

    ### Parameters:
        - info_attr: Struct.InfoAttr.
        - opts: Keyword list. See `desired_schema/2`.

    ### Returns:
        - column().
    """
    @spec to_bigquery_column(InfoAttr.t(), keyword()) :: column()
    def to_bigquery_column(%InfoAttr{} = info_attr, opts \\ []) do
        allow_required? = Keyword.get(opts, :allow_required, true)

        %{
            name: to_string(info_attr.id),
            type: TypeMapping.resolve(info_attr.type),
            mode: mode_for(info_attr, allow_required?),
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
    # Resolves the BigQuery column mode for an `InfoAttr`'s constraint. A
    # `:required` constraint only resolves to `"REQUIRED"` when `allow_required?`
    # is true — otherwise it logs a warning and resolves to `"NULLABLE"` instead,
    # since BigQuery only allows a `REQUIRED` column at table creation.
    #
    # ### Parameters:
    #     - info_attr: Struct.InfoAttr.
    #     - allow_required?: Boolean.
    #
    # ### Returns:
    #     - String. `"NULLABLE"` or `"REQUIRED"`.
    #
    defp mode_for(%InfoAttr{constraint: :nullable}, _allow_required?), do: "NULLABLE"
    defp mode_for(%InfoAttr{constraint: :required}, true), do: "REQUIRED"

    defp mode_for(%InfoAttr{constraint: :required, id: id}, false) do
        Logger.warning("required ignorado en #{id}: solo se permite al crear la tabla")
        "NULLABLE"
    end

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
