
defmodule Common.Table do
    @moduledoc"""
    Module oriented to common functions for working with tables
    """

    # import Type.Type, only: [convert: 2]


    @doc"""
    Checks if the specified name matches any column

    ### Parameter:

        - table: Atom. Table name. It is assumed that this has implemented the function attr_list/0 -> List(Struct.InfoAttr)

        - name: Atom | String. Name of the column to check.

    ### Return:

        - Boolean.

    """
    def is_attr?(name, table) when is_binary(name) and is_atom(table) do
        name
        |> String.to_atom()
        |> is_attr?(table)
    end

    def is_attr?(name, table) when is_atom(name) and is_atom(table) do
        name in Enum.map(table.attr_list(), fn attr -> attr.id end)
    end

    # @doc"""
    # Obtains the values registered in Bigquery, associated with a set of record identifiers

    # ### Parameters:

    #     - pid: Process. Process connecting Elixir and ODBC.

    #     - attr_list: List of Tools.Struct.InfoAttr. Attributes to carry the query response to the defined data type.

    #     - ids: List of Tools.Struct.InfoAttr. Attributes that will be used to differentiate the sets of records that share the same identifiers.

    #     - statement: String. Statement to get the records from the database in Bigquery.

    # ### Return:

    #     - Exception | Map, where the key contains the values of `keys` and the values are the data that Bigquery has associated with the record with that identifier

    # """
    # def get_stored_values_in_bigquery(pid, attr_list, ids, statement) do
    #     Odbc.select(pid, statement)
    #     |> Enum.reduce(%{}, fn list, acc ->
    #         typed_list =
    #             list
    #             |> Enum.reduce(
    #                 [],
    #                 fn {key, value}, acc ->
    #                     try do
    #                         attr =
    #                             attr_list
    #                             |> Stream.filter(fn attr -> attr.id == key end)
    #                             |> Enum.take(1)
    #                             |> hd()
    #                         acc ++ [{key, convert(value, attr.type)}]
    #                     rescue
    #                         # caso especifico del campo `row_column` u otra columna sin interes
    #                         _error ->
    #                             acc ++ [{key, value}]
    #                     end
    #                 end
    #             )

    #         id =
    #             ids
    #             |> Enum.map_join("_", fn field ->
    #                 typed_list
    #                 |> List.keyfind(field.id, 0)
    #                 |> elem(1)
    #                 |> Type.convert(:string)
    #             end)

    #         Map.put(
    #             acc,
    #             id,
    #             typed_list
    #         )
    #     end)
    # end



end
