
defmodule Struct.InfoAttr do
    @moduledoc"""
    Definition of the attributes belonging to each table and link with the payload.
    The payload is assumed to be in `map` format.

    ### Fields:
        - id: Atom. Name of the attribute in the database.
        - id_payload: String. Name of the associated attribute, defined in the payload.
        - type: Atom. Value type of attribute in the database.
        - keys_to_search: List of String. Keys to search in each level of the map.
        - default_value: Default value.
        - description: String | nil. Human-readable description of the column, used as its BigQuery column description (`DataModel.Schema.Introspector`).
        - constraint: `:nullable` | `:required` | `:unique`. Defaults to `:nullable`. `:required` and `:unique` both resolve to a `REQUIRED` BigQuery column mode; `:unique` is, in addition, only honoured when the entity's BigQuery table does not exist yet — its first, `:create_table` migration via `DataModel.Schema.Generator.generate/2`. It is never honoured for a table that already exists, including one baselined via `DataModel.Schema.Generator.bootstrap/2`: `DataModel.Schema.Introspector` ignores it in that case, logging a warning instead of failing.

    """

    defstruct id: "",
              id_payload: "",
              type: nil,
              keys_to_search: [],
              default_value: nil,
              description: nil,
              constraint: :nullable


    defimpl String.Chars do
        def to_string(info_attr) do
            "InfoAttr(id: #{info_attr.id}, id_payload: #{info_attr.id_payload}, type: #{info_attr.type}, keys_to_search: #{inspect(info_attr.keys_to_search)}, default_value: #{inspect(info_attr.default_value)}, description: #{inspect(info_attr.description)}, constraint: #{info_attr.constraint})"
        end
    end
end
