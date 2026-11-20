defmodule DataModel.Behaviour do
    @moduledoc """
    Common contract of the data model modules: sub-entities (`DataModel.Attribute.Provider`)
    and entities (`DataModel.Record.Base`, `DataModel.RecordPg.Base`).

    Every module exposes the list of attributes it extracts from the payload and, optionally,
    a post-processing function applied after the extraction.
    """


    @doc """
    Returns the list of attributes extracted from the payload.

    ### Returns:
        - List of Struct.InfoAttr.
    """
    @callback attr_list() :: [struct()]

    @doc """
    Processing to the data, after extracting it from the payload. Depends only on the current payload.

    ### Parameters:
        - values: Keyword list. Values extracted from the payload.
        - payload: Map. Payload.

    ### Returns:
        - Keyword list. Same values, updated.
    """
    @callback special_post_processing(values :: keyword(), payload :: map()) :: keyword()

    @doc """
    Processing to the data, after extracting it from the payload. Depends also on the data already stored.

    ### Parameters:
        - new_values: Keyword list. Values extracted from the payload.
        - stored_values: Keyword list. Values already stored for the same record.
        - payload: Map. Payload.

    ### Returns:
        - Keyword list. Same new values, updated.
    """
    @callback special_post_processing(new_values :: keyword(), stored_values :: keyword(), payload :: map()) :: keyword()

    @optional_callbacks special_post_processing: 2, special_post_processing: 3


end
