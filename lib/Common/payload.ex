
defmodule Common.Payload do
    @moduledoc """
    Module oriented to common functions for working with payloads
    """

    import Type.Type, only: [convert: 2]


    @doc"""
    Extract the `value` of the key defined in the map

    ### Parameters:

        - payload: Map. Container of the information (<key, value>) that is required.

        - tag: String. Key to search within the map.

        - list: List of String. List of tags to search in depth, by structure chaining.

        - default_value: t(). Default value, in case it cannot be found. If not defined, it takes value nil.

    ### Return:

        - t() | nil. If the defined labels are correct, it returns the desired value; otherwise nil.

    """
    def extract_data(payload, tag, list \\ [], default_value \\ nil)

    def extract_data(nil, _, _, default_value) do
        default_value
    end

    def extract_data(payload, tag, [], default_value) do
        Map.get(payload, tag, default_value)
    end

    def extract_data(payload, tag, [h|t], default_value) do
        Map.get(payload, h)
        |> extract_data(tag, t, default_value)
    end

    @doc"""
    Extract the information and attach it to the defined map. If it does not appear, it gives the default value in each case.

     ###Parameters:

        - payload_: Map. Payload.

        - attr_list. List of InfoAttr. Fields to search for in the payload.

        - eliminate_null_value: Boolean. Indicates if you want to eliminate fields with null values.

    ### Return:

        - list of {attr.id, values_extracted_from_the_payload} | empty list

    """
    def extract_with_format(payload, attr_list, eliminate_null_value \\ true) do
        attr_list
        |> Enum.map(fn attr -> {
                            attr,
                            Map.get(attr, :id),
                            extract_data(
                                payload,
                                Map.get(attr, :id_payload),
                                Map.get(attr, :keys_to_search),
                                Map.get(attr, :default_value)
                                )
                            }
                        end)
        |> Enum.map(fn {attr, field, value} -> {
                            field,
                            convert(value, Map.get(attr, :type))
                        }
                    end)
        |> Enum.filter(fn {_, value} -> not (is_nil(value) and eliminate_null_value) end)
    end

    @doc"""
    Group the maps with equal value in a certain field

    ### Parameters:

        - list: List of map. Data.

        - fields: Set of fields to set the identifier of each set. The identifier is the concatenation of each one, and the character '_'.

    ### Return:

        - {A, B} where

            A Map where values is a list of values of `list` such that they share the same value in the defined field

            B List of t() coincides with A.key()

    """
    def reduce_by(list, fields) do
        {map, keys} =
            list
            |> Enum.reduce({%{}, MapSet.new([])}, fn payload, {map_acc, key_acc} ->
                unique_id =
                    fields
                    |> Enum.map_join("__", fn field ->
                        payload
                        |> extract_data(
                            field.id_payload,
                            field.keys_to_search
                        )
                        |> convert(:string)
                    end)

                    {
                        Map.update(
                            map_acc,
                            unique_id,
                            [payload],
                            &(&1 ++ [payload])
                        ),
                        MapSet.put(key_acc, unique_id)
                    }
            end)
        {map, MapSet.to_list(keys)}
    end





end
