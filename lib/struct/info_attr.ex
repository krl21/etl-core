
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
        - constraint: `:nullable` | `:required`. Defaults to `:nullable`. `:required` resolves to a `REQUIRED` BigQuery column mode, but only on an entity's very first `generate/2` call (its `:create_table` migration) — BigQuery only allows a `REQUIRED` column at table creation, never via `ALTER TABLE` on an existing one. Every later call, and `DataModel.Schema.Generator.bootstrap/2` (always, since it is only for tables that already exist), resolves `:required` to `NULLABLE` instead, logging a warning rather than attempting a change BigQuery would reject.

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
