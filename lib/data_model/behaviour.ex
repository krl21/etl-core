
defmodule DataModel.Behaviour do
    @moduledoc """
    Behaviours for defining entity and sub-entity contracts.

    This module defines the behaviours that must be implemented by:
    - `DataModel.AttributeProvider`: For sub-entities that define attributes (InfoAttr)
    - `DataModel.RecordBase`: For main entities (Records) that process data
    """

    @doc """
    Returns the list of attributes defined by the entity.

    ### Returns:
        - List of `Struct.InfoAttr`. The attributes defined by this entity.
    """
    @callback attr_list() :: list(Struct.InfoAttr.t())

    @doc """
    Optional processing of data after extraction from the payload.

    ### Parameters:
        - `values`: List of {key, value} with values extracted from the payload
        - `payload`: Map with the original payload

    ### Returns:
        - List of {key, value} with updated values
    """
    @callback special_post_processing(values :: keyword(), payload :: map()) :: keyword()

    @doc """
    Optional processing of data with stored values.

    ### Parameters:
        - `new_values`: List of {key, value} with newly extracted values from the payload
        - `stored_values`: List of {key, value} with previously stored values (can be empty if none exist)
        - `payload`: Map with the original payload

    ### Returns:
        - List of {key, value} with updated values
    """
    @callback special_post_processing(
                new_values :: keyword(),
                stored_values :: keyword(),
                payload :: map()
                ) :: keyword()

    # Mark both processing functions as optional
    @optional_callbacks [
        special_post_processing: 2,
        special_post_processing: 3
    ]

    @doc """
    Returns the identifier of the table in BigQuery where records are stored.

    This function retrieves the table name from the application configuration.

    ### Returns:
        - String. The table name in BigQuery.
    """
    @callback table_id() :: String.t()

    @doc """
    Inserts records from a batch into the database.

    ### Parameters:
        - `batch`: List of map. Payloads to insert.
        - `batch_id`: String. Batch identifier.
        - `additional_info`: List. Additional information needed for processing (can be empty).

    ### Returns:
        - Any. Result of the insert operation.
    """
    @callback insert_by_lote(
                batch :: list(map()),
                batch_id :: String.t(),
                additional_info :: list()
                ) :: any()

    @doc """
    Optional callback to specify a custom name for the insert function.

    Allows modules to define an alternative name for `insert_by_lote/3`.
    If not implemented, the default name `:insert_by_lote` is used.

    ### Returns:
        - Atom. Name of the custom insert function (default: `:insert_by_lote`)

    ### Example:
        def custom_insert_function_name() do
            :my_custom_insert
        end

    If you define `custom_insert_function_name/0` to return `:my_custom_insert`,
    the framework will look for and call `my_custom_insert/3` instead of `insert_by_lote/3`.
    """
    @callback custom_insert_function_name() :: atom()

    @optional_callbacks [custom_insert_function_name: 0]


end
