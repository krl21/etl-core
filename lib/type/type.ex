
defmodule Type.Type do
    @moduledoc"""
    Module for working with data types
    """

    import Type.PConvertTo
    alias Type.Normalize


    @doc"""
    Converts a data to its equivalent of a defined type

    ### Parameters:
        - x: Data to convert.
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
        # cond do
        #     to == :string -> convert_to(x, to) |> normalize_unicode_chars()
        #     true -> convert_to(x, to)
        # end
    end

    @doc"""
    Converts the data into a format understandable by BigQuery

    ### Parameter:
        - x: Value.

    ### Return:
        - String

    """
    def convert_for_bigquery(x) when is_binary(x) do
        x
        |> Normalize.normalize_special_chars()
        |> escape_bigquery_string()
    end

    def convert_for_bigquery(x) when is_map(x) do
        try do
            x
            |> Map.get(:__struct__)
            |> case do
                struct when struct in [DateTime, NaiveDateTime] ->
                    "TIMESTAMP('#{to_string(x)}')"
                Date ->
                    "DATE('#{to_string(x)}')"
                Time ->
                    x
                    |> Time.to_erl()
                    |> time_to_bigquery()
                _ -> raise ""
            end
        rescue
            _ ->
                "JSON '#{x |> Poison.encode!() |> Normalize.normalize_special_chars()}'"
        end
    end

    def convert_for_bigquery(nil), do: "NULL"
    def convert_for_bigquery(x), do: convert(x, :string)

    defp escape_bigquery_string(x), do:
        "'#{x}'"

    defp unescape_bigquery_string(x) do
        Normalize.denormalize_special_chars(x)
    end

    defp time_to_bigquery({h, m, s}), do:
        "TIME(#{h}, #{m}, #{s})"


    @doc """
    Convert bigquery text to understandable format

    ### Parameter:
        - x: t(). Value.

    ### Return:
        - String

    """
    def convert_from_bigquery(x) when is_binary(x), do:
        unescape_bigquery_string(x)



end
