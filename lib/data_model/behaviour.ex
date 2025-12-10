
defmodule DataModel.Behaviour do
    @moduledoc """
    Behaviours for defining entity and sub-entity contracts.

    This module defines the callbacks that can be implemented by:
    - `DataModel.AttributeProvider`: For sub-entities that define attributes (InfoAttr)
    - `DataModel.RecordBase`: For main entities (Records) that process data

    ## Callbacks Classification

    ### Required Callbacks
    - `attr_list/0` - Returns the list of attributes
    - `table_id/0` - Returns the BigQuery table identifier
    - `unique_id_attr/0` - Returns the unique identifier attribute
    - `timestamp_attr/0` - Returns the timestamp attribute

    ### Primary Callback (Entry Point)
    - `insert_by_lote/2` or `insert_by_lote/3` - Main function to insert records

    ### Helper Callbacks (Building Blocks)
    These are optional and have default implementations:
    - `filter_batch/1` - Filters batch before processing
    - `group_by_unique_id/1` - Groups payloads by unique_id
    - `fetch_stored_data/2` - Fetches existing data from storage
    - `build_data/3` - Builds record data from payloads
    - `apply_post_processing/3` - Applies special post-processing
    - `prepare_insert_query/4` - Prepares the insert query
    - `build_insert_tuples/1` - Builds insertion tuples
    - `execute_insert/2` - Executes the insert in database
    - `handle_processing_error/4` - Handles errors during processing
    """

    # ============================================
    # REQUIRED CALLBACKS
    # ============================================

    @doc """
    Returns the list of attributes defined by the entity.

    ### Returns:
        - List of `Struct.InfoAttr`
    """
    @callback attr_list() :: list(Struct.InfoAttr.t())

    @doc """
    Returns the identifier of the table in BigQuery.

    ### Returns:
        - String. The table name in BigQuery.
    """
    @callback table_id() :: String.t()

    @doc """
    Returns the attribute that uniquely identifies the record.

    ### Returns:
        - `Struct.InfoAttr`
    """
    @callback unique_id_attr() :: Struct.InfoAttr.t()

    @doc """
    Returns the attribute used for timestamp.

    ### Returns:
        - `Struct.InfoAttr`
    """
    @callback timestamp_attr() :: Struct.InfoAttr.t()

    # ============================================
    # PRIMARY CALLBACK (Entry Point)
    # ============================================

    @doc """
    Main function to insert records from a batch (2-arity version).

    ### Parameters:
        - `batch`: List of map. Payloads to insert.
        - `batch_id`: String. Batch identifier.

    ### Returns:
        - `:ok` | `:error` | any
    """
    @callback insert_by_lote(
                batch :: list(map()),
                batch_id :: String.t()
                ) :: any()

    @doc """
    Main function to insert records from a batch (3-arity version).

    ### Parameters:
        - `batch`: List of map. Payloads to insert.
        - `batch_id`: String. Batch identifier.
        - `additional_info`: List. Additional context for processing.

    ### Returns:
        - `:ok` | `:error` | any
    """
    @callback insert_by_lote(
                batch :: list(map()),
                batch_id :: String.t(),
                additional_info :: list()
                ) :: any()

    # ============================================
    # HELPER CALLBACKS (Building Blocks)
    # ============================================

    @doc """
    Filters the batch before processing.

    ### Parameters:
        - `batch`: List of maps with payloads

    ### Returns:
        - List of filtered maps
    """
    @callback filter_batch(batch :: list(map())) :: list(map())

    @doc """
    Groups payloads by unique_id attribute.

    ### Parameters:
        - `batch`: List of maps with payloads

    ### Returns:
        - `{map_grouped_by_key, list_of_keys}`
    """
    @callback group_by_unique_id(batch :: list(map())) :: {map(), list(String.t())}

    @doc """
    Fetches existing data from storage for the given keys.

    ### Parameters:
        - `keys`: List of unique identifiers
        - `additional_info`: List. Additional context

    ### Returns:
        - `{:ok, map()}` with stored data grouped by key
        - `{:error, reason}` if fetch fails
    """
    @callback fetch_stored_data(
                keys :: list(String.t()),
                additional_info :: list()
                ) :: {:ok, map()} | {:error, any()}

    @doc """
    Builds the record data from payloads.

    ### Parameters:
        - `payloads`: List of maps with payloads for the same unique_id
        - `stored_data`: Keyword list with previously stored values (can be empty)
        - `additional_info`: List. Additional context

    ### Returns:
        - Keyword list with extracted and processed values
    """
    @callback build_data(
                payloads :: list(map()),
                stored_data :: keyword(),
                additional_info :: list()
                ) :: keyword()

    @doc """
    Applies special post-processing to extracted values.

    ### Parameters:
        - `new_values`: Keyword list with newly extracted values
        - `stored_values`: Keyword list with previously stored values
        - `payload`: Map with the original payload

    ### Returns:
        - Keyword list with processed values
    """
    @callback apply_post_processing(
                new_values :: keyword(),
                stored_values :: keyword(),
                payload :: map()
                ) :: keyword()

    @doc """
    Prepares and builds the insert query for a record.

    ### Parameters:
        - `unique_id`: String. Unique record identifier
        - `payloads`: List of maps with associated payloads
        - `stored_data`: Keyword list with stored data
        - `additional_info`: List. Additional context

    ### Returns:
        - `{:ok, {unique_id, query}}` if successful
        - `{:error, reason}` if there's an error
    """
    @callback prepare_insert_query(
                unique_id :: String.t(),
                payloads :: list(map()),
                stored_data :: keyword(),
                additional_info :: list()
                ) :: {:ok, {String.t(), String.t()}} | {:error, any()}

    @doc """
    Builds insertion tuples by combining multiple queries.

    ### Parameters:
        - `records`: List of tuples `{unique_id, query}`

    ### Returns:
        - `{list_of_keys, merged_query}` or `[]` if empty
    """
    @callback build_insert_tuples(records :: list({String.t(), String.t()})) ::
                {list(String.t()), String.t()} | []

    @doc """
    Executes the insert operation in the database.

    ### Parameters:
        - `data`: List of tuples `{keys, query}` to insert
        - `batch_id`: String. Batch identifier

    ### Returns:
        - List of results (`:ok` | `:error`)
    """
    @callback execute_insert(
                data :: list({list(String.t()), String.t()}),
                batch_id :: String.t()
                ) :: list(:ok | :error)

    @doc """
    Handles errors during record processing.

    ### Parameters:
        - `batch_id`: String. Batch identifier
        - `unique_id`: String or list. Record identifier(s)
        - `error`: The error that occurred
        - `context`: Map with additional context (function name, module, etc.)
    """
    @callback handle_processing_error(
                batch_id :: String.t(),
                unique_id :: String.t() | list(String.t()),
                error :: any(),
                context :: map()
                ) :: any()

    # ============================================
    # OPTIONAL CALLBACKS FOR AttributeProvider
    # ============================================

    @doc """
    Optional processing of data after extraction (2-arity version).

    ### Parameters:
        - `values`: Keyword list with extracted values
        - `payload`: Map with the original payload

    ### Returns:
        - Keyword list with updated values
    """
    @callback special_post_processing(values :: keyword(), payload :: map()) :: keyword()

    @doc """
    Optional processing of data with stored values (3-arity version).

    ### Parameters:
        - `new_values`: Keyword list with newly extracted values
        - `stored_values`: Keyword list with previously stored values
        - `payload`: Map with the original payload

    ### Returns:
        - Keyword list with updated values
    """
    @callback special_post_processing(
                new_values :: keyword(),
                stored_values :: keyword(),
                payload :: map()
                ) :: keyword()

    # ============================================
    # OPTIONAL CALLBACKS DECLARATION
    # ============================================

    @optional_callbacks [
        # insert_by_lote can be 2 or 3 arity
        insert_by_lote: 2,
        insert_by_lote: 3,

        # AttributeProvider callbacks
        special_post_processing: 2,
        special_post_processing: 3,

        # Helper callbacks (have default implementations)
        filter_batch: 1,
        group_by_unique_id: 1,
        fetch_stored_data: 2,
        build_data: 3,
        apply_post_processing: 3,
        prepare_insert_query: 4,
        build_insert_tuples: 1,
        execute_insert: 2,
        handle_processing_error: 4
    ]


end
