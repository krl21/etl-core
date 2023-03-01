
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

    """

    defstruct id: "", id_payload: "", type: nil, keys_to_search: [], default_value: nil


end
