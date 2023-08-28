
defmodule Type.Type do
    @moduledoc"""
    Module for working with data types
    """

    import Type.PConvertTo


    @doc"""
    Converts a data to its equivalent of a defined type

    ### Parameters:

        - x. Data to convert.

        - to: Data type that `x` will be converted to.

    ### Return:

        - value | nil | Exception

    ### Examples:

        iex> Type.convert(2, :float)
        2.0

        iex> Type.convert("2", :integer)
        2

        iex>Type.convert("14", :integer)
        14Type.convert("chain", :map)

        iex> Type.convert("chain", :string)
        "chain"

        iex> Type.convert("chain", :map)
        (throw) "NotImplementedError => from `binary` to `map`"

        iex> Type.convert(1668036600542, :string_datetime)
        "2022-11-09T23:30:00.542Z"

    ### Special considerations:

        - Elixir built-in data types to work with: binary, nil, integer, float, atom, list, map, boolean.

        - Elixir's non-built-in data types to work with: DateTime

        - Elixir non-existent data types, but need to create its name:

            - string: Binary equivalent.

            - string_datetime: Equivalent to converting from an integer to a binary, in DateTime format.


    """
    def convert(x, to) do
        convert_to(x, to)
    end

    @doc"""
    Converts the data into a format understandable by BigQuery

    ### Parameter:

        - x: t(). Value.

    ### Return:

        - String

    """
    def convert_for_bigquery(x) when is_binary(x) do
        x = x
            |> String.replace("\n", " ")
            |> String.replace("\t", "")
            |> String.replace("'", "_")
            |> String.replace("ñ", "%n")
            |> String.replace("Ñ", "%N")
            |> String.replace("á", "%a")
            |> String.replace("Á", "%A")
            |> String.replace("é", "%e")
            |> String.replace("É", "%E")
            |> String.replace("í", "%i")
            |> String.replace("Í", "%i")
            |> String.replace("ó", "%o")
            |> String.replace("Ó", "%O")
            |> String.replace("ú", "%u")
            |> String.replace("Ú", "%U")
            |> String.replace("–", "-")

        "'#{x}'"
    end

    def convert_for_bigquery(x) when is_map(x) do
        try do
            if Timex.is_valid?(x) do
                "TIMESTAMP('#{x |> to_string}')"
            else
                raise("")
            end
        rescue
            _ ->
                x = x
                |> Poison.encode!()
                |> String.replace("\\t", "")
                |> String.replace("'", "_")
                |> String.replace("ñ", "%n")
                |> String.replace("Ñ", "%N")
                |> String.replace("á", "%a")
                |> String.replace("Á", "%A")
                |> String.replace("é", "%e")
                |> String.replace("É", "%E")
                |> String.replace("í", "%i")
                |> String.replace("Í", "%i")
                |> String.replace("ó", "%o")
                |> String.replace("Ó", "%O")
                |> String.replace("ú", "%u")
                |> String.replace("Ú", "%U")
            "JSON '#{x}'"
        end
    end

    def convert_for_bigquery(x) when is_nil(x) do
        "NULL"
    end

    def convert_for_bigquery(x) do
        convert(x, :string)
    end

    @doc"""
    Convert bigquery text to understandable format

    ### Parameter:

        - x: t(). Value.

    ### Return:

        - String

    """
    def convert_from_bigquery(x) when is_binary(x) do
        x
        |> String.replace("_", "'")
        |> String.replace("%n", "ñ")
        |> String.replace("%N", "Ñ")
        |> String.replace("%a", "á")
        |> String.replace("%A", "Á")
        |> String.replace("%e", "é")
        |> String.replace("%E", "É")
        |> String.replace("%i", "í")
        |> String.replace("%i", "Í")
        |> String.replace("%o", "ó")
        |> String.replace("%O", "Ó")
        |> String.replace("%u", "ú")
        |> String.replace("%U", "Ú")
    end



end
