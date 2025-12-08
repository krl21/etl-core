
defmodule DataModel.FunctionDispatcher do
    @moduledoc """
    Helper module for calling functions that may have custom names.

    This module provides utilities to call functions on entities that may
    have renamed functions through the `custom_insert_function_name/0` callback.
    """

    @doc """
    Gets the function name to use for inserting records.

    ### Parameters:
        - `entity`: Module that implements DataModel.Behaviour

    ### Return:
        - Atom representing the function name to call

    ### Example:
        function_name = get_insert_function_name(DataModel.Record)
        # => :insert_by_lote (default)
        # or => :my_custom_insert (if custom_insert_function_name/0 is defined)
    """
    def get_insert_function_name(entity) do
        if function_exported?(entity, :custom_insert_function_name, 0) do
            entity.custom_insert_function_name()
        else
            :insert_by_lote
        end
    end

    @doc """
    Calls the insert function on an entity, using custom name if defined.

    ### Parameters:
        - `entity`: Module that implements DataModel.Behaviour
        - `batch`: List of payloads to insert
        - `batch_id`: String identifier for the batch
        - `additional_info`: List. Additional information needed for processing

    ### Return:
        - Result of the insert function call
    """
    def call_insert_function(entity, batch, batch_id, additional_info \\ []) do
        function_name = get_insert_function_name(entity)

        if function_exported?(entity, function_name, 3) do
            apply(
                entity,
                function_name,
                [batch, batch_id, additional_info]
            )
        else
            raise """
            Function #{function_name}/3 not found in #{inspect(entity)}.
            Make sure you have implemented either:
            - The standard function: insert_by_lote/3
            - Or defined custom_insert_function_name/0 and implemented the custom function.
            """
        end
    end


end
