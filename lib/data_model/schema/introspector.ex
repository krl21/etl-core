
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
            - `:allow_unique` (boolean, default `true`). When `false`, any `InfoAttr`
              with `constraint: :unique` is treated as a plain `:required` column for
              description purposes (see `to_bigquery_column/2`) and a warning is logged.
              Used by `DataModel.Schema.Generator.generate/2` to enforce that `:unique`
              only has an effect when the entity's BigQuery table does not exist yet
              (its first, `:create_table` migration). `DataModel.Schema.Generator.bootstrap/2`
              always passes `false`, since it is only used for tables that already exist —
              a field can never be made `:unique` on those.

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
        allow_unique? = Keyword.get(opts, :allow_unique, true)

        %{
            name: to_string(info_attr.id),
            type: TypeMapping.resolve(info_attr.type),
            mode: mode_for(info_attr),
            description: description_for(info_attr, allow_unique?)
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
    #     - String. `"NULLABLE"` or `"REQUIRED"` — `:unique` also resolves to
    #       `"REQUIRED"`, since uniqueness implies not-null; the uniqueness
    #       itself is handled separately, as metadata, by `description_for/2`.
    #
    defp mode_for(%InfoAttr{constraint: :nullable}), do: "NULLABLE"
    defp mode_for(%InfoAttr{constraint: :required}), do: "REQUIRED"
    defp mode_for(%InfoAttr{constraint: :unique}), do: "REQUIRED"

    #
    # Builds the column description, applying the `" [unique]"` suffix only
    # when `constraint: :unique` is actually honoured (`allow_unique? == true`).
    # Otherwise logs a warning and returns the plain description, enforcing
    # that `:unique` only has an effect on an entity's initial migration.
    #
    # ### Parameters:
    #     - info_attr: Struct.InfoAttr.
    #     - allow_unique?: Boolean.
    #
    # ### Returns:
    #     - String.t() | nil.
    #
    defp description_for(%InfoAttr{constraint: :unique, description: description, id: id}, false) do
        Logger.warning("unique ignorado en #{id}: solo se permite en la migración inicial")
        description
    end

    defp description_for(%InfoAttr{constraint: :unique, description: description}, true) do
        append_suffix(description, " [unique]")
    end

    defp description_for(%InfoAttr{description: description}, _allow_unique?), do: description

    #
    # Appends `suffix` to a possibly-nil description.
    #
    # ### Parameters:
    #     - description: String.t() | nil.
    #     - suffix: String.t().
    #
    # ### Returns:
    #     - String.t().
    #
    defp append_suffix(nil, suffix), do: String.trim_leading(suffix)
    defp append_suffix(description, suffix), do: description <> suffix

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
