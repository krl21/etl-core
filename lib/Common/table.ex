
defmodule Common.Table do
    @moduledoc"""
    Module oriented to common functions for working with tables
    """

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



end
