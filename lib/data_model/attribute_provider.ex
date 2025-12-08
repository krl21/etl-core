
defmodule DataModel.AttributeProvider do
    @moduledoc """
    Macros and utilities for defining sub-entities that provide attributes.

    ## Usage example:

        defmodule DataModel.Record.Buyer do
            use DataModel.AttributeProvider

            @name %Struct.InfoAttr{
                id: :nombre_comprador,
                type: :string
            }

            @rut %Struct.InfoAttr{
                id: :rut_comprador,
                id_payload: "comprador_rut",
                type: :string,
                keys_to_search: ["data"]
            }

            attr_list [
                @name,
                @rut
            ]

            # Optional: special processing function
            def special_post_processing(values, payload) do
                # Processing logic
                values
            end
        end

    The `attr_list` macro defines the final list that will be returned. Additionally, getter functions are automatically generated for each defined attribute.
    """

    @doc """
    Callback invoked when `use DataModel.AttributeProvider` is called.

    Imports the necessary macros and sets up the behaviour.
    """
    defmacro __using__(_opts) do
        quote do
        @behaviour DataModel.Behaviour
        import DataModel.AttributeProviderMacro
        end
    end


end
